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
    # A message sent while a turn runs, but asks nothing, waits for that turn to end.
    #
    # Thread-safe: every method runs under the backend's monitor.
    class Session
      # @return [Puri::Core::Conversation]
      attr_reader :conversation

      # @param conversation [Puri::Core::Conversation]
      # @param lock [Monitor] the backend's
      # @param threads [ThreadGroup] the backend's, which takes each turn's thread
      # @param think [Float] see {Turn#initialize}
      # @param pace [Float] see {Turn#initialize}
      def initialize(conversation, lock:, threads:, think:, pace:)
        @conversation = conversation
        @lock = lock
        @threads = threads
        @think = think
        @pace = pace
        @turn = nil
        @waiting = []
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
          if @waiting.empty?
            @conversation.activity = Protocol::Activity::IDLE
          else
            start(@waiting.shift)
          end
        end
      end

      private

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
