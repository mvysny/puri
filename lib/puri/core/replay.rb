# frozen_string_literal: true

module Puri
  module Core
    # A saved conversation's blocks, rebuilt from its pikuri history:
    #
    #   Replay.blocks(store.history(id))   # => [UserMessage, Reply, UserMessage, Reply]
    #
    # Each user message becomes a {Protocol::UserMessage} and each assistant message with text a
    # {Protocol::Reply}, as {TurnListener} renders one when it finishes, so a reloaded reply gets
    # today's renderer. What never became a message is gone: notices, and the partial reply a
    # cancel cut off. The blocks' ids are nil, for {Conversation#restore} to assign.
    module Replay
      # @param history [Pikuri::Agent::History]
      # @return [Array<Puri::Protocol::UserMessage, Puri::Protocol::Reply>]
      def self.blocks(history)
        history.lift_inline_thinking.messages.filter_map do |message|
          case message.role
          when 'user'
            Protocol::UserMessage.new(id: nil, text: message.content) unless message.kind == 'reference'
          when 'assistant'
            Protocol::Reply.new(id: nil, parts: ReplyRenderer.render(message.content)) unless message.content.empty?
          end
        end
      end
    end
  end
end
