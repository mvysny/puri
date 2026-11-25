# frozen_string_literal: true

require 'fileutils'
require 'rbconfig'
require 'socket'

# A llama-server for {Puri::Core::LlamaServer}'s specs, run as its child: it prints its pid, its
# arguments and its key, then answers `/health` as llama-server does, 503 while the model loads
# and 200 once it has. spec/puri/core/llama_server_spec.rb runs the real one too.
#
#   FakeLlamaServer.download(cache)
#   server = Puri::Core::LlamaServer.new(FakeLlamaServer.embedded, cache:, command: FakeLlamaServer.command)
#
# Its modes: `serve` loads for `load` seconds; `crash` says why and exits 1; `crash-once` crashes
# while `marker` names no file, creating it, then serves.
module FakeLlamaServer
  # @return [String] what {download} puts in the cache
  MODEL = 'ggml-org/Qwen3.5-4B-GGUF:Q4_K_M'

  # @return [String] run with `ruby -e`: mode, marker, load seconds, then llama-server's arguments
  SCRIPT = <<~'RUBY'
    require 'socket'
    mode, marker, load, *args = ARGV
    $stdout.sync = true
    puts "pid #{Process.pid}", "args #{args.join(' ')}", "key #{ENV.fetch('LLAMA_API_KEY', '')}"
    if mode == 'crash' || (mode == 'crash-once' && !File.exist?(marker) && File.write(marker, ''))
      puts 'error: the model failed to load'
      exit 1
    end
    server = TCPServer.new('127.0.0.1', Integer(args[args.index('--port') + 1]))
    ready_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Float(load)
    loop do
      client = server.accept
      nil while (line = client.gets) && line != "\r\n"
      ok = Process.clock_gettime(Process::CLOCK_MONOTONIC) >= ready_at
      body = ok ? '{"status":"ok"}' : '{"error":{"code":503,"message":"Loading model"}}'
      client.write("HTTP/1.1 #{ok ? '200 OK' : '503 Service Unavailable'}\r\nContent-Length: " \
                   "#{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      client.close
    end
  RUBY

  # @param mode [String] `serve`, `crash` or `crash-once`
  # @param marker [String] the file `crash-once` creates
  # @param load [Float] seconds `serve` answers 503
  # @return [Array<String>] a {Puri::Core::LlamaServer} `command:`
  def self.command(mode = 'serve', marker: '', load: 0.3)
    [RbConfig.ruby, '--disable=gems,rubyopt', '-e', SCRIPT, mode, marker, load.to_s]
  end

  # @return [Puri::Core::Config::EmbeddedServer] on a free port, its key `k3y`
  def self.embedded
    port = TCPServer.open('127.0.0.1', 0) { _1.addr[1] }
    Puri::Core::Config::EmbeddedServer.new(id: 'local', model: MODEL, port:, api_key: 'k3y')
  end

  # Puts {MODEL} in `cache`, as `-hf` leaves it.
  #
  # @param cache [Puri::Core::HubCache]
  # @return [void]
  def self.download(cache)
    base = File.join(cache.root, 'models--ggml-org--Qwen3.5-4B-GGUF')
    FileUtils.mkdir_p([File.join(base, 'snapshots', 'c0ffee'), File.join(base, 'refs')])
    File.write(File.join(base, 'snapshots', 'c0ffee', 'Qwen3.5-4B-Q4_K_M.gguf'), 'GGUF')
    File.write(File.join(base, 'refs', 'main'), 'c0ffee')
  end
end
