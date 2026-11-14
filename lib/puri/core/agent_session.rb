# frozen_string_literal: true

module Puri
  module Core
    # One {PikuriCore} conversation's pikuri side: its live `Pikuri::Conversations::Conversation`,
    # opened on the first question, the {Confirmer} its tools ask through, and its folder in the
    # store. It is that conversation's listener, so the gem's hooks reach it through
    # `conversation.listener`:
    #
    #   session = AgentSession.new(conversation, entry:, store:, conversations:, transport:,
    #                              tools: ->(confirmer) { [] }, lock:, saved: true)
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
      # @return [Logger]
      LOGGER = Pikuri.logger_for('AgentSession')

      # @param conversation [Puri::Core::Conversation] where the turns show
      # @param entry [Pikuri::Conversations::Store::Entry] its folder
      # @param store [Pikuri::Conversations::Store]
      # @param conversations [Pikuri::Conversations] the live ones, which this one joins on its
      #   first question
      # @param transport [Pikuri::Agent::ChatTransport]
      # @param tools [Proc] takes the conversation's {Confirmer}, returns the agent's
      #   `Array<Pikuri::Tool>`
      # @param lock [Monitor] the core's
      # @param saved [Boolean] whether the store holds this conversation already
      def initialize(conversation, entry:, store:, conversations:, transport:, tools:, lock:, saved:)
        super()
        @conversation = conversation
        @entry = entry
        @store = store
        @conversations = conversations
        @transport = transport
        @tools = tools
        @lock = lock
        @saved = saved
        @untitled = !saved || store.stamp_titled?(entry) || entry.title == Conversation::NEW_TITLE
        @display = Pikuri::Conversations::RateLimitedListener.new(
          TurnListener.new(conversation, server: transport.api_base), fps: 15
        )
        @live = nil
        @history = nil
        @confirmer = nil
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
        if @confirmer&.redirect(text)
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
      def answer(confirmation, approved) = @confirmer&.answer(confirmation, approved)

      # Closes the live conversation, cancelling its turn, and removes it from disk; the turn's
      # own save, still to come, writes nothing.
      #
      # @return [void]
      def delete
        @live&.close(force: true)
        @store.delete(@entry)
      end

      # The gem's `configure:`: the agent's {Confirmer} and tools, on the booting thread.
      #
      # @param config [Pikuri::Agent::Configurator]
      # @return [void]
      def configure(config)
        @confirmer = Confirmer.new(@conversation, lock: @lock)
        config.add_tools(@tools.call(@confirmer))
      end

      # The gem's `on_turn_end:`. Any failure, not only a disk's, ends in the error notice: a
      # history that won't serialize is as lost as one that won't write.
      #
      # @param history [Pikuri::Agent::History]
      # @return [void]
      def save(history)
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
        @live ||= @conversations.open(id: @conversation.id, transport: @transport, listener: self,
                                      history: @history, boot: false, untitled: @untitled)
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
