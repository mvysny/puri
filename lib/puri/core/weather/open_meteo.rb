# frozen_string_literal: true

require 'uri'

module Puri
  module Core
    module Weather
      # Open-Meteo's forecast API: free, keyless, the data CC BY 4.0 (`R_open_meteo`).
      #
      #   open_meteo = OpenMeteo.new(http: Http.new)
      #   forecast = open_meteo.forecast(lat: 38.7223, lon: -9.1393, units: Units.gnome, cancellable:)
      #   forecast.days.size   # => 15 or 16: today and what follows, in Lisbon's time
      #
      # Every call asks for the whole forecast, so asking again about the same place within
      # {MAX_AGE} costs no request. The point goes out rounded to {PRECISION} decimals, about a
      # kilometre, finer than the weather models' grid, so a home address's exact point never
      # reaches Open-Meteo.
      #
      # Thread-safe.
      class OpenMeteo
        # @return [String] the public API; `[weather] url` may name a self-hosted one
        URL = 'https://api.open-meteo.com'

        # @return [Integer] seconds an answer is reused: the `current` data's own step
        MAX_AGE = 900

        # @return [Integer] decimals of latitude and longitude sent
        PRECISION = 2

        # @return [Integer] days ahead, today included, the most the API gives
        FORECAST_DAYS = 16

        # @return [Integer] the last day after today that reliably has data: the sixteenth often
        #   has none
        AHEAD = 14

        # @return [Integer] the most days back the API gives
        PAST_DAYS = 92

        # The WMO weather codes Open-Meteo answers, in its own words.
        #
        # @return [Hash{Integer => String}]
        CONDITIONS = {
          0 => 'clear sky', 1 => 'mainly clear', 2 => 'partly cloudy', 3 => 'overcast',
          45 => 'fog', 48 => 'depositing rime fog',
          51 => 'light drizzle', 53 => 'moderate drizzle', 55 => 'dense drizzle',
          56 => 'light freezing drizzle', 57 => 'dense freezing drizzle',
          61 => 'slight rain', 63 => 'moderate rain', 65 => 'heavy rain',
          66 => 'light freezing rain', 67 => 'heavy freezing rain',
          71 => 'slight snowfall', 73 => 'moderate snowfall', 75 => 'heavy snowfall', 77 => 'snow grains',
          80 => 'slight rain showers', 81 => 'moderate rain showers', 82 => 'violent rain showers',
          85 => 'slight snow showers', 86 => 'heavy snow showers',
          95 => 'thunderstorm', 96 => 'thunderstorm with slight hail', 97 => 'heavy thunderstorm',
          99 => 'thunderstorm with heavy hail'
        }.freeze

        # @return [String]
        CURRENT = 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m'
        # @return [String]
        DAILY = 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,' \
                'precipitation_probability_max,wind_speed_10m_max,sunrise,sunset'
        # @return [String]
        HOURLY = 'temperature_2m,weather_code,precipitation,precipitation_probability,wind_speed_10m'

        # @param http [Puri::Core::Http] shared with the place tools, so its pacing covers all
        # @param url [String] the API's base, without `/v1`
        def initialize(http:, url: URL)
          @http = http
          @url = url.chomp('/')
        end

        # @param lat [Float]
        # @param lon [Float]
        # @param units [Puri::Core::Weather::Units]
        # @param past_days [Integer] days before today to include, up to {PAST_DAYS}
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Puri::Core::Weather::Forecast]
        # @raise [Puri::Core::Http::Error]
        def forecast(lat:, lon:, units:, past_days: 0, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          query = URI.encode_www_form(
            latitude: lat.round(PRECISION), longitude: lon.round(PRECISION), timezone: 'auto',
            forecast_days: FORECAST_DAYS, past_days: past_days.clamp(0, PAST_DAYS),
            current: CURRENT, daily: DAILY, hourly: HOURLY,
            temperature_unit: units.open_meteo_temperature, wind_speed_unit: units.open_meteo_wind,
            precipitation_unit: units.open_meteo_precipitation
          )
          json = @http.get_json("#{@url}/v1/forecast?#{query}", max_age: MAX_AGE, cancellable:)
          read(json, units)
        end

        private

        # @param json [Hash{String => Object}]
        # @param units [Puri::Core::Weather::Units]
        # @return [Puri::Core::Weather::Forecast]
        # @raise [Puri::Core::Http::Error] on an answer missing its parts, or with no day of data
        def read(json, units)
          current = json['current'] or raise Http::Error, 'Open-Meteo answered with no current weather'
          daily = json['daily'] or raise Http::Error, 'Open-Meteo answered with no daily forecast'
          hourly = json['hourly'] or raise Http::Error, 'Open-Meteo answered with no hourly forecast'
          # The sixteenth day often holds only nulls: the weather models stop before it ends.
          known = days(daily, units).reject { _1.condition.nil? && _1.high.nil? }
          raise Http::Error, 'Open-Meteo has no forecast for this place' if known.empty?

          Forecast.new(timezone: json['timezone'].to_s, now: now(current, units), days: known,
                       hours: hours(hourly, units).reject { _1.condition.nil? && _1.temperature.nil? })
        end

        # @param current [Hash{String => Object}]
        # @param units [Puri::Core::Weather::Units]
        # @return [Puri::Core::Weather::Forecast::Now]
        def now(current, units)
          Forecast::Now.new(time: current.fetch('time'), condition: condition(current['weather_code']),
                            temperature: current['temperature_2m'], feels_like: current['apparent_temperature'],
                            wind: units.wind_speed(current['wind_speed_10m']))
        end

        # @param daily [Hash{String => Array<Object>}] columns, one per variable
        # @param units [Puri::Core::Weather::Units]
        # @return [Array<Puri::Core::Weather::Forecast::Day>]
        def days(daily, units)
          daily.fetch('time').each_index.map do |i|
            column = ->(name) { daily[name]&.[](i) }
            Forecast::Day.new(date: Date.iso8601(column.call('time')),
                              condition: condition(column.call('weather_code')),
                              high: column.call('temperature_2m_max'), low: column.call('temperature_2m_min'),
                              precipitation: column.call('precipitation_sum'),
                              chance: column.call('precipitation_probability_max'),
                              wind: units.wind_speed(column.call('wind_speed_10m_max')),
                              sunrise: column.call('sunrise')&.[](11, 5), sunset: column.call('sunset')&.[](11, 5))
          end
        end

        # @param hourly [Hash{String => Array<Object>}] columns, one per variable
        # @param units [Puri::Core::Weather::Units]
        # @return [Array<Puri::Core::Weather::Forecast::Hour>]
        def hours(hourly, units)
          hourly.fetch('time').each_index.map do |i|
            column = ->(name) { hourly[name]&.[](i) }
            Forecast::Hour.new(time: column.call('time'), condition: condition(column.call('weather_code')),
                               temperature: column.call('temperature_2m'), precipitation: column.call('precipitation'),
                               chance: column.call('precipitation_probability'),
                               wind: units.wind_speed(column.call('wind_speed_10m')))
          end
        end

        # @param code [Integer, nil]
        # @return [String, nil]
        def condition(code) = code && CONDITIONS.fetch(code) { "weather code #{code}" }
      end
    end
  end
end
