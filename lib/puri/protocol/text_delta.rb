# frozen_string_literal: true

module Puri
  module Protocol
    # Event: the next piece of the reply, as the model streams it.
    #
    # @!attribute [r] conversation
    #   @return [String] the conversation's id
    # @!attribute [r] text
    #   @return [String] appended to the reply so far
    class TextDelta < Data.define(:conversation, :text)
    end
  end
end
