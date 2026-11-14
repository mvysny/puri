# frozen_string_literal: true

module Puri
  module Core
    # Turns a pikuri conversation's events into a {Conversation}'s blocks and activity, the one
    # place that decides which block an event becomes:
    #
    #   TurnStarted(user_message:) → a UserMessage; ActivityChanged(working, "Thinking…")
    #   UserTurn(mid_loop: true)  → a UserMessage: a message sent during the turn, as the model reads it
    #   ThinkingDelta             → ActivityChanged(working, "Thinking…")
    #   AssistantDelta            → appended to the Reply, opened on the first; ActivityChanged(streaming)
    #   Assistant                 → that Reply, rendered whole from the final text
    #   TurnEnded                 → a Notice when cancelled or failed
    #
    # It renders every delta it gets, so it sits behind the gem's limiter, which coalesces them:
    #
    #   listener = Pikuri::Conversations::RateLimitedListener.new(TurnListener.new(conversation, server:), fps: 15)
    #   conversations.open(id:, transport:, listener:)
    #
    # Going idle is not an event's: {AgentSession} asks the gem whether work is under way.
    #
    # Tool events wait for phase 2's tools, which word their own lines.
    #
    # == Threading
    #
    # Its state is the turn thread's, with no lock: only the agent's events, `TurnStarted` and
    # `TurnEnded` touch it, and the gem emits those on the turn's thread. Every other
    # conversation event — `PendingChanged`, `CancelRequested`, `Cleared`… — may come from the
    # thread that submits or cancels, so it must do nothing here.
    class TurnListener < Pikuri::Agent::Listener::Base
      # @return [Puri::Protocol::Activity] a turn before its first token
      THINKING = Protocol::Activity.new(state: 'working', status: 'Thinking…')

      # @param conversation [Puri::Core::Conversation]
      # @param server [String, nil] the model's `api_base`, which a failure names
      def initialize(conversation, server:)
        super()
        @conversation = conversation
        @server = server
        @reply = nil
        @stream = nil
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
        case event.outcome
        when :cancelled then @conversation.add(Protocol::Notice.new(id: nil, text: 'Cancelled', error: false))
        when :failed then @conversation.add(Protocol::Notice.new(id: nil, text: failure(event.error), error: true))
        end
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
      end

      # @param text [String]
      # @return [void]
      def delta(text)
        open_reply
        @reply = @conversation.put(@reply.with(parts: @stream.append(text)))
      end

      # The final text is authoritative: deltas need not add up to it. A reply shorter than one
      # frame comes with no delta at all, the limiter having dropped them at this bookend.
      #
      # @param text [String]
      # @return [void]
      def finish(text)
        open_reply
        parts = @stream.finish(text)
        @conversation.put(@reply.with(parts:)) unless parts == @reply.parts
        reset
      end

      # @return [void]
      def open_reply
        return if @reply

        @reply = @conversation.add(Protocol::Reply.new(id: nil, parts: []))
        @stream = ReplyStream.new
        @conversation.activity = Protocol::Activity.new(state: 'streaming')
      end
    end
  end
end
