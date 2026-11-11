# frozen_string_literal: true

module Puri
  module Protocol
    # Part of a {Reply}: a fenced code block.
    #
    # @!attribute [r] text
    #   @return [String] plain text, never markup
    class Code < Data.define(:text)
    end
  end
end
