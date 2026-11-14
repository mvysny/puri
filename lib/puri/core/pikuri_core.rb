# frozen_string_literal: true

require 'monitor'

module Puri
  module Core
    # The backend: each conversation a pikuri agent on the configured model, hosted by
    # `Pikuri::Conversations`, everything reported as {Protocol} events.
    #
    #   core = PikuriCore.new(transport: config.primary_llm.transport, titler:, store:) { |event| … }
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

      # Our own system prompt (`D_own_prompts`); the date is appended per conversation.
      #
      # @return [String]
      SYSTEM_PROMPT = File.read(File.expand_path('../../../prompts/puri.txt', __dir__)).rstrip

      # What `meta.json`'s `shell` says wrote a conversation.
      #
      # @return [String]
      SHELL = 'puri'

      # @return [Logger]
      LOGGER = Pikuri.logger_for('PikuriCore')

      # Longest {#close} waits for the cancelled turns to be saved, and then again for their
      # agents to close.
      #
      # @return [Integer] seconds
      CLOSE_SECONDS = 5

      # The core `config` describes: conversations on its first `[[llm]]`, titles on its
      # `[titler]`. Also sets each `[[server]]`'s `max_concurrent_requests` as that server's
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
        new(transport: config.primary_llm.transport, titler:, store:, &)
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

      # @param transport [Pikuri::Agent::ChatTransport] where conversations run
      # @param titler [Pikuri::Conversations::Titler] names each new conversation from its first message
      # @param store [Pikuri::Conversations::Store] where conversations are saved
      # @param tools [Proc] takes a conversation's {Confirmer}, returns its agent's
      #   `Array<Pikuri::Tool>`; called once per conversation
      # @yieldparam event [Data] a {Protocol} event, on whichever thread caused it
      # @yieldreturn [void]
      def initialize(transport:, titler:, store:, tools: ->(_confirmer) { [] }, &listener)
        raise ArgumentError, 'PikuriCore needs a listener block' unless listener

        @transport = transport
        @store = store
        @tools = tools
        @listener = listener
        @lock = Monitor.new
        @conversations = {}
        @entries = {}
        @sessions = {}
        @live = Pikuri::Conversations.new(
          system_prompt: ->(_conversation) { "#{SYSTEM_PROMPT}\n\nToday is #{Time.now.strftime('%A, %-d %B %Y')}." },
          configure: ->(config, conversation) { conversation.listener.configure(config) },
          on_turn_end: ->(conversation, history) { conversation.listener.save(history) },
          streaming: true, priority: -3, titler:
        )
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

      # Cancels every turn and waits for it to be saved, then closes every agent.
      #
      # @return [void]
      def close
        @live.each(&:cancel)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + CLOSE_SECONDS
        until @live.none? { _1.status.state == :running } || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          sleep 0.01
        end
        @live.shutdown(timeout: CLOSE_SECONDS)
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
                                       tools: @tools, lock: @lock, saved:)
      end

      # @return [void]
      def publish
        @listener.call(Protocol::ConversationsChanged.new(conversations: list_conversations))
      end
    end
  end
end
