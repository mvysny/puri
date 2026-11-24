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
        Dir.mktmpdir do |user|
          @home = home
          @system = system
          @user = user
          example.run
        end
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

  # @return [Hash{String => String}] `HOME` is a scratch one too, for the Documents folder
  def env = { 'XDG_CONFIG_HOME' => @home, 'XDG_CONFIG_DIRS' => @system, 'HOME' => @user }

  # @return [Puri::Core::Config]
  def load = described_class.load(env:)

  # Writes {Puri::Core::Config::EXAMPLE} as shipped, and the scratch home's Documents folder it
  # reads.
  #
  # @return [String] that folder
  def write_example
    write(@home, File.read(described_class::EXAMPLE))
    File.join(@user, 'Documents').tap { FileUtils.mkdir_p(_1) }
  end

  # @param fragment [String] a regexp source the error message must match
  # @return [void]
  def assert_rejected(fragment)
    error = assert_raises(described_class::Error) { load }
    assert_match(Regexp.new(fragment), error.message)
  end

  describe 'nothing configured' do
    it 'raises with the commands that copy the example where Puri reads it, when there is no file' do
      error = assert_raises(described_class::Error) { load }
      assert_includes error.message, 'no config file found'
      assert_includes error.message, "cp #{described_class::EXAMPLE} #{File.join(@home, 'puri', 'config.toml')}"
    end

    it "never reads pikuri's shared config" do
      FileUtils.mkdir_p(File.join(@home, 'pikuri'))
      File.write(File.join(@home, 'pikuri', 'config.toml'), minimal)
      assert_rejected('no config file found')
    end

    it 'points at the example for a file with no [[llm]]' do
      write(@home, "[titler]\nllm = \"x\"\n")
      assert_rejected("no \\[\\[llm\\]\\] is defined; #{Regexp.escape(described_class::EXAMPLE)}")
    end

    it 'requires [titler]: there is no default titling connection' do
      write(@home, minimal.sub(/\[titler\]\nllm = "Local"\n/, ''))
      assert_rejected('no \[titler\] names the connection')
    end
  end

  describe 'EXAMPLE, the config the install guide copies' do
    it 'loads: the main model, the same one with its thinking off writing the titles' do
      write_example
      config = load
      assert_equal 'ggml-org/Qwen3.5-4B-GGUF:Q4_K_M', config.primary_llm.model
      assert_equal 'http://localhost:8080', config.primary_llm.server
      assert_equal({ 'enable_thinking' => true }, config.primary_llm.params['chat_template_kwargs'])
      assert_equal({ 'enable_thinking' => false }, config.titler_llm.params['chat_template_kwargs'])
      assert_in_delta 0.7, config.titler_llm.params['temperature']
      assert_equal config.primary_llm.model, config.titler_llm.model
    end

    it 'turns every feature on but web search, which waits for a key' do
      docs = write_example
      config = load
      assert_nil config.search
      assert_nil config.thunderbird.profile_dir
      assert_equal docs, config.documents.folder
      assert_equal 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', config.maps.tiles
      assert_equal Puri::Core::Weather::OpenMeteo::URL, config.weather.url
      assert_equal 'http://127.0.0.1:8081', config.dictation.url
    end
  end

  describe '[search]' do
    # @param body [String] the [search] table's lines
    # @return [void] the file written at 0600, as a file with a key should be
    def with_search(body) = File.chmod(0o600, write(@home, "#{minimal}[search]\n#{body}\n"))

    it 'is nil when absent' do
      write(@home, minimal)
      assert_nil load.search
    end

    it 'takes a Brave key, every keyed engine searched' do
      with_search('brave_key = "B"')
      assert_equal described_class::SearchTable.new(brave_key: 'B'), load.search
    end

    it 'takes an engine list naming engines with keys' do
      with_search(%(brave_key = "B"\nexa_key = "E"\nengines = ["exa"]))
      assert_equal %w[exa], load.search.engines
    end

    it 'is nil with neither key, whatever it names' do
      with_search(%(engines = ["brave"]\nbrave_key = " "))
      assert_nil load.search
    end

    it 'rejects duckduckgo: it returns no page text' do
      with_search(%(brave_key = "B"\nengines = ["brave", "duckduckgo"]))
      assert_rejected('duckduckgo returns no page text')
    end

    it 'rejects an engine named without its key' do
      with_search(%(brave_key = "B"\nengines = ["exa"]))
      assert_rejected('exa')
    end

    it 'rejects an unknown engine' do
      with_search(%(brave_key = "B"\nengines = ["bing"]))
      assert_rejected('unknown engine.*bing')
    end

    it 'rejects an unknown key' do
      with_search(%(brave_key = "B"\nconfirm = false))
      assert_rejected('confirm')
    end
  end

  describe '[thunderbird]' do
    it 'discovers the profile when absent' do
      write(@home, minimal)
      assert_equal described_class::ThunderbirdTable.new, load.thunderbird
    end

    it 'takes a profile directory, ~ expanded' do
      write(@home, %(#{minimal}[thunderbird]\nprofile_dir = "~/tb/x"\n))
      assert_equal File.expand_path('~/tb/x'), load.thunderbird.profile_dir
    end

    it 'is nil when switched off' do
      write(@home, "#{minimal}[thunderbird]\nenabled = false\n")
      assert_nil load.thunderbird
    end

    it 'rejects a blank profile directory' do
      write(@home, %(#{minimal}[thunderbird]\nprofile_dir = " "\n))
      assert_raises(described_class::Error) { load }
    end

    it 'stays off in a config built in code' do
      assert_nil described_class.new(llms: [], servers: [], titler_llm: nil).thunderbird
    end
  end

  describe '[documents]' do
    around do |example|
      Dir.mktmpdir('puri-docs') do |folder|
        @folder = folder
        example.run
      end
    end

    it 'is off without the table' do
      write(@home, minimal)
      assert_nil load.documents
    end

    it 'resolves the folder, its notes and its memory' do
      write(@home, %(#{minimal}[documents]\nfolder = "#{@folder}"\n))
      documents = load.documents
      assert_equal described_class::Documents.new(folder: @folder), documents
      assert_equal File.join(@folder, 'Notes', 'PURI.md'), documents.memory
    end

    # @param line [String] user-dirs.dirs' Documents line, as xdg-user-dirs writes it
    # @return [void]
    def user_dirs(line) = File.write(File.join(@home, 'user-dirs.dirs'), "# written by xdg-user-dirs-update\n#{line}\n")

    it "defaults to the desktop's own Documents folder, named in its language" do
      FileUtils.mkdir_p(File.join(@user, 'Dokumenty'))
      user_dirs('XDG_DOCUMENTS_DIR="$HOME/Dokumenty"')
      write(@home, "#{minimal}[documents]\n")
      assert_equal File.join(@user, 'Dokumenty'), load.documents.folder
    end

    it 'takes an absolute path from user-dirs.dirs' do
      user_dirs(%(XDG_DOCUMENTS_DIR="#{@folder}"))
      write(@home, "#{minimal}[documents]\n")
      assert_equal @folder, load.documents.folder
    end

    it 'falls back to ~/Documents without user-dirs.dirs' do
      FileUtils.mkdir_p(File.join(@user, 'Documents'))
      write(@home, "#{minimal}[documents]\n")
      assert_equal File.join(@user, 'Documents'), load.documents.folder
    end

    it 'never takes the home itself, which is xdg-user-dirs switching the folder off' do
      user_dirs('XDG_DOCUMENTS_DIR="$HOME/"')
      write(@home, "#{minimal}[documents]\n")
      assert_rejected("documents.folder: #{Regexp.escape(File.join(@user, 'Documents'))} is not a directory")
    end

    it 'rejects a folder that is not a directory' do
      write(@home, %(#{minimal}[documents]\nfolder = "#{@folder}/nope"\n))
      assert_rejected('documents.folder')
    end
  end

  describe '[maps]' do
    it 'is off without the table' do
      write(@home, minimal)
      assert_nil load.maps
    end

    it 'takes the tiles' do
      write(@home, %(#{minimal}[maps]\ntiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"\n))
      assert_equal 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', load.maps.tiles
    end

    it 'rejects a tile URL missing a placeholder, or not over HTTP' do
      write(@home, %(#{minimal}[maps]\ntiles = "https://tile.example/{z}/{x}.png"\n))
      assert_rejected('maps.tiles: .* has no \{y\}')
      write(@home, %(#{minimal}[maps]\ntiles = "file:///tiles/{z}/{x}/{y}.png"\n))
      assert_rejected('maps.tiles: .* is no http\(s\) URL')
    end

    it 'requires the tiles in the table' do
      write(@home, %(#{minimal}[maps]\n))
      assert_rejected('maps.tiles')
    end
  end

  describe '[weather]' do
    let(:maps) { %([maps]\ntiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"\n) }

    it 'is off without the table' do
      write(@home, "#{minimal}#{maps}")
      assert_nil load.weather
    end

    it "is on with an empty table, asking Open-Meteo's public API" do
      write(@home, "#{minimal}#{maps}[weather]\n")
      assert_equal 'https://api.open-meteo.com', load.weather.url
    end

    it 'takes a self-hosted Open-Meteo, over HTTP only' do
      write(@home, %(#{minimal}#{maps}[weather]\nurl = "http://127.0.0.1:8080"\n))
      assert_equal 'http://127.0.0.1:8080', load.weather.url
      write(@home, %(#{minimal}#{maps}[weather]\nurl = "127.0.0.1:8080"\n))
      assert_rejected('weather.url: .* is no http\(s\) URL')
    end

    it 'needs [maps], which finds its places' do
      write(@home, "#{minimal}[weather]\n")
      assert_rejected('\[weather\] needs \[maps\]')
    end
  end

  describe '[dictation]' do
    it 'is off without the table' do
      write(@home, minimal)
      assert_nil load.dictation
    end

    it 'takes the URL, on whisper-1 with no key by default' do
      write(@home, %(#{minimal}[dictation]\nurl = "http://127.0.0.1:8081"\n))
      assert_equal Puri::Core::Config::DictationTable.new(url: 'http://127.0.0.1:8081', api_key: nil,
                                                          model: 'whisper-1'), load.dictation
    end

    it 'requires an http(s) URL' do
      write(@home, %(#{minimal}[dictation]\n))
      assert_rejected('dictation.url')
      write(@home, %(#{minimal}[dictation]\nurl = "127.0.0.1:8081"\n))
      assert_rejected('dictation.url: .* is no http\(s\) URL')
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

    it 'builds a pikuri transport from a connection, carrying its params' do
      write_example
      transport = load.titler_llm.transport
      assert_equal 'http://localhost:8080/v1', transport.api_base
      assert_equal 'ggml-org/Qwen3.5-4B-GGUF:Q4_K_M', transport.model
      assert_equal 'not-needed', transport.api_key
      assert_equal({ temperature: 0.7, top_p: 0.8, top_k: 20, min_p: 0.0, presence_penalty: 1.5,
                     chat_template_kwargs: { enable_thinking: false } }, transport.params)
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

    it "warns for a search engine's key too" do
      File.chmod(0o644, write(@home, "#{minimal}[search]\nexa_key = \"E\"\n"))
      assert_output(nil, /chmod 600/) { load }
    end

    it "warns for the dictation server's key too" do
      File.chmod(0o644, write(@home, "#{minimal}[dictation]\nurl = \"https://api.example\"\napi_key = \"k\"\n"))
      assert_output(nil, /chmod 600/) { load }
    end
  end
end
