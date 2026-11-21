# frozen_string_literal: true

require 'uri'

module Puri
  module Core
    module Places
      # OpenStreetMap's public services, the ones GNOME Maps asks too: Photon finds a place by its
      # name, Nominatim what's nearby by its kind, its opening hours, and the address at a point,
      # and FOSSGIS's OSRM drives between points.
      #
      #   osm = Osm.new
      #   jumbo = osm.search('Jumbo Vantaa').first
      #   shop = osm.search('Vantaan Musiikki', near: jumbo).first
      #   osm.route(jumbo, shop)            # => Route(distance: 6315.1, duration: 530.4, line: […])
      #   cafes = osm.nearby('cafe', near: shop)
      #   osm.drives(shop, cafes)           # => [Route(distance: 939.4, …), …], one per café
      #
      # Every call may raise {Http::Error}, and takes the turn's `cancellable`, which a wait for the
      # host's turn honours.
      #
      # Thread-safe.
      class Osm
        # @return [String]
        PHOTON = 'https://photon.komoot.io'
        # @return [String]
        NOMINATIM = 'https://nominatim.openstreetmap.org'
        # @return [String] the car profile; FOSSGIS runs bike and foot beside it
        OSRM = 'https://routing.openstreetmap.de/routed-car'

        # Photon's and Nominatim's letters for an OSM object's type.
        #
        # @return [Hash{String => String}]
        TYPES = { 'N' => 'node', 'W' => 'way', 'R' => 'relation' }.freeze

        # @param http [Puri::Core::Places::Http] shared, so its pacing covers every caller
        # @param photon [String] a spec points these at its own server
        # @param nominatim [String]
        # @param osrm [String]
        def initialize(http: Http.new, photon: PHOTON, nominatim: NOMINATIM, osrm: OSRM)
          @http = http
          @photon = photon
          @nominatim = nominatim
          @osrm = osrm
        end

        # Places matching `query`, likeliest first: a name, an address, or both. Without `near`,
        # "Prisma" finds Bolivia's.
        #
        # @param query [String]
        # @param near [Puri::Core::Places::Place, nil] what the likeliest is near
        # @param limit [Integer]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array<Puri::Core::Places::Place>]
        # @raise [Puri::Core::Places::Http::Error]
        def search(query, near: nil, limit: 5, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          params = { q: query, limit: }
          params.merge!(lat: near.lat, lon: near.lon) if near
          get("#{@photon}/api/", params, cancellable).fetch('features', []).map { photon_place(_1) }
        end

        # Places of one kind within about `radius` metres of `near`, in no order, with their opening
        # hours and websites.
        #
        # @param kind [String] OSM's type: "cafe", "pharmacy", "supermarket"…
        # @param near [Puri::Core::Places::Place]
        # @param radius [Integer] metres, each way: a box, not a circle
        # @param limit [Integer]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array<Puri::Core::Places::Place>]
        # @raise [Puri::Core::Places::Http::Error]
        def nearby(kind, near:, radius: 1500, limit: 10, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          params = { amenity: kind, viewbox: viewbox(near, radius), bounded: 1, format: 'jsonv2', addressdetails: 1,
                     extratags: 1, limit: }
          get("#{@nominatim}/search", params, cancellable).map { nominatim_place(_1) }
        end

        # `places` with their opening hours and websites, in one Nominatim lookup. A bare point, or
        # a place Nominatim doesn't return, comes back as it was.
        #
        # @param places [Array<Puri::Core::Places::Place>]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array<Puri::Core::Places::Place>] in the same order
        # @raise [Puri::Core::Places::Http::Error]
        def details(places, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          ids = places.filter_map(&:osm).uniq.first(50).map { |osm| osm[0].upcase + osm[%r{/(\d+)\z}, 1] }
          return places if ids.empty?

          found = get("#{@nominatim}/lookup", { osm_ids: ids.join(','), format: 'jsonv2', extratags: 1 }, cancellable)
          tags = found.to_h { ["#{_1['osm_type']}/#{_1['osm_id']}", _1['extratags'] || {}] }
          places.map { |place| (extra = tags[place.osm]) ? detailed(place, extra) : place }
        end

        # The address at a point, for coordinates the user gave. The point stays where it was given,
        # nameless: a shop at the address would be a guess.
        #
        # @param lat [Float]
        # @param lon [Float]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Puri::Core::Places::Place] with no address where Nominatim knows none
        # @raise [Puri::Core::Places::Http::Error]
        def reverse(lat, lon, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          found = get("#{@nominatim}/reverse", { lat:, lon:, format: 'jsonv2', addressdetails: 1 }, cancellable)
          Place.new(name: nil, lat:, lon:, address: address(found['address'] || {}))
        end

        # Driving from one place to another.
        #
        # @param from [Puri::Core::Places::Place]
        # @param to [Puri::Core::Places::Place]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Puri::Core::Places::Route]
        # @raise [Puri::Core::Places::Http::Error] also when no road joins them
        def route(from, to, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          found = get("#{@osrm}/route/v1/driving/#{points(from, to)}",
                      { overview: 'simplified', geometries: 'geojson' }, cancellable)
          route = found['routes']&.first or raise Http::Error, "OSRM found no route: #{found['code']}"
          Route.new(distance: route['distance'].to_f, duration: route['duration'].to_f,
                    line: route['geometry']['coordinates'].map { |lon, lat| [lat.to_f, lon.to_f] })
        end

        # Driving from one place to each of several, in one request.
        #
        # @param from [Puri::Core::Places::Place]
        # @param places [Array<Puri::Core::Places::Place>]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array<Puri::Core::Places::Route, nil>] one per place, nil where no road leads; their
        #   lines empty
        # @raise [Puri::Core::Places::Http::Error]
        def drives(from, places, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          return [] if places.empty?

          found = get("#{@osrm}/table/v1/driving/#{points(from, *places)}",
                      { sources: 0, annotations: 'distance,duration' }, cancellable)
          distances = found.dig('distances', 0) or raise Http::Error, "OSRM found no distances: #{found['code']}"
          distances.drop(1).zip(found.dig('durations', 0).drop(1)).map do |distance, duration|
            Route.new(distance: distance.to_f, duration: duration.to_f, line: []) if distance && duration
          end
        end

        private

        # @param base [String] up to the query
        # @param params [Hash{Symbol => Object}]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Hash{String => Object}, Array<Object>]
        def get(base, params, cancellable) = @http.get_json("#{base}?#{URI.encode_www_form(params)}", cancellable:)

        # @param places [Array<Puri::Core::Places::Place>]
        # @return [String] OSRM's "lon,lat;lon,lat"
        def points(*places) = places.map { "#{_1.lon.round(6)},#{_1.lat.round(6)}" }.join(';')

        # @param near [Puri::Core::Places::Place]
        # @param radius [Integer] metres
        # @return [String] Nominatim's "left,top,right,bottom"
        def viewbox(near, radius)
          dlat = radius / 111_320.0
          dlon = radius / (111_320.0 * Math.cos(near.lat * Math::PI / 180))
          [near.lon - dlon, near.lat + dlat, near.lon + dlon, near.lat - dlat].map { _1.round(5) }.join(',')
        end

        # @param feature [Hash{String => Object}] one of Photon's GeoJSON features
        # @return [Puri::Core::Places::Place]
        def photon_place(feature)
          props = feature['properties']
          lon, lat = feature.dig('geometry', 'coordinates')
          street = [props['street'], props['housenumber']].compact.join(' ')
          town = [props['postcode'], props['city'] || props['locality'] || props['county']].compact.join(' ')
          name = props['name']
          Place.new(name:, category: (readable(props['osm_value']) if name), lat:, lon:,
                    address: [street, town].reject(&:empty?).join(', '),
                    osm: (type = TYPES[props['osm_type']]) && "#{type}/#{props['osm_id']}")
        end

        # @param found [Hash{String => Object}] one of Nominatim's `jsonv2` results
        # @return [Puri::Core::Places::Place]
        def nominatim_place(found)
          detailed(Place.new(name: found['name'], category: readable(found['type']), lat: found['lat'],
                             lon: found['lon'], address: address(found['address'] || {}),
                             osm: "#{found['osm_type']}/#{found['osm_id']}"),
                   found['extratags'] || {})
        end

        # @param place [Puri::Core::Places::Place]
        # @param tags [Hash{String => Object}] Nominatim's `extratags`
        # @return [Puri::Core::Places::Place]
        def detailed(place, tags)
          place.with(hours: tags['opening_hours'] || place.hours,
                     website: tags['website'] || tags['contact:website'] || place.website)
        end

        # @param parts [Hash{String => Object}] Nominatim's `address`
        # @return [String] "Peltolantie 2, 01300 Vantaa"
        def address(parts)
          street = [parts['road'] || parts['pedestrian'] || parts['square'], parts['house_number']].compact.join(' ')
          town = [parts['postcode'],
                  parts['city'] || parts['town'] || parts['village'] || parts['municipality']].compact.join(' ')
          [street, town].reject(&:empty?).join(', ')
        end

        # @param value [String, nil] an OSM value, "musical_instrument"
        # @return [String, nil] "musical instrument"; nil for OSM's "yes", which says nothing
        def readable(value)
          value.to_s.tr('_', ' ') unless value.to_s.empty? || value == 'yes'
        end
      end
    end
  end
end
