# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Table} part of a reply: a grid of selectable cells, the header row bold,
    # scrolling sideways when it is wider than the reply.
    #
    # == Implementation details
    #
    # Cells never wrap. A wrapping label makes the grid height-for-width, and a streaming table
    # then gets measured against the height of its previous, shorter self: GTK warns "Trying to
    # measure GtkGrid for height of 58, but it needs at least 76" on every delta.
    class ReplyTable < Gtk::ScrolledWindow
      # @return [Gtk::Grid] the cells
      attr_reader :grid

      # @param part [Puri::Protocol::Table]
      def initialize(part)
        super()
        set_policy(:automatic, :never)
        self.halign = :start
        self.propagate_natural_width = true
        @grid = Gtk::Grid.new
        @grid.add_css_class('puri-table')
        @grid.overflow = :hidden
        self.child = @grid
        self.part = part
      end

      # @param part [Puri::Protocol::Table]
      # @return [void]
      def part=(part)
        return if part == @part

        @part = part
        while (child = @grid.first_child)
          @grid.remove(child)
        end
        [part.header, *part.rows].each_with_index do |row, y|
          row.each_with_index { |markup, x| @grid.attach(cell(markup, header: y.zero?), x, y, 1, 1) }
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
        label.selectable = true
        label.add_css_class('header') if header
        label
      end
    end
  end
end
