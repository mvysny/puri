# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: one step the agent took, worded by Core, drawn as one dimmed line. It
    # stays in the transcript to show what left the machine, and so a local model's slow steps
    # read as progress, not a stall.
    #
    #   ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado preservation"', error: false)
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] text
    #   @return [String] plain text, never markup
    # @!attribute [r] error
    #   @return [Boolean] whether the step failed
    class ToolLine < Data.define(:id, :text, :error)
      include Block
    end
  end
end
