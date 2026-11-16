# frozen_string_literal: true

module Puri
  module Core
    # One {PikuriCore} conversation's pikuri side: its live `Pikuri::Conversations::Conversation`,
    # opened on the first question, the {Confirmer} its tools and extensions ask through, and its folder in the
    # store. It opens that conversation as its listener and its saver, its agents built by its
    # {Initializer}:
    #
    #   session = AgentSession.new(conversation, entry:, store:, conversations:, transport:, config:, lock:,
    #                              saved: true)
    #   session.restore                        # a saved one's blocks, once, before anyone reads them
    #   session.ask('how do I keep an avocado?')
    #   session.cancel
    #   session.delete                         # closes it, and removes it from disk
    #
    # Every turn is saved once it ends, a cancelled or failed one too; a save that fails ends in an
    # error notice. The gem titles a conversation opened `untitled:` after its first turn, and the
    # title is saved too.
    #
    # == Threading
    #
    # {#ask}, {#cancel}, {#answer}, {#restore} and {#delete} come from the core, under its lock.
    # {#on_event} and {#save} run on the gem's threads; {#save} and a title's write take this
    # session's own lock, so a save never carries a title older than the one on disk. A save
    # still ending after {#delete} writes nothing: `Store#delete` is final.
    class AgentSession < Pikuri::Agent::Listener::Base
      include Pikuri::Conversations::Saver

      # @return [Logger]
      LOGGER = Pikuri.logger_for('AgentSession')

      # Builds each of a session's agents from the config: our system prompt, the web tools
      # `[search]` keys, and the {Confirmer} the agent's tools ask through.
      #
      #   initializer = Initializer.new(config, conversation, lock:)
      #   conversations.open(id:, transport:, listener:, initializer:)
      #   initializer.confirmer   # the latest agent's, once one has booted
      #
      # Called on the boot's thread, once per agent: a clear or a failed boot builds another, with
      # a {Confirmer} of its own.
      class Initializer
        include Pikuri::Conversations::AgentInitializer

        # Where our own system prompts live (`D_own_prompts`).
        #
        # @return [String]
        PROMPTS = File.expand_path('../../../prompts', __dir__)

        # Our system prompt, and the fragment that says what the agent can reach; {#system_prompt}
        # appends the date.
        #
        # @param web [Boolean] whether the agent has the web tools
        # @return [String]
        def self.system_prompt(web:)
          %W[puri.txt #{web ? 'web.txt' : 'offline.txt'}].map { File.read(File.join(PROMPTS, _1)).rstrip }.join("\n")
        end

        # @return [Confirmer, nil] the latest agent's; nil until one has booted
        attr_reader :confirmer

        # @param config [Puri::Core::Config]
        # @param conversation [Puri::Core::Conversation] where a confirmation shows
        # @param lock [Monitor] the core's
        def initialize(config, conversation, lock:)
          @config = config
          @conversation = conversation
          @lock = lock
          @confirmer = nil
        end

        # @param _conversation [Pikuri::Conversations::Conversation] this session's
        # @return [String] {.system_prompt} for the tools the config gives, then today's date; the
        #   agent appends its extensions' own fragments
        def system_prompt(_conversation)
          "#{Initializer.system_prompt(web: !@config.search.nil?)}\n\nToday is #{Time.now.strftime('%A, %-d %B %Y')}."
        end

        # Adds the web tools. An extension goes here too, built afresh for each agent as pikuri
        # asks, and one that asks before it acts takes {#confirmer}.
        #
        # @param configurator [Pikuri::Agent::Configurator]
        # @param _conversation [Pikuri::Conversations::Conversation] this session's
        # @return [void]
        def configure(configurator, _conversation)
          @confirmer = Confirmer.new(@conversation, lock: @lock)
          configurator.add_tools(web_tools)
        end

        private

        # @return [Array<Pikuri::Tool>] `web_search` with page text, and `web_read_cached`; none
        #   without a keyed `[search]`
        def web_tools
          search = @config.search or return []
          [Pikuri::Web::Search.build(engines: search.engines, brave_key: search.brave_key, exa_key: search.exa_key,
                                     page_text: true),
           Pikuri::Web::READ_CACHED]
        end
      end

      # @param conversation [Puri::Core::Conversation] where the turns show
      # @param entry [Pikuri::Conversations::Store::Entry] its folder
      # @param store [Pikuri::Conversations::Store]
      # @param conversations [Pikuri::Conversations] the live ones, which this one joins on its
      #   first question
      # @param transport [Pikuri::Agent::ChatTransport]
      # @param config [Puri::Core::Config] what its agents are built from
      # @param lock [Monitor] the core's
      # @param saved [Boolean] whether the store holds this conversation already
      def initialize(conversation, entry:, store:, conversations:, transport:, config:, lock:, saved:)
        super()
        @conversation = conversation
        @entry = entry
        @store = store
        @conversations = conversations
        @transport = transport
        # self.class's: a spec's subclass brings an Initializer that adds what Puri doesn't wire.
        @initializer = self.class::Initializer.new(config, conversation, lock:)
        @lock = lock
        @saved = saved
        @untitled = !saved || store.stamp_titled?(entry) || entry.title == Conversation::NEW_TITLE
        @display = Pikuri::Conversations::RateLimitedListener.new(
          TurnListener.new(conversation, server: transport.api_base), fps: 15
        )
        @live = nil
        @history = nil
        @writes = Mutex.new
        @unreadable = false
      end

      # Fills a saved conversation's blocks from its history, the first time only; the agent
      # resumes from that history. One that can't be read ends in an error notice, and the
      # conversation is never saved over it.
      #
      # @return [void]
      def restore
        return unless @saved

        @saved = false
        @history = @store.history(@entry)
        @conversation.restore(Replay.blocks(@history))
      rescue Pikuri::Conversations::HistoryFile::Error => e
        @unreadable = true
        @conversation.add(Protocol::Notice.new(id: nil, text: "Can't read this conversation: #{e.message}",
                                               error: true))
      end

      # Answers a waiting confirmation with the text, or else sends it to the agent: it starts a
      # turn, or the running turn reads it after its current step.
      #
      # @param text [String]
      # @return [void]
      def ask(text)
        @conversation.asked(text)
        if @initializer.confirmer&.redirect(text)
          @conversation.add(Protocol::UserMessage.new(id: nil, text:))
        else
          @conversation.activity = TurnListener::THINKING unless @conversation.running?
          live.submit(text)
        end
      end

      # Stops the running turn; a message it hasn't read yet is shown, and dropped.
      #
      # @return [void]
      def cancel
        return unless @live

        drop_pending
        @live.cancel
      end

      # @param confirmation [String] the block id the user answered
      # @param approved [Boolean]
      # @return [void]
      def answer(confirmation, approved) = @initializer.confirmer&.answer(confirmation, approved)

      # Closes the live conversation, cancelling its turn, and removes it from disk; the turn's
      # own save, still to come, writes nothing.
      #
      # @return [void]
      def delete
        @live&.close(force: true)
        @store.delete(@entry)
      end

      # Any failure, not only a disk's, ends in the error notice: a history that won't serialize
      # is as lost as one that won't write.
      #
      # @param _conversation [Pikuri::Conversations::Conversation] this session's
      # @param history [Pikuri::Agent::History]
      # @return [void]
      def save(_conversation, history)
        @writes.synchronize do
          next if @unreadable

          summary = @conversation.summary
          extra = { 'last_question' => summary.last_question,
                    'asked_at' => summary.asked_at && Time.iso8601(summary.asked_at).utc.iso8601 }
          on = @live.status.model
          @store.save(@entry, history, model: on.model, server: on.api_base, extra:)
        end
      rescue StandardError => e
        @conversation.add(Protocol::Notice.new(id: nil, text: "Can't save this conversation: #{e.message}",
                                               error: true))
      end

      # Shows the event, then goes idle once the gem says no work is under way. `TurnEnded` goes
      # through the limiter too: it flushes a failed turn's tail ahead of the failure notice.
      #
      # @param event [Object] an agent's `Pikuri::Agent::Event` or a `Pikuri::Conversations::Event`
      # @return [void]
      def on_event(event)
        case event
        when Pikuri::Conversations::Event::Titled then retitle(event.title)
        when Pikuri::Conversations::Event::Ready then cancelled_boot
        when Pikuri::Conversations::Event::BootFailed then failed_boot(event.error)
        else @display.on_event(event)
        end
        settle
      end

      private

      # @return [Pikuri::Conversations::Conversation] opened on first use
      def live
        @live ||= @conversations.open(id: @conversation.id, transport: @transport, listener: self, saver: self,
                                      initializer: @initializer, history: @history, boot: false,
                                      untitled: @untitled)
      end

      # @param title [String]
      # @return [void]
      def retitle(title)
        @conversation.title = title
        @writes.synchronize { @entry = @unreadable ? @entry.with(title:) : @store.retitle(@entry, title) }
      rescue SystemCallError => e
        LOGGER.warn("can't save the title of #{@conversation.id}: #{e.message}")
      end

      # A boot that ends with no work under way was cancelled, its message dropped: every boot
      # here has one waiting, since a conversation opens on its first {#ask}.
      #
      # @return [void]
      def cancelled_boot
        return if @live.status.busy?

        @conversation.add(Protocol::Notice.new(id: nil, text: 'Cancelled', error: false))
      end

      # The messages that waited for the agent are shown, then dropped with the error.
      #
      # @param error [StandardError]
      # @return [void]
      def failed_boot(error)
        drop_pending
        @conversation.add(Protocol::Notice.new(id: nil, text: "Can't start the agent: #{error.message}", error: true))
      end

      # Idle once `Status#busy?` says so, re-read on every event rather than inferred from which
      # events came: a boot cancelled before its turn ends in `Ready` alone. Under the core's lock,
      # so it never undoes the "Thinking…" {#ask} shows before its message reaches the gem.
      #
      # @return [void]
      def settle
        @lock.synchronize do
          @conversation.activity = Protocol::Activity::IDLE if @live && @conversation.running? && !@live.status.busy?
        end
      end

      # Takes the messages the agent hasn't read, showing each, so none vanishes unseen.
      #
      # @return [void]
      def drop_pending
        @live.discard_pending.each do |item|
          @conversation.add(Protocol::UserMessage.new(id: nil, text: item.content)) if item.kind == :user
        end
      end
    end
  end
end
