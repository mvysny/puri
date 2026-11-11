# frozen_string_literal: true

module Puri
  module Protocol
    # Event: a conversation's turn started, moved on, or ended.
    #
    # @!attribute [r] conversation
    #   @return [String]
    # @!attribute [r] activity
    #   @return [Puri::Protocol::Activity]
    class ActivityChanged < Data.define(:conversation, :activity)
    end
  end
end
