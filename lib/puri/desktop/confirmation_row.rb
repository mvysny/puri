# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Confirmation}: the question in a card with Cancel and the approve button
    # while it is pending, then the outcome in their place.
    #
    #   row = ConfirmationRow.new(block) { |id, approved| client.answer(conversation, id, approved) }
    #
    # The buttons never take focus on their own, so a stray Enter in the entry can't press one.
    class ConfirmationRow < Gtk::Box
      # @return [Hash{String => String}] what an answered one says, by state
      OUTCOMES = { 'approved' => '✓ %s', 'rejected' => 'Cancelled', 'redirected' => 'Changed, see below',
                   'cancelled' => 'Cancelled' }.freeze

      # @return [Gtk::Button]
      attr_reader :approve_button, :cancel_button

      # @param block [Puri::Protocol::Confirmation]
      # @yieldparam confirmation [String] the block's id
      # @yieldparam approved [Boolean]
      # @yieldreturn [void]
      def initialize(block, &on_answer)
        super(:vertical, 10)
        add_css_class('card')
        add_css_class('puri-confirmation')
        @on_answer = on_answer
        @question = Gtk::Label.new
        @question.wrap = true
        @question.xalign = 0
        @question.selectable = true
        @cancel_button = Gtk::Button.new(label: 'Cancel')
        @approve_button = Gtk::Button.new
        [@cancel_button, @approve_button].each { _1.focus_on_click = false }
        @cancel_button.signal_connect('clicked') { answer(false) }
        @approve_button.signal_connect('clicked') { answer(true) }
        @buttons = Gtk::Box.new(:horizontal, 8)
        @buttons.halign = :end
        @buttons.append(@cancel_button)
        @buttons.append(@approve_button)
        @outcome = Gtk::Label.new
        @outcome.xalign = 1
        @outcome.add_css_class('dim-label')
        append(@question)
        append(@buttons)
        append(@outcome)
        self.block = block
      end

      # @param block [Puri::Protocol::Confirmation]
      # @return [void]
      def block=(block)
        @block = block
        @question.text = block.question
        @approve_button.label = block.approve_label
        @approve_button.remove_css_class('destructive-action')
        @approve_button.remove_css_class('suggested-action')
        @approve_button.add_css_class(block.destructive ? 'destructive-action' : 'suggested-action')
        @buttons.visible = block.pending?
        @outcome.visible = !block.pending?
        @outcome.text = format(OUTCOMES.fetch(block.state, block.state), block.approve_label)
      end

      private

      # @param approved [Boolean]
      # @return [void]
      def answer(approved)
        @buttons.sensitive = false
        @on_answer&.call(@block.id, approved)
      end
    end
  end
end
