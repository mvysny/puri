# frozen_string_literal: true

module Puri
  module Desktop
    # A {Protocol::Reply}: its parts top to bottom. A streamed reply arrives whole again with
    # every delta; a part that keeps its kind keeps its widget, so the update is in place and a
    # selection in an earlier part survives.
    class ReplyView < Gtk::Box
      # @return [Hash{Class => Class}] the widget for each kind of part
      WIDGETS = { Protocol::Prose => ProseLabel, Protocol::Code => CodeBlock, Protocol::Table => ReplyTable }.freeze

      # @param block [Puri::Protocol::Reply]
      def initialize(block)
        super(:vertical, 12)
        @widgets = []
        self.block = block
      end

      # @param block [Puri::Protocol::Reply]
      # @return [void]
      def block=(block)
        block.parts.each_with_index do |part, i|
          widget_class = WIDGETS.fetch(part.class)
          if @widgets[i].instance_of?(widget_class)
            @widgets[i].part = part
          else
            replace(i, widget_class.new(part))
          end
        end
        remove(@widgets.pop) while @widgets.size > block.parts.size
      end

      private

      # @param index [Integer]
      # @param widget [Gtk::Widget]
      # @return [void]
      def replace(index, widget)
        old = @widgets[index]
        if old
          insert_child_after(widget, old)
          remove(old)
        else
          append(widget)
        end
        @widgets[index] = widget
      end
    end
  end
end
