# frozen_string_literal: true

require 'fileutils'
require 'open3'

module Puri
  module Setup
    # Puri on the user's desktop, run from this checkout: no root, no copy, so a `git pull`
    # updates it. The session bus starts Puri on the first `gapplication launch`, the command the
    # global shortcut runs; with `autostart:`, the session also starts it hidden at login.
    #
    #   install = Install.new
    #   install.write(hotkey: Install::DEFAULT_HOTKEY, autostart: true)   # => the files it wrote
    #   install.installed?    # => true: the entry and the service run this checkout's exe/puri
    #   install.hotkey        # => "<Super><Alt>space", what the shortcut is bound to now
    #   install.remove
    #
    # Declarative: {#write} sets everything from its arguments, so `autostart: false` removes an
    # earlier autostart entry, and `hotkey: nil` the shortcut. The shortcut is a GNOME custom
    # keybinding at a fixed path, so a reinstall finds it.
    class Install
      # @return [String] the D-Bus name, and the base name of every installed file
      APP_ID = 'io.github.mvysny.Puri'

      # @return [String] what Puri is bound to unless the user picks another
      DEFAULT_HOTKEY = '<Super><Alt>space'

      # @return [String] GNOME's custom keybindings, the ones Settings → Keyboard lists
      MEDIA_KEYS = 'org.gnome.settings-daemon.plugins.media-keys'

      # @return [String] Puri's own entry among them
      KEYBINDING = "/#{MEDIA_KEYS.tr('.', '/')}/custom-keybindings/puri/".freeze

      # @return [String] what the desktop runs
      EXE = File.expand_path('../../../exe/puri', __dir__)

      # @param value [String] an accelerator such as `<Super>p`, or empty for none
      # @return [String, nil] `value`; nil for none
      # @raise [ArgumentError] for anything else, so a bad one writes nothing
      def self.hotkey(value)
        return nil if value.empty?
        return value if value.match?(/\A(<\w+>)*\w+\z/)

        raise ArgumentError, "#{value.inspect} isn't an accelerator like '<Super>p'"
      end

      # @param hotkey [String] an accelerator
      # @return [String] as a person reads it: `<Super><Alt>space` is "Super+Alt+Space"
      def self.label(hotkey)
        [*hotkey.scan(/<(\w+)>/).flatten, hotkey[/\w+\z/]].map { _1[0].upcase + _1[1..] }.join('+')
      end

      # @param env [#[]] where `HOME`, `XDG_DATA_HOME` and `XDG_CONFIG_HOME` come from
      def initialize(env: ENV)
        @env = env
      end

      # @return [Hash{Symbol => String}] each file {#write} may write, by role
      def paths
        home = @env['HOME'].to_s.empty? ? Dir.home : @env['HOME']
        data = @env['XDG_DATA_HOME'].to_s.empty? ? File.join(home, '.local', 'share') : @env['XDG_DATA_HOME']
        config = @env['XDG_CONFIG_HOME'].to_s.empty? ? File.join(home, '.config') : @env['XDG_CONFIG_HOME']
        { desktop: "#{data}/applications/#{APP_ID}.desktop", service: "#{data}/dbus-1/services/#{APP_ID}.service",
          autostart: "#{config}/autostart/#{APP_ID}.desktop" }
      end

      # @param hotkey [String, nil] see {.hotkey}; nil binds none
      # @param autostart [Boolean]
      # @return [Array<String>] the files it wrote, each in full
      # @raise [ArgumentError] for a checkout whose path can't go in an `Exec=` line, before
      #   writing anything
      # @raise [Puri::Setup::GSettings::Error] when the shortcut can't be bound
      def write(hotkey:, autostart:)
        exec = exec_line
        written = []
        written << file(paths[:desktop], <<~DESKTOP)
          [Desktop Entry]
          Type=Application
          Name=Puri
          Comment=Ask Puri: a desktop assistant on your own machine
          Exec=#{exec}
          DBusActivatable=true
          Terminal=false
          Categories=Utility;
        DESKTOP
        written << file(paths[:service], <<~SERVICE)
          [D-BUS Service]
          Name=#{APP_ID}
          Exec=#{exec} --gapplication-service
        SERVICE
        if autostart
          written << file(paths[:autostart], <<~AUTOSTART)
            [Desktop Entry]
            Type=Application
            Name=Puri
            Exec=#{exec} --gapplication-service
            NoDisplay=true
            X-GNOME-Autostart-enabled=true
          AUTOSTART
        else
          FileUtils.rm_f(paths[:autostart])
        end
        reload_bus
        bind(hotkey)
        written
      end

      # Removes every file {#write} wrote, and the shortcut.
      #
      # @return [void]
      # @raise [Puri::Setup::GSettings::Error]
      def remove
        paths.each_value { FileUtils.rm_f(_1) }
        reload_bus
        bind(nil)
      end

      # @return [Boolean] whether the desktop entry and the D-Bus service run this checkout
      def installed?
        exec = exec_line
        read(paths[:desktop]).include?("\nExec=#{exec}\n") &&
          read(paths[:service]).include?("\nExec=#{exec} --gapplication-service\n")
      rescue ArgumentError
        false
      end

      # @return [Boolean] whether a desktop entry or a service is there, perhaps another checkout's
      def present? = File.exist?(paths[:desktop]) || File.exist?(paths[:service])

      # @return [Boolean] whether Puri starts at login
      def autostart? = File.exist?(paths[:autostart])

      # @return [String, nil] what Puri's shortcut is bound to; nil for none
      # @raise [Puri::Setup::GSettings::Error]
      def hotkey
        return nil unless GSettings.strv(MEDIA_KEYS, 'custom-keybindings').include?(KEYBINDING)

        GSettings.string(entry, 'binding')
      end

      private

      # `exe/puri` in quotes, as both a desktop entry's and a D-Bus service's `Exec=` take it. A path
      # that would need escaping inside the quotes is refused rather than escaped.
      #
      # @return [String]
      # @raise [ArgumentError]
      def exec_line
        raise ArgumentError, "can't install from #{EXE.inspect}: quote, backslash, $, ` or newline in the path" if
          EXE.match?(/["\\$`\n]/)

        %("#{EXE}")
      end

      # @param path [String]
      # @param content [String]
      # @return [String] `path`
      def file(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        path
      end

      # @param path [String]
      # @return [String] its content; empty when it's missing
      def read(path) = File.file?(path) ? "\n#{File.read(path)}" : ''

      # @return [String] the schema and path of Puri's keybinding
      def entry = "#{MEDIA_KEYS}.custom-keybinding:#{KEYBINDING}"

      # Binds Puri's custom keybinding to `hotkey`, or removes it.
      #
      # @param hotkey [String, nil]
      # @return [void]
      def bind(hotkey)
        list = GSettings.strv(MEDIA_KEYS, 'custom-keybindings')
        if hotkey
          GSettings.set_string(entry, 'name', 'Puri')
          GSettings.set_string(entry, 'command', "gapplication launch #{APP_ID}")
          GSettings.set_string(entry, 'binding', hotkey)
          GSettings.set_strv(MEDIA_KEYS, 'custom-keybindings', list | [KEYBINDING])
        else
          GSettings.set_strv(MEDIA_KEYS, 'custom-keybindings', list - [KEYBINDING])
          %w[name command binding].each { GSettings.reset(entry, _1) }
        end
      end

      # Makes the session bus re-read its service files, or `gapplication launch` may find Puri "not
      # activatable" until the next login (`R_gnome_activation`).
      #
      # @return [void]
      def reload_bus
        _, err, status = Open3.capture3('gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
                                        '--object-path', '/org/freedesktop/DBus',
                                        '--method', 'org.freedesktop.DBus.ReloadConfig')
        return if status.success?

        warn "The session bus didn't reload (#{err.strip}); log out and back in before the shortcut starts Puri"
      end
    end
  end
end
