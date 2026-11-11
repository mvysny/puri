# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::UserMessage}: a grey bubble on the right.
    class UserMessageRow < Gtk::Box
      # @param block [Puri::Protocol::UserMessage]
      def initialize(block)
        super(:horizontal, 0)
        @label = Gtk::Label.new
        @label.wrap = true
        @label.wrap_mode = :word_char
        @label.selectable = true
        @label.xalign = 0
        @label.add_css_class('puri-user')
        @label.halign = :end
        @label.hexpand = true
        @label.margin_start = 48
        append(@label)
        self.block = block
      end

      # @param block [Puri::Protocol::UserMessage]
      # @return [void]
      def block=(block)
        @label.text = block.text
      end
    end
  end
end
