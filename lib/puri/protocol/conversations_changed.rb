# frozen_string_literal: true

module Puri
  module Protocol
    # Event: the history changed: a conversation began, got its title, started or stopped
    # running, or was deleted. Carries the whole list, as {Backend#list_conversations} returns it.
    #
    # @!attribute [r] conversations
    #   @return [Array<Puri::Protocol::ConversationSummary>] newest first
    class ConversationsChanged < Data.define(:conversations)
    end
  end
end
