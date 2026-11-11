# frozen_string_literal: true

module Puri
  # What {Core} and {Desktop} say to each other. Desktop calls the methods of {Backend}; Core
  # pushes events back. Arguments, results and events are `Data` of this namespace, strings,
  # numbers, booleans, nil and arrays of these, so all of it survives JSON, and a later split into
  # two processes over D-Bus maps the methods to D-Bus methods and the events to signals.
  #
  #   transcript = client.load_conversation('3f2…')     # => Transcript, its blocks in order
  #   client.ask('3f2…', 'and bananas?')                # => "3f2…"
  #   # then, pushed: ActivityChanged(working), BlockChanged(UserMessage), BlockChanged(Reply)…
  #
  # The transcript is pikuri-web's: Core renders, Desktop places. Every block carries an id and
  # its whole current content; {BlockChanged} upserts it by id, so streaming re-sends the growing
  # {Reply} and a stale event is overwritten by the next one.
  #
  # Protocol names neither side, nor anything outside the stdlib.
  module Protocol
    # Serializes a value, each `Data` in it as its fields plus its class name under `type`.
    #
    #   Protocol.encode(BlockRemoved.new(conversation: 'c1', block: 'b2'))
    #   # => {"conversation":"c1","block":"b2","type":"BlockRemoved"}
    #
    # @param value [Object] a `Data` of this namespace, or JSON-able values and arrays of them
    # @return [String] JSON
    # @raise [ArgumentError] on a value JSON can't carry faithfully: a Hash, a Symbol, a Time…
    def self.encode(value) = JSON.generate(dump(value))

    # The inverse of {encode}.
    #
    # @param json [String] what {encode} produced
    # @return [Object] the value
    # @raise [ArgumentError] when a `type` names no message of this namespace
    def self.decode(json) = load(JSON.parse(json, symbolize_names: true))

    # Takes a value through JSON and back. {Desktop::BackendClient} does this to every argument,
    # result and event, so neither side ever holds a Ruby object of the other's, and swapping the
    # in-process call for D-Bus changes nothing else.
    #
    # @param value [Object] see {encode}
    # @return [Object] an equal copy
    def self.round_trip(value) = decode(encode(value))

    # @param value [Object]
    # @return [Object] JSON-able
    def self.dump(value)
      case value
      when Data
        value.to_h.transform_values { dump(_1) }.merge(type: value.class.name.delete_prefix("#{name}::"))
      when Array then value.map { dump(_1) }
      when String, Integer, Float, true, false, nil then value
      else raise ArgumentError, "Puri::Protocol can't carry #{value.inspect}"
      end
    end

    # @param tree [Object] parsed JSON, keys symbolized
    # @return [Object]
    def self.load(tree)
      case tree
      when Hash
        fields = tree.except(:type).transform_values { load(_1) }
        message_class(tree[:type], tree).new(**fields)
      when Array then tree.map { load(_1) }
      else tree
      end
    end

    # @param tag [Object] the `type` field
    # @param tree [Hash] the whole object, for the error
    # @return [Class]
    def self.message_class(tag, tree)
      klass = const_get(tag, false) if tag.is_a?(String) && const_defined?(tag, false)
      raise ArgumentError, "not a Puri::Protocol message: #{tree.inspect}" unless klass.is_a?(Class) && klass < Data

      klass
    end

    private_class_method :dump, :load, :message_class
  end
end
