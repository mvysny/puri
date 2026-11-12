# frozen_string_literal: true

module Puri
  module Core
    # Turns a pikuri agent's events into a {Conversation}'s blocks and activity, the one place
    # that decides which block an event becomes:
    #
    #   ThinkingDelta            → ActivityChanged(working, "Thinking…")
    #   AssistantDelta, …        → a Reply, re-sent at most `fps` times a second; ActivityChanged(streaming)
    #   Assistant                → that Reply, rendered whole from the final text
    #   any other event          → the deltas held back so far, shown first
    #
    #   listener = TurnListener.new(conversation)
    #   Pikuri::Agent.new(transport:, system_prompt:, streaming: true) { |c| c.add_listener(listener) }
    #
    # `UserTurn` shows nothing, since {Conversation} shows the user's message as the turn starts,
    # before the agent's thread runs; it only drops a reply a cancel left open. Tool events wait
    # for phase 2's tools, which word their own lines.
    #
    # == Implementation details
    #
    # A delta that comes within a frame of the last re-send waits, unparsed, for the next delta
    # past it: a fast model then costs neither a Markdown parse nor a Desktop relayout per token.
    # No timer: when the model stalls mid-reply, the held text waits for its next event.
    class TurnListener < Pikuri::Agent::Listener::Base
      # @param conversation [Puri::Core::Conversation]
      # @param fps [Numeric] how often a streaming reply re-renders, at most
      # @param clock [Proc] zero-arg, monotonic seconds as a Float; specs pass a fake one
      def initialize(conversation, fps: 15, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        super()
        @conversation = conversation
        @period = 1.0 / fps
        @clock = clock
        @reply = nil
        @stream = nil
        @pending = +''
        @next_at = -Float::INFINITY
      end

      # @param event [Object] a `Pikuri::Agent::Event` variant, or an extension's own
      # @return [void]
      def on_event(event)
        case event
        when Pikuri::Agent::Event::UserTurn then reset
        when Pikuri::Agent::Event::ThinkingDelta then thinking
        when Pikuri::Agent::Event::AssistantDelta then delta(event.content)
        when Pikuri::Agent::Event::Assistant then finish(event.content)
        else flush
        end
      end

      private

      # @return [void]
      def thinking
        return if @conversation.transcript.activity.state == 'working'

        @conversation.activity = Protocol::Activity.new(state: 'working', status: 'Thinking…')
      end

      # @return [void]
      def reset
        @reply = @stream = nil
        @pending = +''
        @next_at = -Float::INFINITY
      end

      # @param text [String]
      # @return [void]
      def delta(text)
        @pending << text
        now = @clock.call
        return if now < @next_at

        @next_at = now + @period
        flush
      end

      # Shows the held deltas, opening the reply on the first.
      #
      # @return [void]
      def flush
        return if @pending.empty?

        unless @reply
          @reply = @conversation.add(Protocol::Reply.new(id: nil, parts: []))
          @stream = ReplyStream.new
          @conversation.activity = Protocol::Activity.new(state: 'streaming')
        end
        text = @pending
        @pending = +''
        @reply = @conversation.put(@reply.with(parts: @stream.append(text)))
      end

      # The final text is authoritative: deltas need not add up to it, so the held ones are
      # dropped. The agent streams, so a reply always opened with a delta, and the first delta
      # of a turn shows at once.
      #
      # @param text [String]
      # @return [void]
      def finish(text)
        @pending = +''
        return unless @reply

        parts = @stream.finish(text)
        @conversation.put(@reply.with(parts:)) unless parts == @reply.parts
        @reply = @stream = nil
      end
    end
  end
end
