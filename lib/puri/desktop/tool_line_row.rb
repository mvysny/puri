# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::ToolLine}: one dimmed line, red when the step failed.
    class ToolLineRow < Gtk::Label
      # @param block [Puri::Protocol::ToolLine]
      def initialize(block)
        super()
        self.xalign = 0
        self.wrap = true
        self.wrap_mode = :word_char
        self.selectable = true
        add_css_class('puri-tool')
        self.block = block
      end

      # @param block [Puri::Protocol::ToolLine]
      # @return [void]
      def block=(block)
        self.text = block.text
        block.error ? add_css_class('error') : remove_css_class('error')
        block.error ? remove_css_class('dim-label') : add_css_class('dim-label')
      end
    end
  end
end
