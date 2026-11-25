# frozen_string_literal: true

require 'io/console'

module Puri
  module Setup
    # What `bin/setup` prints and asks, a line per check, marked:
    #
    #   ✓ The packages from Ubuntu's archive
    #   ! No graphics for the model to run on, so it runs on the processor alone …
    #   → This computer's graphics have the memory for Ornith 1.5, a smarter model …
    #   ✗ Thunderbird's global search is off, so Puri finds no mail: in Thunderbird, …
    #   ? Download it from Hugging Face, 3.0 GB? [Y/n]
    #     [=============                 ]  42 %  1.3 of 3.0 GB  11 MB/s
    #
    #   terminal.done("The packages from Ubuntu's archive")
    #   terminal.note('No graphics …')       # a warning that needs nothing of the user
    #   terminal.tip('This computer …')      # a way to more, for the user to take or not
    #   terminal.todo('Thunderbird's …')     # needs the user; counted in #todos
    #   terminal.ask?('Download it?')        # => true for Enter, y or yes; false at end of input
    #   bar = terminal.progress(total, already)
    #   bar.update(fetched)
    #   bar.finish
    #
    # A message wraps at the terminal's width, at most {WIDTH}, its later lines indented under the
    # mark; a line that starts with spaces, such as a command to copy, is never wrapped. The bar
    # draws only on a terminal.
    #
    # Ruby's standard library only: `bin/setup` loads it before `bundle install`.
    class Terminal
      # @return [Integer] columns a message wraps at, on a wide terminal or none
      WIDTH = 96

      # @return [Integer] how many {#todo}s were printed
      attr_reader :todos

      # @param input [IO] where answers come from
      # @param output [IO]
      def initialize(input: $stdin, output: $stdout)
        @input = input
        @output = output
        @todos = 0
      end

      # @param text [String]
      # @return [void]
      def say(text) = text.empty? ? @output.puts : emit('', text)

      # @param text [String] a check that passed
      # @return [void]
      def done(text) = emit('✓', text)

      # @param text [String] a warning the user may act on, or not
      # @return [void]
      def note(text) = emit('!', text)

      # @param text [String] a way to more, which the user may take
      # @return [void]
      def tip(text) = emit('→', text)

      # @param text [String] what the user must do before Puri works fully
      # @return [void]
      def todo(text)
        @todos += 1
        emit('✗', text)
      end

      # Asks until the answer is yes or no. Reads no further than the answer's line, so the
      # answers piped in after it are left for the doctor `bin/setup` execs into.
      #
      # @param question [String]
      # @param default [Boolean] what Enter alone answers
      # @return [Boolean] false at the end of input, whatever the default, so a script piping
      #   nothing in agrees to nothing
      def ask?(question, default: true)
        loop do
          lines = wrap("#{question} #{default ? '[Y/n]' : '[y/N]'}", width - 2)
          @output.print(lines.each_with_index.map { |line, i| "#{i.zero? ? '?' : ' '} #{line}" }.join("\n"), ' ')
          @output.flush
          answer = read_line
          @output.puts if answer.nil?
          return false if answer.nil?

          case answer.strip.downcase
          when '' then return default
          when 'y', 'yes' then return true
          when 'n', 'no' then return false
          end
        end
      end

      # @param total [Integer] bytes
      # @param start [Integer] bytes already there, a download that stopped halfway
      # @return [Puri::Setup::Terminal::Progress]
      def progress(total, start = 0) = Progress.new(@output, total, start)

      # @param path [String]
      # @return [String] `path` with the home folder as `~`
      def self.tilde(path)
        home = Dir.home
        path == home || path.start_with?("#{home}/") ? "~#{path.delete_prefix(home)}" : path
      end

      # @param bytes [Integer]
      # @return [String] in decimal units, as the site states sizes: "3.0 GB", "488 MB"
      def self.size(bytes) = bytes >= 1e9 ? format('%.1f GB', bytes / 1e9) : "#{(bytes / 1e6).round} MB"

      # A download's bar, redrawn in place at most five times a second.
      class Progress
        # @return [Integer] characters between the brackets
        BAR = 30

        # @param output [IO]
        # @param total [Integer] bytes
        # @param start [Integer] bytes there before this run
        def initialize(output, total, start)
          @output = output
          @total = [total, 1].max
          @start = start
          @since = clock
          @drawn = nil
          @tty = output.tty?
        end

        # @param fetched [Integer] bytes there now, {#initialize}'s `start` included
        # @return [void]
        def update(fetched)
          return unless @tty
          return if @drawn && clock - @drawn < 0.2

          @drawn = clock
          draw(fetched)
        end

        # @return [void]
        def finish
          return unless @tty

          draw(@total)
          @output.puts
        end

        # Ends the bar's line where the download stopped short.
        #
        # @return [void]
        def stop
          @output.puts if @drawn
        end

        private

        # @param fetched [Integer]
        # @return [void]
        def draw(fetched)
          share = fetched.fdiv(@total).clamp(0.0, 1.0)
          rate = (fetched - @start) / [clock - @since, 0.001].max
          bar = ('=' * (share * BAR).round).ljust(BAR)
          @output.print("\r  [#{bar}] #{(share * 100).floor.to_s.rjust(3)} %  " \
                        "#{Terminal.size(fetched)} of #{Terminal.size(@total)}  #{Terminal.size(rate.round)}/s   ")
          @output.flush
        end

        # @return [Float]
        def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      private

      # A byte at a time: `gets` reads ahead from a pipe, into a buffer `exec` drops.
      #
      # @return [String, nil] nil at the end of input
      def read_line
        line = String.new
        line << @input.readpartial(1) until line.end_with?("\n")
        line
      rescue EOFError
        line.empty? ? nil : line
      end

      # @param mark [String] one character, or '' for none
      # @param text [String] perhaps several lines
      # @return [void]
      def emit(mark, text)
        prefix = mark.empty? ? '' : "#{mark} "
        indent = ' ' * prefix.size
        text.each_line(chomp: true) do |para|
          if para.empty? || para.start_with?(' ')
            @output.puts(para.empty? ? '' : "#{indent}#{para}")
          else
            wrap(para, width - prefix.size).each do |line|
              @output.puts("#{prefix}#{line}")
              prefix = indent
            end
          end
          prefix = indent
        end
      end

      # @param text [String] one paragraph
      # @param columns [Integer]
      # @return [Array<String>] never empty
      def wrap(text, columns)
        text.split(' ').each_with_object([+'']) do |word, lines|
          if lines.last.empty? then lines.last << word
          elsif lines.last.size + 1 + word.size <= columns then lines.last << ' ' << word
          else lines << word.dup
          end
        end
      end

      # @return [Integer]
      def width
        columns = @output.tty? ? @output.winsize[1] : WIDTH
        columns.positive? ? [columns, WIDTH].min : WIDTH
      rescue SystemCallError
        WIDTH
      end
    end
  end
end
