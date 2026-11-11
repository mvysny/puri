# frozen_string_literal: true

module Puri
  module Protocol
    # Part of a {Reply}: a table, each cell Pango markup.
    #
    # @!attribute [r] header
    #   @return [Array<String>] one cell per column
    # @!attribute [r] rows
    #   @return [Array<Array<String>>] each as wide as {#header}
    class Table < Data.define(:header, :rows)
    end
  end
end
