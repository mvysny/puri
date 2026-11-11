# frozen_string_literal: true

module Puri
  module Protocol
    # What every transcript block is: {UserMessage}, {Reply}, {ToolLine}, {Confirmation} or
    # {Notice}. Each has an `id`, unique within its conversation, which {BlockChanged} and
    # {BlockRemoved} address it by. A type name only, with nothing to share.
    module Block
    end
  end
end
