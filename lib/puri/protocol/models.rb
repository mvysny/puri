# frozen_string_literal: true

module Puri
  module Protocol
    # The models a conversation can run on, what {Backend#list_models} returns.
    #
    #   Models.new(names: ['Ornith 1.5', 'Qwen 3.6'], selected: 'Ornith 1.5')
    #
    # @!attribute [r] names
    #   @return [Array<String>] the config's connections, in its order; never empty
    # @!attribute [r] selected
    #   @return [String] the one a new conversation starts on
    class Models < Data.define(:names, :selected)
    end
  end
end
