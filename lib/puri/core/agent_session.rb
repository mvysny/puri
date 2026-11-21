# frozen_string_literal: true

module Puri
  module Core
    # One {PikuriCore} conversation's pikuri side: its live `Pikuri::Conversations::Conversation`,
    # opened on the first question, the {Confirmer} its tools and extensions ask through, and its folder in the
    # store. It opens that conversation as its listener and its saver, its agents built by its
    # {Initializer}:
    #
    #   session = AgentSession.new(conversation, entry:, store:, conversations:, transport:, models:, config:,
    #                              lock:, saved: true)
    #   session.restore                        # a saved one's blocks, once, before anyone reads them
    #   session.ask('how do I keep an avocado?')
    #   session.select_model(models.find('Qwen 3.6'))   # for the next turn
    #   session.cancel
    #   session.delete                         # closes it, and removes it from disk
    #
    # Every turn is saved once it ends, a cancelled or failed one too, the {Places::Notebook} of
    # what its place tools found with it; a save that fails ends in an error notice. The gem
    # titles a conversation opened `untitled:` after its first turn, and the title is saved too.
    # The conversation's {Protocol::Status} follows the model picked and the tokens each reply
    # reports, through a {ContextReadout}.
    #
    # == Threading
    #
    # {#ask}, {#cancel}, {#answer}, {#select_model}, {#restore} and {#delete} come from the core,
    # under its lock.
    # {#on_event} and {#save} run on the gem's threads; {#save} and a title's write take this
    # session's own lock, so a save never carries a title older than the one on disk. A save
    # still ending after {#delete} writes nothing: `Store#delete` is final.
    class AgentSession < Pikuri::Agent::Listener::Base
      include Pikuri::Conversations::Saver

      # @return [Logger]
      LOGGER = Pikuri.logger_for('AgentSession')

      # Builds each of a session's agents from the config: our system prompt, the web tools
      # `[search]` keys, the Thunderbird profile `[thunderbird]` names, and the {Confirmer} the
      # agent's tools ask through.
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

        # Our system prompt, and the fragments that say what the agent can reach; {#system_prompt}
        # appends the date, and the memory.
        #
        # @param web [Boolean] whether the agent has the web tools
        # @param documents [Boolean] whether it has the documents folder
        # @param places [Boolean] whether it has the place tools
        # @return [String]
        def self.system_prompt(web:, documents:, places: false)
          files = %W[puri.txt #{web ? 'web.txt' : 'offline.txt'} #{documents ? 'documents.txt' : 'no-documents.txt'}]
          files << 'places.txt' if places
          files.map { File.read(File.join(PROMPTS, _1)).rstrip }.join("\n")
        end

        # @return [Confirmer, nil] the latest agent's; nil until one has booted
        attr_reader :confirmer

        # @param config [Puri::Core::Config]
        # @param conversation [Puri::Core::Conversation] where a confirmation shows
        # @param lock [Monitor] the core's
        # @param library [Puri::Core::Library, nil] the `[documents]` folder; nil without one
        # @param cache_dir [String] where each agent's Thunderbird snapshots go, in a folder of their own
        # @param osm [Puri::Core::Places::Osm, nil] what the place tools ask; nil wires none
        # @param notebook [Puri::Core::Places::Notebook, nil] the conversation's places, which the
        #   place tools number and draw in
        def initialize(config, conversation, lock:, library: nil, cache_dir: PikuriCore.cache_dir, osm: nil,
                       notebook: nil)
          @config = config
          @conversation = conversation
          @lock = lock
          @library = library
          @cache_dir = cache_dir
          @osm = notebook && osm
          @notebook = notebook
          @confirmer = nil
        end

        # The machine's time zone, for the prompt:
        #
        #   Initializer.time_zone(Time.now)   # => "Europe/Helsinki (UTC+02:00)"
        #
        # Just "UTC+02:00" when neither `TZ` nor the `/etc/localtime` link names a zone.
        #
        # @param now [Time] local
        # @param tz_env [String, nil] the `TZ` variable
        # @param localtime [String] the zoneinfo link
        # @return [String]
        def self.time_zone(now, tz_env: ENV.fetch('TZ', nil), localtime: '/etc/localtime')
          name = tz_env.to_s.delete_prefix(':')
          name = File.readlink(localtime) if name.empty? && File.symlink?(localtime)
          name = name[%r{zoneinfo/(.+)\z}, 1] || name
          offset = "UTC#{now.strftime('%:z')}"
          name.empty? ? offset : "#{name} (#{offset})"
        end

        # @param _conversation [Pikuri::Conversations::Conversation] this session's
        # @return [String] {.system_prompt} for the tools the config gives, then today's date, the
        #   time zone, and with documents their folder and the memory; the agent appends its
        #   extensions' own fragments
        def system_prompt(_conversation)
          now = Time.now
          "#{Initializer.system_prompt(web: !@config.search.nil?, documents: !@library.nil?, places: !@osm.nil?)}\n\n" \
            "Today is #{now.strftime('%A, %-d %B %Y')}; the time zone is #{Initializer.time_zone(now)}." \
            "#{library_prompt}"
        end

        # Adds the calculator, the web tools, the place tools, the Thunderbird extension, and the
        # documents' search and file tools. An extension is built afresh for each agent as pikuri
        # asks, and one that asks before it acts takes {#confirmer}.
        #
        # @param configurator [Pikuri::Agent::Configurator]
        # @param _conversation [Pikuri::Conversations::Conversation] this session's
        # @return [void]
        def configure(configurator, _conversation)
          @confirmer = Confirmer.new(@conversation, lock: @lock)
          configurator.add_tool(Pikuri::Tool::CALCULATOR)
          configurator.add_tools(web_tools)
          if @osm
            configurator.add_tools([Places::SearchTool.new(osm: @osm, notebook: @notebook),
                                    Places::RouteTool.new(osm: @osm, notebook: @notebook)])
          end
          configurator.add_extension(thunderbird(configurator)) if @config.thunderbird
          return unless @library

          configurator.add_tools(@library.file_index_tools)
          configurator.add_extension(workspace)
        end

        private

        # The memory is read once per agent, so a change the agent makes reaches the prompt in
        # the next conversation: rewriting this one's would cost the server's cache of it, for a
        # fact the write already told the model.
        #
        # @return [String] "" without documents
        def library_prompt
          return '' unless @library

          documents = @library.documents
          memory = @library.memory
          path = Pathname.new(documents.memory).relative_path_from(documents.folder)
          block = if memory.empty?
                    "#{path} does not exist yet or is empty; create it the first time the user asks you to " \
                      'remember something.'
                  else
                    "<memory path=\"#{path}\">\n#{memory}\n</memory>"
                  end
          "\n\nThe user's documents folder is #{documents.folder}.\n\n#{block}"
        end

        # Reads the whole documents folder, and writes only its `Notes/`, unasked (owner,
        # 2026-11-17): the folder is the gate, and each write's line names its file. No `grep`: it
        # can't see inside a PDF, and would answer "no match" where `fileindex_search` finds it.
        #
        # @return [Pikuri::Workspace::Extension]
        def workspace
          documents = @library.documents
          filesystem = Pikuri::Workspace::Filesystem.new(project_root: documents.folder, root_writable: false,
                                                         writable: [documents.notes], private: true, trusted: false)
          Pikuri::Workspace::Extension.new(filesystem:, confirmer: Pikuri::Workspace::Confirmer::AutoApprove.new,
                                           grep: false)
        end

        # Mail, contacts and calendar, read from the local profile, and both hand-offs: a drafted
        # mail opens in Thunderbird's compose window, an event in its import wizard, and the user
        # sends or adds it there, so neither asks through {#confirmer}. No profile on the machine
        # wires nothing; two installs with a mail account fail the boot, naming both.
        #
        # Its snapshots go in a fresh folder under {#initialize}'s `cache_dir`, removed when the
        # agent closes: two extensions sharing one copy each other's under an open database.
        #
        # @param configurator [Pikuri::Agent::Configurator]
        # @return [Pikuri::Thunderbird::Extension]
        def thunderbird(configurator)
          FileUtils.mkdir_p(@cache_dir, mode: 0o700)
          snapshots = Dir.mktmpdir('thunderbird-', @cache_dir)
          # Registered before the extension's own, so it runs after they close the copies.
          configurator.on_close { FileUtils.rm_rf(snapshots) }
          Pikuri::Thunderbird::Extension.new(profile_dir: @config.thunderbird.profile_dir, cache_dir: snapshots,
                                             allow_compose_mail: true, allow_create_calendar_event: true)
        end

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
      # @param transport [Pikuri::Agent::ChatTransport] the connection it starts on
      # @param models [Puri::Core::Models] what names the connection in its status
      # @param config [Puri::Core::Config] what its agents are built from
      # @param lock [Monitor] the core's
      # @param saved [Boolean] whether the store holds this conversation already
      # @param library [Puri::Core::Library, nil] the `[documents]` folder its agents search
      # @param osm [Puri::Core::Places::Osm, nil] what its place tools ask; nil wires none
      def initialize(conversation, entry:, store:, conversations:, transport:, models:, config:, lock:, saved:,
                     library: nil, osm: nil)
        super()
        @conversation = conversation
        @entry = entry
        @store = store
        @conversations = conversations
        @transport = transport
        @models = models
        # Kept without [maps] too, so a save never drops the places an earlier run found.
        @notebook = Places::Notebook.new(tiles: config.maps&.tiles, saved: (entry.extra['places'] if saved))
        # self.class's: a spec's subclass brings an Initializer that adds what Puri doesn't wire.
        @initializer = self.class::Initializer.new(config, conversation, lock:, library:,
                                                                         osm: (osm if config.maps), notebook: @notebook)
        @lock = lock
        @saved = saved
        @untitled = !saved || store.stamp_titled?(entry) || entry.title == Conversation::NEW_TITLE
        @display = Pikuri::Conversations::RateLimitedListener.new(
          TurnListener.new(conversation, server: transport.api_base, notebook: @notebook), fps: 15
        )
        @live = nil
        @history = nil
        @writes = Mutex.new
        @unreadable = false
        @readout = ContextReadout.new(cap: Pikuri::Conversations::Probe.facts(transport).context_window)
        publish_status
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
        @conversation.restore(Replay.blocks(@history, notebook: @notebook))
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

      # Stops the running turn, which says "Cancelling…" until it notices; a message it hasn't
      # read yet moves from the queue into the transcript, and is dropped.
      #
      # @return [void]
      def cancel
        return unless @live

        drop_pending
        @conversation.cancelling if @live.cancel == :cancelled
      end

      # The next turn runs on `choice`; a running one ends on its own model.
      #
      # @param choice [Puri::Core::Models::Choice]
      # @return [void]
      def select_model(choice)
        if @live
          @live.switch_model(choice.transport)
        else
          @transport = choice.transport
          @readout.cap = Pikuri::Conversations::Probe.facts(choice.transport).context_window
        end
        publish_status
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
          extra['places'] = @notebook.to_h unless @notebook.empty?
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
        when Pikuri::Conversations::Event::PendingChanged then pending(event.items)
        when Pikuri::Conversations::Event::ModelPending, Pikuri::Agent::Event::ModelSwitched
          publish_status
          @display.on_event(event)
        else
          publish_status if @readout.on_event(event)
          @display.on_event(event)
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

      # Under the core's lock, so two threads' updates land in the order they read the gem.
      #
      # @return [void]
      def publish_status
        @lock.synchronize do
          @conversation.status = @readout.status(@models.name_for(@live ? @live.status.next_model : @transport))
        end
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

      # Shows what the user sent that the agent hasn't read; the system items the gem queues are
      # the agent's own. An event can arrive stale: a mid-turn submit emits its queue once the
      # gem's lock drops, and the turn's drain, on its own thread, may get there first. So an
      # empty queue, by the gem's count, wins over the event's items.
      #
      # @param items [Array<Pikuri::Agent::Control::Interloper::Item>]
      # @return [void]
      def pending(items)
        @lock.synchronize do
          drained = @live.nil? || @live.status.pending.zero?
          @conversation.pending = drained ? [] : items.select { _1.kind == :user }.map(&:content)
        end
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
