# frozen_string_literal: true

module Puri
  module Protocol
    # A whole conversation as Desktop draws it, what {Backend#load_conversation} returns. Later
    # changes arrive as {BlockChanged}, {BlockRemoved}, {ActivityChanged}, {StatusChanged} and
    # {PendingChanged}.
    #
    # @!attribute [r] conversation
    #   @return [String] its id
    # @!attribute [r] title
    #   @return [String]
    # @!attribute [r] blocks
    #   @return [Array<Puri::Protocol::Block>] in order
    # @!attribute [r] activity
    #   @return [Puri::Protocol::Activity]
    # @!attribute [r] status
    #   @return [Puri::Protocol::Status]
    # @!attribute [r] pending
    #   @return [Array<String>] the messages the agent hasn't read yet, as {PendingChanged#texts}
    class Transcript < Data.define(:conversation, :title, :blocks, :activity, :status, :pending)
      # @param conversation [String]
      # @param title [String]
      # @param blocks [Array<Puri::Protocol::Block>]
      # @param activity [Puri::Protocol::Activity]
      # @param status [Puri::Protocol::Status]
      # @param pending [Array<String>]
      def initialize(conversation:, title:, blocks:, activity:, status:, pending: []) = super
    end
  end
end
