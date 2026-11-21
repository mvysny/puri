# frozen_string_literal: true

module Puri
  module Desktop
    # The mic's state under the entry, shown only while dictating or after it failed:
    #
    #   ▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱             the mic's level while listening; a pulsing bar while transcribing
    #   Listening… press F5 when done
    #
    #   row = DictationRow.new
    #   row.dictation = event   # each Protocol::DictationChanged
    #
    # A level bar rather than a progress bar while listening: there is nothing to progress
    # toward, and a flat level shows a dead mic at once (`D_dictation`).
    class DictationRow < Gtk::Box
      # @return [Gtk::LevelBar]
      attr_reader :level

      # @return [Gtk::Label]
      attr_reader :status

      def initialize
        super(:vertical, 4)
        add_css_class('puri-dictation')
        @level = Gtk::LevelBar.new
        # Adwaita colours a low level as a warning; a quiet voice is none.
        %w[low high full].each { @level.remove_offset_value(_1) }
        @pulse = Gtk::ProgressBar.new
        @pulse.pulse_step = 0.12
        @status = Gtk::Label.new
        @status.xalign = 0
        @status.wrap = true
        @status.add_css_class('dim-label')
        @status.add_css_class('puri-status')
        [@level, @pulse, @status].each { append(_1) }
        self.visible = false
        signal_connect('unmap') { pulsing(false) }
      end

      # @param event [Puri::Protocol::DictationChanged]
      # @return [void]
      def dictation=(event)
        self.visible = event.state != 'idle'
        @level.visible = event.state == 'listening'
        @level.value = event.level
        @pulse.visible = event.state == 'transcribing'
        pulsing(event.state == 'transcribing')
        @status.text = event.status
        event.state == 'failed' ? @status.add_css_class('error') : @status.remove_css_class('error')
      end

      private

      # @param on [Boolean]
      # @return [void]
      def pulsing(on)
        if on && !@timer
          @timer = GLib::Timeout.add(ProgressRow::PULSE) do
            @pulse.pulse
            true
          end
        elsif !on && @timer
          GLib::Source.remove(@timer)
          @timer = nil
        end
      end
    end
  end
end
