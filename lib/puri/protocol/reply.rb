# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: the model's answer, rendered by Core into parts Desktop only places.
    # While it streams, Core re-sends the whole reply with each delta.
    #
    #   Reply.new(id: 'b3', parts: [
    #     Prose.new(markup: "<b>Avocados</b> keep for…\n\n• in the fridge"),
    #     Table.new(header: ['Where', 'Days'], rows: [['Fridge', '3–5']]),
    #   ])
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] parts
    #   @return [Array<Puri::Protocol::Prose, Puri::Protocol::Code, Puri::Protocol::Table>] in order
    class Reply < Data.define(:id, :parts)
      include Block
    end
  end
end
