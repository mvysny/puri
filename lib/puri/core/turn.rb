# frozen_string_literal: true

module Puri
  module Core
    # One turn of a {PikuriCore} {Conversation}: the agent's `run_loop` on the turn's thread,
    # ended by a {Protocol::Notice} when it is cancelled or fails. The agent reports the turn
    # itself, through the {TurnListener} it was built with.
    #
    #   turn = Turn.new(conversation, agent:, cancellable:)
    #   Thread.new { turn.run('how do I keep an avocado?') }
    #   turn.cancel   # from any thread
    class Turn
      # @param conversation [Puri::Core::Conversation]
      # @param agent [Pikuri::Agent] the conversation's, kept across its turns
      # @param cancellable [Pikuri::Agent::Control::Cancellable] the agent's
      def initialize(conversation, agent:, cancellable:)
        @conversation = conversation
        @agent = agent
        @cancellable = cancellable
      end

      # @param text [String] the user's message
      # @return [void]
      def run(text)
        @agent.run_loop(user_message: text)
      rescue Pikuri::Agent::Control::Cancellable::Cancelled
        @conversation.add(Protocol::Notice.new(id: nil, text: 'Cancelled', error: false))
      rescue StandardError => e
        @conversation.add(Protocol::Notice.new(id: nil, text: failure(e), error: true))
      ensure
        @conversation.finish(self)
      end

      # Stops at the next streamed token; a cancel during prefill lands on the first one.
      #
      # @return [void]
      def cancel = @cancellable.cancel!

      # @param _confirmation [String]
      # @param _approved [Boolean]
      # @return [void]
      def answer(_confirmation, _approved) = nil

      # @param _text [String]
      # @return [void]
      def redirect(_text) = nil

      # @return [Boolean]
      def confirming? = false

      private

      # @param error [StandardError]
      # @return [String] what the user reads
      def failure(error)
        server = @agent.transport.api_base
        case error
        when RubyLLM::ConnectionError then "Can't reach the model at #{server}: #{error.message}"
        else "The turn failed: #{error.message} (#{error.class}, #{server})"
        end
      end
    end
  end
end
