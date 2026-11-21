# frozen_string_literal: true

module Puri
  module Core
    module Places
      # `route`: how far and how long by car from one place to another, through FOSSGIS's OSRM.
      # Each end is a number a search gave, an address, or coordinates, and the result names what
      # each turned out to be, so a wrong match shows. Draws its map: both ends and the road.
      #
      #   RouteTool.new(osm:, notebook:).run('from' => '1', 'to' => 'Peltolantie 2, Vantaa').content
      #   # => From: [1] Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa
      #   #    To: [2] Peltolantie 2, 01300 Vantaa
      #   #    By car: 6.3 km, 9 min, without traffic.
      #
      # An address is looked up near the other end, or "Prisma" could be Bolivia's.
      #
      # Sharing: P_one_agent, through its {Notebook}, which is one conversation's.
      class RouteTool < Pikuri::Tool
        # FOSSGIS's terms ask a route's display for a way to fix the map.
        #
        # @return [String] Pango markup
        NOTE = 'Route by <a href="https://routing.openstreetmap.de/">FOSSGIS OSRM</a> · ' \
               '<a href="https://www.openstreetmap.org/fixthemap">Fix the map</a>'

        # @return [String]
        DESCRIPTION = <<~DESC
          The distance and the time by car from one place to another, without traffic.

          Usage:
          - Each end is a number from place_search's results ("3"), an address ("Kielotie 4, Vantaa"), or coordinates ("60.2931, 25.0307"). Prefer the number once the user has said which place they mean.
          - "From home" is the user's home address; pass the address itself.
          - The result names what each end turned out to be. When that isn't the place the user meant, say so, or search for it.
        DESC

        # @param osm [Puri::Core::Places::Osm]
        # @param notebook [Puri::Core::Places::Notebook] the conversation's
        def initialize(osm:, notebook:)
          @osm = osm
          @notebook = notebook
          super(
            name: 'route', description: DESCRIPTION,
            parameters: Pikuri::Tool::Parameters.build do |p|
              p.required_string :from, 'Where the drive starts: a number from place_search, an address, or ' \
                                       'coordinates.'
              p.required_string :to, 'Where it ends, the same way.'
            end,
            execute: ->(from:, to:, context:) { route(from, to, context.cancellable) },
            # The ends leave the machine unreviewed, to a host the tool fixes; the names it echoes
            # are whatever anyone mapped.
            trifecta_legs: Pikuri::Tool::TrifectaLegs.new(private: false, untrusted: :hard,
                                                          egress_payload_review: :unreviewed,
                                                          egress_destination: :tool_vouched),
            wants_context: true
          )
        end

        # @param arguments [Hash] the model's
        # @return [String] "1 → Peltolantie 2, Vantaa"
        def describe_call(arguments)
          args = arguments.transform_keys(&:to_s)
          Pikuri::Tool.one_line("#{args['from']} → #{args['to']}")
        end

        private

        # @param from [String]
        # @param to [String]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Pikuri::Tool::Result]
        def route(from, to, cancellable)
          (from_number, start), (to_number, finish) = ends(from, to, cancellable)
          drive = @osm.route(start, finish, cancellable:)
          content = "From: [#{from_number}] #{start.label}\nTo: [#{to_number}] #{finish.label}\n" \
                    "By car: #{drive.words}, without traffic.\n\nA map of the route appears under your answer."
          @notebook.draw(content, pins: [start.pin(from_number), finish.pin(to_number)], line: drive.line, note: NOTE)
          Pikuri::Tool::Result.new(content:, summary: "#{drive.words} by car")
        rescue Ends::Unresolved => e
          Pikuri::Tool::Result.error(e.message)
        rescue Http::Error => e
          Pikuri::Tool::Result.error(e.message)
        end

        # Resolves a number or coordinates first, so an address at the other end has a place to be
        # looked up near.
        #
        # @param from [String]
        # @param to [String]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array(Array(Integer, Puri::Core::Places::Place), Array(Integer, Puri::Core::Places::Place))]
        # @raise [Puri::Core::Places::Ends::Unresolved]
        def ends(from, to, cancellable)
          resolve = lambda do |side, text, near|
            Ends.resolve(text, osm: @osm, notebook: @notebook, near:, cancellable:)
          rescue Ends::Unresolved => e
            raise Ends::Unresolved, "#{side}: #{e.message}"
          end
          if fixed?(to) && !fixed?(from)
            finish = resolve.call('to', to, nil)
            [resolve.call('from', from, finish.last), finish]
          else
            start = resolve.call('from', from, nil)
            [start, resolve.call('to', to, start.last)]
          end
        end

        # @param text [String]
        # @return [Boolean] whether it is a number or coordinates, which need no place to be near
        def fixed?(text) = text.strip.match?(Ends::HANDLE) || text.strip.match?(Ends::COORDINATES)
      end
    end
  end
end
