# frozen_string_literal: true

module Puri
  module Core
    module Places
      # A place a service found, or a point given as coordinates.
      #
      #   place.label   # => "Vantaan Musiikki (musical instrument), Peltolantie 2, 01300 Vantaa"
      #   place.url     # => "https://www.openstreetmap.org/node/9444805490"
      #   place.pin(3)  # => Protocol::Pin(label: "3", …), for the map
      #
      # @!attribute [r] name
      #   @return [String, nil] nil for an address or a bare point
      # @!attribute [r] category
      #   @return [String, nil] OSM's type of it, readable: "musical instrument", "cafe"
      # @!attribute [r] address
      #   @return [String] street, number, postcode and town, as far as known; "" for none
      # @!attribute [r] lat
      #   @return [Float]
      # @!attribute [r] lon
      #   @return [Float]
      # @!attribute [r] osm
      #   @return [String, nil] the OSM object, "node/9444805490"; nil for a bare point
      # @!attribute [r] hours
      #   @return [String, nil] its `opening_hours`, OSM's syntax verbatim
      # @!attribute [r] website
      #   @return [String, nil]
      class Place < Data.define(:name, :category, :address, :lat, :lon, :osm, :hours, :website)
        # @param name [String, nil]
        # @param lat [Float]
        # @param lon [Float]
        # @param category [String, nil]
        # @param address [String]
        # @param osm [String, nil]
        # @param hours [String, nil]
        # @param website [String, nil]
        def initialize(name:, lat:, lon:, category: nil, address: '', osm: nil, hours: nil, website: nil)
          super(name: blank(name), category: blank(category), address: address.to_s, lat: lat.to_f, lon: lon.to_f,
                osm:, hours: blank(hours), website: blank(website))
        end

        # @return [String] "name (category), address", as much as is known; the coordinates for a
        #   bare point
        def label
          named = name && (category ? "#{name} (#{category})" : name)
          text = [named, (address unless address.empty?)].compact.join(', ')
          text.empty? ? coordinates : text
        end

        # @return [String] "60.29311, 25.03075"
        def coordinates = "#{lat.round(5)}, #{lon.round(5)}"

        # @return [String] the OSM object's page, or a marker on the point; GNOME Maps opens both
        def url
          return "https://www.openstreetmap.org/#{osm}" if osm

          "https://www.openstreetmap.org/?mlat=#{lat.round(6)}&mlon=#{lon.round(6)}&zoom=17"
        end

        # @param number [Integer, nil] what the pin shows; nil draws a dot
        # @return [Puri::Protocol::Pin]
        def pin(number) = Protocol::Pin.new(label: number&.to_s, name: label, lat:, lon:, url:)

        # @param other [Puri::Core::Places::Place]
        # @return [Float] metres in a straight line, along the Earth's surface
        def distance_to(other)
          rad = Math::PI / 180
          dlat = (other.lat - lat) * rad
          dlon = (other.lon - lon) * rad
          a = (Math.sin(dlat / 2)**2) + (Math.cos(lat * rad) * Math.cos(other.lat * rad) * (Math.sin(dlon / 2)**2))
          2 * 6_371_000 * Math.asin(Math.sqrt(a))
        end

        private

        # @param text [String, nil]
        # @return [String, nil] nil for blank
        def blank(text) = text.to_s.strip.empty? ? nil : text.to_s.strip
      end
    end
  end
end
