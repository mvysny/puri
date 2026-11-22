# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: one step the agent took, worded by Core, drawn as one dimmed line. It
    # stays in the transcript to show what left the machine, and so a local model's slow steps
    # read as progress, not a stall.
    #
    #   ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado preservation"', error: false)
    #   ToolLine.new(id: 'b3', text: '🌦 Weather from Open-Meteo: Lisbon', error: false,
    #                markup: '🌦 Weather from <a href="https://open-meteo.com/">Open-Meteo</a>: Lisbon')
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] text
    #   @return [String] plain text, never markup
    # @!attribute [r] error
    #   @return [Boolean] whether the step failed
    # @!attribute [r] markup
    #   @return [String, nil] the same line as Pango markup, drawn in place of `text`, where a
    #     data source's terms want their credit linked beside the data; nil for a plain line
    class ToolLine < Data.define(:id, :text, :error, :markup)
      include Block

      # @param id [String, nil]
      # @param text [String]
      # @param error [Boolean]
      # @param markup [String, nil]
      def initialize(id:, text:, error:, markup: nil) = super
    end
  end
end
