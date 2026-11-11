# frozen_string_literal: true

module Puri
  module Protocol
    # Event: Core took an {Ask} and is working on the reply.
    #
    # @!attribute [r] conversation
    #   @return [String] the conversation's id, newly made when the {Ask} carried none
    class TurnStarted < Data.define(:conversation)
    end
  end
end
