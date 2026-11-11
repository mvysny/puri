# frozen_string_literal: true

module Puri
  module Desktop
    # The indeterminate progress bar shown while a turn works, with the latest step under it.
    #
    #   row = ProgressRow.new
    #   row.status = 'Searching the web…'
    #
    # It pulses only while mapped.
    class ProgressRow < Gtk::Box
      # @return [Integer] milliseconds between pulses
      PULSE = 120

      def initialize
        super(:vertical, 6)
        self.margin_top = 4
        @bar = Gtk::ProgressBar.new
        @bar.pulse_step = 0.12
        @status = Gtk::Label.new
        @status.xalign = 0
        @status.add_css_class('dim-label')
        @status.add_css_class('puri-status')
        append(@bar)
        append(@status)
        signal_connect('map') { start }
        signal_connect('unmap') { stop }
      end

      # @param text [String] the step as Core words it
      # @return [void]
      def status=(text)
        @status.text = text
      end

      # @return [String]
      def status = @status.text

      private

      # @return [void]
      def start
        return if @timer

        @timer = GLib::Timeout.add(PULSE) do
          @bar.pulse
          true
        end
      end

      # @return [void]
      def stop
        GLib::Source.remove(@timer) if @timer
        @timer = nil
      end
    end
  end
end
