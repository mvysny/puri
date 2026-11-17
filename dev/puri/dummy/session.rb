# frozen_string_literal: true

module Puri
  module Dummy
    # One {Backend} conversation's turns, each a {Turn} on a thread of its own, as
    # `Pikuri::Conversations` runs a real one's:
    #
    #   session = Session.new(conversation, lock:, threads:, think:, pace:)
    #   session.ask('reschedule my dentist in the calendar')   # starts a turn
    #   session.ask('make it Wednesday')    # a confirmation waits: redirects it
    #   session.cancel
    #
    # A message sent while a turn runs, but asks nothing, waits for that turn to end. Each turn
    # that ends reports made-up token counts, about four characters a token, to the status bar.
    #
    # Thread-safe: every method runs under the backend's monitor.
    class Session
      # @return [Integer] tokens, what the status bar measures the context against
      CONTEXT_WINDOW = 32_768

      # @return [Integer] tokens of system prompt and tools every turn sends
      PROMPT_TOKENS = 1500

      # @return [Puri::Core::Conversation]
      attr_reader :conversation

      # @param conversation [Puri::Core::Conversation]
      # @param lock [Monitor] the backend's
      # @param threads [ThreadGroup] the backend's, which takes each turn's thread
      # @param think [Float] see {Turn#initialize}
      # @param pace [Float] see {Turn#initialize}
      # @param model [String] one of {Backend::MODELS}
      def initialize(conversation, lock:, threads:, think:, pace:, model:)
        @conversation = conversation
        @lock = lock
        @threads = threads
        @think = think
        @pace = pace
        @turn = nil
        @waiting = []
        @model = model
        @readout = Core::ContextReadout.new(cap: CONTEXT_WINDOW)
        @context = PROMPT_TOKENS
        publish_status
      end

      # @param model [String] one of {Backend::MODELS}
      # @return [void]
      def select_model(model)
        @lock.synchronize do
          @model = model
          publish_status
        end
      end

      # @param text [String]
      # @return [void]
      def ask(text)
        @lock.synchronize do
          @conversation.asked(text)
          if @turn&.confirming?
            @conversation.add(Protocol::UserMessage.new(id: nil, text:))
            @turn.redirect(text)
          elsif @turn
            @waiting << text
          else
            start(text)
          end
        end
      end

      # @return [void]
      def cancel
        @lock.synchronize do
          @waiting.clear
          @turn&.cancel
        end
      end

      # @param confirmation [String]
      # @param approved [Boolean]
      # @return [void]
      def answer(confirmation, approved)
        @lock.synchronize { @turn&.answer(confirmation, approved) }
      end

      # Called by `turn` on its way out: goes idle, or starts the message that waited.
      #
      # @param turn [Puri::Dummy::Turn] the turn {#ask} started
      # @return [void]
      def finish(turn)
        @lock.synchronize do
          next unless @turn.equal?(turn)

          @turn = nil
          spent(turn)
          if @waiting.empty?
            @conversation.activity = Protocol::Activity::IDLE
          else
            start(@waiting.shift)
          end
        end
      end

      private

      # @return [void]
      def publish_status
        @conversation.status = @readout.status(@model)
      end

      # Counts the turn's question and answer, as a server's usage would.
      #
      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def spent(turn)
        input = turn.question.size / 4
        output = turn.written / 4
        @readout.on_event(Pikuri::Agent::Event::Tokens.new(input:, output:, cached: @context, cache_creation: nil,
                                                           thinking: nil, model_id: @model))
        @context += input + output
        publish_status
      end

      # @param text [String]
      # @return [void]
      def start(text)
        @conversation.add(Protocol::UserMessage.new(id: nil, text:))
        turn = Turn.new(self, lock: @lock, think: @think, pace: @pace)
        @turn = turn
        @conversation.activity = Core::TurnListener::THINKING
        @threads.add(Thread.new { turn.run(text) })
      end
    end
  end
end
