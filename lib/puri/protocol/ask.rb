# frozen_string_literal: true

module Puri
  module Protocol
    # Command: the user asked something.
    #
    # @!attribute [r] conversation
    #   @return [String, nil] the conversation to continue; nil starts a new one
    # @!attribute [r] text
    #   @return [String] what the user typed
    class Ask < Data.define(:conversation, :text)
    end
  end
end
