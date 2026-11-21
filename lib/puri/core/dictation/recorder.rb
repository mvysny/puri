# frozen_string_literal: true

require 'open3'

module Puri
  module Core
    class Dictation
      # One clip from the mic: `pw-record`'s raw PCM, 16 kHz mono s16le, read as it records,
      # its level reported on the way.
      #
      #   recorder = Recorder.new { |level| show(level) }   # 0..1, ~15 times a second
      #   pcm = recorder.stop                               # or recorder.cancel
      #   pcm.bytesize / Recorder::BYTES_PER_SECOND         # => seconds heard
      #
      # The command is any that writes such PCM to stdout and stops on SIGINT; specs `cat` a
      # file, which ends by itself, and the clip then waits for {#stop} all the same.
      #
      # Thread-safe.
      class Recorder
        # Raised when the command can't start, or dies before giving any sound.
        class Error < StandardError; end

        # @return [Array<String>]
        COMMAND = %w[pw-record --raw --rate 16000 --channels 1 --format s16 -].freeze

        # @return [Integer] 16 kHz of 2-byte samples
        BYTES_PER_SECOND = 32_000

        # @return [Float] seconds between two levels
        LEVEL_INTERVAL = 1.0 / 15

        # @return [Float] dBFS the level bar shows as empty; speech sits some 20 to 40 above
        FLOOR_DB = -60.0

        # @return [Integer] seconds {#stop} waits for the command to flush and exit
        STOP_SECONDS = 2

        # @param command [Array<String>]
        # @yieldparam level [Float] 0 (silence) to 1 (full scale), on the reader's thread
        # @yieldreturn [void]
        # @raise [Error] when the command isn't installed
        def initialize(command: COMMAND, &on_level)
          @on_level = on_level
          @pcm = String.new(encoding: Encoding::BINARY)
          @lock = Mutex.new
          stdin, @stdout, @stderr, @wait = Open3.popen3(*command)
          stdin.close
          @reader = Thread.new { read }
        rescue SystemCallError => e
          raise Error, "can't start #{command.first}: #{e.message}"
        end

        # Stops recording.
        #
        # @return [String] the PCM heard, binary; empty when stopped before the first chunk
        # @raise [Error] when the command died by itself before giving any sound, with its own
        #   words
        def stop
          finish
          @lock.synchronize { @pcm.dup }.tap do |pcm|
            raise Error, failure if pcm.empty? && @died
          end
        end

        # Stops recording and forgets the clip.
        #
        # @return [void]
        def cancel
          finish
          @lock.synchronize { @pcm.clear }
        end

        private

        # @return [void]
        def finish
          ended = !@wait.alive?
          signal('INT')
          signal('KILL') unless @reader.join(STOP_SECONDS)
          @reader.join
          @status = @wait.value
          @died = ended && !@status.success?
          @errors = @stderr.read.to_s
          [@stdout, @stderr].each(&:close)
        end

        # @param name [String]
        # @return [void]
        def signal(name)
          Process.kill(name, @wait.pid)
        rescue Errno::ESRCH
          nil # ended by itself
        end

        # @return [void]
        def read
          @sum = 0.0
          @count = 0
          @reported = clock
          @carry = String.new(encoding: Encoding::BINARY)
          loop do
            chunk = @stdout.readpartial(4096)
            @lock.synchronize { @pcm << chunk }
            measure(chunk)
          end
        rescue IOError
          nil # EOFError: the command ended
        end

        # @param chunk [String]
        # @return [void]
        def measure(chunk)
          bytes = @carry + chunk
          @carry = bytes.bytesize.odd? ? bytes.byteslice(-1, 1) : String.new(encoding: Encoding::BINARY)
          bytes.byteslice(0, bytes.bytesize & ~1).unpack('s<*').each { @sum += _1 * _1 }
          @count += bytes.bytesize / 2
          return unless @on_level && clock - @reported >= LEVEL_INTERVAL

          @on_level.call(level)
          @sum = 0.0
          @count = 0
          @reported = clock
        end

        # @return [Float] the RMS since the last level, in dBFS mapped from {FLOOR_DB}..0 to 0..1
        def level
          rms = @count.zero? ? 0.0 : Math.sqrt(@sum / @count) / 32_768
          return 0.0 if rms <= 0

          ((20 * Math.log10(rms)) - FLOOR_DB).fdiv(-FLOOR_DB).clamp(0.0, 1.0)
        end

        # @return [String] the command's first line on stderr, or its exit status
        def failure
          @errors.lines.map(&:strip).reject(&:empty?).first || "the recorder exited with #{@status.exitstatus}"
        end

        # @return [Float]
        def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
