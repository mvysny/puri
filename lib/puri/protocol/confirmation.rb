# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: the agent asks before it acts. While `pending`, Desktop shows Cancel and
    # the approve button, and answers through {Backend#answer}; typed text answers it too
    # ({Backend#ask}). Answered, Core re-sends it with its final state.
    #
    #   Confirmation.new(id: 'b4', question: 'Move “Dentist” (Personal) to Thursday 15:00?',
    #                    approve_label: 'Update', destructive: true, state: 'pending')
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] question
    #   @return [String] plain text naming everything that matters: which calendar, which note
    # @!attribute [r] approve_label
    #   @return [String] the approve button's word, "Update", "Open draft"
    # @!attribute [r] destructive
    #   @return [Boolean] true paints the approve button red, false blue
    # @!attribute [r] state
    #   @return [String] one of {STATES}
    class Confirmation < Data.define(:id, :question, :approve_label, :destructive, :state)
      include Block

      # @return [Array<String>]
      STATES = %w[pending approved rejected redirected cancelled].freeze

      # @return [Boolean]
      def pending? = state == 'pending'
    end
  end
end
