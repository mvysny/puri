# frozen_string_literal: true

require 'open3'

# Installs Puri for the current user, running from this checkout: no root, no copy, so a
# `git pull` updates it. The session bus starts Puri on the first `gapplication launch`, the
# command the global shortcut runs; `AUTOSTART=1` also starts it hidden at login.
#
# The shortcut is a GNOME custom keybinding, Super+Space unless `HOTKEY` names another
# (`HOTKEY='<Super>p'`) or none (`HOTKEY=`). Super+Space is GNOME's input-source switcher, so
# taking it moves the switcher to Super+Alt+Space; any other choice moves it back.

# @return [String] the D-Bus name, and the base name of every installed file
INSTALL_APP_ID = 'io.github.mvysny.Puri'

# @return [String] what Puri is bound to when `HOTKEY` is unset
INSTALL_DEFAULT_HOTKEY = '<Super>space'

# @return [String] GNOME's window-manager keybindings, the input-source switcher among them
INSTALL_WM_KEYS = 'org.gnome.desktop.wm.keybindings'

# @return [Hash{String => Array(String, String)}] each switcher key: the binding Puri takes, and
#   where it moves to
INSTALL_SWITCHER_MOVES = {
  'switch-input-source' => ['<Super>space', '<Super><Alt>space'],
  'switch-input-source-backward' => ['<Shift><Super>space', '<Shift><Super><Alt>space']
}.freeze

# @return [String] GNOME's custom keybindings, the ones Settings → Keyboard lists
INSTALL_MEDIA_KEYS = 'org.gnome.settings-daemon.plugins.media-keys'

# @return [String] Puri's own entry among them, at a fixed path so a reinstall finds it
INSTALL_KEYBINDING = "/#{INSTALL_MEDIA_KEYS.tr('.', '/')}/custom-keybindings/puri/".freeze

# @return [String] where the user's `applications/` and `dbus-1/services/` live
def install_data_home = ENV.fetch('XDG_DATA_HOME', File.expand_path('~/.local/share'))

# @return [Hash{Symbol => String}] each installed file, by role
def install_paths
  config_home = ENV.fetch('XDG_CONFIG_HOME', File.expand_path('~/.config'))
  {
    desktop: "#{install_data_home}/applications/#{INSTALL_APP_ID}.desktop",
    service: "#{install_data_home}/dbus-1/services/#{INSTALL_APP_ID}.service",
    autostart: "#{config_home}/autostart/#{INSTALL_APP_ID}.desktop"
  }
end

