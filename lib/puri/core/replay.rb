# frozen_string_literal: true

module Puri
  module Core
    # A saved conversation's blocks, rebuilt from its pikuri history:
    #
    #   Replay.blocks(store.history(id), notebook:)   # => [UserMessage, ToolLine, Reply, Map, UserMessage, Reply]
    #
    # Each user message becomes a {Protocol::UserMessage}, each assistant message with text a
    # {Protocol::Reply}, as {TurnListener} renders one when it finishes, so a reloaded reply gets
    # today's renderer; each tool answer becomes the {Protocol::ToolLine} {ToolWording} words for
    # its call, as it did live. The map of a turn's last place tool closes the turn, as live, once
    # an answer followed it. What never became a message is gone: notices, and the partial reply a
    # cancel cut off. The blocks' ids are nil, for {Conversation#restore} to assign.
    module Replay
      # @param history [Pikuri::Agent::History]
      # @param notebook [Puri::Core::Places::Notebook, nil] where a place tool's map is found
      # @return [Array<Puri::Protocol::Block>] user messages, replies, tool lines and maps
      def self.blocks(history, notebook: nil)
        calls = {}
        map = nil
        answered = false
        blocks = []
        history.messages.each do |message|
          case message.role
          when 'user'
            next if message.kind == 'reference'

            blocks << map if map && answered
            map = nil
            blocks << Protocol::UserMessage.new(id: nil, text: message.content)
          when 'assistant'
            message.tool_calls.each { |call| calls[call.id] = call }
            next if message.content.empty?

            answered = true
            blocks << Protocol::Reply.new(id: nil, parts: ReplyRenderer.render(message.content))
          when 'tool'
            call = calls[message.tool_call_id] or next

            blocks << ToolWording.line(call, content: message.content, summary: message.summary)
            drawn = notebook&.map_for(message.content.to_s)
            if drawn
              map = drawn
              answered = false
            end
          end
        end
        blocks << map if map && answered
        blocks
      end
    end
  end
end
