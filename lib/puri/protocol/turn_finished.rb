# frozen_string_literal: true

module Puri
  module Protocol
    # Event: the reply is complete.
    #
    # @!attribute [r] conversation
    #   @return [String] the conversation's id
    class TurnFinished < Data.define(:conversation)
    end
  end
end
