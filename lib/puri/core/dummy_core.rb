# frozen_string_literal: true

module Puri
  module Core
    # Milestone 1's stand-in for the pikuri-backed Core: "thinks" a while, then streams lorem
    # ipsum word by word, from a thread of its own as pikuri's agent will.
    #
    #   core = DummyCore.new { |event| client.deliver(event) }   # called on the turn's thread
    #   core.handle(Protocol::Ask.new(conversation: nil, text: 'hi'))
    #   # TurnStarted(conversation: "3f2…") at once, then a TextDelta per word, then TurnFinished
    class DummyCore
      # @return [Array<String>] the reply, one word per {Protocol::TextDelta}
      WORDS = <<~LOREM.split.freeze
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut
        labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco
        laboris nisi ut aliquip ex ea commodo consequat.
      LOREM

      # @param think [Float] seconds before the first word
      # @param pace [Float] seconds between words
      # @yieldparam event [Data] a {Protocol} event, called on the turn's thread
      # @yieldreturn [void]
      def initialize(think: 1.0, pace: 1.0 / 30, &listener)
        raise ArgumentError, 'DummyCore needs a listener block' unless listener

        @think = think
        @pace = pace
        @listener = listener
      end

      # @param command [Data] a {Protocol} command
      # @return [Thread] the turn, already running
      # @raise [ArgumentError] for anything but a command it knows
      def handle(command)
        case command
        in Protocol::Ask(conversation:)
          conversation ||= SecureRandom.uuid
          @listener.call(Protocol::TurnStarted.new(conversation:))
          Thread.new { stream(conversation) }
        else
          raise ArgumentError, "DummyCore can't handle #{command.inspect}"
        end
      end

      private

      # @param conversation [String]
      # @return [void]
      def stream(conversation)
        sleep @think
        WORDS.each_with_index do |word, i|
          sleep @pace
          @listener.call(Protocol::TextDelta.new(conversation:, text: i.zero? ? word : " #{word}"))
        end
        @listener.call(Protocol::TurnFinished.new(conversation:))
      end
    end
  end
end
