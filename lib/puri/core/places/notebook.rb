# frozen_string_literal: true

require 'digest'

module Puri
  module Core
    module Places
      # What one conversation's place tools found: a number for each place, the handle the model
      # passes back, and the map each call drew. Saved with the conversation, so after a restart a
      # number still means its place and an old answer redraws its map.
      #
      #   notebook = Notebook.new(tiles: config.maps.tiles)
      #   notebook.number(place)                  # => 3: numbers count up through the conversation
      #   notebook[3]                             # => that place
      #   notebook.draw(result.content, pins:)    # the call's map, under the text the model got
      #   notebook.map_for(event.content)         # => that Protocol::Map; nil for any other tool's
      #   store.save(…, extra: { 'places' => notebook.to_h })
      #   Notebook.new(tiles:, saved: entry.extra['places'])
      #
      # A place found twice keeps its first number. Without tiles — no `[maps]` table — it still
      # keeps what it saved, but draws no map.
      #
      # Thread-safe.
      class Notebook
        # A map as drawn, before it knows its tiles.
        #
        # @!attribute [r] pins
        #   @return [Array<Puri::Protocol::Pin>]
        # @!attribute [r] line
        #   @return [Array<Array<Float>>]
        # @!attribute [r] note
        #   @return [String, nil] Pango markup
        class Drawing < Data.define(:pins, :line, :note); end

        # @return [Logger]
        LOGGER = Pikuri.logger_for('Places::Notebook')

        # @param tiles [String, nil] the `[maps]` tile URL template; nil draws no map
        # @param saved [Object] what {#to_h} saved, as `meta.json` read it back; nil for a new
        #   conversation. One that doesn't read is logged and dropped.
        def initialize(tiles:, saved: nil)
          @tiles = tiles
          @lock = Mutex.new
          @places = {}
          @drawings = {}
          load(saved) if saved
        end

        # @param place [Puri::Core::Places::Place]
        # @return [Integer] its number, the one it had if it was found before
        def number(place)
          @lock.synchronize do
            @places.find { |_, known| same?(known, place) }&.first ||
              (@places.keys.max.to_i + 1).tap { @places[_1] = place }
          end
        end

        # @param number [Integer]
        # @return [Puri::Core::Places::Place, nil]
        def [](number) = @lock.synchronize { @places[number] }

        # Keeps a call's map under the text its result gave the model.
        #
        # @param content [String] the result's `content`
        # @param pins [Array<Puri::Protocol::Pin>]
        # @param line [Array<Array<Float>>]
        # @param note [String, nil] Pango markup
        # @return [void]
        def draw(content, pins:, line: [], note: nil)
          @lock.synchronize { @drawings[key(content)] = Drawing.new(pins:, line:, note:) }
        end

        # @param content [String] a tool result's `content`, live or saved
        # @return [Puri::Protocol::Map, nil] the map that call drew, with no id; nil for a call that
        #   drew none, or with no tiles
        def map_for(content)
          return nil unless @tiles

          drawing = @lock.synchronize { @drawings[key(content)] } or return nil
          Protocol::Map.new(id: nil, tiles: @tiles, license: LICENSE, pins: drawing.pins, line: drawing.line,
                            note: drawing.note)
        end

        # @return [Boolean] whether it holds nothing to save
        def empty? = @lock.synchronize { @places.empty? && @drawings.empty? }

        # @return [Hash{String => Object}] JSON-able, for `meta.json`
        def to_h
          @lock.synchronize do
            { 'places' => @places.map { |number, place| { 'number' => number, **stringify(place.to_h) } },
              'maps' => @drawings.transform_values do |drawing|
                { 'pins' => drawing.pins.map { stringify(_1.to_h) }, 'line' => drawing.line, 'note' => drawing.note }
              end }
          end
        end

        private

        # @param saved [Object]
        # @return [void]
        def load(saved)
          saved.fetch('places').each do |entry|
            fields = entry.transform_keys(&:to_sym)
            @places[Integer(fields.delete(:number))] = Place.new(**fields)
          end
          saved.fetch('maps').each do |key, drawing|
            pins = drawing.fetch('pins').map { Protocol::Pin.new(**_1.transform_keys(&:to_sym)) }
            @drawings[key] = Drawing.new(pins:, line: drawing.fetch('line'), note: drawing['note'])
          end
        rescue StandardError => e
          LOGGER.warn("can't read the saved places, starting afresh: #{e.class}: #{e.message}")
          @places.clear
          @drawings.clear
        end

        # @param known [Puri::Core::Places::Place]
        # @param place [Puri::Core::Places::Place]
        # @return [Boolean]
        def same?(known, place)
          return known.osm == place.osm if known.osm || place.osm

          known.lat == place.lat && known.lon == place.lon
        end

        # @param content [String]
        # @return [String]
        def key(content) = Digest::SHA256.hexdigest(content)[0, 24]

        # @param fields [Hash{Symbol => Object}]
        # @return [Hash{String => Object}]
        def stringify(fields) = fields.transform_keys(&:to_s)
      end
    end
  end
end
