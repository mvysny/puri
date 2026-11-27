# frozen_string_literal: true

require 'spec_helper'
require 'cgi'
require 'fileutils'
require 'tmpdir'
require 'tomlrb'

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

  it 'gives every page the same header and footer, but for which page the menu marks' do
    assert_operator pages.size, :>=, 2
    %w[header footer].each do |tag|
      shared = pages.values.map { element(_1, tag).sub(' aria-current="page"', '') }
      assert_equal 1, shared.uniq.size, "the pages' <#{tag}>s differ"
    end
  end

  it "lists every page in the header's menu, and marks the one it's on" do
    pages.each do |name, html|
      menu = html[%r{<nav class="menu".*?</nav>}m]
      hrefs = menu.scan(/<a href="([^"]+)"/).flatten.map { _1 == './' ? 'index.html' : _1 }
      assert_equal pages.keys, hrefs.sort, "#{name}'s menu"
      current = menu.scan(/<a href="([^"]+)" aria-current="page"/).flatten
      assert_equal [name == 'index.html' ? './' : name], current, "#{name}'s menu marks another page"
    end
  end

  it 'names on tools.html every tool Puri wires, each with the line its call shows' do
    page = pages.fetch('tools.html').gsub('<wbr>', '')
    rows = page.scan(%r{<td><code>([a-z_]+)</code><span class="shows">(.*?)</span></td>})
    wordings = Puri::Core::ToolWording::WORDINGS
    assert_equal (wordings.keys + %w[web_search web_read_cached]).sort, rows.map(&:first).sort
    rows.each do |name, shows|
      assert_equal wordings[name].line, CGI.unescapeHTML(shows), name if wordings.key?(name)
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

  it 'shows config fragments that are valid TOML' do
    fragments = pages.values.flat_map { _1.scan(%r{<pre class="file toml">(.*?)</pre>}m).flatten }
    refute_empty fragments
    fragments.each { Tomlrb.parse(CGI.unescapeHTML(_1)) }
  end

  it "loads models.html's Ornith tables, put in place of the config's Qwen ones as the page says" do
    ornith = CGI.unescapeHTML(pages.fetch('models.html')[%r{<pre class="file toml">(\[\[llm\]\].*?)</pre>}m, 1])
    qwen = /^\[\[llm\]\].*?^llm = "Qwen 3.5 4B, no thinking"\n/m
    config = File.read(Puri::Core::Config::EXAMPLE).sub(qwen, "#{ornith}\n")
    Dir.mktmpdir do |home|
      FileUtils.mkdir_p([File.join(home, 'puri'), File.join(home, 'Documents')])
      File.write(File.join(home, 'puri', 'config.toml'), config)
      loaded = Puri::Core::Config.load(env: { 'XDG_CONFIG_HOME' => home, 'XDG_CONFIG_DIRS' => File.join(home, 'none'),
                                              'HOME' => home })
      assert_equal ['Ornith 1.5', 'Ornith 1.5, no thinking'], loaded.llms.map(&:name)
      assert_equal 'Ornith 1.5, no thinking', loaded.titler_llm.name
    end
  end

  it "has the install guide's apt line install what bin/setup checks for" do
    line = commands(pages.fetch('install.html')).find { _1.start_with?('sudo apt install git ') }
    assert_equal Puri::Setup::Packages::LIST.sort, line.split.reject { _1 == '\\' }.drop(3).sort
  end

  it "shows on the front page only commands the install guide has, so the two can't drift" do
    guide = commands(pages.fetch('install.html'))
    commands(pages.fetch('index.html')).each { assert_includes guide, _1 }
  end
end
