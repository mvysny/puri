# frozen_string_literal: true

module Puri
  module Core
    # A saved conversation's blocks, rebuilt from its pikuri history:
    #
    #   Replay.blocks(store.history(id))   # => [UserMessage, ToolLine, Reply, UserMessage, Reply]
    #
    # Each user message becomes a {Protocol::UserMessage}, each assistant message with text a
    # {Protocol::Reply}, as {TurnListener} renders one when it finishes, so a reloaded reply gets
    # today's renderer; each tool answer becomes the {Protocol::ToolLine} {ToolWording} words for
    # its call, as it did live. What never became a message is gone: notices, and the partial
    # reply a cancel cut off. The blocks' ids are nil, for {Conversation#restore} to assign.
    module Replay
      # @param history [Pikuri::Agent::History]
      # @return [Array<Puri::Protocol::UserMessage, Puri::Protocol::Reply, Puri::Protocol::ToolLine>]
      def self.blocks(history)
        calls = {}
        history.messages.filter_map do |message|
          case message.role
          when 'user'
            Protocol::UserMessage.new(id: nil, text: message.content) unless message.kind == 'reference'
          when 'assistant'
            message.tool_calls.each { |call| calls[call.id] = call }
            Protocol::Reply.new(id: nil, parts: ReplyRenderer.render(message.content)) unless message.content.empty?
          when 'tool'
            call = calls[message.tool_call_id]
            ToolWording.line(call, content: message.content, summary: message.summary) if call
          end
        end
      end
    end
  end
end
