# frozen_string_literal: true

module Puri
  module Protocol
    # Event: the mic in the prompt changed state. Dictation is the window's, not a
    # conversation's, so it names none.
    #
    #   DictationChanged.new(state: 'listening', status: 'Listening… press F5 when done', level: 0.4)
    #   DictationChanged.new(state: 'transcribing', status: 'Transcribing…')
    #   DictationChanged.new(state: 'idle', text: 'buy avocados')     # insert at the cursor
    #   DictationChanged.new(state: 'failed', status: "Couldn't transcribe: …")
    #
    # @!attribute [r] state
    #   @return [String] one of {STATES}
    # @!attribute [r] status
    #   @return [String] what to show under the bar, as Core words it; empty while `idle`
    # @!attribute [r] level
    #   @return [Float] the mic's level while `listening`, 0 (silence) to 1; 0 otherwise
    # @!attribute [r] text
    #   @return [String] on the `idle` that ends a transcription, what was heard, squeezed to
    #     single spaces; empty for silence and on every other event
    class DictationChanged < Data.define(:state, :status, :level, :text)
      # @return [Array<String>]
      STATES = %w[idle listening transcribing failed].freeze

      # @param state [String] one of {STATES}
      # @param status [String]
      # @param level [Float]
      # @param text [String]
      # @raise [ArgumentError] for any other state
      def initialize(state:, status: '', level: 0.0, text: '')
        raise ArgumentError, "unknown dictation state: #{state.inspect}" unless STATES.include?(state)

        super
      end

      # @return [Boolean] whether the mic records or its clip is being transcribed
      def active? = %w[listening transcribing].include?(state)
    end
  end
end
