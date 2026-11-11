# frozen_string_literal: true

require 'streaming_markdown_parser'

module Puri
  module Core
    # A reply's Markdown as it streams in, as {Protocol::Reply} parts: each finished block is
    # converted once, and only the open tail again per delta.
    #
    #   stream = ReplyStream.new
    #   stream.append("Keep it **cold**.\n\nOr fre")   # => [Prose("Keep it <b>cold</b>.\n\nOr fre")]
    #   stream.append("eze it.\n")                     # => [Prose("Keep it <b>cold</b>.\n\nOr freeze it.")]
    #   stream.finish                                   # => the same parts, all final
    #
    # The parts always equal {ReplyRenderer.render} of the text so far.
    class ReplyStream
      include StreamingMarkdownParser::Listener

      def initialize
        @parser = StreamingMarkdownParser.new(self, **ReplyRenderer::OPTIONS)
        @done = []
        @open = []
      end

      # @param delta [String]
      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def append(delta)
        @parser.append(delta)
        parts
      end

      # @param final [String, nil] the reply's final text, nil for the deltas as they came
      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def finish(final = nil)
        @parser.finish(final)
        parts
      end

      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def parts = ReplyRenderer.merge(@done + @open)

      # @param root [Kramdown::Element]
      # @return [void]
      def on_block(root) = @done.concat(ReplyRenderer.parts(root))

      # @param root [Kramdown::Element]
      # @return [void]
      def on_open(root)
        @open = ReplyRenderer.parts(root)
      end

      # @return [void]
      def on_reset = @done.clear
    end
  end
end
