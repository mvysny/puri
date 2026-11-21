# frozen_string_literal: true

require 'json'

RSpec.describe Puri::Core::Places::Notebook do
  pl = Puri::Core::Places
  tiles = 'https://tile.example/{z}/{x}/{y}.png'

  let(:notebook) { described_class.new(tiles:) }
  let(:shop) { pl::Place.new(name: 'Vantaan Musiikki', lat: 60.2931102, lon: 25.0307498, osm: 'node/9444805490') }
  let(:point) { pl::Place.new(name: nil, address: 'Peltolantie 2, 01300 Vantaa', lat: 60.2931, lon: 25.0307) }
  let(:pins) { [shop.pin(1), point.pin(nil)] }

  it 'numbers places up through the conversation, and a place found again keeps its number' do
    assert_equal [1, 2, 1], [notebook.number(shop), notebook.number(point), notebook.number(shop.with(hours: 'Mo'))]
    assert_equal shop, notebook[1]
    assert_nil notebook[3]
  end

  it 'finds a call’s map by the text its result gave the model' do
    notebook.draw('Near: [1] …', pins:, line: [[60.29, 24.96], [60.29, 25.03]], note: 'Route by …')
    map = notebook.map_for('Near: [1] …')
    assert_equal Puri::Protocol::Map.new(id: nil, tiles:, license: '© OpenStreetMap contributors', pins:,
                                         line: [[60.29, 24.96], [60.29, 25.03]], note: 'Route by …'), map
    assert_nil notebook.map_for('1. Avocado …')
  end

  it 'draws no map without tiles' do
    bare = described_class.new(tiles: nil)
    bare.draw('Near: [1] …', pins:)
    assert_nil bare.map_for('Near: [1] …')
  end

  it 'reads back what it saved through meta.json, so numbers and maps outlive a restart' do
    notebook.number(shop)
    notebook.number(point)
    notebook.draw('Near: [1] …', pins:, line: [[60.29, 24.96]])
    saved = JSON.parse(JSON.generate(notebook.to_h))
    restored = described_class.new(tiles:, saved:)
    assert_equal [shop, point], [restored[1], restored[2]]
    assert_equal notebook.map_for('Near: [1] …'), restored.map_for('Near: [1] …')
    assert_equal 3, restored.number(pl::Place.new(name: 'Jumbo', lat: 60.29, lon: 24.96))
  end

  it 'starts afresh from saved places it can’t read' do
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    restored = described_class.new(tiles:, saved: { 'places' => [{ 'number' => 'x' }], 'maps' => {} })
    assert restored.empty?
    assert_includes Pikuri.log_io.string, "can't read the saved places"
  ensure
    Pikuri.log_io = log
  end
end