# `exe/puri` in quotes, as both a desktop entry's and a D-Bus service's `Exec=` take it. A path
# that would need escaping inside the quotes is refused rather than escaped.
#
# @return [String]
def install_exec
  exe = File.expand_path('../exe/puri', __dir__)
  raise "can't install from #{exe.inspect}: quote, backslash, $, ` or newline in the path" if exe.match?(/["\\$`\n]/)

  %("#{exe}")
end

# @param path [String]
# @param content [String]
# @return [void]
def install_write(path, content)
  mkdir_p File.dirname(path), verbose: false
  File.write(path, content)
  puts "wrote #{path}"
end

# @param args [Array<String>] gsettings' arguments, one per word
# @return [String] its stdout
def install_gsettings(*args)
  out, err, status = Open3.capture3('gsettings', *args)
  raise "gsettings #{args.join(' ')} failed: #{err}" unless status.success?

  out
end

# @param schema [String]
# @param key [String] a key of type `as`
# @return [Array<String>]
def install_strv(schema, key) = install_gsettings('get', schema, key).scan(/'([^']*)'/).flatten

# @param schema [String]
# @param key [String] a key of type `as`
# @param list [Array<String>] none may hold a quote
# @return [void]
def install_set_strv(schema, key, list)
  install_gsettings('set', schema, key, list.empty? ? '@as []' : "[#{list.map { "'#{_1}'" }.join(', ')}]")
end

# @return [String, nil] the accelerator to bind, nil for none
def install_hotkey
  hotkey = ENV.fetch('HOTKEY', INSTALL_DEFAULT_HOTKEY)
  return nil if hotkey.empty?
  raise "HOTKEY=#{hotkey.inspect} isn't an accelerator like '<Super>p'" unless hotkey.match?(/\A(<\w+>)*\w+\z/)

  hotkey
end

# Moves the input-source switcher off Super+Space, or back onto it. Only the two bindings in
# {INSTALL_SWITCHER_MOVES} change; anything else the user bound stays.
#
# @param off [Boolean] true to move it off Super+Space, false to move it back
# @return [void]
def install_switcher(off:)
  INSTALL_SWITCHER_MOVES.each do |key, (taken, moved)|
    from, to = off ? [taken, moved] : [moved, taken]
    list = install_strv(INSTALL_WM_KEYS, key)
    install_set_strv(INSTALL_WM_KEYS, key, list.map { _1 == from ? to : _1 }.uniq) if list.include?(from)
  end
end

# Binds Puri's custom keybinding to `hotkey`, or removes it.
#
# @param hotkey [String, nil] nil removes it
# @return [void]
def install_keybinding(hotkey)
  list = install_strv(INSTALL_MEDIA_KEYS, 'custom-keybindings')
  entry = "#{INSTALL_MEDIA_KEYS}.custom-keybinding:#{INSTALL_KEYBINDING}"
  if hotkey
    install_gsettings('set', entry, 'name', "'Puri'")
    install_gsettings('set', entry, 'command', "'gapplication launch #{INSTALL_APP_ID}'")
    install_gsettings('set', entry, 'binding', "'#{hotkey}'")
    install_set_strv(INSTALL_MEDIA_KEYS, 'custom-keybindings', list | [INSTALL_KEYBINDING])
  else
    install_set_strv(INSTALL_MEDIA_KEYS, 'custom-keybindings', list - [INSTALL_KEYBINDING])
    %w[name command binding].each { install_gsettings('reset', entry, _1) }
  end
end

# @param hotkey [String, nil] nil for none
# @return [void]
def install_shortcut(hotkey)
  install_keybinding(hotkey)
  install_switcher(off: hotkey == INSTALL_DEFAULT_HOTKEY)
end

desc "Install Puri for this user, run from this checkout; HOTKEY='<Super>p' (default Super+Space), AUTOSTART=1"
task :install do
  hotkey = install_hotkey # first, so a bad HOTKEY writes nothing
  paths = install_paths
  install_write(paths[:desktop], <<~DESKTOP)
    [Desktop Entry]
    Type=Application
    Name=Puri
    Comment=Ask Puri: a desktop assistant on your own machine
    Exec=#{install_exec}
    DBusActivatable=true
    Terminal=false
    Categories=Utility;
  DESKTOP
  install_write(paths[:service], <<~SERVICE)
    [D-BUS Service]
    Name=#{INSTALL_APP_ID}
    Exec=#{install_exec} --gapplication-service
  SERVICE

  # Declarative: a plain install turns off an earlier AUTOSTART=1, and the same goes for HOTKEY.
  if ENV['AUTOSTART'] == '1'
    install_write(paths[:autostart], <<~AUTOSTART)
      [Desktop Entry]
      Type=Application
      Name=Puri
      Exec=#{install_exec} --gapplication-service
      NoDisplay=true
      X-GNOME-Autostart-enabled=true
    AUTOSTART
  else
    rm_f paths[:autostart]
  end

  install_shortcut(hotkey)
  if hotkey == INSTALL_DEFAULT_HOTKEY
    puts 'Super+Space opens Puri; the keyboard layout switcher moved to Super+Alt+Space'
  elsif hotkey
    puts "#{hotkey} opens Puri"
  else
    puts "No shortcut bound; bind one to: gapplication launch #{INSTALL_APP_ID}"
  end
end

desc 'Remove what `rake install` wrote, and move the keyboard layout switcher back to Super+Space'
task :uninstall do
  install_paths.each_value { |path| rm_f path }
  install_shortcut(nil)
end
