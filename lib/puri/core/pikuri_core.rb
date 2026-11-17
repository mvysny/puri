# frozen_string_literal: true

require 'monitor'

module Puri
  module Core
    # The backend: each conversation a pikuri agent on the configured model, hosted by
    # `Pikuri::Conversations`, everything reported as {Protocol} events.
    #
    #   core = PikuriCore.new(config:, transport: config.primary_llm.transport, titler:, store:) { |event| … }
    #   id = core.ask(nil, 'how do I keep an avocado?')
    #   core.load_conversation(id).blocks   # => [UserMessage, Reply] once it has answered
    #   core.list_conversations.first.title  # => "Keeping An Avocado Fresh", once titled
    #   core.close                           # stops every turn, closes every agent
    #
    # Every conversation the store holds is listed from the start, and read in when it's first
    # loaded or asked in; each is saved after every turn, and deleting one removes it from disk. A
    # new conversation is "New conversation" until the titler names it, once its first turn has
    # ended; a title that fails is logged, and the name stays until a later turn.
    #
    # Thread-safe.
    class PikuriCore
      include Protocol::Backend

      # What `meta.json`'s `shell` says wrote a conversation.
      #
      # @return [String]
      SHELL = 'puri'

      # @return [Logger]
      LOGGER = Pikuri.logger_for('PikuriCore')

      # Longest {#close} waits, in all, for the cancelled turns to be saved and their agents
      # closed.
      #
      # @return [Integer] seconds
      CLOSE_SECONDS = 5

      # The core `config` describes: conversations on its first `[[llm]]`, titles on its
      # `[titler]`, and `web_search` and `web_read_cached` on its `[search]` engines, which
      # return the page text the reader reads (`D_search_engines`). Without a Brave or Exa key it
      # logs an error and wires no web tools, and the system prompt says so. Also sets each
      # `[[server]]`'s `max_concurrent_requests` as that server's
      # `Pikuri::Conversations::Throttle.limit`, which is process-wide; a server stating none is
      # sized from its own slot count.
      #
      #   core = PikuriCore.from_config(Config.load, store: PikuriCore.store) { |event| … }
      #
      # @param config [Puri::Core::Config]
      # @param store [Pikuri::Conversations::Store]
      # @yieldparam event [Data] see {#initialize}
      # @yieldreturn [void]
      # @return [Puri::Core::PikuriCore]
      def self.from_config(config, store:, &)
        config.servers.each do |server|
          permits = server.max_concurrent_requests or next
          Pikuri::Conversations::Throttle.limit(server.url, permits)
          LOGGER.info("#{server.id}: at most #{permits} concurrent request(s) to #{server.url}")
        end
        titler = Pikuri::Conversations::Titler.new(transport: config.titler_llm.transport,
                                                   params_declared: !config.titler_llm.params.empty?)
        unless config.search
          LOGGER.error('[search] in config.toml sets no Brave or Exa key: the agent has no web tools')
        end
        new(config:, transport: config.primary_llm.transport, titler:, store:, &)
      end

      # The saved conversations, in pikuri-web's folder format (`D_port_pikuri_web`).
      #
      # @param env [#[]] where `XDG_STATE_HOME` comes from
      # @return [Pikuri::Conversations::Store] at `$XDG_STATE_HOME/puri/conversations`,
      #   `~/.local/state` by default
      def self.store(env: ENV)
        state = env['XDG_STATE_HOME'].to_s.empty? ? File.join(Dir.home, '.local', 'state') : env['XDG_STATE_HOME']
        Pikuri::Conversations::Store.new(root: File.join(state, 'puri', 'conversations'), shell: SHELL)
      end

      # Puri's cache; not created here.
      #
      # @param env [#[]] where `XDG_CACHE_HOME` comes from
      # @return [String] `$XDG_CACHE_HOME/puri`, `~/.cache/puri` by default
      def self.cache_dir(env: ENV)
        cache = env['XDG_CACHE_HOME'].to_s.empty? ? File.join(Dir.home, '.cache') : env['XDG_CACHE_HOME']
        File.join(cache, 'puri')
      end

      # @param config [Puri::Core::Config] what each conversation's agent is built from
      # @param transport [Pikuri::Agent::ChatTransport] where conversations run
      # @param titler [Pikuri::Conversations::Titler] names each new conversation from its first message
      # @param store [Pikuri::Conversations::Store] where conversations are saved
      # @yieldparam event [Data] a {Protocol} event, on whichever thread caused it
      # @yieldreturn [void]
      def initialize(config:, transport:, titler:, store:, &listener)
        raise ArgumentError, 'PikuriCore needs a listener block' unless listener

        @transport = transport
        @store = store
        @config = config
        @listener = listener
        @lock = Monitor.new
        @conversations = {}
        @entries = {}
        @sessions = {}
        @live = Pikuri::Conversations.new(streaming: true, priority: -3, titler:)
        store.list.reverse_each { |entry| saved(entry) }
      end

      # (see Puri::Protocol::Backend#ask)
      def ask(conversation, text)
        @lock.synchronize do
          id = conversation || create
          session(id).ask(text)
          id
        end
      end

      # (see Puri::Protocol::Backend#cancel)
      def cancel(conversation) = session(conversation).cancel

      # (see Puri::Protocol::Backend#answer)
      def answer(conversation, confirmation, approved) = session(conversation).answer(confirmation, approved)

      # (see Puri::Protocol::Backend#list_conversations)
      def list_conversations
        @lock.synchronize { @conversations.values.reverse.map(&:summary) }
      end

      # (see Puri::Protocol::Backend#load_conversation)
      def load_conversation(conversation)
        @lock.synchronize do
          session(conversation)
          @conversations.fetch(conversation).transcript
        end
      end

      # (see Puri::Protocol::Backend#delete_conversation)
      def delete_conversation(conversation)
        @lock.synchronize do
          session(conversation).delete
          @conversations.delete(conversation)
          @sessions.delete(conversation)
          publish
        end
      end

      # Closes every conversation, cancelling its turn, and waits for each turn to be saved and
      # its agent closed. Not under the core's lock: a turn's save takes it.
      #
      # @return [void]
      def close
        return if @live.shutdown(timeout: CLOSE_SECONDS)

        LOGGER.warn("a turn still saving after #{CLOSE_SECONDS} s of closing")
      end

      private

      # @param id [String]
      # @return [Puri::Core::AgentSession] a saved conversation's, read in on first use
      # @raise [ArgumentError] for a conversation this core doesn't hold
      def session(id)
        @lock.synchronize do
          @sessions[id] ||= begin
            conversation = @conversations[id] or raise ArgumentError, "no conversation #{id.inspect}"
            agent_session(conversation, @entries.fetch(id), saved: true).tap(&:restore)
          end
        end
      end

      # @return [String] the new conversation's id
      def create
        entry = @store.create
        conversation = add(entry)
        @sessions[entry.id] = agent_session(conversation, entry, saved: false)
        publish
        entry.id
      end

      # Lists a saved conversation; {#session} reads it in.
      #
      # @param entry [Pikuri::Conversations::Store::Entry]
      # @return [void]
      def saved(entry)
        add(entry, title: @store.stamp_titled?(entry) ? Conversation::NEW_TITLE : entry.title,
                   last_question: entry.extra['last_question']&.to_s, asked_at: time(entry.extra['asked_at']))
      end

      # @param iso [Object] a `meta.json` value
      # @return [Time, nil] local time; nil for anything but an ISO 8601 string
      def time(iso)
        Time.iso8601(iso).getlocal if iso.is_a?(String)
      rescue ArgumentError
        nil
      end

      # @param entry [Pikuri::Conversations::Store::Entry]
      # @param state [Hash{Symbol => Object}] a saved one's {Conversation#initialize} `title:`,
      #   `last_question:` and `asked_at:`
      # @return [Puri::Core::Conversation]
      def add(entry, **state)
        @entries[entry.id] = entry
        @conversations[entry.id] = Conversation.new(id: entry.id, lock: @lock, emit: @listener,
                                                    changed: -> { publish }, started_at: entry.created_at.getlocal,
                                                    **state)
      end

      # @param conversation [Puri::Core::Conversation]
      # @param entry [Pikuri::Conversations::Store::Entry]
      # @param saved [Boolean]
      # @return [Puri::Core::AgentSession]
      def agent_session(conversation, entry, saved:)
        AgentSession.new(conversation, entry:, store: @store, conversations: @live, transport: @transport,
                                       config: @config, lock: @lock, saved:)
      end

      # @return [void]
      def publish
        @listener.call(Protocol::ConversationsChanged.new(conversations: list_conversations))
      end
    end
  end
end
