# frozen_string_literal: true

module Puri
  module Core
    # The connections a conversation can run on, by the name `config.toml` gives each `[[llm]]`:
    #
    #   models = Models.from_config(config)
    #   models.names                          # => ["Ornith 1.5", "Ornith 1.5, no thinking"]
    #   models.find('Ornith 1.5').transport   # => what conversations.open takes
    #   models.name_for(live.status.model)    # => "Ornith 1.5", whatever the probe filled in
    #   models.saved(entry)                   # => the Choice a saved conversation resumes on, or nil
    #
    # Immutable.
    class Models
      # @!attribute [r] name
      #   @return [String]
      # @!attribute [r] transport
      #   @return [Pikuri::Agent::ChatTransport]
      # @!attribute [r] embedded
      #   @return [Boolean] whether it runs on the llama-server Puri runs itself
      class Choice < Data.define(:name, :transport, :embedded)
        # @param name [String]
        # @param transport [Pikuri::Agent::ChatTransport]
        # @param embedded [Boolean]
        def initialize(name:, transport:, embedded: false) = super
      end

      # @param config [Puri::Core::Config]
      # @return [Puri::Core::Models] every `[[llm]]`, in the file's order
      def self.from_config(config)
        embedded = config.embedded_server&.url
        new(config.llms.map { Choice.new(name: _1.name, transport: _1.transport, embedded: _1.server == embedded) })
      end

      # A connection's identity: two `[[llm]]` on one model and one server differ in `params`
      # alone, as the titler's thinking-off twin does. The probe fills in the context window,
      # so a whole transport never `==` the one it started as.
      #
      # @param transport [Pikuri::Agent::ChatTransport]
      # @return [Array(String, String, Hash{String => Object})]
      def self.key(transport) = [transport.model, transport.api_base, transport.params]

      # @param choices [Array<Puri::Core::Models::Choice>] the first is the default; never empty
      # @raise [ArgumentError] when empty
      def initialize(choices)
        raise ArgumentError, 'Models needs at least one connection' if choices.empty?

        @choices = choices.freeze
        freeze
      end

      # @return [Puri::Core::Models::Choice] the first
      def default = @choices.first

      # @return [Array<String>]
      def names = @choices.map(&:name)

      # @param name [String]
      # @return [Puri::Core::Models::Choice]
      # @raise [ArgumentError] for a name no connection has
      def find(name)
        @choices.find { _1.name == name } or raise ArgumentError, "no model named #{name.inspect}"
      end

      # @param transport [Pikuri::Agent::ChatTransport]
      # @return [String] its connection's name; the bare model id for one the config lacks
      def name_for(transport)
        key = Models.key(transport)
        @choices.find { Models.key(_1.transport) == key }&.name || transport.model
      end

      # `meta.json` keeps the model and the server, not the params, so of two connections that
      # differ only in params the first in the file wins. The llama-server Puri runs gets a new
      # port every run, so failing the server, a connection to it on the same model will do.
      #
      # @param entry [Pikuri::Conversations::Store::Entry]
      # @return [Puri::Core::Models::Choice, nil] the connection it was saved on; nil when the
      #   config no longer has it, or it was never saved
      def saved(entry)
        @choices.find { _1.transport.model == entry.model && _1.transport.api_base == entry.server } ||
          @choices.find { _1.embedded && _1.transport.model == entry.model }
      end
    end
  end
end
