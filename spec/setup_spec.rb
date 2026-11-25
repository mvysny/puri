# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'support/fake_hugging_face'
require_relative 'support/scratch_gsettings'

# `bin/setup` as the user runs it, from the apt check to the last line, against a scratch home:
# stand-ins for dpkg-query, llama-server, localsearch and tinysparql on the PATH, a fake Hugging
# Face, and gsettings on a keyfile. The bundle is this checkout's, so `bundle check` passes.
RSpec.describe 'bin/setup' do
  let(:root) { File.expand_path('..', __dir__) }
  qwen = 'GGUF qwen'
  whisper = 'lmgg whisper'

  # @return [Hash{String => String}] each stand-in, by the command it stands in for
  fakes = {
    'dpkg-query' => <<~'SH',
      shift 3
      for p; do [ "$p" = "$MISSING" ] || echo "$p installed"; done
    SH
    'llama-server' => <<~SH,
      echo "Available devices:"
      echo "  Vulkan0: Fake Graphics (8192 MiB, 8000 MiB free)"
    SH
    'localsearch' => <<~SH,
      case "$1" in status) echo "Indexer is idle" ;; info) exit 0 ;; esac
    SH
    'tinysparql' => <<~SH
      echo "Results:"
      echo "  v:file%3A%2F%2F%2Fhome%2Fdoc.txt"
    SH
  }

  around do |example|
    Dir.mktmpdir('puri-setup') do |home|
      @home = home
      FileUtils.mkdir_p([File.join(home, 'bin'), File.join(home, 'Documents')])
      fakes.each do |name, script|
        File.write(File.join(home, 'bin', name), "#!/bin/sh\n#{script}")
        File.chmod(0o755, File.join(home, 'bin', name))
      end
      @hf = FakeHuggingFace.new({ 'ggml-org/Qwen3.5-4B-GGUF' => { 'Qwen3.5-4B-Q4_K_M.gguf' => qwen },
                                  'ggerganov/whisper.cpp' => { 'ggml-small.bin' => whisper } })
      example.run
    ensure
      @hf&.close
    end
  end

  # @param answers [String] what the user types
  # @param extra [Hash{String => String, nil}]
  # @return [Array(String, Process::Status)] everything it printed, and how it ended
  def setup(answers = '', extra = {})
    env = { 'HOME' => @home, 'XDG_DATA_HOME' => "#{@home}/data", 'XDG_STATE_HOME' => "#{@home}/state",
            'XDG_CACHE_HOME' => "#{@home}/cache", 'XDG_CONFIG_DIRS' => "#{@home}/etc",
            'LLAMA_CACHE' => nil, 'HF_HUB_CACHE' => nil, 'HF_HOME' => nil, 'HF_ENDPOINT' => @hf.url,
            'DBUS_SESSION_BUS_ADDRESS' => "unix:path=#{@home}/no-bus", 'PATH' => "#{@home}/bin:#{ENV.fetch('PATH')}",
            'MISSING' => nil, **ScratchGSettings.env(@home), **extra }
    # As from a terminal, not from inside this spec's `bundle exec`.
    Bundler.with_unbundled_env do
      Open3.capture2e(env, File.join(root, 'bin', 'setup'), stdin_data: answers, chdir: @home)
    end
  end

  # @return [Puri::Core::HubCache]
  def cache = Puri::Core::HubCache.new(env: { 'HOME' => @home, 'XDG_CACHE_HOME' => "#{@home}/cache" })

  it 'installs on its first run, asking first, and finds everything in place on the next' do
    out, status = setup("y\ny\ny\n")
    assert status.success?, out
    assert_includes out, '✓ The packages from Ubuntu\'s archive'
    assert_includes out, "✓ Puri's Ruby libraries"
    assert_includes out, '✓ Puri is on your desktop: Super+Alt+Space opens it.'
    assert_includes out, '✓ Wrote the config, ~/config/puri/config.toml'
    assert_includes out, '✓ The model, ggml-org/Qwen3.5-4B-GGUF:Q4_K_M, downloaded'
    assert_includes out, "✓ Dictation's model, ggerganov/whisper.cpp:ggml-small.bin, downloaded"
    assert_includes out, '! Thunderbird has no mail account here'
    assert_includes out, "✓ Your documents, ~/Documents, in GNOME's file index"
    assert_includes out, 'Puri is ready: press Super+Alt+Space, and ask it something.'

    assert_equal File.read(Puri::Core::Config::EXAMPLE), File.read("#{@home}/config/puri/config.toml")
    assert_includes File.read("#{@home}/data/applications/io.github.mvysny.Puri.desktop"), "#{root}/exe/puri"
    assert File.exist?("#{@home}/config/autostart/io.github.mvysny.Puri.desktop"), 'Puri starts at login'
    assert_equal qwen, File.read(cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M'))
    assert_equal whisper, File.read(cache.file('ggerganov/whisper.cpp:ggml-small.bin'))

    out, status = setup
    assert status.success?, out
    refute_includes out, '?', 'nothing left to ask'
    assert_includes out, '✓ The config, ~/config/puri/config.toml'
    assert_includes out, '✓ The model, ggml-org/Qwen3.5-4B-GGUF:Q4_K_M'
  end

  it "fixes nothing it wasn't allowed to, and says what's left" do
    out, status = setup("n\nn\n")
    assert_equal 1, status.exitstatus, out
    assert_includes out, "✗ Puri isn't on your desktop"
    assert_includes out, "✗ The model, ggml-org/Qwen3.5-4B-GGUF:Q4_K_M, isn't downloaded"
    assert_includes out, "✗ Dictation's model"
    assert_includes out, '3 things above, marked ✗, need you.'
    refute File.exist?("#{@home}/data/applications/io.github.mvysny.Puri.desktop")
    assert_nil cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M')
  end

  it 'stops at a missing package, with the apt line that installs it' do
    out, status = setup('', 'MISSING' => 'whisper.cpp')
    assert_equal 1, status.exitstatus, out
    assert_includes out, 'sudo apt install whisper.cpp'
    refute_includes out, 'Ruby libraries'
    refute File.exist?("#{@home}/config/puri"), 'nothing is written before the packages are in'
  end

  it 'stops after a broken config, saying what is wrong' do
    FileUtils.mkdir_p("#{@home}/config/puri")
    File.write("#{@home}/config/puri/config.toml", "[[llm]]\nname = 'x'\n")
    out, status = setup("n\n")
    assert_equal 1, status.exitstatus, out
    assert_includes out, "✗ The config has a mistake, so Puri won't start:"
    refute_includes out, 'The model'
  end
end
