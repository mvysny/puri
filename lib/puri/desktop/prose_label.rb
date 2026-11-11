# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Prose} part of a reply: Core's Pango markup in one selectable label.
    class ProseLabel < Gtk::Label
      # @param part [Puri::Protocol::Prose]
      def initialize(part)
        super()
        self.wrap = true
        self.wrap_mode = :word_char
        self.selectable = true
        self.xalign = 0
        add_css_class('puri-reply')
        self.part = part
      end

      # @param part [Puri::Protocol::Prose]
      # @return [void]
      def part=(part)
        self.markup = part.markup unless part.markup == @markup
        @markup = part.markup
      end
    end
  end
end
