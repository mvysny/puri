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
    #   ToolCall                  → ActivityChanged(working, "Searching the web…")
    #   ToolResult                → a ToolLine; ActivityChanged(working, "Thinking…")
    #   TurnEnded                 → a Notice when cancelled or failed; when completed, the Map of
    #                               the turn's last place tool, under its answer
    #   ModelSwitched             → nothing shown; a later failure names the new server
    #
    # It renders every delta it gets, so it sits behind the gem's limiter, which coalesces them:
    #
    #   listener = TurnListener.new(conversation, server:, notebook:)
    #   conversations.open(id:, transport:, listener: Pikuri::Conversations::RateLimitedListener.new(listener, fps: 15))
    #
    # Going idle is not an event's: {AgentSession} asks the gem whether work is under way. Each
    # step goes through {Conversation#step}, so a cancelled turn says "Cancelling…" until it ends.
    # {ToolWording} words a tool's status and line, as {Replay} does a saved one's.
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
      # @param notebook [Puri::Core::Places::Notebook, nil] where a place tool's map is found
      def initialize(conversation, server:, notebook: nil)
        super()
        @conversation = conversation
        @server = server
        @notebook = notebook
        @reply = nil
        @stream = nil
        @calls = {}
        @map = nil
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
        when Pikuri::Agent::Event::ToolCall then tool_call(event)
        when Pikuri::Agent::Event::ToolResult then tool_result(event)
        when Pikuri::Conversations::Event::TurnEnded then ended(event)
        when Pikuri::Agent::Event::ModelSwitched then @server = event.to.api_base
        end
      end

      private

      # @param text [String, nil] nil for a turn that only delivers what was sent during the last
      # @return [void]
      def started(text)
        @map = nil
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

        @conversation.step(THINKING)
      end

      # @param event [Pikuri::Conversations::Event::TurnEnded]
      # @return [void]
      def ended(event)
        case event.outcome
        when :cancelled then @conversation.add(Protocol::Notice.new(id: nil, text: 'Cancelled', error: false))
        when :failed then @conversation.add(Protocol::Notice.new(id: nil, text: failure(event.error), error: true))
        when :completed then @conversation.add(@map) if @map
        end
        @map = nil
      end

      # @param event [Pikuri::Agent::Event::ToolCall]
      # @return [void]
      def tool_call(event)
        @calls[event.tool_call_id] = event
        @conversation.step(Protocol::Activity.new(state: 'working', status: ToolWording.status(event)))
      end

      # A result whose call never showed — one a cancel answered before it ran — shows nothing.
      #
      # @param event [Pikuri::Agent::Event::ToolResult]
      # @return [void]
      def tool_result(event)
        call = @calls.delete(event.tool_call_id) or return

        @conversation.add(ToolWording.line(call, content: event.content, summary: event.summary))
        @map = @notebook&.map_for(event.content.to_s) || @map
        @conversation.step(THINKING)
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
        @conversation.step(Protocol::Activity.new(state: 'streaming'))
      end
    end
  end
end
