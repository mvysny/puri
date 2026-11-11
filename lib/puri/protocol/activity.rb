# frozen_string_literal: true

module Puri
  module Protocol
    # What a conversation's turn is doing.
    #
    #   Activity.new(state: 'working', status: 'Searching the web…')   # progress bar, status under it
    #   Activity.new(state: 'streaming', status: '')                   # reply text arriving
    #   Activity.new(state: 'confirming', status: '')                  # a Confirmation waits
    #   Activity::IDLE                                                 # no turn
    #
    # @!attribute [r] state
    #   @return [String] one of {STATES}
    # @!attribute [r] status
    #   @return [String] the latest step as Core words it; empty but while `working`
    class Activity < Data.define(:state, :status)
      # @return [Array<String>]
      STATES = %w[idle working streaming confirming].freeze

      # @param state [String] one of {STATES}
      # @param status [String]
      # @raise [ArgumentError] for any other state
      def initialize(state:, status: '')
        raise ArgumentError, "unknown activity state: #{state.inspect}" unless STATES.include?(state)

        super
      end

      # @return [Boolean] whether a turn runs, in whatever state
      def running? = state != 'idle'

      # @return [Activity]
      IDLE = new(state: 'idle')
    end
  end
end
