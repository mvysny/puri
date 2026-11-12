# frozen_string_literal: true

module Puri
  module Core
    # Turns a pikuri agent's events into a {Conversation}'s blocks and activity, the one place
    # that decides which block an event becomes:
    #
    #   ThinkingDelta            → ActivityChanged(working, "Thinking…")
    #   AssistantDelta, …        → a Reply, re-sent per delta; ActivityChanged(streaming)
    #   Assistant                → that Reply, rendered whole from the final text
    #
    # Pass it to the agent behind `Listener::RateLimited`, which coalesces the deltas, so the
    # reply re-renders at most 15 times a second however fast the model streams:
    #
    #   listener = TurnListener.new(conversation)
    #   Pikuri::Agent.new(transport:, system_prompt:, streaming: true) do |c|
    #     c.add_listener(Pikuri::Agent::Listener::RateLimited.new(listener, fps: 15))
    #   end
    #
    # `UserTurn` shows nothing, since {Conversation} shows the user's message as the turn starts,
    # before the agent's thread runs; it only drops a reply a cancel left open. Tool events wait
    # for phase 2's tools, which word their own lines.
    class TurnListener < Pikuri::Agent::Listener::Base
      # @param conversation [Puri::Core::Conversation]
      def initialize(conversation)
        super()
        @conversation = conversation
        @reply = nil
        @stream = nil
      end

      # @param event [Object] a `Pikuri::Agent::Event` variant, or an extension's own
      # @return [void]
      def on_event(event)
        case event
        when Pikuri::Agent::Event::UserTurn then @reply = @stream = nil
        when Pikuri::Agent::Event::ThinkingDelta then thinking
        when Pikuri::Agent::Event::AssistantDelta then delta(event.content)
        when Pikuri::Agent::Event::Assistant then finish(event.content)
        end
      end

      private

      # @return [void]
      def thinking
        return if @conversation.transcript.activity.state == 'working'

        @conversation.activity = Protocol::Activity.new(state: 'working', status: 'Thinking…')
      end

      # @param text [String]
      # @return [void]
      def delta(text)
        unless @reply
          @reply = @conversation.add(Protocol::Reply.new(id: nil, parts: []))
          @stream = ReplyStream.new
          @conversation.activity = Protocol::Activity.new(state: 'streaming')
        end
        @reply = @conversation.put(@reply.with(parts: @stream.append(text)))
      end

      # The final text is authoritative: deltas need not add up to it. The agent streams, so a
      # reply always opened with a delta.
      #
      # @param text [String]
      # @return [void]
      def finish(text)
        return unless @reply

        parts = @stream.finish(text)
        @conversation.put(@reply.with(parts:)) unless parts == @reply.parts
        @reply = @stream = nil
      end
    end
  end
end
