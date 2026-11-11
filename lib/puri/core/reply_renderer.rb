# frozen_string_literal: true

require 'cgi'
require 'kramdown'
require 'kramdown-parser-gfm'

module Puri
  module Core
    # The model's Markdown as {Protocol::Reply} parts: prose as Pango markup, code blocks and
    # tables as parts of their own. pikuri-web's MarkdownRenderer with Pango for HTML.
    #
    #   ReplyRenderer.render("Keep it **cold**:\n\n- fridge\n- freezer")
    #   # => [Prose(markup: "Keep it <b>cold</b>:\n\n• fridge\n• freezer")]
    #
    # Streaming re-renders the whole source per delta, so a closing fence or a widening table
    # reformats what came before. Unfinished Markdown (`**bol`) renders as the literal text.
    #
    # Links are plain text and images only their alt text: a model-chosen URL is egress
    # (`design/ideas/trifecta-and-tools.md`, *Links in the reply*).
    module ReplyRenderer
      # @return [Hash{Symbol => Object}] GFM input; LLM paragraphs reflow, so no hard wraps
      OPTIONS = { input: 'GFM', hard_wrap: false, smart_quotes: %w[lsquo rsquo ldquo rdquo] }.freeze

      # @return [Hash{Symbol => String}] kramdown's typographic symbols
      SYMBOLS = { hellip: '…', mdash: '—', ndash: '–', laquo: '«', raquo: '»',
                  laquo_space: '« ', raquo_space: ' »' }.freeze

      # @return [Hash{Symbol => String}]
      QUOTES = { lsquo: '‘', rsquo: '’', ldquo: '“', rdquo: '”' }.freeze

      module_function

      # @param markdown [String]
      # @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>]
      def render(markdown)
        root = Kramdown::Document.new(markdown.to_s, **OPTIONS).root
        parts = []
        prose = []
        flush = lambda do
          parts << Protocol::Prose.new(markup: prose.join("\n\n")) unless prose.empty?
          prose = []
        end
        root.children.each do |node|
          case node.type
          when :codeblock
            flush.call
            parts << Protocol::Code.new(text: node.value.to_s.chomp)
          when :table
            flush.call
            parts << table(node)
          when :blank then nil
          else
            markup = block(node, 0)
            prose << markup unless markup.empty?
          end
        end
        flush.call
        parts
      end

      # @param node [Kramdown::Element] a block-level element
      # @param depth [Integer] list nesting
      # @return [String] Pango markup
      def block(node, depth)
        case node.type
        when :p then inline(node).rstrip
        when :header then heading(node)
        when :ul, :ol then list(node, depth)
        when :blockquote
          node.children.map { block(_1, depth) }.reject(&:empty?).map { "<i>▎ #{_1}</i>" }.join("\n")
        when :codeblock then "<tt>#{escape(node.value.to_s.chomp)}</tt>"
        when :hr then '<span alpha="40%">―――</span>'
        when :blank then ''
        when :table then table(node).rows.map { _1.join(' · ') }.join("\n")
        else inline(node)
        end
      end

      # @param node [Kramdown::Element] a `:header`
      # @return [String]
      def heading(node)
        size = { 1 => 'x-large', 2 => 'large' }.fetch(node.options[:level], 'medium')
        %(<span size="#{size}" weight="bold">#{inline(node)}</span>)
      end

      # @param node [Kramdown::Element] a `:ul` or `:ol`
      # @param depth [Integer]
      # @return [String]
      def list(node, depth)
        start = node.options.fetch(:first_list_number, 1) || 1
        node.children.select { _1.type == :li }.each_with_index.map do |li, i|
          bullet = node.type == :ol ? "#{start + i}." : '•'
          # A nested list renders its own indent, so it just takes the next line.
          body = li.children.reject { _1.type == :blank }.map { block(_1, depth + 1) }
          "#{'    ' * depth}#{bullet} #{body.join("\n")}"
        end.join("\n")
      end

      # @param node [Kramdown::Element] a `:table`
      # @return [Puri::Protocol::Table]
      def table(node)
        rows = node.children.flat_map(&:children).select { _1.type == :tr }
        cells = rows.map { |tr| tr.children.map { inline(_1) } }
        header, *body = cells
        width = cells.map(&:size).max || 0
        pad = ->(row) { row + ([''] * (width - row.size)) }
        Protocol::Table.new(header: pad.call(header || []), rows: body.map(&pad))
      end

      # @param node [Kramdown::Element]
      # @return [String] its children as Pango markup
      def inline(node)
        node.children.map { span(_1) }.join
      end

      # @param node [Kramdown::Element] a span-level element
      # @return [String]
      def span(node)
        case node.type
        when :text then escape(node.value)
        when :strong then "<b>#{inline(node)}</b>"
        when :em then "<i>#{inline(node)}</i>"
        when :codespan then "<tt>#{escape(node.value)}</tt>"
        when :del then "<s>#{inline(node)}</s>"
        when :br then "\n"
        when :a then inline(node)
        when :img then node.attr['alt'].to_s.empty? ? '' : "[#{escape(node.attr['alt'])}]"
        when :smart_quote then QUOTES.fetch(node.value, '"')
        when :typographic_sym then SYMBOLS.fetch(node.value, '')
        when :entity then escape(node.value.char)
        when :html_element then html(node)
        when :xml_comment then ''
        else node.children.empty? ? escape(node.value.to_s) : inline(node)
        end
      end

      # @return [Hash{String => String}] the HTML tags kept, as their Pango twin
      HTML = { 'b' => 'b', 'strong' => 'b', 'i' => 'i', 'em' => 'i', 'del' => 's', 's' => 's',
               'code' => 'tt', 'u' => 'u', 'sub' => 'sub', 'sup' => 'sup' }.freeze

      # Raw HTML keeps its text; a formatting tag becomes its Pango twin, any other is dropped.
      # GFM's `~~strike~~` arrives this way too, as a `del` element.
      #
      # @param node [Kramdown::Element] an `:html_element`
      # @return [String]
      def html(node)
        tag = HTML[node.value.to_s.downcase]
        tag ? "<#{tag}>#{inline(node)}</#{tag}>" : inline(node)
      end

      # @param text [String]
      # @return [String] safe inside Pango markup
      def escape(text) = CGI.escapeHTML(text.to_s)
    end
  end
end
