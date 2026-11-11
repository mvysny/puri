# frozen_string_literal: true

require 'streaming_markdown_parser'

module Puri
  module Core
    # A reply's Markdown as it streams in, as {Protocol::Reply} parts: each finished block is
    # converted once, and only the open tail again per delta.
    #
    #   stream = ReplyStream.new
    #   stream.append("Keep it **cold**.\n\nOr fre")   # => [Prose("Keep it <b>cold</b>."), Prose("Or fre")]
    #   stream.append("eze it.\n")                     # => [Prose("Keep it <b>cold</b>."), Prose("Or freeze it.")]
    #   stream.finish                                   # => [Prose("Keep it <b>cold</b>.\n\nOr freeze it.")]
    #
    # {#finish} equals {ReplyRenderer.render} of the whole text; until then, {ReplyRenderer.merge}
    # of the parts equals it for the text so far.
    #
    # == Implementation details
    #
    # The open tail stays its own part rather than merging into the finished prose before it:
    # Desktop lays out a changed part whole, at ~4 ms per KB on the main loop, so a merged run
    # would grow per delta until it stalls the UI (`D_whole_reply`). A selection reaches across the
    # tail only once the reply is finished.
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
        ReplyRenderer.merge(@done + @open)
      end

      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def parts = ReplyRenderer.merge(@done) + @open

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
