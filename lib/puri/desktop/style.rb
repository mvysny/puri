# frozen_string_literal: true

module Puri
  module Desktop
    # Puri's CSS on top of Adwaita's, installed once for the display.
    module Style
      # @return [String]
      CSS = <<~CSS
        window.puri-popup.pill { border-radius: 30px; }
        .puri-prompt { font-size: 1.2em; min-height: 46px; padding: 0 16px; border-radius: 23px; }
        window.puri-popup.pill .puri-prompt {
          font-size: 1.35em; min-height: 52px; background: none; box-shadow: none; outline: none;
        }
        .puri-transcript { padding: 6px 18px 18px 18px; }
        .puri-user {
          background: alpha(currentColor, 0.08); border-radius: 18px; padding: 8px 14px;
        }
        .puri-reply { line-height: 1.35; }
        .puri-code {
          font-family: monospace; font-size: 0.92em; padding: 10px 12px; border-radius: 10px;
          background: alpha(currentColor, 0.06);
        }
        .puri-table { border-radius: 10px; border: 1px solid alpha(currentColor, 0.12); }
        .puri-table label { padding: 5px 12px; }
        .puri-table label.header { font-weight: bold; background: alpha(currentColor, 0.05); }
        .puri-tool { font-size: 0.9em; }
        .puri-notice { font-style: italic; }
        .puri-confirmation { padding: 14px; }
        .puri-confirmation button { padding: 4px 18px; }
        .puri-status { font-size: 0.9em; }
        .puri-history-row { padding: 6px 4px; }
        .puri-running { color: @accent_color; }
      CSS

      # Safe to call twice.
      #
      # @return [void]
      def self.install
        return if @installed

        provider = Gtk::CssProvider.new
        provider.load(data: CSS)
        Gtk::StyleContext.add_provider_for_display(Gdk::Display.default, provider,
                                                   Gtk::StyleProvider::PRIORITY_APPLICATION)
        @installed = true
      end
    end
  end
end
