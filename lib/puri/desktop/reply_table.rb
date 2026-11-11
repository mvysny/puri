# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Table} part of a reply: a grid of selectable cells, the header row bold.
    class ReplyTable < Gtk::Grid
      # @param part [Puri::Protocol::Table]
      def initialize(part)
        super()
        add_css_class('puri-table')
        self.halign = :start
        self.overflow = :hidden
        self.part = part
      end

      # @param part [Puri::Protocol::Table]
      # @return [void]
      def part=(part)
        return if part == @part

        @part = part
        while (child = first_child)
          remove(child)
        end
        [part.header, *part.rows].each_with_index do |row, y|
          row.each_with_index { |markup, x| attach(cell(markup, header: y.zero?), x, y, 1, 1) }
        end
      end

      private

      # @param markup [String]
      # @param header [Boolean]
      # @return [Gtk::Label]
      def cell(markup, header:)
        label = Gtk::Label.new
        label.markup = markup
        label.xalign = 0
        label.wrap = true
        label.selectable = true
        label.add_css_class('header') if header
        label
      end
    end
  end
end
