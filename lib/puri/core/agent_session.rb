# frozen_string_literal: true

module Puri
  module Core
    # A {PikuriCore} conversation's pikuri agent, kept across its turns so the model sees the
    # whole conversation. It is the {Conversation}'s `turns` strategy, and builds the agent on
    # the first turn:
    #
    #   session = AgentSession.new(transport:, system_prompt:)
    #   conversation = Conversation.new(id:, lock:, emit:, changed:, threads:, turns: session)
    #   conversation.ask('how do I keep an avocado?')   # session.call(conversation) → a Turn
    #   session.close                                    # the conversation is gone
    #
    # Each call comes from its conversation, under the core's lock.
    class AgentSession
      # @param transport [Pikuri::Agent::ChatTransport]
      # @param system_prompt [String]
      def initialize(transport:, system_prompt:)
        @transport = transport
        @system_prompt = system_prompt
        @cancellable = Pikuri::Agent::Control::Cancellable.new
        @agent = nil
      end

      # @param conversation [Puri::Core::Conversation]
      # @return [Puri::Core::Turn] the next turn, not started
      def call(conversation)
        @agent ||= build(conversation)
        Turn.new(conversation, agent: @agent, cancellable: @cancellable)
      end

      # @return [void]
      def close = @agent&.close

      private

      # @param conversation [Puri::Core::Conversation]
      # @return [Pikuri::Agent]
      def build(conversation)
        listener = Pikuri::Agent::Listener::RateLimited.new(TurnListener.new(conversation), fps: 15)
        Pikuri::Agent.new(transport: @transport, system_prompt: @system_prompt, cancellable: @cancellable,
                          streaming: true) do |c|
          c.add_listener(listener)
        end
      end
    end
  end
end
