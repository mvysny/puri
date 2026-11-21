# frozen_string_literal: true

require 'gtk_helper'
require 'net/http'

RSpec.describe 'Puri::Desktop::PlaceMap' do
  p = Puri::Protocol

  let(:opened) { [] }
  let(:pins) do
    [p::Pin.new(label: nil, name: 'Peltolantie 2', lat: 60.2931, lon: 25.0307, url: 'https://www.openstreetmap.org/?mlat=60.2931'),
     p::Pin.new(label: '1', name: 'Picnic (cafe)', lat: 60.2909, lon: 25.0332, url: 'https://www.openstreetmap.org/node/1'),
     p::Pin.new(label: '2', name: 'Cafe Silkki (cafe)', lat: 60.2892, lon: 25.0370, url: 'https://www.openstreetmap.org/node/2')]
  end
  let(:block) do
    p::Map.new(id: 'b4', tiles: Puri::Dummy::TileServer.url, license: '© OpenStreetMap contributors', pins:,
               line: [], note: nil)
  end
  let(:place_map) { Puri::Desktop::PlaceMap.new(block) { |url| opened << url } }

  it 'shows a numbered pin per place and a dot where the search started, each opening its place' do
    assert_equal(['', '1', '2'], place_map.pins.map { _1.label.to_s })
    assert_equal 'Picnic (cafe)', place_map.pins[1].tooltip_text
    place_map.pins[2].clicked
    assert_equal ['https://www.openstreetmap.org/node/2'], opened
  end

  it 'fits the view to the pins' do
    viewport = place_map.map.viewport
    assert_in_delta 60.2912, viewport.latitude, 0.001
    assert_in_delta 25.0338, viewport.longitude, 0.001
    assert_operator viewport.zoom_level, :>, 14
  end

  it 'attributes the tiles on the map, and shows a note only when the block has one' do
    assert_equal '© OpenStreetMap contributors', place_map.map.map_source.license
    refute place_map.note.visible?
    place_map.block = block.with(note: 'Route by <a href="https://routing.openstreetmap.de/">FOSSGIS OSRM</a>')
    assert place_map.note.visible?
    assert_equal 'Route by FOSSGIS OSRM', place_map.note.text
  end

  it 'leaves the wheel to the transcript, which scrolls' do
    controllers = place_map.map.map.observe_controllers
    scrolls = Array.new(controllers.n_items) { controllers.get_item(_1) }.grep(Gtk::EventControllerScroll)
    assert_equal([:none], scrolls.map { _1.propagation_phase.nick.to_sym })
  end

  it 'gets its tiles from the block’s server, the dummy’s on this machine' do
    tile = Net::HTTP.get_response(URI(Puri::Dummy::TileServer.url.sub('{z}/{x}/{y}', '13/4663/2363')))
    assert_equal ['200', 'image/png'], [tile.code, tile['Content-Type']]
  end

  describe '.fit' do
    it 'centres the points and zooms until they fill the view, less a margin' do
      lat, lon, zoom = Puri::Desktop::PlaceMap.fit([[60.2916, 24.9657], [60.2931, 25.0307]], width: 600, height: 280)
      assert_in_delta 60.29235, lat, 0.0001
      assert_in_delta 24.9982, lon, 0.0001
      # 0.0650° of longitude is 0.0001806 of the world: 504 px of 600, less two margins, at zoom 13.4.
      assert_in_delta 13.41, zoom, 0.01
    end

    it 'zooms to the street for a single place' do
      assert_equal([60.2931, 25.0307, 16.0], Puri::Desktop::PlaceMap.fit([[60.2931, 25.0307]], width: 600, height: 280)
                                                                    .map { _1.round(4) })
    end
  end
end
