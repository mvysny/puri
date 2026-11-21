# frozen_string_literal: true

require 'json'

RSpec.describe Puri::Core::Places::SearchTool do
  pl = Puri::Core::Places

  let(:fake) { FakeOsm.new }
  let(:notebook) { pl::Notebook.new(tiles: 'https://tile.example/{z}/{x}/{y}.png') }
  let(:tool) { described_class.new(osm: fake.places, notebook:) }

  after { fake.close }

  # @param distances [Array<Float, nil>] metres to each hit, nil for no road
  # @return [String] an OSRM table answer, a minute per kilometre
  def table(distances)
    JSON.generate(code: 'Ok', distances: [[0, *distances]], durations: [[0, *distances.map { _1 && (_1 * 0.06) }]])
  end

  describe 'by name' do
    before do
      fake.answer('/api/', 'photon-jumbo.json', q: 'Jumbo Vantaa')
      fake.answer('/api/', 'photon-vantaan-musiikki.json', q: 'Vantaan Musiikki')
      fake.answer('/lookup', 'nominatim-lookup.json')
      fake.answer('/table/', body: table([6315.1, 7200, 10_000, nil]))
    end

    let(:result) { tool.run('query' => 'Vantaan Musiikki', 'near' => 'Jumbo Vantaa') }

    it 'numbers each hit, with its drive, hours and website, likeliest first' do
      assert_equal <<~TEXT.chomp, result.content
        Near: [1] Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa

        [2] Musiikki Silfverberg Oy Vantaan Musiikki (musical instrument), Peltolantie 2, 01300 Vantaa — 6.3 km, 6 min by car. Opening hours: Mo-Fr 10:00-17:00; Sa 10:00-14:00. Website: https://www.vantaanmusiikki.fi/
        [3] Vantaan musiikkiopisto (music school), Lummetie 4, 01300 Vantaa — 7.2 km, 7 min by car.
        [4] Vantaan musiikkitalon peruskivi (memorial), Louhelantie, 01600 Vantaa — 10 km, 10 min by car.
        [5] Vantaan musiikkiopisto (music school), Patotie 2, 01600 Vantaa — 6.7 km away in a straight line.

        Car distances are from [1], without traffic. A map of these places, numbered as above, appears under your answer.
      TEXT
      assert_equal 'Found 4 places', result.summary
    end

    it 'looks the name up near where it was asked' do
      result
      bias = fake.requests.find { _1.query['q'] == 'Vantaan Musiikki' }.query
      assert_equal %w[60.2915942 24.9656777], bias.values_at('lat', 'lon')
    end

    it 'draws the hits as numbered pins, and where it searched from as a dot' do
      map = notebook.map_for(result.content)
      assert_equal [nil, '2', '3', '4', '5'], map.pins.map(&:label)
      assert_equal 'https://www.openstreetmap.org/node/9444805490', map.pins[1].url
      assert_empty map.line
      assert_nil map.note
    end

    it 'keeps the numbers for route' do
      result
      assert_equal 'Musiikki Silfverberg Oy Vantaan Musiikki', notebook[2].name
    end

    it 'says where it looked, and what it looked for' do
      assert_equal 'Vantaan Musiikki near Jumbo Vantaa', tool.describe_call('query' => 'Vantaan Musiikki',
                                                                            'near' => 'Jumbo Vantaa')
    end
  end

  describe 'by category' do
    before do
      fake.answer('/reverse', 'nominatim-reverse.json')
      fake.answer('/search', 'nominatim-cafes.json')
    end

    it 'finds what’s near a point, the nearest by road first' do
      cafes = JSON.parse(File.read(File.join(FakeOsm::FIXTURES, 'nominatim-cafes.json')))
      fake.answer('/table/', body: table(cafes.each_index.map { (cafes.size - _1) * 100.0 }))
      result = tool.run('category' => 'cafe', 'near' => '60.2931, 25.0307')
      lines = result.content.lines
      assert_equal "Near: [1] Peltolantie 2, 01300 Vantaa\n", lines.first
      assert_match(/\A\[2\] #{Regexp.escape(cafes.last['name'])} \(cafe\), .* — 100 m, 1 min by car\./, lines[2])
      assert_equal 'amenity', fake.requests.find { _1.path == '/search' }.query.keys.first
      assert_equal 'cafe near 60.2931, 25.0307', tool.describe_call('category' => 'cafe', 'near' => '60.2931, 25.0307')
    end

    it 'takes only its own categories' do
      result = tool.run('category' => 'nightclub', 'near' => '1')
      assert result.error?
      assert_includes result.content, 'cafe'
    end
  end

  it 'takes a query or a category, never both' do
    both = tool.run('query' => 'Picnic', 'category' => 'cafe', 'near' => '1')
    assert_equal 'Error: give a query or a category, not both', both.content
    assert_equal 'Error: give a query or a category', tool.run('near' => '1').content
  end

  it 'tells the model a number no search gave' do
    assert_equal 'Error: near: no place is numbered 9 in this conversation: pass a number place_search gave, ' \
                 'or an address', tool.run('query' => 'Picnic', 'near' => '9').content
  end

  it 'passes a service’s failure on to the model' do
    result = tool.run('query' => 'Picnic', 'near' => 'Jumbo Vantaa')
    assert_equal 'Error: 127.0.0.1 answered HTTP 404: no fixture', result.content
  end
end
