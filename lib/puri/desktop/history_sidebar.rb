# frozen_string_literal: true

module Puri
  module Desktop
    # Every earlier conversation, newest first, with a search over the titles. It fills itself
    # from Core and stays current through {Protocol::ConversationsChanged}.
    #
    #   sidebar = HistorySidebar.new(client)
    #   sidebar.on_selected { |id| conversation_view.conversation = id }   # clicked, or arrowed to
    #   sidebar.on_activated { |_| entry.grab_focus }                       # clicked, or Enter
    #   sidebar.selected = id      # marks the conversation on screen
    #
    # Delete on a selected row asks, then deletes it.
    class HistorySidebar < Gtk::Box
      # @return [Gtk::SearchEntry]
      attr_reader :search

      # @return [Gtk::ListBox]
      attr_reader :list

      # @param client [Puri::Desktop::BackendClient]
      def initialize(client)
        super(:vertical, 0)
        @client = client
        @selected = nil
        @search = Gtk::SearchEntry.new
        @search.placeholder_text = 'Search conversations'
        @search.margin_top = @search.margin_bottom = 8
        @search.margin_start = @search.margin_end = 10
        @search.signal_connect('search-changed') { @list.invalidate_filter }
        @list = Gtk::ListBox.new
        @list.add_css_class('navigation-sidebar')
        @list.selection_mode = :single
        @list.set_filter_func { |row| row.matches?(@search.text.strip.downcase) }
        @list.signal_connect('row-activated') do |_, row|
          select(row.summary.id)
          @on_activated&.call(row.summary.id)
        end
        @list.signal_connect('row-selected') { |_, row| select(row.summary.id) if row && !@filling }
        keys = Gtk::EventControllerKey.new
        keys.signal_connect('key-pressed') { |_, keyval| keyval == Gdk::Keyval::KEY_Delete && ask_to_delete }
        @list.add_controller(keys)
        scroll = Gtk::ScrolledWindow.new
        scroll.set_policy(:never, :automatic)
        scroll.vexpand = true
        scroll.child = @list
        append(@search)
        append(scroll)
        client.subscribe do |event|
          self.conversations = event.conversations if event.is_a?(Protocol::ConversationsChanged)
        end
        refresh
      end

      # Fetches the list again.
      #
      # @return [void]
      def refresh
        self.conversations = @client.list_conversations
      end

      # @param conversations [Array<Puri::Protocol::ConversationSummary>] newest first
      # @return [void]
      def conversations=(conversations)
        @filling = true
        @rows = {}
        @list.remove_all
        conversations.each do |summary|
          row = HistoryRow.new(summary)
          @rows[summary.id] = row
          @list.append(row)
        end
        self.selected = @selected
      ensure
        @filling = false
      end

      # @return [Array<Puri::Desktop::HistoryRow>]
      def rows = @rows.values

      # Marks the conversation on screen, without telling {#on_selected}.
      #
      # @param id [String, nil]
      # @return [void]
      def selected=(id)
        @selected = id
        filling = @filling
        @filling = true
        row = @rows[id]
        row ? @list.select_row(row) : @list.unselect_all
      ensure
        @filling = filling
      end

      # @yieldparam id [String] the conversation the user picked
      # @yieldreturn [void]
      # @return [void]
      def on_selected(&listener)
        @on_selected = listener
      end

      # A click, or Enter on a row: done browsing. Arrow keys only select.
      #
      # @yieldparam id [String] the conversation the user picked
      # @yieldreturn [void]
      # @return [void]
      def on_activated(&listener)
        @on_activated = listener
      end

      # @return [void]
      def focus_search
        @search.grab_focus
      end

      # Asks whether to delete the selected conversation, and does on Delete.
      #
      # @return [Boolean] whether a row was selected
      def ask_to_delete
        row = @list.selected_row or return false

        summary = row.summary
        dialog = Adw::AlertDialog.new("Delete “#{summary.title}”?", 'It is gone for good.')
        dialog.add_response('cancel', 'Cancel')
        dialog.add_response('delete', 'Delete')
        dialog.set_response_appearance('delete', :destructive)
        dialog.default_response = 'cancel'
        dialog.close_response = 'cancel'
        dialog.signal_connect('response') do |_, response|
          @client.delete_conversation(summary.id) if response == 'delete'
        end
        dialog.present(self)
        true
      end

      private

      # @param id [String]
      # @return [void]
      def select(id)
        return if id == @selected

        @selected = id
        @on_selected&.call(id)
      end
    end
  end
end
