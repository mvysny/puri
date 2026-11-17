# frozen_string_literal: true

module Puri
  module Desktop
    # The messages the agent hasn't read yet, under the transcript: each a dimmed
    # {UserMessageRow}, "Queued" under the last; hidden while none waits.
    #
    #   queued = QueuedMessages.new
    #   queued.texts = ['and bananas?']   # PendingChanged
    #   queued.texts = []                 # the turn read it
    class QueuedMessages < Gtk::Box
      # @return [Array<String>] the texts shown
      attr_reader :texts

      def initialize
        super(:vertical, 4)
        add_css_class('puri-queued')
        @bubbles = Gtk::Box.new(:vertical, 14)
        append(@bubbles)
        caption = Gtk::Label.new('Queued')
        caption.add_css_class('puri-queued-caption')
        caption.halign = :end
        append(caption)
        @texts = []
        self.visible = false
      end

      # @param texts [Array<String>] in the order the agent will read them
      # @return [void]
      def texts=(texts)
        return if texts == @texts

        @texts = texts
        @bubbles.remove(@bubbles.first_child) while @bubbles.first_child
        texts.each { @bubbles.append(UserMessageRow.new(Protocol::UserMessage.new(id: '', text: _1))) }
        self.visible = !texts.empty?
      end
    end
  end
end
