# frozen_string_literal: true

module Puri
  module Protocol
    # Event: a transcript block appeared or changed. Desktop replaces the block with this id, or
    # appends it when it has none.
    #
    # @!attribute [r] conversation
    #   @return [String]
    # @!attribute [r] block
    #   @return [Puri::Protocol::Block]
    class BlockChanged < Data.define(:conversation, :block)
    end
  end
end
