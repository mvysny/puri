# frozen_string_literal: true

module Puri
  module Desktop
    # The one window. It opens as a pill holding only the entry; the first question expands it
    # at once to a third of the screen's width and 70 % of its height, the conversation over the
    # entry; it never grows with the text, which looks restless. The history button widens it by
    # the sidebar of earlier conversations. Hiding it always brings back an empty pill next time.
    #
    #   window = PopupWindow.new(app, client)
    #   window.present
    #
    # Keys: Escape cancels a running turn and hides, except that while a reply streams the first
    # Escape only stops it, leaving the partial answer to read; Ctrl+N starts a new conversation,
    # Ctrl+F searches the history, F9 shows or hides it. The header's × hides without cancelling.
    # Losing focus hides only the empty pill, so a glance at another window never loses a
    # running answer.
    class PopupWindow < Adw::ApplicationWindow
      # @return [Float] share of the screen's width the window takes, pill or expanded
      WIDTH = 0.33

      # @return [Float] share of the screen's height the expanded window takes
      HEIGHT = 0.70

      # @return [Integer] pixels, however small the screen
      MIN_WIDTH = 520

      # @return [Integer] pixels the history adds to the window's width
      SIDEBAR_WIDTH = 280

      # @return [Puri::Desktop::ConversationView]
      attr_reader :conversation_view

      # @return [Puri::Desktop::HistorySidebar]
      attr_reader :sidebar

      # @param app [Adw::Application]
      # @param client [Puri::Desktop::BackendClient]
      def initialize(app, client)
        super(app)
        Style.install
        @client = client
        self.title = 'Puri'
        self.hide_on_close = true
        # libadwaita's windows ask for 360 × 200 at least, taller than the pill.
        set_size_request(MIN_WIDTH, -1)
        add_css_class('puri-popup')

        @conversation_view = ConversationView.new(client)
        @conversation_view.on_asked { |id| asked(id) }
        @sidebar = HistorySidebar.new(client)
        @sidebar.on_selected { |id| open_conversation(id) }
        # After the click is done with focus, or the row takes it back.
        @sidebar.on_activated { GLib::Idle.add { @conversation_view.entry.grab_focus && false } }
        self.content = layout

        install_actions
        signal_connect('notify::visible') { reset unless visible? }
        # Only a mapped window knows its monitor; until then the size is a guess.
        signal_connect('map') { resize }
        signal_connect('notify::is-active') { focus_changed }
        client.subscribe do |event|
          show_title(event.conversations) if event.is_a?(Protocol::ConversationsChanged)
        end
        reset
      end

      # @return [Boolean] false while it is the pill
      def expanded? = @expanded

      # @return [Boolean]
      def history_visible? = @split.show_sidebar?

      # @return [String] the header's title
      def header_title = @title.title

      # Shows or hides the history, widening or narrowing the window by it.
      #
      # @param visible [Boolean]
      # @return [void]
      def history_visible=(visible)
        expand if visible
        # Hidden, the sidebar would still hold the window to its own minimum height.
        @sidebar.visible = visible
        @split.show_sidebar = visible
        @history_button.active = visible
        @sidebar.refresh if visible
        resize
      end

      # Escape: see the class doc.
      #
      # @return [void]
      def escape
        if @conversation_view.activity.state == 'streaming' && !@escape_cancelled
          @conversation_view.cancel
          @escape_cancelled = true
        else
          @conversation_view.cancel unless @escape_cancelled
          self.visible = false
        end
      end

      # Ctrl+N: an empty conversation, in the window as it is.
      #
      # @return [void]
      def new_conversation
        @conversation_view.conversation = nil
        @sidebar.selected = nil
        @title.title = 'New conversation'
        @conversation_view.entry.grab_focus
      end

      private

      # @return [Gtk::Widget]
      def layout
        @title = Adw::WindowTitle.new('Puri', '')
        @history_button = Gtk::ToggleButton.new
        @history_button.icon_name = 'sidebar-show-symbolic'
        @history_button.tooltip_text = 'History (F9)'
        @history_button.signal_connect('toggled') do |button|
          self.history_visible = button.active? if button.active? != history_visible?
        end
        compose = Gtk::Button.new(icon_name: 'document-edit-symbolic')
        compose.tooltip_text = 'New conversation (Ctrl+N)'
        compose.action_name = 'win.new-conversation'
        header = Adw::HeaderBar.new
        header.decoration_layout = 'close:'
        header.title_widget = @title
        header.pack_end(@history_button)
        header.pack_end(compose)

        @toolbar = Adw::ToolbarView.new
        @toolbar.add_top_bar(header)
        @toolbar.content = @conversation_view

        @split = Adw::OverlaySplitView.new
        @split.collapsed = false
        @split.min_sidebar_width = @split.max_sidebar_width = SIDEBAR_WIDTH
        @split.sidebar = @sidebar
        @split.content = @toolbar

        # The empty margins drag the window, as Siri's card does; text stays selectable.
        handle = Gtk::WindowHandle.new
        handle.child = @split
        handle
      end

      # @return [void]
      def install_actions
        shortcuts = Gtk::ShortcutController.new
        {
          'escape' => [[Gdk::Keyval::KEY_Escape, 0], -> { escape }],
          'new-conversation' => [[Gdk::Keyval::KEY_n, :control_mask], -> { new_conversation }],
          'search' => [[Gdk::Keyval::KEY_f, :control_mask], -> { search }],
          'toggle-history' => [[Gdk::Keyval::KEY_F9, 0], -> { self.history_visible = !history_visible? }],
          'hide' => [nil, -> { self.visible = false }]
        }.each do |name, (key, body)|
          action = Gio::SimpleAction.new(name)
          action.signal_connect('activate') { body.call }
          add_action(action)
          next unless key

          shortcuts.add_shortcut(Gtk::Shortcut.new(Gtk::KeyvalTrigger.new(*key), Gtk::NamedAction.new("win.#{name}")))
        end
        add_controller(shortcuts)
      end

      # The empty pill, as every popup starts.
      #
      # @return [void]
      def reset
        @escape_cancelled = false
        @was_active = false
        @expanded = false
        @split.show_sidebar = false
        @sidebar.visible = false
        @history_button.active = false
        @conversation_view.conversation = nil
        @conversation_view.expanded = false
        @toolbar.reveal_top_bars = false
        @sidebar.selected = nil
        @title.title = 'Puri'
        add_css_class('pill')
        resize
        @conversation_view.entry.grab_focus
      end

      # @return [void]
      def expand
        return if @expanded

        @expanded = true
        remove_css_class('pill')
        @toolbar.reveal_top_bars = true
        @conversation_view.expanded = true
        resize
      end

      # @param id [String]
      # @return [void]
      def asked(id)
        @escape_cancelled = false
        expand
        @sidebar.selected = id
        show_title(@client.list_conversations)
      end

      # @param id [String]
      # @return [void]
      def open_conversation(id)
        expand
        @escape_cancelled = false
        @conversation_view.conversation = id
        show_title(@client.list_conversations)
      end

      # Ctrl+F: the history, its search focused.
      #
      # @return [void]
      def search
        self.history_visible = true
        @sidebar.focus_search
      end

      # @param conversations [Array<Puri::Protocol::ConversationSummary>]
      # @return [void]
      def show_title(conversations)
        shown = conversations.find { _1.id == @conversation_view.conversation } or return
        @title.title = shown.title
      end

      # Hides the empty pill once it loses focus; a conversation on screen stays.
      #
      # @return [void]
      def focus_changed
        if active?
          @was_active = true
        elsif @was_active && !@expanded && visible?
          self.visible = false
        end
      end

      # Sizes the window for its state, from the size of the screen it is on.
      #
      # @return [void]
      def resize
        screen_width, screen_height = screen_size
        width = [(screen_width * WIDTH).round, MIN_WIDTH].max
        width += SIDEBAR_WIDTH if history_visible?
        # The pill asks for no height; GTK raises it to what the entry needs.
        height = @expanded ? (screen_height * HEIGHT).round : 1
        set_default_size(width, height)
      end

      # @return [Array(Integer, Integer)] the screen's width and height, in logical pixels
      def screen_size
        display = Gdk::Display.default
        monitor = (display.get_monitor_at_surface(surface) if surface) || display.monitors.get_item(0)
        return [1920, 1080] unless monitor

        [monitor.geometry.width, monitor.geometry.height]
      end
    end
  end
end
