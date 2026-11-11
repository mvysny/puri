# frozen_string_literal: true

module Puri
  module Protocol
    # A whole conversation as Desktop draws it, what {Backend#load_conversation} returns. Later
    # changes arrive as {BlockChanged}, {BlockRemoved} and {ActivityChanged}.
    #
    # @!attribute [r] conversation
    #   @return [String] its id
    # @!attribute [r] title
    #   @return [String]
    # @!attribute [r] blocks
    #   @return [Array<Puri::Protocol::Block>] in order
    # @!attribute [r] activity
    #   @return [Puri::Protocol::Activity]
    class Transcript < Data.define(:conversation, :title, :blocks, :activity)
    end
  end
end
