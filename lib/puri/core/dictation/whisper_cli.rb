# frozen_string_literal: true

require 'open3'

module Puri
  module Core
    class Dictation
      # Turns a clip into text with apt's `whisper-cli`, run once per clip on the `[dictation]`
      # model, so no process holds that model between clips (`D_embedded`):
      #
      #   whisper = WhisperCli.new(config.dictation)
      #   whisper.transcribe(pcm)   # => "Buy avocados and limes."
      #
      # The WAV goes in on stdin and the text comes out on stdout, so the voice never touches the
      # disk. The model is looked up in the {HubCache} at every clip: one downloaded while Puri runs
      # works from the next press.
      #
      # == Implementation details
      #
      # `-np` keeps whisper.cpp's log off stderr, its own reason for a failure with it: a missing
      # model reads only "failed to initialize whisper context", hence the lookup first
      # (`R_whisper_cli`).
      #
      # Thread-safe.
      class WhisperCli
        # Raised when the model isn't downloaded, or whisper-cli can't run or fails.
        class Error < StandardError; end

        # @return [Array<String>]
        COMMAND = %w[whisper-cli].freeze

        # @return [Integer] seconds a clip may take, as on a server
        TIMEOUT = Transcriber::TIMEOUT

        # @param table [Puri::Core::Config::DictationTable] one with no `url`
        # @param cache [Puri::Core::HubCache] where the model is
        # @param command [Array<String>] what runs `whisper-cli`; specs run a stand-in
        # @param timeout [Numeric] seconds a clip may take; specs shorten it
        def initialize(table, cache: HubCache.new, command: COMMAND, timeout: TIMEOUT)
          @model = table.model
          @language = table.language
          @cache = cache
          @command = command
          @timeout = timeout
        end

        # @param pcm [String] 16 kHz mono s16le, as {Recorder#stop} returns it
        # @return [String] see {Dictation.squeeze}
        # @raise [Error] saying why, the model's name and the cache's folder when it isn't there
        def transcribe(pcm)
          model = @cache.file(@model) or
            raise Error, "the model #{@model} isn't downloaded: it isn't in #{@cache.root}"
          out, err, status = run(model, Transcriber.wav(pcm))
          raise Error, "whisper-cli failed: #{last_line(err) || status}" unless status.success?

          Dictation.squeeze(out)
        end

        private

        # @param model [String] the file's path
        # @param wav [String]
        # @return [Array(String, String, Process::Status)] stdout, stderr and how it ended
        # @raise [Error] when it can't start, or takes longer than the timeout
        def run(model, wav)
          argv = [*@command, '-m', model, '-f', '-', '-l', @language, '-nt', '-otxt', '-np']
          Open3.popen3(*argv) do |stdin, stdout, stderr, wait|
            writer = Thread.new { feed(stdin, wav) }
            out = Thread.new { stdout.read }
            err = Thread.new { stderr.read }
            late = !wait.join(@timeout)
            kill(wait.pid) if late
            # Before popen3 closes the pipes, which would fail a read still under way.
            [writer, out, err].each(&:join)
            raise Error, "whisper-cli took over #{@timeout} s" if late

            [out.value, err.value, wait.value]
          end
        rescue SystemCallError => e
          raise Error, "can't run #{@command.first}: #{e.message}"
        end

        # @param stdin [IO]
        # @param wav [String]
        # @return [void]
        def feed(stdin, wav)
          stdin.binmode
          stdin.write(wav)
        rescue Errno::EPIPE, IOError
          nil # it exited before reading the clip, and says why on stderr
        ensure
          stdin.close unless stdin.closed?
        end

        # @param pid [Integer]
        # @return [void]
        def kill(pid)
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil # it ended as the timeout ran out
        end

        # @param err [String]
        # @return [String, nil]
        def last_line(err) = err.lines.map(&:strip).reject(&:empty?).last
      end
    end
  end
end
