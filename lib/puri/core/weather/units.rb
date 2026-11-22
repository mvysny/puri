# frozen_string_literal: true

require 'open3'

module Puri
  module Core
    module Weather
      # What a forecast is shown in: GNOME's choice, so Puri says what GNOME Weather and the
      # shell's clock say.
      #
      #   Units.gnome   # => Units(temperature: :celsius, wind: :kmh, precipitation: :mm) on a metric desktop
      #   units.wind_label        # => "km/h"
      #   units.wind_speed(17.24) # => 17; with wind: :bft, Open-Meteo's 9.2 m/s => force 5
      #
      # GNOME keeps temperature and wind in `org.gnome.GWeather4`; precipitation follows its
      # distance unit, miles meaning inches. Each key's `default` follows the locale's
      # `LC_MEASUREMENT`: imperial gives °F, mph and inches, anything else °C, km/h and mm.
      #
      # @!attribute [r] temperature
      #   @return [Symbol] `:celsius` or `:fahrenheit`
      # @!attribute [r] wind
      #   @return [Symbol] `:kmh`, `:ms`, `:mph`, `:kn` or `:bft`
      # @!attribute [r] precipitation
      #   @return [Symbol] `:mm` or `:inch`
      class Units < Data.define(:temperature, :wind, :precipitation)
        # @return [Logger]
        LOGGER = Pikuri.logger_for('Weather::Units')

        # @return [String]
        SCHEMA = 'org.gnome.GWeather4'

        # GWeather's `speed-unit` values, as Units says them.
        #
        # @return [Hash{String => Symbol}]
        WINDS = { 'kph' => :kmh, 'ms' => :ms, 'mph' => :mph, 'knots' => :kn, 'bft' => :bft }.freeze

        # @return [Hash{Symbol => String}]
        WIND_LABELS = { kmh: 'km/h', ms: 'm/s', mph: 'mph', kn: 'kn', bft: 'Bft' }.freeze

        # Each Beaufort force's highest wind, in m/s; anything above the last is force 12.
        #
        # @return [Array<Float>]
        BEAUFORT = [0.5, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7].freeze

        # @param settings [Hash{String => String}] the `temperature-unit`, `speed-unit` and
        #   `distance-unit` keys, as `gsettings get` prints them, quotes stripped; a key missing
        #   is `default`
        # @param imperial [Boolean] whether the locale measures in imperial units
        # @return [Puri::Core::Weather::Units]
        def self.from(settings, imperial:)
          temperature = case settings['temperature-unit']
                        when 'fahrenheit' then :fahrenheit
                        when 'centigrade', 'kelvin' then :celsius
                        else imperial ? :fahrenheit : :celsius
                        end
          wind = WINDS.fetch(settings['speed-unit'].to_s) { imperial ? :mph : :kmh }
          precipitation = case settings['distance-unit']
                          when 'miles' then :inch
                          when 'meters', 'km' then :mm
                          else imperial ? :inch : :mm
                          end
          new(temperature:, wind:, precipitation:)
        end

        # This desktop's units. A machine without GNOME's schema, or without `gsettings`, gets the
        # locale's.
        #
        # @return [Puri::Core::Weather::Units]
        def self.gnome
          keys = %w[temperature-unit speed-unit distance-unit]
          from(keys.to_h { [_1, gsetting(_1)] }, imperial: imperial_locale?)
        end

        # @param key [String]
        # @return [String, nil] its value, quotes stripped; nil when it can't be read
        def self.gsetting(key)
          out, status = Open3.capture2e('gsettings', 'get', SCHEMA, key)
          return out.strip.delete("'") if status.success?

          LOGGER.info("can't read #{SCHEMA} #{key}, using the locale's: #{out.strip}")
          nil
        rescue SystemCallError => e
          LOGGER.info("can't run gsettings, using the locale's units: #{e.message}")
          nil
        end

        # @return [Boolean] whether `LC_MEASUREMENT` says imperial: glibc's `measurement=2`
        def self.imperial_locale?
          out, status = Open3.capture2e('locale', '-k', 'LC_MEASUREMENT')
          status.success? && out.match?(/^measurement=2$/)
        rescue SystemCallError => e
          LOGGER.info("can't run locale, assuming metric: #{e.message}")
          false
        end

        private_class_method :gsetting, :imperial_locale?

        # @return [String] "°C" or "°F"
        def temperature_label = temperature == :fahrenheit ? '°F' : '°C'

        # @return [String] "km/h", "m/s", "mph", "kn" or "Bft"
        def wind_label = WIND_LABELS.fetch(wind)

        # @return [String] "mm" or "in"
        def precipitation_label = precipitation == :inch ? 'in' : 'mm'

        # @return [String] Open-Meteo's `temperature_unit`
        def open_meteo_temperature = temperature.to_s

        # @return [String] Open-Meteo's `wind_speed_unit`; Beaufort, which it lacks, comes as m/s
        def open_meteo_wind = wind == :bft ? 'ms' : wind.to_s

        # @return [String] Open-Meteo's `precipitation_unit`
        def open_meteo_precipitation = precipitation.to_s

        # @param speed [Float, nil] as Open-Meteo answered it
        # @return [Integer, nil] rounded in these units: m/s become a Beaufort force
        def wind_speed(speed)
          return nil unless speed

          wind == :bft ? beaufort(speed) : speed.round
        end

        # @param metres_per_second [Float]
        # @return [Integer] 0 to 12
        def beaufort(metres_per_second) = BEAUFORT.index { metres_per_second < _1 } || 12
      end
    end
  end
end
