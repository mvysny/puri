# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative 'support/broadway'

# `rake install` against a scratch home: the XDG dirs point into a temp dir and gsettings writes a
# keyfile there, so no example touches the desktop it runs on.
RSpec.describe 'rake install' do
  root = File.expand_path('..', __dir__)
  app_id = 'io.github.mvysny.Puri'
  media_keys = 'org.gnome.settings-daemon.plugins.media-keys'
  wm_keys = 'org.gnome.desktop.wm.keybindings'
  puri_keybinding = '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/puri/'
  other_keybinding = '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/'

  around do |example|
    Dir.mktmpdir('puri-install') do |home|
      @home = home
      example.run
    end
  end

  # @param extra [Hash{String => String, nil}] nil unsets
  # @return [Hash{String => String, nil}]
  def env(extra = {})
    { 'XDG_DATA_HOME' => "#{@home}/data", 'XDG_CONFIG_HOME' => "#{@home}/config",
      'GSETTINGS_BACKEND' => 'keyfile', 'HOTKEY' => nil, 'AUTOSTART' => nil }.merge(extra)
  end

  # @param task [String]
  # @param vars [Hash{String => String}]
  # @return [Array(String, String, Process::Status)]
  def rake(task, vars = {})
    Open3.capture3(env(vars), RbConfig.ruby, Gem.bin_path('rake', 'rake'), task,
                   chdir: File.expand_path('..', __dir__))
  end

  # @param task [String]
  # @param vars [Hash{String => String}]
  # @return [String] stdout
  def rake!(task, vars = {})
    out, err, status = rake(task, vars)
    assert status.success?, "rake #{task} failed:\n#{out}#{err}"
    out
  end

  # @param args [Array<String>]
  # @return [String] stdout, stripped
  def gsettings(*args)
    out, err, status = Open3.capture3(env, 'gsettings', *args)
    assert status.success?, err
    out.strip
  end

  # @param schema [String]
  # @param key [String]
  # @return [Array<String>]
  def strv(schema, key) = gsettings('get', schema, key).scan(/'([^']*)'/).flatten

  # @param path [String]
  # @return [void]
  def assert_valid_desktop_entry(path)
    out, status = Open3.capture2e('desktop-file-validate', path)
    assert status.success?, "#{path}:\n#{out}"
  end

  let(:desktop) { "#{@home}/data/applications/#{app_id}.desktop" }
  let(:service) { "#{@home}/data/dbus-1/services/#{app_id}.service" }
  let(:autostart) { "#{@home}/config/autostart/#{app_id}.desktop" }

  it 'writes a D-Bus-activatable desktop entry and a service that runs exe/puri' do
    rake!('install')
    assert_valid_desktop_entry desktop
    assert_includes File.read(desktop), "\nDBusActivatable=true\n"
    assert_includes File.read(service), %(\nExec="#{root}/exe/puri" --gapplication-service\n)
    refute File.exist?(autostart), 'autostart is opt-in'
  end

  it 'binds Super+Space beside existing custom shortcuts, moving the layout switcher off it' do
    gsettings('set', media_keys, 'custom-keybindings', "['#{other_keybinding}']")
    out = rake!('install')
    assert_includes out, 'Super+Space opens Puri'

    assert_equal [other_keybinding, puri_keybinding], strv(media_keys, 'custom-keybindings')
    entry = "#{media_keys}.custom-keybinding:#{puri_keybinding}"
    assert_equal "'<Super>space'", gsettings('get', entry, 'binding')
    assert_equal "'gapplication launch #{app_id}'", gsettings('get', entry, 'command')

    switcher = strv(wm_keys, 'switch-input-source')
    assert_includes switcher, '<Super><Alt>space'
    refute_includes switcher, '<Super>space'
    assert_includes strv(wm_keys, 'switch-input-source-backward'), '<Shift><Super><Alt>space'
  end

  it 'moves the layout switcher back for another HOTKEY, and uninstall undoes everything' do
    gsettings('set', media_keys, 'custom-keybindings', "['#{other_keybinding}']")
    switcher_before = strv(wm_keys, 'switch-input-source')
    rake!('install')

    rake!('install', 'HOTKEY' => '<Super>p')
    assert_equal "'<Super>p'", gsettings('get', "#{media_keys}.custom-keybinding:#{puri_keybinding}", 'binding')
    assert_equal switcher_before, strv(wm_keys, 'switch-input-source')

    assert_includes rake!('install', 'HOTKEY' => ''), 'No shortcut bound'
    assert_equal [other_keybinding], strv(media_keys, 'custom-keybindings')

    rake!('install')
    rake!('uninstall')
    refute File.exist?(desktop)
    refute File.exist?(service)
    assert_equal [other_keybinding], strv(media_keys, 'custom-keybindings')
    assert_equal switcher_before, strv(wm_keys, 'switch-input-source')
  end

  it 'adds a valid autostart entry for AUTOSTART=1, and a plain install takes it away' do
    rake!('install', 'AUTOSTART' => '1')
    assert_valid_desktop_entry autostart
    assert_includes File.read(autostart), '--gapplication-service'

    rake!('install')
    refute File.exist?(autostart)
  end

  it 'refuses a HOTKEY that is no accelerator, before writing anything' do
    _, err, status = rake('install', 'HOTKEY' => "x'; rm")
    refute status.success?
    assert_includes err, "isn't an accelerator"
    refute File.exist?(desktop)
  end

  # The whole path a shortcut takes, on a private session bus that reads the services from the
  # scratch home: `gapplication launch` with no Puri running makes the bus start one.
  it 'lets the session bus start Puri on `gapplication launch`' do
    Broadway.start
    rake!('install', 'HOTKEY' => '')
    # The bus hands its own environment to the Puri it starts. Local GIO, or that Puri asks the bus
    # for gvfs, which can't mount here; err: quiets the bus's activation log.
    bus = IO.popen([env('GIO_USE_VFS' => 'local'), 'dbus-daemon', '--session', '--nofork', '--print-address'],
                   err: File::NULL)
    begin
      address = bus.gets&.strip or raise 'dbus-daemon printed no address'
      on_bus = env('DBUS_SESSION_BUS_ADDRESS' => address)

      _, err, status = Open3.capture3(on_bus, 'gapplication', 'launch', app_id)
      assert status.success?, err

      owner = Open3.capture2(on_bus, 'gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
                             '--object-path', '/org/freedesktop/DBus',
                             '--method', 'org.freedesktop.DBus.GetConnectionUnixProcessID', app_id).first
      pid = owner[/\(uint32 (\d+),\)/, 1] or raise "nobody owns #{app_id}: #{owner.inspect}"
      Process.kill('KILL', Integer(pid))
    ensure
      Process.kill('TERM', bus.pid)
      bus.close
    end
  end
end
