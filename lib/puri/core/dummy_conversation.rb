# frozen_string_literal: true

require 'time'

module Puri
  module Core
    # One conversation of {DummyCore}: its blocks, its activity and its running {DummyTurn}.
    # Every change is emitted as the {Protocol} event a real Core would send.
    #
    #   conversation.ask('reschedule my dentist in the calendar')   # starts a turn
    #   conversation.ask('make it Wednesday')    # a confirmation waits: redirects it
    #   conversation.cancel
    #
    # A message sent while a turn runs, but asks nothing, waits for that turn to end.
    #
    # Thread-safe: every method runs under the monitor {DummyCore} shares with it.
    class DummyConversation
      # @return [String]
      attr_reader :id

      # @param id [String]
      # @param lock [Monitor] {DummyCore}'s
      # @param emit [Proc] takes a {Protocol} event
      # @param changed [Proc] called when {#summary} changed
      # @param threads [ThreadGroup] {DummyCore}'s, which takes each turn's thread
      # @param think [Float] see {DummyTurn#initialize}
      # @param pace [Float] see {DummyTurn#initialize}
      # @param started_at [Time]
      def initialize(id:, lock:, emit:, changed:, threads:, think:, pace:, started_at: Time.now)
        @id = id
        @lock = lock
        @emit = emit
        @changed = changed
        @threads = threads
        @think = think
        @pace = pace
        @started_at = started_at
        @title = 'New conversation'
        @blocks = {}
        @next_block = 0
        @activity = Protocol::Activity::IDLE
        @turn = nil
        @waiting = []
        @last_question = nil
        @asked_at = nil
      end

      # @return [Time]
      attr_reader :started_at

      # @param text [String]
      # @return [void]
      def ask(text)
        @lock.synchronize do
          @last_question = text
          @asked_at = Time.now
          if @turn&.confirming?
            add(Protocol::UserMessage.new(id: nil, text:))
            @turn.redirect(text)
          elsif @turn
            @waiting << text
          else
            start(text)
          end
          @changed.call
        end
      end

      # Fills in an exchange that happened before Core started, as a saved history would.
      #
      # @param question [String]
      # @param parts [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>] the answer
      # @return [void]
      def restore(question, parts)
        @lock.synchronize do
          add(Protocol::UserMessage.new(id: nil, text: question))
          add(Protocol::Reply.new(id: nil, parts:))
          @last_question = question
          @asked_at = @started_at
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

      # @param title [String]
      # @return [void]
      def title=(title)
        @lock.synchronize do
          @title = title
          @changed.call
        end
      end

      # @return [Puri::Protocol::ConversationSummary]
      def summary
        @lock.synchronize do
          Protocol::ConversationSummary.new(id:, title: @title, started_at: @started_at.iso8601,
                                            running: @activity.running?, last_question: @last_question,
                                            asked_at: @asked_at&.iso8601)
        end
      end

      # @return [Puri::Protocol::Transcript]
      def transcript
        @lock.synchronize do
          Protocol::Transcript.new(conversation: id, title: @title, blocks: @blocks.values, activity: @activity)
        end
      end

      # Appends a block, giving it the next id.
      #
      # @param block [Puri::Protocol::Block] its id nil
      # @return [Puri::Protocol::Block] the block as stored, id set
      def add(block)
        @lock.synchronize do
          @next_block += 1
          put(block.with(id: "b#{@next_block}"))
        end
      end

      # Replaces the block with this id, or appends it.
      #
      # @param block [Puri::Protocol::Block]
      # @return [Puri::Protocol::Block]
      def put(block)
        @lock.synchronize do
          @blocks[block.id] = block
          @emit.call(Protocol::BlockChanged.new(conversation: id, block:))
          block
        end
      end

      # @param activity [Puri::Protocol::Activity]
      # @return [void]
      def activity=(activity)
        @lock.synchronize do
          was_running = @activity.running?
          @activity = activity
          @emit.call(Protocol::ActivityChanged.new(conversation: id, activity:))
          @changed.call if was_running != activity.running?
        end
      end

      # Called by `turn` on its way out: goes idle, or starts the message that waited.
      #
      # @param turn [Puri::Core::DummyTurn]
      # @return [void]
      def finish(turn)
        @lock.synchronize do
          next unless @turn.equal?(turn)

          @turn = nil
          if @waiting.empty?
            self.activity = Protocol::Activity::IDLE
          else
            start(@waiting.shift)
          end
        end
      end

      private

      # @param text [String]
      # @return [void]
      def start(text)
        add(Protocol::UserMessage.new(id: nil, text:))
        turn = DummyTurn.new(self, lock: @lock, think: @think, pace: @pace)
        @turn = turn
        self.activity = Protocol::Activity.new(state: 'working', status: 'Thinking…')
        @threads.add(Thread.new { turn.run(text) })
      end
    end
  end
end
