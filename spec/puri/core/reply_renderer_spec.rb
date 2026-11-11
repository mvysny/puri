# frozen_string_literal: true

RSpec.describe Puri::Core::ReplyRenderer do
  p = Puri::Protocol

  # @param markdown [String]
  # @return [String] the one prose part's markup
  def prose(markdown)
    parts = described_class.render(markdown)
    assert_equal [Puri::Protocol::Prose], parts.map(&:class)
    parts.first.markup
  end

  it 'turns paragraphs, emphasis and code spans into Pango markup' do
    assert_equal "Keep it <b>cold</b>, <i>dry</i> and <tt>x</tt>.\n\nThen <s>eat</s> it.",
                 prose("Keep it **cold**, _dry_ and `x`.\n\nThen ~~eat~~ it.")
  end

  it 'escapes every character the model wrote' do
    assert_equal 'x &lt; y &amp; z <tt>&lt;i&gt;</tt>', prose('x < y & z `<i>`')
  end

  it 'keeps the text of raw HTML, but none of its tags' do
    assert_equal 'a <b>bold</b> word and a plain one',
                 prose('a <strong>bold</strong> word and a <span x="y">plain</span> one')
  end

  it 'draws headings bigger, lists with bullets or numbers, nesting indented' do
    heading = '<span size="x-large" weight="bold">Avocados</span>'
    assert_equal "#{heading}\n\n• ripe\n    • soft\n• cheap\n\n1. one\n2. two",
                 prose("# Avocados\n\n- ripe\n  - soft\n- cheap\n\n1. one\n1. two")
  end

  it 'gives code blocks and tables parts of their own, between the prose' do
    parts = described_class.render("Look:\n\n```\nx < y\n```\n\n| A | B |\n|---|---|\n| *x* | 2 |\n| 3 |\n\nDone.")
    assert_equal [p::Prose.new(markup: 'Look:'), p::Code.new(text: 'x < y'),
                  p::Table.new(header: %w[A B], rows: [['<i>x</i>', '2'], ['3', '']]),
                  p::Prose.new(markup: 'Done.')], parts
  end

  it 'never makes a link or an image reach out: link text only, alt text only' do
    assert_equal 'see docs and [chart]', prose('see [docs](https://evil.example/?d=1) and ![chart](https://evil.example/x.png)')
  end

  it "marks a footnote with the model's label and lists the notes at the end, in citing order" do
    rule = Puri::Core::ReplyRenderer::RULE
    assert_equal "Fridges<sup>b</sup> help<sup>a</sup>.\n\nCold<sup>b</sup>.\n\n" \
                 "#{rule}\n<sup>b</sup> USDA, <i>2024</i>.\n<sup>a</sup> FDA.",
                 prose("Fridges[^b] help[^a].\n\nCold[^b].\n\n[^a]: FDA.\n[^b]: USDA, _2024_.\n")
  end

  it 'closes the reply with the notes even after a code block' do
    parts = described_class.render("See[^1]:\n\n```\nx\n```\n\n[^1]: Here.\n")
    assert_equal [p::Prose.new(markup: 'See<sup>1</sup>:'), p::Code.new(text: 'x'),
                  p::Prose.new(markup: "#{Puri::Core::ReplyRenderer::RULE}\n<sup>1</sup> Here.")], parts
  end

  it 'shows unfinished Markdown as it stands, so a stream renders at every word' do
    assert_equal 'half **bol', prose('half **bol')
    assert_empty described_class.render('')
  end
end
