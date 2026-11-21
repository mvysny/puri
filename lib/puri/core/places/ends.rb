# frozen_string_literal: true

module Puri
  module Core
    module Places
      # Turns what the model wrote for a route's end, or for where a search is near, into a place:
      #
      #   Ends.resolve('3', osm:, notebook:)                        # place [3] a search found
      #   Ends.resolve('60.2931, 25.0307', osm:, notebook:)         # the address at that point
      #   Ends.resolve('Kielotie 4, Vantaa', osm:, notebook:, near:) # Photon's likeliest, near `near`
      #
      # Each comes back numbered in the notebook, so the result can name it "[5] …" and the model
      # can pass 5 next time.
      module Ends
        # The model's text names nothing: a number no search gave, coordinates off the globe, an
        # address nothing matches. The message is for the model, to correct itself.
        class Unresolved < StandardError; end

        # @return [Regexp] "3" or "[3]"
        HANDLE = /\A\[?(\d{1,5})\]?\z/
        # @return [Regexp] "60.2931,25.0307", spaces allowed
        COORDINATES = /\A(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\z/

        module_function

        # @param text [String]
        # @param osm [Puri::Core::Places::Osm]
        # @param notebook [Puri::Core::Places::Notebook]
        # @param near [Puri::Core::Places::Place, nil] what an address is looked up near
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Array(Integer, Puri::Core::Places::Place)] its number, and the place
        # @raise [Unresolved]
        # @raise [Puri::Core::Places::Http::Error]
        def resolve(text, osm:, notebook:, near: nil, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          text = text.to_s.strip
          place =
            case text
            when '' then raise Unresolved, 'it is empty: pass a number from place_search, an address or coordinates'
            when HANDLE then handle(Integer(::Regexp.last_match(1), 10), notebook)
            when COORDINATES then point(Float(::Regexp.last_match(1)), Float(::Regexp.last_match(2)), osm, cancellable)
            else address(text, osm, near, cancellable)
            end
          [notebook.number(place), place]
        end

        # @param number [Integer]
        # @param notebook [Puri::Core::Places::Notebook]
        # @return [Puri::Core::Places::Place]
        # @raise [Unresolved]
        def handle(number, notebook)
          notebook[number] or
            raise Unresolved, "no place is numbered #{number} in this conversation: pass a number place_search " \
                              'gave, or an address'
        end

        # @param lat [Float]
        # @param lon [Float]
        # @param osm [Puri::Core::Places::Osm]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Puri::Core::Places::Place]
        # @raise [Unresolved]
        def point(lat, lon, osm, cancellable)
          raise Unresolved, "#{lat}, #{lon} is no point on Earth: latitude first, then longitude" unless
            lat.between?(-90, 90) && lon.between?(-180, 180)

          osm.reverse(lat, lon, cancellable:)
        end

        # @param text [String]
        # @param osm [Puri::Core::Places::Osm]
        # @param near [Puri::Core::Places::Place, nil]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Puri::Core::Places::Place]
        # @raise [Unresolved]
        def address(text, osm, near, cancellable)
          osm.search(text, near:, limit: 1, cancellable:).first or
            raise Unresolved, "nothing matches #{text.inspect}: add the town, or spell it as on a map"
        end

        private_class_method :handle, :point, :address
      end
    end
  end
end
