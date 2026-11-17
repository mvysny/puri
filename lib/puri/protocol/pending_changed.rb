# frozen_string_literal: true

module Puri
  module Protocol
    # Event: the messages the user sent that the agent hasn't read yet changed — one typed during
    # a turn, or the first one while the agent boots. It carries all of them, so the last one
    # alone says what waits; `[]` once the agent read them or a cancel dropped them.
    #
    # @!attribute [r] conversation
    #   @return [String]
    # @!attribute [r] texts
    #   @return [Array<String>] plain text, in the order the agent will read them
    class PendingChanged < Data.define(:conversation, :texts)
    end
  end
end
