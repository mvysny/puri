# frozen_string_literal: true

module Puri
  module Desktop
    # The line under the entry: the model the next turn runs on, a pick away, then how full the
    # conversation's context is.
    #
    #   [Ornith 1.5 ▾]  ▰▰▱▱▱▱  7.4k of 64.0k tokens          msg #2  Δ+1.6k  ↑1.0k  ↓0.6k
    #    <model pick>   <fill>  <context>                                         <detail>
    #
    #   bar = StatusBar.new(client)
    #   bar.show(id, transcript.status)   # a conversation loaded
    #   bar.show(nil)                     # a new one: the model it will start on
    #   bar.show(id)                      # the new one just asked in; its StatusChanged follows
    #
    # Picking a model calls `select_model` on the conversation shown, or, in a new one, picks the
    # model it will start on.
    class StatusBar < Gtk::Box
      # @return [Gtk::DropDown]
      attr_reader :model

      # @return [Gtk::Label]
      attr_reader :context

      # @return [Gtk::Label]
      attr_reader :detail

      # @param client [Puri::Desktop::BackendClient]
      def initialize(client)
        super(:horizontal, 10)
        @client = client
        @conversation = nil
        add_css_class('puri-status-bar')
        @names = client.list_models.names
        @model = Gtk::DropDown.new(Gtk::StringList.new(@names), nil)
        @model.tooltip_text = 'Model for the next answer'
        @model.sensitive = @names.size > 1
        @model.signal_connect('notify::selected') { picked unless @showing }
        @fill = Gtk::LevelBar.new
        @fill.valign = :center
        @fill.width_request = 64
        @context = Gtk::Label.new('')
        @detail = Gtk::Label.new('')
        @detail.hexpand = true
        @detail.xalign = 1
        @detail.ellipsize = :end
        @detail.add_css_class('dim-label')
        [@model, @fill, @context, @detail].each { append(_1) }
        client.subscribe do |event|
          self.status = event.status if event.is_a?(Protocol::StatusChanged) && event.conversation == @conversation
        end
      end

      # @param conversation [String, nil] nil for a new one
      # @param status [Puri::Protocol::Status, nil] its status; nil keeps what is shown until the
      #   conversation's next {Protocol::StatusChanged}, but for a new one
      # @return [void]
      def show(conversation, status = nil)
        @conversation = conversation
        status ||= Protocol::Status.new(model: @client.list_models.selected) unless conversation
        self.status = status if status
      end

      # @return [String, nil] the model picked
      def model_name = @model.selected_item&.string

      private

      # @param status [Puri::Protocol::Status]
      # @return [void]
      def status=(status)
        @showing = true
        @model.selected = @names.index(status.model) || Gtk::INVALID_LIST_POSITION
        @showing = false
        @fill.visible = !status.fill.nil?
        @fill.value = status.fill || 0
        @context.label = status.context
        @detail.label = status.detail
      end

      # @return [void]
      def picked
        name = model_name or return
        @client.select_model(@conversation, name)
      end
    end
  end
end
