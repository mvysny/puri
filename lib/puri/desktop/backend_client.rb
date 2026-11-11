# frozen_string_literal: true

module Puri
  module Desktop
    # Desktop's one door to Core: the {Protocol::Backend} methods, forwarded, and Core's events,
    # handed to subscribers on the GTK main loop. Components call it and subscribe to it
    # themselves; there is no controller.
    #
    #   client = BackendClient.new(core)
    #   core_listener = ->(event) { client.deliver(event) }       # Core's side, any thread
    #   client.subscribe { |event| show(event) }                  # in a component
    #   id = client.ask(nil, 'hi')
    #
    # Every argument, result and event goes through {Protocol.round_trip}, so Desktop never holds
    # a Ruby object of Core's and a D-Bus connection could take this one's place.
    #
    # == Implementation details
    #
    # No unsubscribe on a widget's `destroy`: GTK also emits it while Ruby's GC finalizes the
    # widget, and a Ruby handler running inside the GC aborts the process ("object allocation
    # during garbage collection phase").
    #
    # Main-loop-confined, with exceptions.
    class BackendClient
      include Protocol::Backend

      # @param backend [Puri::Protocol::Backend] Core, or anything that answers like it
      def initialize(backend)
        @backend = backend
        @listeners = []
      end

      # (see Puri::Protocol::Backend#ask)
      def ask(conversation, text) = call(:ask, conversation, text)

      # (see Puri::Protocol::Backend#cancel)
      def cancel(conversation) = command(:cancel, conversation)

      # (see Puri::Protocol::Backend#answer)
      def answer(conversation, confirmation, approved) = command(:answer, conversation, confirmation, approved)

      # (see Puri::Protocol::Backend#list_conversations)
      def list_conversations = call(:list_conversations)

      # (see Puri::Protocol::Backend#load_conversation)
      def load_conversation(conversation) = call(:load_conversation, conversation)

      # (see Puri::Protocol::Backend#delete_conversation)
      def delete_conversation(conversation) = command(:delete_conversation, conversation)

      # Subscribes for good: a component's subscription lives as long as the client.
      #
      # @yieldparam event [Data] a {Protocol} event, on the GTK main loop
      # @yieldreturn [void]
      # @return [void]
      def subscribe(&listener)
        @listeners << listener
      end

      # Hands an event to the subscribers on the GTK main loop; safe from any thread, so Core's
      # threads call it directly and Core never learns GLib exists.
      #
      # @param event [Data] a {Protocol} event
      # @return [void]
      def deliver(event)
        copy = Protocol.round_trip(event)
        GLib::Idle.add do
          @listeners.dup.each { |listener| listener.call(copy) }
          false
        end
      end

      private

      # @param method [Symbol] a {Protocol::Backend} method
      # @param args [Array<Object>]
      # @return [Object] its result, round-tripped
      def call(method, *args)
        Protocol.round_trip(@backend.public_send(method, *Protocol.round_trip(args)))
      end

      # {#call} for a method that returns nothing: whatever the backend returns stays behind.
      #
      # @param method [Symbol] a {Protocol::Backend} method
      # @param args [Array<Object>]
      # @return [void]
      def command(method, *args)
        @backend.public_send(method, *Protocol.round_trip(args))
        nil
      end
    end
  end
end
