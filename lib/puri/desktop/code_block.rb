# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Code} part of a reply: monospace on a tinted background, scrolling sideways
    # rather than wrapping.
    class CodeBlock < Gtk::ScrolledWindow
      # @param part [Puri::Protocol::Code]
      def initialize(part)
        super()
        set_policy(:automatic, :never)
        add_css_class('puri-code')
        @label = Gtk::Label.new
        @label.selectable = true
        @label.xalign = 0
        self.child = @label
        self.part = part
      end

      # @param part [Puri::Protocol::Code]
      # @return [void]
      def part=(part)
        @label.text = part.text
      end
    end
  end
end
