# frozen_string_literal: true

module Puri
  module Core
    # One turn of a {PikuriCore} {Conversation}: the agent's `run_loop` on the turn's thread,
    # ended by a {Protocol::Notice} when it is cancelled or fails. The agent reports the turn
    # itself, through the {TurnListener} it was built with.
    #
    #   turn = Turn.new(conversation, agent:, cancellable:, confirmer:, saved: -> { session.save(conversation) })
    #   Thread.new { turn.run('how do I keep an avocado?') }
    #   turn.cancel   # from any thread
    #
    # Answers to a confirmation go to the conversation's {Confirmer}, where its tool waits.
    class Turn
      # @param conversation [Puri::Core::Conversation]
      # @param agent [Pikuri::Agent] the conversation's, kept across its turns
      # @param cancellable [Pikuri::Agent::Control::Cancellable] the agent's
      # @param confirmer [Puri::Core::Confirmer] the conversation's
      # @param saved [Proc] called on the turn's thread once it has ended, however it ended, before
      #   the next message can start
      def initialize(conversation, agent:, cancellable:, confirmer:, saved:)
        @conversation = conversation
        @agent = agent
        @cancellable = cancellable
        @confirmer = confirmer
        @saved = saved
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
        @saved.call
        @conversation.finish(self)
      end

      # Stops at the next streamed token, or within 0.1 s from a waiting confirmation; a cancel
      # during prefill lands on the first token.
      #
      # @return [void]
      def cancel = @cancellable.cancel!

      # @param confirmation [String] the block id
      # @param approved [Boolean]
      # @return [void]
      def answer(confirmation, approved) = @confirmer.answer(confirmation, approved)

      # @param text [String]
      # @return [void]
      def redirect(text) = @confirmer.redirect(text)

      # @return [Boolean]
      def confirming? = @confirmer.pending?

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
