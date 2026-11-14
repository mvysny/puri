# frozen_string_literal: true

require 'time'

module Puri
  module Core
    # One conversation as Desktop sees it: its blocks, its activity, its title and its last
    # question, each change emitted as a {Protocol} event. Whatever runs its turns reports
    # through {#add}, {#put} and {#activity=}, so {PikuriCore} and the dummy backend in `dev/`
    # share it:
    #
    #   conversation = Conversation.new(id:, lock:, emit:, changed:)
    #   conversation.asked('how do I keep an avocado?')     # the question, for the history row
    #   reply = conversation.add(Protocol::Reply.new(id: nil, parts: []))   # => the block, id "b1"
    #   conversation.put(reply.with(parts:))                 # re-sent whole
    #   conversation.activity = Protocol::Activity::IDLE
    #
    # == Threading
    #
    # Thread-safe: every method runs under the monitor its core shares with it.
    class Conversation
      # What a conversation is called until it has been titled.
      #
      # @return [String]
      NEW_TITLE = 'New conversation'

      # @return [String]
      attr_reader :id

      # @param id [String]
      # @param lock [Monitor] the core's
      # @param emit [Proc] takes a {Protocol} event
      # @param changed [Proc] called when {#summary} changed
      # @param started_at [Time]
      # @param title [String]
      # @param last_question [String, nil]
      # @param asked_at [Time, nil] when `last_question` was asked
      def initialize(id:, lock:, emit:, changed:, started_at: Time.now, title: NEW_TITLE, last_question: nil,
                     asked_at: nil)
        @id = id
        @lock = lock
        @emit = emit
        @changed = changed
        @started_at = started_at
        @title = title
        @blocks = {}
        @next_block = 0
        @activity = Protocol::Activity::IDLE
        @last_question = last_question
        @asked_at = asked_at
      end

      # @return [Time]
      attr_reader :started_at

      # Records the user's latest question, which the history shows under the title.
      #
      # @param text [String]
      # @return [void]
      def asked(text)
        @lock.synchronize do
          @last_question = text
          @asked_at = Time.now
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

      # @param title [String]
      # @return [void]
      def title=(title)
        @lock.synchronize do
          @title = title
          @changed.call
        end
      end

      # @return [Boolean] whether a turn runs
      def running? = @lock.synchronize { @activity.running? }

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
    end
  end
end
