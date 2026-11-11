# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: what the user typed.
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] text
    #   @return [String] plain text, never markup
    class UserMessage < Data.define(:id, :text)
      include Block
    end
  end
end
