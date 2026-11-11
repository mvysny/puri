# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: a line from Puri itself, not the model: "Cancelled", or why a turn failed.
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] text
    #   @return [String] plain text, never markup
    # @!attribute [r] error
    #   @return [Boolean] true for a failure, false for a plain note
    class Notice < Data.define(:id, :text, :error)
      include Block
    end
  end
end
