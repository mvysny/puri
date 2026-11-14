# frozen_string_literal: true

module Puri
  module Core
    # Asks the user in the transcript: a tool's `ask` shows a {Protocol::Confirmation} and waits
    # on the turn's thread until the user answers from the main loop.
    #
    #   confirmer.ask(request:, cancellable:)  # turn thread: a pending Confirmation, activity confirming
    #   confirmer.answer('b4', true)           # main loop: Update → Approved
    #   confirmer.answer('b4', false)          # Cancel → Rejected
    #   confirmer.redirect('make it Wed')      # typed text → Redirected('make it Wed')
    #   cancellable.cancel!                    # Escape, close, quit → ask raises Cancellable::Cancelled
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
    # showing it and marking it pending are one step for {#pending?}. A parked `ask` waits in a
    # `Pikuri::Agent::Control::Handoff` on the asking turn's Cancellable, so any cancel of that
    # turn reaches it.
    #
    # Thread-safe.
    class Confirmer < Pikuri::Workspace::Confirmer
      # @param conversation [Puri::Core::Conversation] where the question shows
      # @param lock [Monitor] the core's
      def initialize(conversation, lock:)
        super()
        @conversation = conversation
        @lock = lock
        @pending = nil
        @handoff = nil
      end

      # The question is the tool's, sanitized; its detail follows it, and a spoof the sanitizer
      # found leads it.
      #
      # @param request [Pikuri::Workspace::Confirmer::Request]
      # @param cancellable [Pikuri::Agent::Control::Cancellable] the asking turn's
      # @return [Pikuri::Workspace::Confirmer::Approved, Pikuri::Workspace::Confirmer::Rejected,
      #   Pikuri::Workspace::Confirmer::Redirected]
      # @raise [Pikuri::Agent::Control::Cancellable::Cancelled] when the turn is cancelled first
      def ask(request:, cancellable:)
        handoff = Pikuri::Agent::Control::Handoff.new(cancellable)
        @lock.synchronize do
          @pending = @conversation.add(Protocol::Confirmation.new(id: nil, question: question(request),
                                                                  approve_label: 'Approve', destructive: false,
                                                                  state: 'pending'))
          @handoff = handoff
          @conversation.activity = Protocol::Activity.new(state: 'confirming')
        end
        decide(request, handoff)
      end

      # @param confirmation [String] the block id the user answered
      # @param approved [Boolean]
      # @return [void]
      def answer(confirmation, approved)
        @lock.synchronize { hand(approved ? :approved : :rejected) if confirmation == @pending&.id }
      end

      # @param text [String] what the user typed while the confirmation waits
      # @return [Boolean] false when no confirmation waits for an answer, and `text` is the
      #   caller's to send on
      def redirect(text) = @lock.synchronize { hand([:redirected, text]) }

      # @return [Boolean] whether a confirmation waits for the user
      def pending? = @lock.synchronize { !@pending.nil? }

      private

      # Hands the waiting `ask` its answer; the caller holds the lock.
      #
      # @param answer [Symbol, Array(Symbol, String)]
      # @return [Boolean] false when no question waits for one, or it has its answer already
      def hand(answer)
        return false unless @handoff

        @handoff.complete(answer)
        @handoff = nil
        true
      end

      # @param request [Pikuri::Workspace::Confirmer::Request]
      # @param handoff [Pikuri::Agent::Control::Handoff]
      # @return [Pikuri::Workspace::Confirmer::Approved, Pikuri::Workspace::Confirmer::Rejected,
      #   Pikuri::Workspace::Confirmer::Redirected]
      # @raise [Pikuri::Agent::Control::Cancellable::Cancelled]
      def decide(request, handoff)
        case handoff.await
        in :approved then settle('approved', Approved.new(new_request_detail: request.detail))
        in :rejected then settle('rejected', Rejected.new)
        in [:redirected, String => text] then settle('redirected', Redirected.new(message: text))
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
          @handoff = nil
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
