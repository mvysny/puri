# frozen_string_literal: true

module Puri
  module Protocol
    # Transcript block: a map under a turn's answer, of what its last place tool found — the
    # places, or a route. Core decides what is on it and which tiles draw it; Desktop fits the
    # view to the pins and the line.
    #
    #   Map.new(id: 'b5', tiles: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    #           license: '© OpenStreetMap contributors',
    #           pins: [Pin.new(label: '1', name: 'Jumbo (mall)', lat: 60.2916, lon: 24.9657, url: '…'), …],
    #           line: [[60.291592, 24.966851], [60.292234, 24.96675], …],
    #           note: 'Route by <a href="https://routing.openstreetmap.de/">FOSSGIS</a> · …')
    #
    # @!attribute [r] id
    #   @return [String] unique within its conversation
    # @!attribute [r] tiles
    #   @return [String] the tile server's URL template, with `{z}`, `{x}` and `{y}` in it
    # @!attribute [r] license
    #   @return [String] the tiles' attribution, plain text, which stays visible on the map
    # @!attribute [r] pins
    #   @return [Array<Puri::Protocol::Pin>]
    # @!attribute [r] line
    #   @return [Array<Array<Float>>] a route's `[lat, lon]` points, in order; empty for none
    # @!attribute [r] note
    #   @return [String, nil] Pango markup under the map, its links clickable
    class Map < Data.define(:id, :tiles, :license, :pins, :line, :note)
      include Block
    end
  end
end
