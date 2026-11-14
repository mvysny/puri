# frozen_string_literal: true

module Puri
  module Dummy
    # One turn of a {Backend} conversation, on a thread of its own as a pikuri agent's turn is. A
    # {Script} drives it through the steps a real turn takes, each reported as the events a
    # real Core would send:
    #
    #   turn.think('Searching the web…')            # ActivityChanged(working), then a pause
    #   turn.tool('🔍 Searched: "avocado"')         # a ToolLine block
    #   turn.stream("Keep it **cold**.")            # a Reply re-sent per word, ActivityChanged(streaming)
    #   turn.confirm('Move “Dentist”…?', 'Update', destructive: true)
    #   # => :approved, :rejected, or [:redirected, "make it Wednesday"]
    #
    # Every pause and every wait is where {#cancel} lands: the step raises {Cancelled}, and
    # {#run} ends the turn with a "Cancelled" notice, keeping what had streamed.
    #
    # == Threading
    #
    # {#run} is the turn's thread; {#cancel}, {#answer} and {#redirect} come from any thread
    # through a queue the steps wait on.
    class Turn
      # Raised inside a step once the turn is cancelled.
      class Cancelled < StandardError; end

      # @param session [Puri::Dummy::Session] whose conversation the blocks go to
      # @param lock [Monitor] the backend's, which also guards the pending confirmation
      # @param think [Float] seconds a {#think} step takes
      # @param pace [Float] seconds between streamed words
      def initialize(session, lock:, think:, pace:)
        @session = session
        @conversation = session.conversation
        @lock = lock
        @think = think
        @pace = pace
        @control = Thread::Queue.new
        @pending = nil
      end

      # Plays the script for `text` to the end, a cancel or a failure, then hands the
      # conversation back to idle.
      #
      # @param text [String] the user's message
      # @return [void]
      def run(text)
        Script.run(self, text)
      rescue Cancelled
        settle('cancelled')
        @conversation.add(Protocol::Notice.new(id: nil, text: 'Cancelled', error: false))
      rescue StandardError => e
        settle('cancelled')
        @conversation.add(Protocol::Notice.new(id: nil, text: e.message, error: true))
      ensure
        @session.finish(self)
      end

      # @return [void]
      def cancel = @control << [:cancel]

      # @param confirmation [String] block id; one not pending is ignored
      # @param approved [Boolean]
      # @return [void]
      def answer(confirmation, approved)
        @control << [:answer, approved] if confirmation == @pending&.id
      end

      # @param text [String] typed while a confirmation waits
      # @return [void]
      def redirect(text) = @control << [:redirect, text]

      # @return [Boolean] whether a confirmation waits for the user
      def confirming? = !@pending.nil?

      # @param status [String] the status line under the progress bar
      # @param seconds [Float]
      # @return [void]
      def think(status, seconds = @think)
        @conversation.activity = Protocol::Activity.new(state: 'working', status:)
        pause(seconds)
      end

      # @param text [String] the step, worded
      # @param error [Boolean]
      # @return [void]
      def tool(text, error: false)
        @conversation.add(Protocol::ToolLine.new(id: nil, text:, error:))
      end

      # Streams Markdown into a new {Protocol::Reply}, a word at a time.
      #
      # @param markdown [String]
      # @return [void]
      def stream(markdown)
        reply = @conversation.add(Protocol::Reply.new(id: nil, parts: []))
        @conversation.activity = Protocol::Activity.new(state: 'streaming')
        stream = Core::ReplyStream.new
        markdown.scan(/\s*\S+/).each do |word|
          pause(@pace)
          reply = reply.with(parts: stream.append(word))
          @conversation.put(reply)
        end
        final = stream.finish
        @conversation.put(reply.with(parts: final)) unless final == reply.parts
      end

      # Asks the user and waits for the answer.
      #
      # @param question [String]
      # @param approve_label [String]
      # @param destructive [Boolean]
      # @return [Symbol, Array(Symbol, String)] `:approved`, `:rejected` or `[:redirected, text]`
      # @raise [Cancelled]
      def confirm(question, approve_label, destructive:)
        @lock.synchronize do
          @pending = @conversation.add(Protocol::Confirmation.new(id: nil, question:, approve_label:,
                                                                  destructive:, state: 'pending'))
        end
        @conversation.activity = Protocol::Activity.new(state: 'confirming')
        case @control.pop
        in [:answer, true] then settle('approved') && :approved
        in [:answer, false] then settle('rejected') && :rejected
        in [:redirect, text] then settle('redirected') && [:redirected, text]
        in [:cancel] then raise Cancelled
        end
      end

      private

      # @param seconds [Float]
      # @return [void]
      # @raise [Cancelled]
      def pause(seconds)
        command = @control.pop(timeout: seconds)
        raise Cancelled if command == [:cancel]
      end

      # Gives the pending confirmation its final state, if there is one.
      #
      # @param state [String]
      # @return [Boolean] true
      def settle(state)
        @lock.synchronize do
          @conversation.put(@pending.with(state:)) if @pending
          @pending = nil
        end
        true
      end
    end
  end
end
