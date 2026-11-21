# frozen_string_literal: true

module Puri
  module Core
    # Where a place is, what's near it, how far by car: the `place_search` and `route` tools, on
    # OpenStreetMap's public services, and the map under the answer (`D_places`).
    #
    #   osm = Places::Osm.new                                  # one per process: it paces requests
    #   notebook = Places::Notebook.new(tiles: config.maps.tiles)   # one per conversation
    #   configurator.add_tools([Places::SearchTool.new(osm:, notebook:), Places::RouteTool.new(osm:, notebook:)])
    #   notebook.map_for(tool_result.content)                  # => the Protocol::Map that call drew
    #
    # Every place a tool finds gets a number in the {Notebook}, the handle the model passes back.
    # Each call also draws its map there, keyed by the text the model got, so {TurnListener} and
    # {Replay} find a call's map from its result alone.
    module Places
      # The tiles' attribution, which OSM's terms keep visible on the map.
      #
      # @return [String]
      LICENSE = '© OpenStreetMap contributors'
    end
  end
end
