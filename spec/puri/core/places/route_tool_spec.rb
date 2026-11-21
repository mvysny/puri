# frozen_string_literal: true

RSpec.describe Puri::Core::Places::RouteTool do
  pl = Puri::Core::Places

  let(:fake) { FakeOsm.new }
  let(:notebook) { pl::Notebook.new(tiles: 'https://tile.example/{z}/{x}/{y}.png') }
  let(:tool) { described_class.new(osm: fake.places, notebook:) }
  let(:jumbo) do
    pl::Place.new(name: 'Jumbo', category: 'mall', address: 'Vantaanportinkatu 3, 01510 Vantaa', lat: 60.2915942,
                  lon: 24.9656777, osm: 'way/25373590')
  end

  before do
    notebook.number(jumbo)
    fake.answer('/api/', 'photon-vantaan-musiikki.json')
    fake.answer('/route/', 'osrm-route.json')
  end

  after { fake.close }

  it 'names both ends, numbered, and the drive' do
    result = tool.run('from' => '1', 'to' => 'Vantaan Musiikki')
    assert_equal <<~TEXT.chomp, result.content
      From: [1] Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa
      To: [2] Musiikki Silfverberg Oy Vantaan Musiikki (musical instrument), Peltolantie 2, 01300 Vantaa
      By car: 6.3 km, 9 min, without traffic.

      A map of the route appears under your answer.
    TEXT
    assert_equal '6.3 km, 9 min by car', result.summary
  end

  it 'looks an address up near the other end, whichever side the number is on' do
    tool.run('from' => 'Vantaan Musiikki', 'to' => '[1]')
    assert_equal %w[60.2915942 24.9656777], fake.requests.find { _1.path == '/api/' }.query.values_at('lat', 'lon')
  end

  it 'draws both ends and the road, with the router’s note' do
    result = tool.run('from' => '1', 'to' => 'Vantaan Musiikki')
    map = notebook.map_for(result.content)
    assert_equal %w[1 2], map.pins.map(&:label)
    assert_equal 29, map.line.size
    assert_includes map.note, 'Fix the map'
  end

  it 'says which end it couldn’t place' do
    assert_equal 'Error: to: 91.0, 25.0 is no point on Earth: latitude first, then longitude',
                 tool.run('from' => '1', 'to' => '91, 25').content
    assert_match(/\AError: from: no place is numbered 7/, tool.run('from' => '7', 'to' => '1').content)
  end

  it 'shows the ends it was given' do
    assert_equal '1 → Vantaan Musiikki', tool.describe_call('from' => '1', 'to' => 'Vantaan Musiikki')
  end
end
