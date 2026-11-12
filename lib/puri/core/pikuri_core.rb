# frozen_string_literal: true

require 'monitor'

module Puri
  module Core
    # The backend: each conversation a pikuri agent on the configured model, its turns on threads
    # of their own, everything reported as {Protocol} events.
    #
    #   core = PikuriCore.new(transport: config.primary_llm.transport) { |event| client.deliver(event) }
    #   id = core.ask(nil, 'how do I keep an avocado?')
    #   core.load_conversation(id).blocks   # => [UserMessage, Reply] once it has answered
    #   core.close                           # stops every turn, closes every agent
    #
    # Thread-safe.
    class PikuriCore
      include Protocol::Backend

      # Our own system prompt (`D_own_prompts`); the date is appended per conversation.
      #
      # @return [String]
      SYSTEM_PROMPT = File.read(File.expand_path('../../../prompts/puri.txt', __dir__)).rstrip

      # @param transport [Pikuri::Agent::ChatTransport] where conversations run
      # @param tools [Proc] takes a conversation's {Confirmer}, returns its agent's
      #   `Array<Pikuri::Tool>`; called once per conversation
      # @yieldparam event [Data] a {Protocol} event, on whichever thread caused it
      # @yieldreturn [void]
      def initialize(transport:, tools: ->(_confirmer) { [] }, &listener)
        raise ArgumentError, 'PikuriCore needs a listener block' unless listener

        @transport = transport
        @tools = tools
        @listener = listener
        @lock = Monitor.new
        @conversations = {}
        @sessions = {}
        @threads = ThreadGroup.new
      end

      # (see Puri::Protocol::Backend#ask)
      def ask(conversation, text)
        @lock.synchronize do
          target = conversation ? fetch(conversation) : create
          target.ask(text)
          target.id
        end
      end

      # (see Puri::Protocol::Backend#cancel)
      def cancel(conversation) = fetch(conversation).cancel

      # (see Puri::Protocol::Backend#answer)
      def answer(conversation, confirmation, approved) = fetch(conversation).answer(confirmation, approved)

      # (see Puri::Protocol::Backend#list_conversations)
      def list_conversations
        @lock.synchronize { @conversations.values.reverse.map(&:summary) }
      end

      # (see Puri::Protocol::Backend#load_conversation)
      def load_conversation(conversation) = fetch(conversation).transcript

      # (see Puri::Protocol::Backend#delete_conversation)
      def delete_conversation(conversation)
        @lock.synchronize do
          fetch(conversation).cancel
          @conversations.delete(conversation)
          @sessions.delete(conversation).close
          publish
        end
      end

      # Kills every turn's thread, waits until they're gone, then closes every agent.
      #
      # @return [void]
      def close
        until (threads = @threads.list).empty?
          threads.each(&:kill).each(&:join)
        end
        @lock.synchronize { @sessions.each_value(&:close) }
      end

      private

      # @param id [String]
      # @return [Puri::Core::Conversation]
      # @raise [ArgumentError]
      def fetch(id)
        @lock.synchronize { @conversations[id] } or raise ArgumentError, "no conversation #{id.inspect}"
      end

      # @return [Puri::Core::Conversation]
      def create
        id = SecureRandom.uuid
        session = AgentSession.new(transport: @transport, lock: @lock, tools: @tools,
                                   system_prompt: "#{SYSTEM_PROMPT}\n\nToday is #{Time.now.strftime('%A, %-d %B %Y')}.")
        conversation = Conversation.new(id:, lock: @lock, emit: @listener, changed: -> { publish },
                                        threads: @threads, turns: session)
        @sessions[id] = session
        @conversations[id] = conversation
        publish
        conversation
      end

      # @return [void]
      def publish
        @listener.call(Protocol::ConversationsChanged.new(conversations: list_conversations))
      end
    end
  end
end
