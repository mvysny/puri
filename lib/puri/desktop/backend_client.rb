# frozen_string_literal: true

module Puri
  module Desktop
    # Desktop's one door to Core. Components submit commands through it and subscribe to Core's
    # events themselves; there is no controller.
    #
    #   client = BackendClient.new { |command| core.handle(command) }
    #   client.subscribe { |event| show(event) }                   # in a component
    #   client.submit(Protocol::Ask.new(conversation: nil, text: 'hi'))
    #   core_listener = ->(event) { client.deliver(event) }        # Core's side, any thread
    #
    # Main-loop-confined, with exceptions.
    class BackendClient
      # @yieldparam command [Data] a {Protocol} command, on its way to Core
      # @yieldreturn [void]
      def initialize(&submitter)
        raise ArgumentError, 'BackendClient needs a submitter block' unless submitter

        @submitter = submitter
        @listeners = []
      end

      # @param command [Data] a {Protocol} command
      # @return [void]
      def submit(command)
        @submitter.call(command)
      end

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
        GLib::Idle.add do
          @listeners.each { |listener| listener.call(event) }
          false
        end
      end
    end
  end
end
