# frozen_string_literal: true

module Puri
  module Core
    module Places
      # `place_search`: where a place is, or what's of one kind near a place, each hit numbered,
      # with its distance and time by car, its opening hours and website. Draws its map: the hits
      # as numbered pins, the point it searched near as a dot.
      #
      #   tool = SearchTool.new(osm:, notebook:)
      #   tool.run('query' => 'Vantaan Musiikki', 'near' => 'Jumbo Vantaa').content
      #   # => Near: [1] Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa
      #   #
      #   #    [2] Musiikki Silfverberg Oy Vantaan Musiikki (musical instrument), Peltolantie 2, 01300 Vantaa
      #   #        — 6.3 km, 9 min by car. Opening hours: Mo-Fr 10:00-17:00. …
      #
      # A name goes to Photon, then one Nominatim lookup adds the hits' hours; a category goes to
      # Nominatim, which has them; one OSRM request drives to every hit. Where OSRM fails, a hit's
      # distance is the straight line.
      #
      # Sharing: P_one_agent, through its {Notebook}, which is one conversation's.
      class SearchTool < Pikuri::Tool
        # The kinds of place a `category` search takes: Nominatim's types, the common ones.
        #
        # @return [Array<String>]
        CATEGORIES = %w[cafe restaurant fast_food bar pub ice_cream bakery supermarket convenience pharmacy hospital
                        doctors dentist fuel charging_station parking atm bank post_office library cinema toilets
                        hotel].freeze

        # @return [String]
        DESCRIPTION = <<~DESC
          Finds places on OpenStreetMap: a place by its name or address, or what's of one kind near a place.

          Usage:
          - Give `query` for a place's name or address ("Vantaan Musiikki", "Kielotie 4, Vantaa"), or `category` for a kind of place nearby ("coffee near me" is category cafe). One of the two, not both.
          - `near` is where to look: a number from an earlier result, an address, or coordinates "60.2931, 25.0307". For "near me" or "near home" pass the user's home address.
          - Each hit is numbered, like [3]. The numbers count up through the whole conversation, so pass 3 to route, or as near, to mean that place.
          - Each hit says its distance and time by car from `near`, and its opening hours and website when OpenStreetMap knows them.
          - Several hits for a name: pick the likeliest from the address, or ask the user which one they mean.
        DESC

        # @param osm [Puri::Core::Places::Osm]
        # @param notebook [Puri::Core::Places::Notebook] the conversation's
        def initialize(osm:, notebook:)
          @osm = osm
          @notebook = notebook
          super(
            name: 'place_search', description: DESCRIPTION,
            parameters: Pikuri::Tool::Parameters.build do |p|
              p.required_string :near, 'Where to look: a number from an earlier result ("3"), an address, or ' \
                                       'coordinates "60.2931, 25.0307".'
              p.optional_string :query, "A place's name or address. Leave out with `category`."
              p.optional_enum :category, 'A kind of place near `near`. Leave out with `query`.', values: CATEGORIES
            end,
            execute: ->(near:, context:, query: nil, category: nil) { search(near:, query:, category:, context:) },
            # The query and the home address leave the machine unreviewed, to a host the tool fixes;
            # what comes back is whatever anyone mapped, names included.
            trifecta_legs: Pikuri::Tool::TrifectaLegs.new(private: false, untrusted: :hard,
                                                          egress_payload_review: :unreviewed,
                                                          egress_destination: :tool_vouched),
            wants_context: true
          )
        end

        # @param arguments [Hash] the model's
        # @return [String] "cafe near Kielotie 4, Vantaa"
        def describe_call(arguments)
          args = arguments.transform_keys(&:to_s)
          Pikuri::Tool.one_line("#{args['query'] || args['category']} near #{args['near']}")
        end

        private

        # @param near [String]
        # @param query [String, nil]
        # @param category [String, nil]
        # @param context [Pikuri::Tool::ExecuteContext]
        # @return [Pikuri::Tool::Result]
        def search(near:, query:, category:, context:)
          return Pikuri::Tool::Result.error('give a query or a category, not both') if query && category
          return Pikuri::Tool::Result.error('give a query or a category') unless query || category

          cancellable = context.cancellable
          origin_number, origin = Ends.resolve(near, osm: @osm, notebook: @notebook, cancellable:)
          hits = find(query, category, origin, cancellable)
          answer(origin_number, origin, hits, query || category)
        rescue Ends::Unresolved => e
          Pikuri::Tool::Result.error("near: #{e.message}")
        rescue Http::Error => e
          Pikuri::Tool::Result.error(e.message)
        end

        # @param query [String, nil]
        # @param category [String, nil]
        # @param origin [Puri::Core::Places::Place]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array<Array(Puri::Core::Places::Place, Puri::Core::Places::Route, nil)>] each hit
        #   and the drive to it; a category's nearest by road first
        def find(query, category, origin, cancellable)
          places = if query
                     @osm.details(@osm.search(query, near: origin, cancellable:), cancellable:)
                   else
                     @osm.nearby(category, near: origin, cancellable:)
                   end
          hits = places.zip(drives(origin, places, cancellable))
          return hits unless category

          hits.sort_by { |place, drive| drive ? [0, drive.distance] : [1, origin.distance_to(place)] }
        end

        # @param origin [Puri::Core::Places::Place]
        # @param places [Array<Puri::Core::Places::Place>]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array<Puri::Core::Places::Route, nil>]
        def drives(origin, places, cancellable)
          @osm.drives(origin, places, cancellable:)
        rescue Http::Error
          []
        end

        # @param origin_number [Integer]
        # @param origin [Puri::Core::Places::Place]
        # @param hits [Array<Array(Puri::Core::Places::Place, Puri::Core::Places::Route, nil)>]
        # @param asked [String] the query or the category
        # @return [Pikuri::Tool::Result]
        def answer(origin_number, origin, hits, asked)
          head = "Near: [#{origin_number}] #{origin.label}"
          if hits.empty?
            return Pikuri::Tool::Result.new(content: "#{head}\n\nNothing found for #{asked.inspect}.",
                                            summary: 'Found nothing')
          end

          numbered = hits.map { |place, drive| [@notebook.number(place), place, drive] }
          lines = numbered.map { |number, place, drive| line(number, place, drive, origin) }
          content = "#{head}\n\n#{lines.join("\n")}\n\nCar distances are from [#{origin_number}], without traffic. " \
                    'A map of these places, numbered as above, appears under your answer.'
          @notebook.draw(content, pins: [origin.pin(nil), *numbered.map { |number, place, _| place.pin(number) }])
          Pikuri::Tool::Result.new(content:, summary: "Found #{Pikuri::Tool.pluralize(hits.size, 'place')}")
        end

        # @param number [Integer]
        # @param place [Puri::Core::Places::Place]
        # @param drive [Puri::Core::Places::Route, nil]
        # @param origin [Puri::Core::Places::Place]
        # @return [String]
        def line(number, place, drive, origin)
          far = drive ? "#{drive.words} by car" : "#{straight(origin, place)} away in a straight line"
          text = "[#{number}] #{place.label} — #{far}."
          text += " Opening hours: #{place.hours}." if place.hours
          text += " Website: #{place.website}" if place.website
          text
        end

        # @param origin [Puri::Core::Places::Place]
        # @param place [Puri::Core::Places::Place]
        # @return [String] "1.2 km"
        def straight(origin, place)
          metres = origin.distance_to(place)
          metres < 1000 ? "#{(metres / 10).round * 10} m" : "#{(metres / 1000).round(1)} km"
        end
      end
    end
  end
end
