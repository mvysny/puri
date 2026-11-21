# frozen_string_literal: true

require 'rbconfig'

module Puri
  module Dummy
    # Dictation with no mic and no server, on Core's own `Core::Dictation`: a process swelling
    # like speech stands in for `pw-record`, and the same sentence comes back every time.
    #
    #   Core::Dictation.new(transcriber: Voice.new(think: 1.0), command: Voice::COMMAND) { |event| … }
    class Voice
      # @return [Array<String>] noise rising and falling as syllables do, in pw-record's format
      #   and pace, until SIGINT
      COMMAND = [RbConfig.ruby, '--disable=gems,rubyopt', '-e', <<~RUBY].freeze
        $stdout.binmode
        0.step do |t|
          amp = 0.05 + (0.3 * (0.5 + (0.5 * Math.sin(t / 2.0))))
          $stdout.write(Array.new(1600) { (amp * 32_767 * ((rand * 2) - 1)).round }.pack('s<*'))
          $stdout.flush
          sleep 0.1
        end
      RUBY

      # @return [String] what it hears
      TEXT = 'Remind me to buy avocados on Friday.'

      # @param think [Float] seconds a transcription takes
      def initialize(think:)
        @think = think
      end

      # @param _pcm [String]
      # @return [String] {TEXT}
      def transcribe(_pcm)
        sleep @think
        TEXT
      end
    end
  end
end
