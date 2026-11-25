# frozen_string_literal: true

require 'fileutils'
require 'monitor'
require 'net/http'

module Puri
  module Core
    # The llama-server Puri runs itself, for the `[[server]]` with no `url` (`D_embedded`): apt's
    # binary as a child on loopback, behind the run's key, restarted when it crashes and stopped
    # when Puri quits.
    #
    #   server = LlamaServer.new(config.embedded_server)
    #   server.start                  # returns at once; the model loads in the child's own time
    #   server.serves?(transport)     # => true for a connection to it
    #   server.wait_ready             # once /health answers; raises Error saying why it can't
    #   server.close
    #
    # A model missing from the {HubCache} fails without a child, saying what to download, since
    # `--offline` alone says only "exactly one out metadata, path_model, and file must be defined".
    # A crash restarts the child after {BACKOFF} seconds, doubling, and the {CRASHES}th within
    # {CRASH_WINDOW} seconds gives up, the log's tail in the error. Either way the next
    # {#wait_ready} starts over, so a model downloaded since, or memory freed since, works without
    # restarting Puri. The log is `$XDG_STATE_HOME/puri/llama-server.log`, emptied at each {#start}.
    #
    # == Implementation details
    #
    # One thread spawns the child and waits on it, and another polls `/health` until it answers.
    # The child runs under `setpriv --pdeathsig TERM`, which the kernel ties to the thread that
    # spawned it: the waiting one, which ends only after the child, so a killed Puri leaves no
    # model loaded (`R_llama_server_embedded`). The key goes in `LLAMA_API_KEY`, never on the
    # command line, which `/proc` shows every user.
    #
    # Thread-safe.
    class LlamaServer
      # Raised by {#wait_ready} when the model can't be served.
      class Error < StandardError; end

      # @return [Array<String>]
      COMMAND = %w[llama-server].freeze

      # @return [Array<String>] what stops the child when the thread that spawned it ends
      DEATH_SIGNAL = %w[setpriv --pdeathsig TERM].freeze

      # @return [Integer] tokens, the context Puri's prompts need
      CONTEXT = 65_536

      # @return [Float] seconds before the first restart
      BACKOFF = 1.0

      # @return [Integer] crashes within {CRASH_WINDOW} that stop the restarts
      CRASHES = 3

      # @return [Integer] seconds
      CRASH_WINDOW = 60

      # @return [Integer] seconds {#wait_ready} waits for a model still loading
      READY_TIMEOUT = 300

      # @return [Integer] seconds {#close} waits for the child to exit before killing it
      STOP_SECONDS = 5

      # @return [Float] seconds between two `/health` polls
      POLL = 0.25

      # @return [Logger]
      LOGGER = Pikuri.logger_for('LlamaServer')

      # @param embedded [Puri::Core::Config::EmbeddedServer]
      # @param cache [Puri::Core::HubCache] where the model is
      # @param env [#[]] where `XDG_STATE_HOME` comes from, for the log
      # @param command [Array<String>] what runs `llama-server`; specs run a stand-in
      # @param backoff [Float] seconds before the first restart; specs shorten it
      def initialize(embedded, cache: HubCache.new, env: ENV, command: COMMAND, backoff: BACKOFF)
        @embedded = embedded
        @cache = cache
        @command = command
        @backoff = backoff
        state = env['XDG_STATE_HOME'].to_s.empty? ? File.join(Dir.home, '.local', 'state') : env['XDG_STATE_HOME']
        @log = File.join(state, 'puri', 'llama-server.log')
        @lock = Monitor.new
        @changed = @lock.new_cond
        @state = :idle
        @error = nil
        @crashes = []
        @child = nil
        @watcher = nil
      end

      # @return [String] where the child's output goes
      attr_reader :log

      # Starts the child, unless it runs already; returns at once.
      #
      # @return [void]
      def start
        @lock.synchronize do
          next unless %i[idle failed].include?(@state)

          unless @cache.gguf(@embedded.model)
            next failed("The model #{@embedded.model} isn't downloaded: it isn't in #{@cache.root}. " \
                        "#{Puri::SETUP}, run in a terminal, downloads it.")
          end
          FileUtils.mkdir_p(File.dirname(@log))
          File.write(@log, '')
          @state = :starting
          @crashes = []
          @watcher = Thread.new { watch }
          LOGGER.info("starting llama-server on #{@embedded.model}, port #{@embedded.port}")
        end
      end

      # @param transport [Pikuri::Agent::ChatTransport]
      # @return [Boolean] whether it connects to this server
      def serves?(transport) = transport.api_base == "#{@embedded.url}/v1"

      # @return [Boolean] whether `/health` has answered since the child last started
      def ready? = @lock.synchronize { @state == :ready }

      # Blocks until the model is loaded, starting over a server that failed: Puri is resident, and
      # a cause gone since must not need its restart.
      #
      # @param timeout [Numeric] seconds
      # @return [void]
      # @raise [Error] when the model isn't downloaded, the child keeps crashing, Puri is
      #   quitting, or the model still loads after `timeout`
      def wait_ready(timeout: READY_TIMEOUT)
        start if @lock.synchronize { @state == :failed }
        deadline = clock + timeout
        @lock.synchronize do
          until %i[ready failed closed].include?(@state)
            left = deadline - clock
            raise Error, "the model #{@embedded.model} is still loading after #{timeout} s" if left <= 0

            @changed.wait(left)
          end
          raise Error, @error if @state == :failed
          raise Error, 'Puri is quitting' if @state == :closed
        end
      end

      # Stops the child and any restart, killing it after {STOP_SECONDS}.
      #
      # @return [void]
      def close
        pid, watcher = @lock.synchronize do
          @state = :closed
          @changed.broadcast
          [@child, @watcher]
        end
        return unless watcher

        signal(pid, 'TERM')
        signal(pid, 'KILL') unless watcher.join(STOP_SECONDS)
        watcher.join
      end

      private

      # The watcher thread: the child's whole life, and each restart.
      #
      # @return [void]
      def watch
        while (pid = launch)
          poller = Thread.new { poll(pid) }
          status = Process.wait2(pid).last
          poller.kill.join
          delay = @lock.synchronize { exited(status) } or break
          @lock.synchronize { @changed.wait(delay) unless @state == :closed }
        end
      end

      # @return [Integer, nil] the child's pid; nil once closed, or when it can't start
      def launch
        @lock.synchronize do
          next nil if @state == :closed

          @child = Process.spawn({ 'LLAMA_API_KEY' => @embedded.api_key }, *command_line,
                                 in: File::NULL, out: [@log, 'a'], err: %i[child out])
        rescue SystemCallError => e
          failed("can't start #{DEATH_SIGNAL.first}: #{e.message}")
          nil
        end
      end

      # @return [Array<String>]
      def command_line
        [*DEATH_SIGNAL, *@command, '-hf', @embedded.model, '--offline', '-c', CONTEXT.to_s, '--no-mmproj',
         '--host', '127.0.0.1', '--port', @embedded.port.to_s, '--cors-origins', 'localhost']
      end

      # Under the lock.
      #
      # @param status [Process::Status]
      # @return [Float, nil] seconds to wait before the restart; nil for none
      def exited(status)
        @child = nil
        return nil if @state == :closed

        now = clock
        @crashes = @crashes.select { now - _1 < CRASH_WINDOW } << now
        LOGGER.warn("llama-server exited: #{status}")
        if @crashes.size >= CRASHES
          failed("llama-server stopped #{CRASHES} times in a minute:\n#{tail}")
          return nil
        end
        @state = :starting
        @changed.broadcast
        @backoff * (2**(@crashes.size - 1))
      end

      # The poller thread, killed when the child exits.
      #
      # @param pid [Integer]
      # @return [void]
      def poll(pid)
        sleep POLL until healthy?
        @lock.synchronize do
          next unless @state == :starting && @child == pid

          @state = :ready
          @changed.broadcast
          LOGGER.info("llama-server is ready on #{@embedded.url}")
        end
      end

      # @return [Boolean]
      def healthy?
        Net::HTTP.start('127.0.0.1', @embedded.port, open_timeout: 1, read_timeout: 5) do |http|
          http.get('/health', 'Authorization' => "Bearer #{@embedded.api_key}").is_a?(Net::HTTPSuccess)
        end
      rescue SystemCallError, IOError, Timeout::Error
        false
      end

      # Under the lock.
      #
      # @param error [String]
      # @return [void]
      def failed(error)
        LOGGER.error(error)
        @state = :failed
        @error = error
        @changed.broadcast
      end

      # @param pid [Integer, nil]
      # @param name [String]
      # @return [void]
      def signal(pid, name)
        Process.kill(name, pid) if pid
      rescue Errno::ESRCH
        nil # exited already
      end

      # @return [String] the log's last lines
      def tail
        File.readlines(@log).map(&:rstrip).reject(&:empty?).last(5).join("\n")
      rescue SystemCallError
        "(no log at #{@log})"
      end

      # @return [Float]
      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
