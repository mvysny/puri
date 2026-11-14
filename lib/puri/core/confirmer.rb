# frozen_string_literal: true

module Puri
  module Core
    # Asks the user in the transcript: a tool's `ask` shows a {Protocol::Confirmation} and waits
    # on the turn's thread until the user answers from the main loop.
    #
    #   confirmer.ask(request:)            # turn thread: a pending Confirmation, activity confirming
    #   confirmer.answer('b4', true)       # main loop: Update → Approved
    #   confirmer.answer('b4', false)      # Cancel → Rejected
    #   confirmer.redirect('make it Wed')  # typed text → Redirected('make it Wed')
    #   cancellable.cancel!                # Escape → ask raises Cancellable::Cancelled
    #
    # Whichever way it ends, the Confirmation is re-sent with its final state. `D_confirmation_answers`
    # has why each gesture is the answer it is.
    #
    # One per conversation, built with its agent, since tools take their confirmer when they're
    # built. An answer meant for a confirmation that no longer waits is dropped.
    #
    # == Implementation details
    #
    # The pending confirmation is guarded by the core's lock, which {Conversation} takes too, so
    # showing it and marking it pending are one step for {#pending?}. A parked `ask` checks the
    # Cancellable every {SLICE_SECONDS} rather than waiting for a message, so no cancel can fall
    # between its check and its wait.
    #
    # Thread-safe.
    class Confirmer < Pikuri::Workspace::Confirmer
      # Longest a cancel waits to be noticed.
      #
      # @return [Float] seconds
      SLICE_SECONDS = 0.1

      # @param conversation [Puri::Core::Conversation] where the question shows
      # @param lock [Monitor] the core's
      # @param cancellable [Pikuri::Agent::Control::Cancellable] the conversation's agent's
      def initialize(conversation, lock:, cancellable:)
        super()
        @conversation = conversation
        @lock = lock
        @cancellable = cancellable
        @answers = Thread::Queue.new
        @pending = nil
      end

      # The question is the tool's, sanitized; its detail follows it, and a spoof the sanitizer
      # found leads it.
      #
      # @param request [Pikuri::Workspace::Confirmer::Request]
      # @return [Pikuri::Workspace::Confirmer::Approved, Pikuri::Workspace::Confirmer::Rejected,
      #   Pikuri::Workspace::Confirmer::Redirected]
      # @raise [Pikuri::Agent::Control::Cancellable::Cancelled] when the turn is cancelled first
      def ask(request:)
        @lock.synchronize do
          @answers.clear
          @pending = @conversation.add(Protocol::Confirmation.new(id: nil, question: question(request),
                                                                  approve_label: 'Approve', destructive: false,
                                                                  state: 'pending'))
          @conversation.activity = Protocol::Activity.new(state: 'confirming')
        end
        decide(request)
      end

      # @param confirmation [String] the block id the user answered
      # @param approved [Boolean]
      # @return [void]
      def answer(confirmation, approved)
        @lock.synchronize { @answers << (approved ? :approved : :rejected) if confirmation == @pending&.id }
      end

      # @param text [String] what the user typed while the confirmation waits
      # @return [Boolean] false when no confirmation waits for an answer, and `text` is the
      #   caller's to send on
      def redirect(text)
        @lock.synchronize do
          next false unless @pending && @answers.empty?

          @answers << [:redirected, text]
          true
        end
      end

      # @return [Boolean] whether a confirmation waits for the user
      def pending? = @lock.synchronize { !@pending.nil? }

      private

      # @param request [Pikuri::Workspace::Confirmer::Request]
      # @return [Pikuri::Workspace::Confirmer::Approved, Pikuri::Workspace::Confirmer::Rejected,
      #   Pikuri::Workspace::Confirmer::Redirected]
      # @raise [Pikuri::Agent::Control::Cancellable::Cancelled]
      def decide(request)
        loop do
          @cancellable.check!
          case @answers.pop(timeout: SLICE_SECONDS)
          in :approved then return settle('approved', Approved.new(new_request_detail: request.detail))
          in :rejected then return settle('rejected', Rejected.new)
          in [:redirected, String => text] then return settle('redirected', Redirected.new(message: text))
          in nil then nil
          end
        end
      rescue Pikuri::Agent::Control::Cancellable::Cancelled
        settle('cancelled', nil)
        raise
      end

      # @param state [String] the Confirmation's final state
      # @param decision [Object, nil]
      # @return [Object, nil] `decision`
      def settle(state, decision)
        @lock.synchronize do
          @conversation.put(@pending.with(state:))
          @pending = nil
          @conversation.activity = Protocol::Activity.new(state: 'working', status: 'Thinking…') if decision
        end
        decision
      end

      # @param request [Pikuri::Workspace::Confirmer::Request]
      # @return [String] plain text
      def question(request)
        question = Pikuri::Sanitizer.sanitize(request.question)
        detail = request.detail && Pikuri::Sanitizer.sanitize(request.detail)
        warnings = [question, detail].compact.flat_map(&:warnings).map { "⚠ #{_1.explanation}" }.uniq
        [*warnings, question.text, detail&.text].compact.join("\n\n")
      end
    end
  end
end
