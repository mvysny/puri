# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

# Each example loads through `env:` pointed at scratch XDG roots, so the host's ~/.config and
# /etc/xdg never take part.
RSpec.describe Puri::Core::Config do
  # The smallest file that loads; most examples edit it rather than write a whole file.
  let(:minimal) do
    <<~TOML
      [[server]]
      id  = "local"
      url = "http://localhost:8080"

      [[llm]]
      name   = "Local"
      server = "local"
      model  = "qwen"

      [titler]
      llm = "Local"

    TOML
  end

  # @param anchor [String] a line of {#minimal}
  # @param line [String] added after it
  # @return [String]
  def minimal_with(anchor, line) = minimal.sub(anchor, "#{anchor}\n#{line}")

  around do |example|
    Dir.mktmpdir do |home|
      Dir.mktmpdir do |system|
        @home = home
        @system = system
        example.run
      end
    end
  end

  # @param root [String] an XDG config root
  # @param body [String] written verbatim
  # @return [String] the file's path
  def write(root, body)
    path = File.join(root, 'puri', 'config.toml')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    path
  end

  # @return [Hash{String => String}]
  def env = { 'XDG_CONFIG_HOME' => @home, 'XDG_CONFIG_DIRS' => @system }

  # @return [Puri::Core::Config]
  def load = described_class.load(env:)

  # @param fragment [String] a regexp source the error message must match
  # @return [void]
  def assert_rejected(fragment)
    error = assert_raises(described_class::Error) { load }
    assert_match(Regexp.new(fragment), error.message)
  end

  describe 'nothing configured' do
    it 'raises with the path to write and the example to paste, when there is no file' do
      error = assert_raises(described_class::Error) { load }
      assert_includes error.message, 'no config file found'
      assert_includes error.message, File.join(@home, 'puri', 'config.toml')
      assert_includes error.message, described_class::EXAMPLE_CONFIG
    end

    it "never reads pikuri's shared config" do
      FileUtils.mkdir_p(File.join(@home, 'pikuri'))
      File.write(File.join(@home, 'pikuri', 'config.toml'), minimal)
      assert_rejected('no config file found')
    end

    it 'raises the same way for a file with no [[llm]]' do
      write(@home, "[titler]\nllm = \"x\"\n")
      assert_rejected("no \\[\\[llm\\]\\] is defined(?m:.*)#{Regexp.escape(described_class::EXAMPLE_CONFIG)}")
    end

    it 'requires [titler]: there is no default titling connection' do
      write(@home, minimal.sub(/\[titler\]\nllm = "Local"\n/, ''))
      assert_rejected('no \[titler\] names the connection')
    end
  end

  describe 'EXAMPLE_CONFIG' do
    it 'loads: the main model, and the same one with its thinking off writing the titles' do
      write(@home, described_class::EXAMPLE_CONFIG)
      config = load
      assert_equal 'Ornith-1.5', config.primary_llm.model
      assert_equal 'http://localhost:8080', config.primary_llm.server
      assert_equal({ 'chat_template_kwargs' => { 'enable_thinking' => false } }, config.titler_llm.params)
      assert_equal config.primary_llm.model, config.titler_llm.model
    end
  end

  describe 'connections' do
    it "resolves an [[llm]]'s server id into that [[server]]'s URL and key" do
      write(@home, <<~TOML)
        [[server]]
        id      = "grok"
        url     = "https://api.x.ai/v1"
        api_key = "xai-secret"
        max_concurrent_requests = 4

        [[llm]]
        name           = "Grok"
        server         = "grok"
        model          = "grok-4.5"
        context_window = 500000

        [titler]
        llm = "Grok"
      TOML
      File.chmod(0o600, File.join(@home, 'puri', 'config.toml'))
      llm = load.primary_llm
      assert_equal 'https://api.x.ai/v1', llm.server
      assert_equal 'xai-secret', llm.api_key
      assert_equal 500_000, llm.context_window
      assert_equal 4, load.servers.first.max_concurrent_requests
    end

    it 'leaves the optional keys nil, and params empty and frozen' do
      write(@home, minimal)
      llm = load.primary_llm
      assert_nil llm.api_key
      assert_nil llm.context_window
      assert_empty llm.params
      assert_predicate llm.params, :frozen?
    end

    it 'takes the first [[llm]] as the primary and resolves [titler] by name' do
      write(@home, minimal.sub('llm = "Local"', 'llm = "Titles"') + <<~TOML)
        [[llm]]
        name   = "Titles"
        server = "local"
        model  = "qwen"
        params = { chat_template_kwargs = { enable_thinking = false } }
      TOML
      config = load
      assert_equal %w[Local Titles], config.llms.map(&:name)
      assert_equal 'Titles', config.titler_llm.name
      assert_predicate config.titler_llm.params, :frozen?
    end

    it 'keeps a [[server]] no [[llm]] names' do
      write(@home, "#{minimal}[[server]]\nid  = \"spare\"\nurl = \"http://spare:8080\"\n")
      assert_equal %w[local spare], load.servers.map(&:id)
    end
  end

  describe 'layers' do
    it 'lets the user file outrank the system one' do
      write(@system, minimal)
      write(@home, minimal.sub('model  = "qwen"', 'model  = "mine"'))
      assert_equal 'mine', load.primary_llm.model
    end

    it "resolves a user [[llm]] against the system file's [[server]]" do
      write(@system, "[[server]]\nid  = \"shared\"\nurl = \"http://box:8080\"\n")
      write(@home, minimal.sub(/\[\[server\]\].*?\n\n/m, '').gsub('"local"', '"shared"'))
      assert_equal 'http://box:8080', load.primary_llm.server
    end
  end

  describe 'rejected' do
    # @param line [String] a key = value line added to the minimal [[llm]]
    # @return [String]
    def with_llm_line(line) = minimal_with('model  = "qwen"', line)

    # @param line [String] a key = value line added to the minimal [[server]]
    # @return [String]
    def with_server_line(line) = minimal_with('url = "http://localhost:8080"', line)

    it "rejects an unknown top-level key, such as pikuri-web's [web]" do
      write(@home, "#{minimal}[web]\nuser = \"u\"\n")
      assert_rejected('web')
    end

    it 'rejects an api_key on an [[llm]]: it belongs on the [[server]]' do
      write(@home, with_llm_line('api_key = "k"'))
      assert_rejected('api_key')
    end

    it 'rejects a blank llm name' do
      write(@home, minimal.sub('name   = "Local"', 'name   = " "'))
      assert_rejected('name')
    end

    it 'rejects a non-positive context_window' do
      write(@home, with_llm_line('context_window = 0'))
      assert_rejected('context_window')
    end

    it 'rejects params that is not a table' do
      write(@home, with_llm_line('params = "x"'))
      assert_rejected('params')
    end

    it 'rejects a non-positive max_concurrent_requests' do
      write(@home, with_server_line('max_concurrent_requests = 0'))
      assert_rejected('max_concurrent_requests')
    end

    it 'rejects duplicate llm names' do
      write(@home, "#{minimal}[[llm]]\nname   = \"Local\"\nserver = \"local\"\nmodel  = \"other\"\n")
      assert_rejected('llm')
    end

    it 'rejects an [[llm]] on an unknown server, listing the known ids' do
      write(@home, minimal.sub('server = "local"', 'server = "nope"'))
      assert_rejected('no \[\[server\]\] has id "nope"; known: "local"')
    end

    it 'rejects a [titler] naming no [[llm]], listing the names' do
      write(@home, minimal.sub('llm = "Local"', 'llm = "Nope"'))
      assert_rejected('titler.llm: no \[\[llm\]\] is named "Nope"; known: "Local"')
    end

    it 'wraps malformed TOML, naming the file' do
      path = write(@home, "[[llm]\n")
      assert_rejected(Regexp.escape(path))
    end
  end

  describe 'a file holding an api_key' do
    let(:body) { minimal.sub('url = "http://localhost:8080"', "url = \"http://localhost:8080\"\napi_key = \"k\"") }

    it 'warns when others can read it' do
      File.chmod(0o644, write(@home, body))
      assert_output(nil, /chmod 600/) { load }
    end

    it 'stays quiet at 0600' do
      File.chmod(0o600, write(@home, body))
      assert_output(nil, '') { load }
    end
  end
end
