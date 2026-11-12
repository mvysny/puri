# frozen_string_literal: true

module Puri
  module Core
    # A {PikuriCore} conversation's pikuri agent, kept across its turns so the model sees the
    # whole conversation, and the conversation's directory in the {Store}. It is the
    # {Conversation}'s `turns` strategy, and builds the agent, its {Confirmer} and its tools on
    # the first turn:
    #
    #   session = AgentSession.new(id:, transport:, system_prompt:, lock:, tools: ->(confirmer) { [] },
    #                              store:, saved: true)
    #   conversation = Conversation.new(id:, lock:, emit:, changed:, threads:, turns: session)
    #   session.restore(conversation)   # a saved one's blocks, once, before anyone reads them
    #   conversation.ask('how do I keep an avocado?')   # session.call(conversation) → a Turn, saved after
    #   session.retitle(conversation)   # once the Titler has named it
    #   session.delete                  # the conversation is gone, from disk too
    #
    # A conversation is saved after every turn, a cancelled or failed one too; a write that fails
    # ends in an error notice, and the turn's text stays in memory.
    #
    # == Threading
    #
    # {#call} and {#restore} come from the conversation, under the core's lock. {#save} runs on
    # the turn's thread and {#retitle} on the title's; they and {#delete} take this session's own
    # lock, so one conversation's writes never overlap, each reads the conversation as it is when
    # it writes, and nothing is written once it's deleted.
    class AgentSession
      # @return [Logger]
      LOGGER = Pikuri.logger_for('AgentSession')

      # @param id [String] the conversation's
      # @param transport [Pikuri::Agent::ChatTransport]
      # @param system_prompt [String]
      # @param lock [Monitor] the core's
      # @param tools [Proc] takes the conversation's {Confirmer}, returns the agent's
      #   `Array<Pikuri::Tool>`
      # @param store [Puri::Core::Store]
      # @param saved [Boolean] whether the store holds this conversation already
      def initialize(id:, transport:, system_prompt:, lock:, tools:, store:, saved: false)
        @id = id
        @transport = transport
        @system_prompt = system_prompt
        @lock = lock
        @tools = tools
        @store = store
        @saved = saved
        @cancellable = Pikuri::Agent::Control::Cancellable.new
        @agent = nil
        @confirmer = nil
        @history = nil
        @writes = Mutex.new
        @persist = true
      end

      # @param conversation [Puri::Core::Conversation]
      # @return [Puri::Core::Turn] the next turn, not started
      def call(conversation)
        @agent ||= build(conversation)
        Turn.new(conversation, agent: @agent, cancellable: @cancellable, confirmer: @confirmer,
                               saved: -> { save(conversation) })
      end

      # Fills a saved conversation's blocks from its history, the first time only; the agent
      # gets the history on the first turn. A history that can't be read ends in an error notice,
      # and the conversation is never saved over it.
      #
      # @param conversation [Puri::Core::Conversation]
      # @return [void]
      def restore(conversation)
        return unless @saved

        @saved = false
        @history = @store.history(@id)
        conversation.restore(Replay.blocks(@history))
      rescue Pikuri::Agent::History::Error => e
        @persist = false
        conversation.add(Protocol::Notice.new(id: nil, text: "Can't read this conversation: #{e.message}",
                                              error: true))
      end

      # Any failure, not only a disk's, ends in the error notice: a history that won't serialize
      # is as lost as one that won't write.
      #
      # @param conversation [Puri::Core::Conversation]
      # @return [void]
      def save(conversation)
        @writes.synchronize do
          next unless @persist && @agent

          @store.save(conversation.summary, @agent.export_history, model: @agent.transport.model,
                                                                   server: @agent.transport.api_base)
        end
      rescue StandardError => e
        conversation.add(Protocol::Notice.new(id: nil, text: "Can't save this conversation: #{e.message}",
                                              error: true))
      end

      # Writes the conversation's title, if it has been saved.
      #
      # @param conversation [Puri::Core::Conversation]
      # @return [void]
      def retitle(conversation)
        @writes.synchronize { @store.retitle(@id, conversation.summary.title) if @persist }
      rescue SystemCallError => e
        LOGGER.warn("can't save the title of #{@id}: #{e.message}")
      end

      # Removes the conversation from the store, and closes its agent.
      #
      # @return [void]
      def delete
        @writes.synchronize do
          @persist = false
          @store.delete(@id)
        end
        close
      end

      # @return [void]
      def close = @agent&.close

      private

      # @param conversation [Puri::Core::Conversation]
      # @return [Pikuri::Agent]
      def build(conversation)
        @confirmer = Confirmer.new(conversation, lock: @lock, cancellable: @cancellable)
        listener = Pikuri::Agent::Listener::RateLimited.new(TurnListener.new(conversation), fps: 15)
        tools = @tools.call(@confirmer)
        agent = Pikuri::Agent.new(transport: @transport, system_prompt: @system_prompt, cancellable: @cancellable,
                                  streaming: true) do |c|
          c.add_listener(listener)
          c.add_tools(tools)
        end
        agent.load_history!(@history) if @history
        @history = nil
        agent
      end
    end
  end
end
