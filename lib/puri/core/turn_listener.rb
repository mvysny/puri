# frozen_string_literal: true

module Puri
  module Core
    # Turns a pikuri conversation's events into a {Conversation}'s blocks and activity, the one
    # place that decides which block an event becomes:
    #
    #   TurnStarted(user_message:) → a UserMessage; ActivityChanged(working, "Thinking…")
    #   UserTurn(mid_loop: true)  → a UserMessage: a message sent during the turn, as the model reads it
    #   ThinkingDelta             → ActivityChanged(working, "Thinking…")
    #   AssistantDelta, …         → a Reply, re-sent at most `fps` times a second; ActivityChanged(streaming)
    #   Assistant                 → that Reply, rendered whole from the final text
    #   TurnEnded                 → a Notice when cancelled or failed; ActivityChanged(idle) unless
    #                               another turn follows
    #   any other event           → the deltas held back so far, shown first
    #
    #   listener = TurnListener.new(conversation, server: transport.api_base)
    #   conversations.open(id:, transport:, listener:)
    #
    # Tool events wait for phase 2's tools, which word their own lines.
    #
    # == Implementation details
    #
    # A delta that comes within a frame of the last re-send waits, unparsed, for the next delta
    # past it: a fast model then costs neither a Markdown parse nor a Desktop relayout per token.
    # No timer: when the model stalls mid-reply, the held text waits for its next event.
    class TurnListener < Pikuri::Agent::Listener::Base
      # @return [Puri::Protocol::Activity] a turn before its first token
      THINKING = Protocol::Activity.new(state: 'working', status: 'Thinking…')

      # @param conversation [Puri::Core::Conversation]
      # @param server [String, nil] the model's `api_base`, which a failure names
      # @param fps [Numeric] how often a streaming reply re-renders, at most
      # @param clock [Proc] zero-arg, monotonic seconds as a Float; specs pass a fake one
      def initialize(conversation, server:, fps: 15, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        super()
        @conversation = conversation
        @server = server
        @period = 1.0 / fps
        @clock = clock
        @reply = nil
        @stream = nil
        @pending = +''
        @next_at = -Float::INFINITY
      end

      # @param event [Object] a `Pikuri::Agent::Event` or `Pikuri::Conversations::Event` variant,
      #   or an extension's own
      # @return [void]
      def on_event(event)
        case event
        when Pikuri::Conversations::Event::TurnStarted then started(event.user_message)
        when Pikuri::Agent::Event::UserTurn then user_turn(event)
        when Pikuri::Agent::Event::ThinkingDelta then thinking
        when Pikuri::Agent::Event::AssistantDelta then delta(event.content)
        when Pikuri::Agent::Event::Assistant then finish(event.content)
        when Pikuri::Conversations::Event::TurnEnded then ended(event)
        else flush
        end
      end

      private

      # @param text [String, nil] nil for a turn that only delivers what was sent during the last
      # @return [void]
      def started(text)
        @conversation.add(Protocol::UserMessage.new(id: nil, text:)) if text
        @conversation.activity = THINKING
      end

      # Drops a reply a cancel left open; a mid-turn message shows where the model reads it.
      #
      # @param event [Pikuri::Agent::Event::UserTurn]
      # @return [void]
      def user_turn(event)
        flush
        reset
        @conversation.add(Protocol::UserMessage.new(id: nil, text: event.content)) if event.mid_loop
      end

      # @return [void]
      def thinking
        return if @conversation.transcript.activity.state == 'working'

        @conversation.activity = THINKING
      end

      # @param event [Pikuri::Conversations::Event::TurnEnded]
      # @return [void]
      def ended(event)
        flush
        case event.outcome
        when :cancelled then @conversation.add(Protocol::Notice.new(id: nil, text: 'Cancelled', error: false))
        when :failed then @conversation.add(Protocol::Notice.new(id: nil, text: failure(event.error), error: true))
        end
        @conversation.activity = Protocol::Activity::IDLE unless event.restarting
      end

      # @param error [StandardError]
      # @return [String] what the user reads
      def failure(error)
        case error
        when RubyLLM::ConnectionError then "Can't reach the model at #{@server}: #{error.message}"
        else "The turn failed: #{error.message} (#{error.class}, #{@server})"
        end
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
