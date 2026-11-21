# frozen_string_literal: true

module Puri
  module Protocol
    # One place on a {Map}: a pin showing the place's number, or a dot for the point a search
    # started from.
    #
    #   Pin.new(label: '3', name: 'Vantaan Musiikki (musical instrument), Peltolantie 2, 01300 Vantaa',
    #           lat: 60.2931102, lon: 25.0307498, url: 'https://www.openstreetmap.org/node/9444805490')
    #
    # @!attribute [r] label
    #   @return [String, nil] what the pin shows, the place's number; nil draws a dot
    # @!attribute [r] name
    #   @return [String] what the place is, plain text, for its tooltip
    # @!attribute [r] lat
    #   @return [Float]
    # @!attribute [r] lon
    #   @return [Float]
    # @!attribute [r] url
    #   @return [String] the place on openstreetmap.org, which a click opens
    class Pin < Data.define(:label, :name, :lat, :lon, :url); end
  end
end
