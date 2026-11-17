# frozen_string_literal: true

require 'time'

module Puri
  module Desktop
    # One conversation, on screen: its transcript over the entry that continues it, and its
    # {StatusBar} under both once the window is expanded. It keeps
    # which conversation it shows and nothing else; the blocks come from Core, and stay current
    # through Core's events for that conversation.
    #
    #   view = ConversationView.new(client)
    #   view.on_asked { expand_the_window }
    #   view.conversation = id     # loads it; nil shows a new, empty one
    #   view.cancel                # Escape
    #
    # Up in the empty entry recalls this conversation's last question or, in a new one, the last
    # question asked anywhere.
    class ConversationView < Gtk::Box
      # @return [String, nil] the conversation shown; nil until the first question
      attr_reader :conversation

      # @return [Puri::Desktop::PromptEntry]
      attr_reader :entry

      # @return [Puri::Desktop::TranscriptView]
      attr_reader :transcript

      # @return [Puri::Desktop::StatusBar]
      attr_reader :status_bar

      # @param client [Puri::Desktop::BackendClient]
      def initialize(client)
        super(:vertical, 0)
        @client = client
        @conversation = nil
        @transcript = TranscriptView.new { |id, approved| @client.answer(@conversation, id, approved) }
        @transcript.vexpand = true
        @entry = PromptEntry.new(recall: -> { recall }) { |text| ask(text) }
        @entry_box = Gtk::Box.new(:vertical, 0)
        @entry_box.append(@entry)
        @status_bar = StatusBar.new(client)
        @status_bar.margin_top = 8
        @status_bar.show(nil)
        @entry_box.append(@status_bar)
        append(@transcript)
        append(@entry_box)
        self.expanded = false
        client.subscribe { |event| show(event) }
      end

      # @param conversation [String, nil]
      # @return [void]
      def conversation=(conversation)
        @conversation = conversation
        transcript = conversation && @client.load_conversation(conversation)
        @transcript.transcript = transcript
        @status_bar.show(conversation, transcript&.status)
      end

      # Shows the transcript over the entry, or the entry alone, as the popup's pill.
      #
      # @param expanded [Boolean]
      # @return [void]
      def expanded=(expanded)
        @transcript.visible = expanded
        @status_bar.visible = expanded
        margin = expanded ? 12 : 6
        %i[top bottom start end].each { @entry_box.send(:"margin_#{_1}=", margin) }
      end

      # @return [Puri::Protocol::Activity] what this conversation's turn is doing
      def activity = @transcript.activity

      # Stops this conversation's turn, if one runs.
      #
      # @return [void]
      def cancel
        @client.cancel(@conversation) if @conversation && activity.running?
      end

      # @yieldparam conversation [String] the conversation just asked in, after it is shown
      # @yieldreturn [void]
      # @return [void]
      def on_asked(&listener)
        @on_asked = listener
      end

      private

      # @param text [String]
      # @return [void]
      def ask(text)
        @conversation = @client.ask(@conversation, text)
        @status_bar.show(@conversation)
        @transcript.scroll_to_bottom
        @on_asked&.call(@conversation)
      end

      # @return [String, nil]
      def recall
        return @transcript.last_question if @conversation

        @client.list_conversations.select(&:asked_at).max_by { Time.iso8601(_1.asked_at) }&.last_question
      end

      # @param event [Data] a {Protocol} event
      # @return [void]
      def show(event)
        return unless event.respond_to?(:conversation) && event.conversation == @conversation

        case event
        in Protocol::BlockChanged(block:) then @transcript.upsert(block)
        in Protocol::BlockRemoved(block:) then @transcript.remove(block)
        in Protocol::ActivityChanged(activity:) then @transcript.activity = activity
        in Protocol::StatusChanged then nil # the status bar's
        end
      end
    end
  end
end
