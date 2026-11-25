# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'stringio'
require 'tmpdir'

# The child is {FakeLlamaServer}, which answers /health as llama-server does.
# `LLAMA_MODEL=ggml-org/Qwen3.5-4B-GGUF:Q4_K_M` adds the real one, on a model already in the hub
# cache.
RSpec.describe Puri::Core::LlamaServer do
  model = FakeLlamaServer::MODEL

  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    Dir.mktmpdir('puri-llama') do |dir|
      @dir = dir
      example.run
    ensure
      @server&.close
    end
  ensure
    Pikuri.log_io = log
  end

  let(:cache) { Puri::Core::HubCache.new(env: { 'LLAMA_CACHE' => File.join(@dir, 'hub') }) }
  let(:embedded) { FakeLlamaServer.embedded }

  # @param mode [String] {FakeLlamaServer}'s
  # @return [Puri::Core::LlamaServer]
  def server(mode = 'serve')
    command = FakeLlamaServer.command(mode, marker: File.join(@dir, 'crashed'))
    @server = described_class.new(embedded, cache:, env: { 'XDG_STATE_HOME' => File.join(@dir, 'state') },
                                            command:, backoff: 0.01)
  end

  # @param pid [Integer]
  # @return [Boolean] whether it runs, a zombie being dead
  def alive?(pid)
    File.read("/proc/#{pid}/stat").split[2] != 'Z'
  rescue Errno::ENOENT
    false
  end

  # @param server [Puri::Core::LlamaServer]
  # @return [Array<Integer>] each child's pid, as it printed it
  def pids(server) = File.read(server.log).scan(/^pid (\d+)$/).flatten.map(&:to_i)

  it 'runs the model on loopback, its key out of the command line, and is ready once /health answers' do
    FakeLlamaServer.download(cache)
    s = server
    s.start
    refute s.ready?, 'the model is still loading'
    s.wait_ready(timeout: 10)
    assert s.ready?
    log = File.read(s.log)
    assert_includes log, "args -hf #{model} --offline -c 65536 --no-mmproj --host 127.0.0.1 " \
                         "--port #{embedded.port} --cors-origins localhost\n"
    assert_includes log, "key k3y\n"
  end

  it "says the model isn't downloaded, starting nothing, and looks again at the next wait" do
    s = server
    s.start
    error = assert_raises(described_class::Error) { s.wait_ready(timeout: 10) }
    assert_includes error.message, "The model #{model} isn't downloaded: it isn't in #{cache.root}"
    refute File.exist?(s.log), 'no child ran'
    FakeLlamaServer.download(cache)
    s.wait_ready(timeout: 10)
    assert s.ready?
  end

  it 'restarts a child that crashes' do
    FakeLlamaServer.download(cache)
    s = server('crash-once')
    s.start
    s.wait_ready(timeout: 10)
    assert_equal 2, pids(s).size
    assert_includes File.read(s.log), 'error: the model failed to load'
  end

  it "gives up after #{described_class::CRASHES} crashes in a minute, the log's tail in the error" do
    FakeLlamaServer.download(cache)
    s = server('crash')
    s.start
    error = assert_raises(described_class::Error) { s.wait_ready(timeout: 10) }
    assert_match(/\Allama-server stopped 3 times in a minute:\n.*error: the model failed to load\z/m, error.message)
    assert_equal 3, pids(s).size
  end

  it 'stops the child when closed, and a wait after says Puri is quitting' do
    FakeLlamaServer.download(cache)
    s = server
    s.start
    s.wait_ready(timeout: 10)
    pid = pids(s).first
    s.close
    refute alive?(pid)
    error = assert_raises(described_class::Error) { s.wait_ready(timeout: 1) }
    assert_equal 'Puri is quitting', error.message
  end

  it 'serves only the connections to it' do
    s = server
    assert s.serves?(Pikuri::Agent::ChatTransport.from_openai_server(server: embedded.url, model:))
    refute s.serves?(Pikuri::Agent::ChatTransport.from_openai_server(server: 'http://127.0.0.1:8080', model:))
  end

  # The kernel's doing, through setpriv: nothing in Puri runs once it is killed.
  it 'leaves no model loaded behind a killed Puri' do
    FakeLlamaServer.download(cache)
    script = <<~'RUBY'
      require 'puri'
      Puri::Core
      Pikuri.log_io = File.open(File::NULL, 'w')
      embedded = Puri::Core::Config::EmbeddedServer.new(id: 'local', model: ARGV[0], port: Integer(ARGV[1]),
                                                        api_key: 'k')
      server = Puri::Core::LlamaServer.new(embedded, cache: Puri::Core::HubCache.new(env: { 'LLAMA_CACHE' => ARGV[2] }),
                                                     env: { 'XDG_STATE_HOME' => ARGV[3] }, command: ARGV[4..])
      server.start
      server.wait_ready(timeout: 10)
      puts 'ready'
      $stdout.flush
      sleep
    RUBY
    state = File.join(@dir, 'state')
    Open3.popen2(RbConfig.ruby, '-I', File.expand_path('../../../lib', __dir__), '-e', script, model,
                 embedded.port.to_s, cache.root, state, *FakeLlamaServer.command) do |_stdin, stdout, wait|
      assert_equal "ready\n", stdout.gets
      pid = File.read(File.join(state, 'puri', 'llama-server.log'))[/^pid (\d+)$/, 1].to_i
      assert alive?(pid)
      Process.kill('KILL', wait.pid)
      wait.join
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      sleep 0.05 while alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      refute alive?(pid), 'the child outlived Puri'
    end
  end

  if ENV['LLAMA_MODEL']
    it 'runs the real llama-server, which takes the key' do
      real = Puri::Core::Config::EmbeddedServer.new(id: 'local', model: ENV['LLAMA_MODEL'], port: embedded.port,
                                                    api_key: 'k3y')
      @server = described_class.new(real, env: { 'XDG_STATE_HOME' => File.join(@dir, 'state') })
      @server.start
      @server.wait_ready(timeout: 120)
      Net::HTTP.start('127.0.0.1', real.port) do |http|
        assert_equal '401', http.get('/props').code
        assert_equal '200', http.get('/props', 'Authorization' => 'Bearer k3y').code
      end
    end
  end
end
