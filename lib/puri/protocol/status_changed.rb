# frozen_string_literal: true

module Puri
  module Protocol
    # Event: a conversation's {Status} changed — a model picked, a reply's tokens counted.
    #
    # @!attribute [r] conversation
    #   @return [String]
    # @!attribute [r] status
    #   @return [Puri::Protocol::Status]
    class StatusChanged < Data.define(:conversation, :status)
    end
  end
end
