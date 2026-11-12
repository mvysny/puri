# frozen_string_literal: true

require 'monitor'

module Puri
  module Core
    # The backend: each conversation a pikuri agent on the configured model, its turns on threads
    # of their own, everything reported as {Protocol} events.
    #
    #   core = PikuriCore.new(transport: config.primary_llm.transport, titler:, store:) { |event| … }
    #   id = core.ask(nil, 'how do I keep an avocado?')
    #   core.load_conversation(id).blocks   # => [UserMessage, Reply] once it has answered
    #   core.list_conversations.first.title  # => "Keeping An Avocado Fresh", once titled
    #   core.close                           # stops every turn and title, closes every agent
    #
    # Every conversation the {Store} holds is listed from the start, and read in when it's first
    # loaded or asked in; each is saved after every turn, and deleting one removes it from disk.
    # A new conversation is "New conversation" until its title arrives, on a thread of its own
    # that runs beside the first turn; a title that fails is logged, and the name stays.
    #
    # Thread-safe.
    class PikuriCore
      include Protocol::Backend

      # Our own system prompt (`D_own_prompts`); the date is appended per conversation.
      #
      # @return [String]
      SYSTEM_PROMPT = File.read(File.expand_path('../../../prompts/puri.txt', __dir__)).rstrip

      # @return [Logger]
      LOGGER = Pikuri.logger_for('PikuriCore')

      # The core `config` describes: conversations on its first `[[llm]]`, titles on its
      # `[titler]`. Also sets each `[[server]]`'s `max_concurrent_requests` as that server's
      # `Pikuri::Agent::ServerPermits.limit`, which is process-wide; a server stating none is
      # left for pikuri to size from its own slot count.
      #
      #   core = PikuriCore.from_config(Config.load, store: Store.new(root: Store.default_root)) { |event| … }
      #
      # @param config [Puri::Core::Config]
      # @param store [Puri::Core::Store]
      # @yieldparam event [Data] see {#initialize}
      # @yieldreturn [void]
      # @return [Puri::Core::PikuriCore]
      def self.from_config(config, store:, &)
        config.servers.each do |server|
          permits = server.max_concurrent_requests or next
          Pikuri::Agent::ServerPermits.limit(server.url, permits)
          LOGGER.info("#{server.id}: at most #{permits} concurrent request(s) to #{server.url}")
        end
        titler = Titler.new(transport: config.titler_llm.transport, params_declared: !config.titler_llm.params.empty?)
        new(transport: config.primary_llm.transport, titler:, store:, &)
      end

      # @param transport [Pikuri::Agent::ChatTransport] where conversations run
      # @param titler [Puri::Core::Titler] names each new conversation from its first message
      # @param store [Puri::Core::Store] where conversations are saved
      # @param tools [Proc] takes a conversation's {Confirmer}, returns its agent's
      #   `Array<Pikuri::Tool>`; called once per conversation
      # @yieldparam event [Data] a {Protocol} event, on whichever thread caused it
      # @yieldreturn [void]
      def initialize(transport:, titler:, store:, tools: ->(_confirmer) { [] }, &listener)
        raise ArgumentError, 'PikuriCore needs a listener block' unless listener

        @transport = transport
        @titler = titler
        @store = store
        @tools = tools
        @listener = listener
        @lock = Monitor.new
        @conversations = {}
        @sessions = {}
        @threads = ThreadGroup.new
        store.list.reverse_each { |summary| saved(summary) }
      end

      # (see Puri::Protocol::Backend#ask)
      def ask(conversation, text)
        @lock.synchronize do
          target = conversation ? fetch(conversation) : create(text)
          target.ask(text)
          target.id
        end
      end

      # (see Puri::Protocol::Backend#cancel)
      def cancel(conversation) = find(conversation).cancel

      # (see Puri::Protocol::Backend#answer)
      def answer(conversation, confirmation, approved) = find(conversation).answer(confirmation, approved)

      # (see Puri::Protocol::Backend#list_conversations)
      def list_conversations
        @lock.synchronize { @conversations.values.reverse.map(&:summary) }
      end

      # (see Puri::Protocol::Backend#load_conversation)
      def load_conversation(conversation) = fetch(conversation).transcript

      # (see Puri::Protocol::Backend#delete_conversation)
      def delete_conversation(conversation)
        @lock.synchronize do
          find(conversation).cancel
          @conversations.delete(conversation)
          session = @sessions.delete(conversation)
          session ? session.delete : @store.delete(conversation)
          publish
        end
      end

      # Kills every turn's and title's thread, waits until they're gone, then closes every agent.
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
      # @return [Puri::Core::Conversation] a saved one maybe not read in yet
      # @raise [ArgumentError]
      def find(id)
        @lock.synchronize { @conversations[id] } or raise ArgumentError, "no conversation #{id.inspect}"
      end

      # @param id [String]
      # @return [Puri::Core::Conversation] read in from the store, if it's a saved one
      # @raise [ArgumentError]
      def fetch(id)
        @lock.synchronize do
          conversation = find(id)
          @sessions[id] ||= session(id, saved: true).tap { |session| session.restore(conversation) }
          conversation
        end
      end

      # @param text [String] the opening message, which the title comes from
      # @return [Puri::Core::Conversation]
      def create(text)
        started_at = Time.now
        id = @store.mint(started_at)
        conversation = add(id:, started_at:)
        @sessions[id] = session(id, saved: false)
        publish
        title(conversation, text)
        conversation
      end

      # Lists a saved conversation; {#fetch} reads it in.
      #
      # @param summary [Puri::Protocol::ConversationSummary]
      # @return [void]
      def saved(summary)
        add(id: summary.id, started_at: Time.iso8601(summary.started_at), title: summary.title,
            last_question: summary.last_question, asked_at: summary.asked_at && Time.iso8601(summary.asked_at))
      end

      # @param id [String]
      # @param state [Hash{Symbol => Object}] {Conversation#initialize}'s `started_at:`, and a saved
      #   one's `title:`, `last_question:` and `asked_at:`
      # @return [Puri::Core::Conversation]
      def add(id:, **state)
        @conversations[id] = Conversation.new(id:, lock: @lock, emit: @listener, changed: -> { publish },
                                              threads: @threads, turns: ->(c) { @sessions.fetch(c.id).call(c) },
                                              **state)
      end

      # @param id [String]
      # @param saved [Boolean] whether the store holds it already
      # @return [Puri::Core::AgentSession]
      def session(id, saved:)
        AgentSession.new(id:, transport: @transport, lock: @lock, tools: @tools, store: @store, saved:,
                         system_prompt: "#{SYSTEM_PROMPT}\n\nToday is #{Time.now.strftime('%A, %-d %B %Y')}.")
      end

      # @param conversation [Puri::Core::Conversation]
      # @param text [String] its opening message
      # @return [void]
      def title(conversation, text)
        @threads.add(Thread.new do
          Thread.current.priority = -3
          title = @titler.title_for(text)
          session = @lock.synchronize do
            next unless title && @conversations.key?(conversation.id)

            conversation.title = title
            @sessions[conversation.id]
          end
          session&.retitle(conversation)
        rescue StandardError => e
          LOGGER.warn("can't title conversation #{conversation.id}: #{e.class}: #{e.message}")
        end)
      end

      # @return [void]
      def publish
        @listener.call(Protocol::ConversationsChanged.new(conversations: list_conversations))
      end
    end
  end
end
