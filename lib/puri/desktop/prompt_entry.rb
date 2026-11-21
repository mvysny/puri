# frozen_string_literal: true

module Puri
  module Desktop
    # Where the user types. Enter submits the trimmed text and clears the entry; Enter on an
    # empty one does nothing, so a stray Enter never answers a confirmation. Up in an empty
    # entry recalls the last question, shell-style.
    #
    #   entry = PromptEntry.new(recall: -> { transcript.last_question }) { |text| ask(text) }
    #   entry.on_mic { client.toggle_dictation }   # a mic icon at the end, F5's twin
    #   entry.dictation = event                    # red while listening; the text lands at the cursor
    class PromptEntry < Gtk::Entry
      # @param recall [Proc] returns the question Up brings back, a String or nil
      # @yieldparam text [String] what the user sent, trimmed
      # @yieldreturn [void]
      def initialize(recall:, &on_submit)
        super()
        @recall = recall
        @on_submit = on_submit
        self.placeholder_text = 'Ask anything…'
        self.primary_icon_name = 'system-search-symbolic'
        self.hexpand = true
        add_css_class('puri-prompt')
        signal_connect('activate') { submit }
        keys = Gtk::EventControllerKey.new
        keys.signal_connect('key-pressed') { |_, keyval| keyval == Gdk::Keyval::KEY_Up && recall_question }
        add_controller(keys)
      end

      # Puts the last question in an empty entry, the cursor at its end.
      #
      # @return [Boolean] whether it did, which consumes the Up key
      def recall_question
        return false unless text.empty?

        question = @recall.call or return false
        self.text = question
        self.position = -1
        true
      end

      # Shows the mic.
      #
      # @yieldreturn [void] called on its click
      # @return [void]
      def on_mic(&listener)
        self.secondary_icon_name = 'audio-input-microphone-symbolic'
        self.secondary_icon_tooltip_text = 'Dictate (F5)'
        signal_connect('icon-press') { |_, position| listener.call if position == Gtk::EntryIconPosition::SECONDARY }
      end

      # @param event [Puri::Protocol::DictationChanged]
      # @return [void]
      def dictation=(event)
        event.state == 'listening' ? add_css_class('puri-listening') : remove_css_class('puri-listening')
        self.secondary_icon_sensitive = event.state != 'transcribing'
        insert_at_cursor(event.text) unless event.text.empty?
      end

      private

      # Inserts dictated words, a space between them and any word they touch.
      #
      # @param words [String]
      # @return [void]
      def insert_at_cursor(words)
        at = position
        before = at.zero? ? ' ' : text[at - 1]
        after = text[at] || ' '
        words = " #{words}" unless before.match?(/\s/)
        words = "#{words} " unless after.match?(/\s/)
        self.text = text[0...at] + words + text[at..]
        self.position = at + words.length
      end

      # @return [void]
      def submit
        message = text.strip
        return if message.empty?

        self.text = ''
        @on_submit.call(message)
      end
    end
  end
end
