# frozen_string_literal: true

require 'spec_helper'

# docs/, the web page at puri-ai.de: hand-written pages with no site generator, so what they share
# is checked here rather than generated. Read as text, since the markup is regular.
RSpec.describe 'the web page' do
  docs = File.expand_path('../docs', __dir__)
  pages = Dir[File.join(docs, '*.html')].sort.to_h { [File.basename(_1), File.read(_1)] }

  # @param html [String]
  # @param tag [String]
  # @return [String] the page's first such element, whole
  def element(html, tag) = html[%r{<#{tag}[ >].*?</#{tag}>}m] || raise("no <#{tag}>")

  # @param html [String]
  # @return [Array<String>] the text of each command in its terminals, `&amp;` and all
  def commands(html) = html.scan(%r{<span class="cmd">(.*?)</span>}m).flatten

  it 'gives every page the same header and footer' do
    assert_operator pages.size, :>=, 2
    %w[header footer].each do |tag|
      assert_equal 1, pages.values.map { element(_1, tag) }.uniq.size, "the pages' <#{tag}>s differ"
    end
  end

  it 'draws only icons that icons.svg has' do
    ids = File.read(File.join(docs, 'icons.svg')).scan(/<symbol id="([^"]+)"/).flatten
    pages.each do |name, html|
      assert_empty html.scan(/href="icons\.svg#([^"]+)"/).flatten.uniq - ids, "#{name} draws a missing icon"
    end
  end

  it 'links only to anchors that exist' do
    pages.each do |name, html|
      html.scan(%r{href="([a-z]+\.html|\./)?#([^"]+)"}).each do |page, anchor|
        target = { nil => name, './' => 'index.html' }.fetch(page, page)
        assert_includes pages.fetch(target).scan(/ id="([^"]+)"/).flatten, anchor, "#{name} links to #{page}##{anchor}"
      end
    end
  end

  it "shows on the front page only commands the install guide has, so the two can't drift" do
    guide = commands(pages.fetch('install.html'))
    commands(pages.fetch('index.html')).each { assert_includes guide, _1 }
  end
end
