# frozen_string_literal: true

module Puri
  # The messages between {Core} and {Desktop}: commands Desktop sends, events Core emits. Each is
  # a `Data` with JSON-able fields only, so this is already the D-Bus API of a later split.
  #
  # Protocol names neither side, nor anything outside the stdlib.
  module Protocol
    # Serializes a message, its class name under `type`.
    #
    #   Protocol.encode(TurnFinished.new(conversation: 'c1'))   # => {"conversation":"c1","type":"TurnFinished"}
    #
    # @param message [Data] a command or event of this namespace
    # @return [String] JSON
    def self.encode(message)
      JSON.generate(message.to_h.merge(type: message.class.name.delete_prefix("#{name}::")))
    end

    # The inverse of {encode}.
    #
    # @param json [String] what {encode} produced
    # @return [Data] the message
    # @raise [ArgumentError] when `type` names no message of this namespace
    def self.decode(json)
      fields = JSON.parse(json, symbolize_names: true)
      type = fields.delete(:type)
      klass = const_get(type, false) if type.is_a?(String) && const_defined?(type, false)
      raise ArgumentError, "not a Puri::Protocol message: #{json}" unless klass.is_a?(Class) && klass < Data

      klass.new(**fields)
    end

    # Takes a message through JSON and back. The in-process connection does this to every
    # message, so neither side ever holds a Ruby object of the other's, and swapping it for D-Bus
    # changes nothing else.
    #
    # @param message [Data] a command or event of this namespace
    # @return [Data] an equal copy
    def self.round_trip(message) = decode(encode(message))
  end
end
