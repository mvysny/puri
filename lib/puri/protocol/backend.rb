# frozen_string_literal: true

module Puri
  module Protocol
    # The methods Desktop calls on Core. A backend includes this module and overrides every
    # method; the bodies here only raise. Calls come from the GTK main loop and return at once:
    # a turn runs on Core's own thread and reports through events ({BlockChanged},
    # {ActivityChanged}, {ConversationsChanged}).
    #
    #   id = backend.ask(nil, 'reschedule my dentist in the calendar')   # a new conversation
    #   # … BlockChanged(Confirmation(state: 'pending')) arrives …
    #   backend.answer(id, 'b4', true)            # Update; false is Cancel
    #   backend.ask(id, 'make it Wednesday')      # typed while it waits: a redirect
    #   backend.cancel(id)                        # Escape
    module Backend
      # Sends the user's message. With a confirmation pending, the message answers it as a
      # redirect: the model follows the words and proposes again. With a turn running, it waits
      # for that turn to end.
      #
      # @param conversation [String, nil] the conversation to continue; nil starts a new one
      # @param text [String] what the user typed
      # @return [String] the conversation's id, new when `conversation` was nil
      def ask(conversation, text)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Stops the running turn, if any; a pending confirmation ends as `cancelled`.
      #
      # @param conversation [String]
      # @return [void]
      def cancel(conversation)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Answers a pending {Confirmation}; one already answered is left alone.
      #
      # @param conversation [String]
      # @param confirmation [String] the {Confirmation}'s block id
      # @param approved [Boolean] true for its approve button, false for Cancel
      # @return [void]
      def answer(conversation, confirmation, approved)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # @return [Array<Puri::Protocol::ConversationSummary>] newest first
      def list_conversations
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # @param conversation [String]
      # @return [Puri::Protocol::Transcript]
      # @raise [ArgumentError] for an unknown id
      def load_conversation(conversation)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end

      # Forgets a conversation, cancelling its turn first.
      #
      # @param conversation [String]
      # @return [void]
      def delete_conversation(conversation)
        raise NotImplementedError, "#{self.class} must implement #{__method__}"
      end
    end
  end
end
