# frozen_string_literal: true

module Puri
  module Desktop
    # One conversation's blocks, top to bottom, and the progress row under them while its turn
    # works. Pure view: told what to show, it reaches nothing itself.
    #
    #   view = TranscriptView.new { |id, approved| client.answer(conversation, id, approved) }
    #   view.transcript = client.load_conversation(id)   # or nil to empty it
    #   view.upsert(event.block)                         # BlockChanged
    #   view.remove(event.block)                         # BlockRemoved
    #   view.activity = event.activity                   # ActivityChanged
    #
    # It follows the newest block only while scrolled to the bottom, so scrolling up to re-read
    # survives a streaming reply.
    class TranscriptView < Gtk::ScrolledWindow
      # @return [Hash{Class => Class}] the row for each kind of block
      ROWS = { Protocol::UserMessage => UserMessageRow, Protocol::Reply => ReplyView,
               Protocol::ToolLine => ToolLineRow, Protocol::Confirmation => ConfirmationRow,
               Protocol::Notice => NoticeRow }.freeze

      # @return [Integer] pixels from the bottom that still count as "at the bottom"
      STICKY = 48

      # @return [Puri::Protocol::Activity]
      attr_reader :activity

      # @yieldparam confirmation [String] a {Protocol::Confirmation}'s id
      # @yieldparam approved [Boolean]
      # @yieldreturn [void]
      def initialize(&on_answer)
        super()
        @on_answer = on_answer
        set_policy(:never, :automatic)
        @column = Gtk::Box.new(:vertical, 14)
        @column.add_css_class('puri-transcript')
        clamp = Adw::Clamp.new
        clamp.maximum_size = 760
        clamp.child = @column
        self.child = clamp
        @progress = ProgressRow.new
        @progress.visible = false
        @column.append(@progress)
        @rows = {}
        @blocks = {}
        @activity = Protocol::Activity::IDLE
        follow_the_bottom
      end

      # @param transcript [Puri::Protocol::Transcript, nil]
      # @return [void]
      def transcript=(transcript)
        @rows.each_value { @column.remove(_1) }
        @rows = {}
        @blocks = {}
        transcript&.blocks&.each { upsert(_1) }
        self.activity = transcript&.activity || Protocol::Activity::IDLE
        scroll_to_bottom
      end

      # Replaces the block with the same id, or appends it.
      #
      # @param block [Puri::Protocol::Block]
      # @return [void]
      def upsert(block)
        row = @rows[block.id]
        if row.instance_of?(row_class(block))
          row.block = block
        else
          fresh = new_row(block)
          # The progress row is always last, so a new block goes just before it.
          @column.insert_child_after(fresh, row || @progress.prev_sibling)
          @column.remove(row) if row
          @rows[block.id] = fresh
        end
        @blocks[block.id] = block
      end

      # @param id [String] a block's id; one never shown is ignored
      # @return [void]
      def remove(id)
        row = @rows.delete(id) or return
        @blocks.delete(id)
        @column.remove(row)
      end

      # @param activity [Puri::Protocol::Activity]
      # @return [void]
      def activity=(activity)
        @activity = activity
        @progress.visible = activity.state == 'working'
        @progress.status = activity.status
      end

      # @return [String, nil] the user's latest message here, for Up in the entry
      def last_question
        @blocks.values.reverse_each.find { _1.is_a?(Protocol::UserMessage) }&.text
      end

      # @param id [String] a block's id
      # @return [Gtk::Widget, nil] the row showing it
      def row(id) = @rows[id]

      # @return [Array<Puri::Protocol::Block>] the blocks shown, in order
      def blocks = @blocks.values

      # @return [Boolean] whether nothing is shown
      def empty? = @rows.empty?

      # @return [void]
      def scroll_to_bottom
        @stick = true
        GLib::Idle.add do
          vadjustment.value = vadjustment.upper - vadjustment.page_size
          false
        end
      end

      private

      # @param block [Puri::Protocol::Block]
      # @return [Class]
      def row_class(block) = ROWS.fetch(block.class)

      # @param block [Puri::Protocol::Block]
      # @return [Gtk::Widget]
      def new_row(block)
        block.is_a?(Protocol::Confirmation) ? ConfirmationRow.new(block, &@on_answer) : row_class(block).new(block)
      end

      # @return [void]
      def follow_the_bottom
        @stick = true
        adjustment = vadjustment
        adjustment.signal_connect('value-changed') do
          @stick = adjustment.value >= adjustment.upper - adjustment.page_size - STICKY
        end
        adjustment.signal_connect('notify::upper') do
          adjustment.value = adjustment.upper - adjustment.page_size if @stick
        end
      end
    end
  end
end
