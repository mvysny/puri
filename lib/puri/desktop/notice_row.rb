# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Notice}: Puri's own line, dimmed, or red for a failure.
    class NoticeRow < Gtk::Label
      # @param block [Puri::Protocol::Notice]
      def initialize(block)
        super()
        self.xalign = 0
        self.wrap = true
        self.wrap_mode = :word_char
        self.selectable = true
        add_css_class('puri-notice')
        self.block = block
      end

      # @param block [Puri::Protocol::Notice]
      # @return [void]
      def block=(block)
        self.text = block.text
        block.error ? add_css_class('error') : remove_css_class('error')
        block.error ? remove_css_class('dim-label') : add_css_class('dim-label')
      end
    end
  end
end
