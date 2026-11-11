# frozen_string_literal: true

module Puri
  module Protocol
    # One row of the history sidebar.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] title
    #   @return [String] "New conversation" until Core names it from the opening question
    # @!attribute [r] started_at
    #   @return [String] ISO 8601 with the offset, `2026-11-11T14:05:00+01:00`
    # @!attribute [r] running
    #   @return [Boolean] whether a turn runs in it now, the sidebar's `●`
    # @!attribute [r] last_question
    #   @return [String, nil] what the user asked last, for Up in an empty entry
    # @!attribute [r] asked_at
    #   @return [String, nil] when, ISO 8601 like {#started_at}
    class ConversationSummary < Data.define(:id, :title, :started_at, :running, :last_question, :asked_at)
    end
  end
end
