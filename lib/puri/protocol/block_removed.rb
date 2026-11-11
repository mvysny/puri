# frozen_string_literal: true

module Puri
  module Protocol
    # Event: a transcript block is gone. An id Desktop never drew is not an error.
    #
    # @!attribute [r] conversation
    #   @return [String]
    # @!attribute [r] block
    #   @return [String] the block's id
    class BlockRemoved < Data.define(:conversation, :block)
    end
  end
end
