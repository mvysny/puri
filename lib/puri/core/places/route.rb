# frozen_string_literal: true

module Puri
  module Core
    module Places
      # A drive OSRM worked out: how far, how long, and the road it takes.
      #
      #   route.words   # => "6.3 km, 9 min"
      #
      # @!attribute [r] distance
      #   @return [Float] metres
      # @!attribute [r] duration
      #   @return [Float] seconds, without traffic
      # @!attribute [r] line
      #   @return [Array<Array<Float>>] the road's `[lat, lon]` points, simplified; empty when only
      #     the distance was asked
      class Route < Data.define(:distance, :duration, :line)
        # @return [String] "850 m, 2 min", "6.3 km, 9 min", "42 km, 1 h 5 min"
        def words = "#{distance_words}, #{duration_words}"

        private

        # @return [String]
        def distance_words
          return "#{(distance / 10).round * 10} m" if distance < 1000

          km = distance / 1000
          km < 10 ? "#{km.round(1)} km" : "#{km.round} km"
        end

        # @return [String]
        def duration_words
          minutes = [(duration / 60).round, 1].max
          minutes < 60 ? "#{minutes} min" : "#{minutes / 60} h #{minutes % 60} min"
        end
      end
    end
  end
end
