# frozen_string_literal: true

require 'time'

module Puri
  module Core
    # One conversation: its blocks, its activity, its title and its running turn. Every change
    # is emitted as a {Protocol} event. What a turn *does* is the `turns` strategy's, so
    # {PikuriCore} and the dummy backend in `dev/` share everything else:
    #
    #   conversation = Conversation.new(id:, lock:, emit:, changed:, threads:, turns: agent_session)
    #   conversation.ask('reschedule my dentist in the calendar')   # starts a turn
    #   conversation.ask('make it Wednesday')    # a confirmation waits: redirects it
    #   conversation.cancel
    #
    # A message sent while a turn runs, but asks nothing, waits for that turn to end.
    #
    # A turn is any object with `run(text)`, which runs on a thread of its own and ends by
    # calling {#finish}; `cancel`, `answer(confirmation, approved)`, `redirect(text)` and
    # `confirming?`, called from any thread. It reports through {#add}, {#put} and {#activity=}.
    #
    # == Threading
    #
    # Thread-safe: every method runs under the monitor its core shares with it. A turn's thread
    # runs at priority −3, so a burst of Ruby on it stalls the GTK main loop by ~25 ms at most
    # rather than a whole 100 ms time slice (`R_gvl_main_loop`).
    class Conversation
      # @return [String]
      attr_reader :id

      # @param id [String]
      # @param lock [Monitor] the core's
      # @param emit [Proc] takes a {Protocol} event
      # @param changed [Proc] called when {#summary} changed
      # @param threads [ThreadGroup] the core's, which takes each turn's thread
      # @param turns [#call] takes this conversation, returns a new turn (see the class doc)
      # @param started_at [Time]
      # @param title [String]
      # @param last_question [String, nil]
      # @param asked_at [Time, nil] when `last_question` was asked
      def initialize(id:, lock:, emit:, changed:, threads:, turns:, started_at: Time.now,
                     title: 'New conversation', last_question: nil, asked_at: nil)
        @id = id
        @lock = lock
        @emit = emit
        @changed = changed
        @threads = threads
        @turns = turns
        @started_at = started_at
        @title = title
        @blocks = {}
        @next_block = 0
        @activity = Protocol::Activity::IDLE
        @turn = nil
        @waiting = []
        @last_question = last_question
        @asked_at = asked_at
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

      # Fills in blocks from before Core started, giving each the next id; emits nothing, since
      # whoever shows this conversation loads it after.
      #
      # @param blocks [Array<Puri::Protocol::Block>] their ids nil
      # @return [void]
      def restore(blocks)
        @lock.synchronize do
          blocks.each do |block|
            @next_block += 1
            block = block.with(id: "b#{@next_block}")
            @blocks[block.id] = block
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
      # @param turn [Object] the turn {#ask} started
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
        turn = @turns.call(self)
        @turn = turn
        self.activity = Protocol::Activity.new(state: 'working', status: 'Thinking…')
        @threads.add(Thread.new do
          Thread.current.priority = -3
          turn.run(text)
        end)
      end
    end
  end
end
