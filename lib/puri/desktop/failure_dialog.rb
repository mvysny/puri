# frozen_string_literal: true

module Puri
  module Desktop
    # What the shortcut shows in place of the popup when Puri can't start: the error, and the
    # config to fix.
    #
    #   FailureDialog.new(app, 'no [titler] names the connection that writes titles',
    #                     config: '/home/me/.config/puri/config.toml').present
    #
    # It is the app's only window, and closing it ends Puri, so the next press of the shortcut
    # starts a fresh one, which reads the config again: fix the file, press the shortcut.
    class FailureDialog < Adw::AlertDialog
      # @param app [Adw::Application]
      # @param message [String] what went wrong, as Core words it
      # @param config [String, nil] the file to fix, which a button opens; nil offers none
      def initialize(app, message, config: nil)
        super("Puri can't start", nil)
        @app = app
        @config = config
        self.extra_child = message_label(message)
        self.prefer_wide_layout = true
        add_response('quit', 'Quit')
        self.close_response = 'quit'
        self.default_response = 'quit'
        return unless config

        add_response('open', 'Open config.toml')
        set_response_appearance('open', :suggested)
        self.default_response = 'open'
        signal_connect('response') { |_, response| open_config if response == 'open' }
      end

      # Shows it in a window of its own, the app's: no popup is there to hold it.
      #
      # @return [void]
      def present
        super(nil)
        @app.add_window(root)
      end

      private

      # Unfocusable, or it opens with all its text selected; selectable, for a search or a bug
      # report.
      #
      # @param message [String]
      # @return [Gtk::Label]
      def message_label(message)
        label = Gtk::Label.new(message)
        label.wrap = true
        label.wrap_mode = :word_char
        label.selectable = true
        label.focusable = false
        label
      end

      # In the user's editor. Puri is held until the launch is through: the dialog closes on the
      # click, and with it would go Puri, the launch half done.
      #
      # @return [void]
      def open_config
        @app.hold
        Gio::AppInfo.launch_default_for_uri_async(Gio::File.new_for_path(@config).uri, nil, nil) do |_, result|
          Gio::AppInfo.launch_default_for_uri_finish(result)
        rescue GLib::Error => e
          warn "puri: can't open #{@config}: #{e.message}"
        ensure
          @app.release
        end
      end
    end
  end
end
