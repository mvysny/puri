# frozen_string_literal: true

require 'monitor'

module Puri
  module Dummy
    # A canned backend, for the GTK specs and for walking the UI with no model (`exe/puri --dummy`).
    # It answers from {Script} instead of a model, but otherwise behaves like
    # `Puri::Core::PikuriCore`: conversations kept in memory and titled a moment after they start,
    # turns on threads of their own, confirmations that wait, Cancel, and the same events.
    #
    #   core = Backend.new { |event| client.deliver(event) }   # called on any thread
    #   id = core.ask(nil, 'search for avocado tips')
    #   core.load_conversation(id).blocks   # => [UserMessage, …] so far
    #   core.close                           # kills the turns and titles still running
    #
    # `seed: true` starts it with a few earlier conversations, so the history isn't empty.
    #
    # Thread-safe.
    class Backend
      include Protocol::Backend

      # @param think [Float] seconds each thinking step takes
      # @param pace [Float] seconds between streamed words
      # @param title_delay [Float] seconds before a new conversation gets its title
      # @param seed [Boolean] whether to start with earlier conversations
      # @yieldparam event [Data] a {Protocol} event, on whichever thread caused it
      # @yieldreturn [void]
      def initialize(think: 1.0, pace: 1.0 / 30, title_delay: 1.0, seed: false, &listener)
        raise ArgumentError, 'the dummy Backend needs a listener block' unless listener

        @think = think
        @pace = pace
        @title_delay = title_delay
        @lock = Monitor.new
        @conversations = {}
        @threads = ThreadGroup.new
        # Silent while seeding: whoever listens may not exist before this returns.
        @listener = ->(_) {}
        seed_history if seed
        @listener = listener
      end

      # (see Puri::Protocol::Backend#ask)
      def ask(conversation, text)
        @lock.synchronize do
          target = conversation ? fetch(conversation) : create(text)
          target.ask(text)
          target.conversation.id
        end
      end

      # (see Puri::Protocol::Backend#cancel)
      def cancel(conversation) = fetch(conversation).cancel

      # (see Puri::Protocol::Backend#answer)
      def answer(conversation, confirmation, approved) = fetch(conversation).answer(confirmation, approved)

      # (see Puri::Protocol::Backend#list_conversations)
      def list_conversations
        @lock.synchronize { @conversations.values.reverse.map { _1.conversation.summary } }
      end

      # (see Puri::Protocol::Backend#load_conversation)
      def load_conversation(conversation) = fetch(conversation).conversation.transcript

      # (see Puri::Protocol::Backend#delete_conversation)
      def delete_conversation(conversation)
        @lock.synchronize do
          fetch(conversation).cancel
          @conversations.delete(conversation)
          publish
        end
      end

      # Kills every thread a turn or a title runs on, and waits until they're gone. A turn killed
      # may start the message that waited for it, on a new thread: that one goes too.
      #
      # @return [void]
      def close
        until (threads = @threads.list).empty?
          threads.each(&:kill).each(&:join)
        end
      end

      private

      # @param id [String]
      # @return [Puri::Dummy::Session]
      # @raise [ArgumentError]
      def fetch(id)
        @lock.synchronize { @conversations[id] } or raise ArgumentError, "no conversation #{id.inspect}"
      end

      # @param text [String] the opening question, which the title comes from
      # @param started_at [Time]
      # @param asked [Boolean] whether `text` was asked already, at `started_at`
      # @return [Puri::Dummy::Session]
      def create(text, started_at: Time.now, asked: false)
        conversation = Core::Conversation.new(
          id: SecureRandom.uuid, lock: @lock, emit: ->(event) { @listener.call(event) },
          changed: -> { publish }, started_at:, last_question: (text if asked), asked_at: (started_at if asked)
        )
        session = Session.new(conversation, lock: @lock, threads: @threads, think: @think, pace: @pace)
        @conversations[conversation.id] = session
        publish
        @threads.add(Thread.new do
          sleep @title_delay
          @lock.synchronize { conversation.title = Script.title(text) if @conversations.key?(conversation.id) }
        end)
        session
      end

      # @return [void]
      def publish
        @listener.call(Protocol::ConversationsChanged.new(conversations: list_conversations))
      end

      # Earlier conversations, already answered.
      #
      # @return [void]
      def seed_history
        [
          [3 * 86_400, 'how do I keep an avocado from browning?',
           "Keep the cut side **covered and cold**: plastic wrap pressed onto the flesh, then the fridge.\n\n" \
           'A little lemon juice buys another day.'],
          [86_400 + 3600, 'what is on my shopping note?',
           'Your **Shopping** note: avocados, limes, coffee beans and AA batteries.'],
          [5400, 'when is the dentist?', 'Tuesday at **10:00**, in your Personal calendar.']
        ].each do |ago, question, answer|
          conversation = create(question, started_at: Time.now - ago, asked: true).conversation
          conversation.restore([Protocol::UserMessage.new(id: nil, text: question),
                                Protocol::Reply.new(id: nil, parts: Core::ReplyRenderer.render(answer))])
          conversation.title = Script.title(question)
        end
      end
    end
  end
end
