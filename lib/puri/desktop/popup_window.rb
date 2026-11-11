# frozen_string_literal: true

module Puri
  module Desktop
    # The one window: an entry to ask in and, under it, the reply as it streams in. Milestone 1
    # grows it into the pill and transcript of `design/ideas/desktop-popup-app.md`.
    class PopupWindow < Adw::ApplicationWindow
      # @return [Gtk::Entry] where the user types; Enter asks
      attr_reader :entry

      # @param app [Adw::Application]
      # @param client [Puri::Desktop::BackendClient]
      def initialize(app, client)
        super(app)
        @client = client
        @conversation = nil
        self.title = 'Puri'
        set_default_size(600, 400)

        @entry = Gtk::Entry.new
        @entry.placeholder_text = 'Ask anything…'
        @entry.signal_connect('activate') { ask }

        @reply = Gtk::Label.new
        @reply.wrap = true
        @reply.selectable = true
        @reply.xalign = 0
        @reply.yalign = 0
        scroll = Gtk::ScrolledWindow.new
        scroll.child = @reply
        scroll.vexpand = true

        box = Gtk::Box.new(:vertical, 12)
        %i[top bottom start end].each { |side| box.send(:"margin_#{side}=", 12) }
        box.append(@entry)
        box.append(scroll)
        self.content = box

        client.subscribe { |event| show(event) }
      end

      # @return [String] the reply so far
      def reply_text = @reply.text

      private

      # @return [void]
      def ask
        text = @entry.text.strip
        return if text.empty?

        @entry.text = ''
        @client.submit(Protocol::Ask.new(conversation: @conversation, text:))
      end

      # @param event [Data] a {Protocol} event
      # @return [void]
      def show(event)
        case event
        in Protocol::TurnStarted(conversation:)
          @conversation = conversation
          @reply.text = ''
        in Protocol::TextDelta(conversation:, text:) if conversation == @conversation
          @reply.text += text
        else
          nil # not for this window
        end
      end
    end
  end
end
