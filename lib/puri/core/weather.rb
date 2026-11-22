# frozen_string_literal: true

module Puri
  module Core
    # "What's the weather like in Lisbon?": the `weather` tool, a forecast from Open-Meteo at a
    # place OpenStreetMap finds, in GNOME's units (`D_weather`).
    #
    #   open_meteo = Weather::OpenMeteo.new(http:)   # one per process, on the place tools' Http
    #   configurator.add_tool(Weather::ForecastTool.new(open_meteo:, osm:, notebook:, units: Weather::Units.gnome,
    #                                                   today: Date.today))
    #
    # {OpenMeteo} asks for the whole forecast and reads it into a {Forecast}; {ForecastTool}
    # finds the place through the place tools' `Places::Ends`, cuts the days asked for out of it
    # and words them.
    module Weather
      # What the tool line says the forecast came from, linked to {CREDIT_URL}: Open-Meteo's
      # licence wants a link beside wherever its data shows.
      #
      # @return [String]
      CREDIT = 'Open-Meteo'

      # @return [String]
      CREDIT_URL = 'https://open-meteo.com/'
    end
  end
end
