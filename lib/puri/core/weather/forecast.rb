# frozen_string_literal: true

require 'date'

module Puri
  module Core
    module Weather
      # One place's weather as Open-Meteo answered it, in the place's own time and in the
      # {Units} asked for: now, a line a day, and each hour.
      #
      #   forecast = open_meteo.forecast(lat: 38.72, lon: -9.14, units:)
      #   forecast.today              # => #<Date 2026-11-22>, the place's
      #   forecast.days.last.date     # => #<Date 2026-12-06>: the last day with data, 14 or 15 ahead
      #   forecast.hours_of(forecast.today).first.clock   # => "00:00"
      #
      # Any value but a time may be nil, where the weather models have none.
      #
      # @!attribute [r] timezone
      #   @return [String] the place's, "Europe/Lisbon"
      # @!attribute [r] now
      #   @return [Puri::Core::Weather::Forecast::Now]
      # @!attribute [r] days
      #   @return [Array<Puri::Core::Weather::Forecast::Day>] in order, past days first
      # @!attribute [r] hours
      #   @return [Array<Puri::Core::Weather::Forecast::Hour>] in order, over the same days
      class Forecast < Data.define(:timezone, :now, :days, :hours)
        # The weather at the moment, from Open-Meteo's 15-minute data.
        #
        # @!attribute [r] time
        #   @return [String] local, "2026-11-22T15:15"
        # @!attribute [r] condition
        #   @return [String, nil] "overcast"
        # @!attribute [r] temperature
        #   @return [Float, nil]
        # @!attribute [r] feels_like
        #   @return [Float, nil]
        # @!attribute [r] wind
        #   @return [Integer, nil] in {Units#wind_label}
        class Now < Data.define(:time, :condition, :temperature, :feels_like, :wind)
          # @return [Date]
          def date = Date.iso8601(time[0, 10])

          # @return [String] "15:15"
          def clock = time[11, 5]
        end

        # @!attribute [r] date
        #   @return [Date]
        # @!attribute [r] condition
        #   @return [String, nil] the day's most significant weather, "slight rain showers"
        # @!attribute [r] high
        #   @return [Float, nil]
        # @!attribute [r] low
        #   @return [Float, nil]
        # @!attribute [r] precipitation
        #   @return [Float, nil] rain and snow together, as water
        # @!attribute [r] chance
        #   @return [Integer, nil] the likeliest hour's chance of any, in per cent
        # @!attribute [r] wind
        #   @return [Integer, nil] the strongest, in {Units#wind_label}
        # @!attribute [r] sunrise
        #   @return [String, nil] "07:39"
        # @!attribute [r] sunset
        #   @return [String, nil] "16:04"
        class Day < Data.define(:date, :condition, :high, :low, :precipitation, :chance, :wind, :sunrise, :sunset); end

        # @!attribute [r] time
        #   @return [String] local, "2026-11-22T15:00"
        # @!attribute [r] condition
        #   @return [String, nil]
        # @!attribute [r] temperature
        #   @return [Float, nil]
        # @!attribute [r] precipitation
        #   @return [Float, nil] over the hour before
        # @!attribute [r] chance
        #   @return [Integer, nil] in per cent
        # @!attribute [r] wind
        #   @return [Integer, nil] in {Units#wind_label}
        class Hour < Data.define(:time, :condition, :temperature, :precipitation, :chance, :wind)
          # @return [Date]
          def date = Date.iso8601(time[0, 10])

          # @return [String] "15:00"
          def clock = time[11, 5]
        end

        # @return [Date] the place's today, which may not be the machine's
        def today = now.date

        # @param date [Date]
        # @return [Puri::Core::Weather::Forecast::Day, nil]
        def day(date) = days.find { _1.date == date }

        # @param date [Date]
        # @return [Array<Puri::Core::Weather::Forecast::Hour>]
        def hours_of(date) = hours.select { _1.date == date }
      end
    end
  end
end
