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
    # {#finish} is {ReplyRenderer.render} of the whole text; until then, {ReplyRenderer.merge} of
    # the parts equals it for the text so far, except that a reference link or footnote whose
    # definition is a block away stays literal (the gem's README, *When is a block finished?*),
    # and the footnotes' text waits for the end ({ReplyRenderer.footnotes}).
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
        @text = +''
        @done = []
        @open = []
      end

      # @param delta [String]
      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def append(delta)
        @text << delta.to_s
        @parser.append(delta)
        parts
      end

      # Renders the whole reply once more, as only the whole text resolves every reference.
      #
      # @param final [String, nil] the reply's final text, nil for the deltas as they came
      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def finish(final = nil)
        ReplyRenderer.render(final || @text)
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
    end
  end
end
