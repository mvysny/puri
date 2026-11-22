# frozen_string_literal: true

# Against answers recorded from the real services on 2026-11-21 (`spec/fixtures/places/`).
RSpec.describe Puri::Core::Places::Osm do
  pl = Puri::Core::Places

  let(:fake) { FakeOsm.new }
  let(:osm) { fake.places }
  let(:jumbo) { pl::Place.new(name: 'Jumbo', category: 'mall', lat: 60.2915942, lon: 24.9656777, osm: 'way/25373590') }
  let(:shop) { pl::Place.new(name: 'Vantaan Musiikki', lat: 60.2931102, lon: 25.0307498, osm: 'node/9444805490') }

  after { fake.close }

  describe '#search' do
    it 'reads Photon’s hits into places, likeliest first, near the bias point' do
      fake.answer('/api/', 'photon-vantaan-musiikki.json')
      places = osm.search('Vantaan Musiikki', near: jumbo)
      assert_equal pl::Place.new(name: 'Musiikki Silfverberg Oy Vantaan Musiikki', category: 'musical instrument',
                                 address: 'Peltolantie 2, 01300 Vantaa', lat: 60.2931102, lon: 25.0307498,
                                 osm: 'node/9444805490'), places.first
      assert_equal 4, places.size
      assert_equal({ 'q' => 'Vantaan Musiikki', 'limit' => '5', 'lat' => '60.2915942', 'lon' => '24.9656777' },
                   fake.requests.last.query)
    end

    it 'sends no bias without a place to be near' do
      fake.answer('/api/', 'photon-jumbo.json')
      assert_equal 'Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa', osm.search('Jumbo Vantaa').first.label
      refute fake.requests.last.query.key?('lat')
    end
  end

  describe '#nearby' do
    it 'asks Nominatim for one kind in a bounded box around the place, with hours and websites' do
      fake.answer('/search', 'nominatim-cafes.json')
      cafes = osm.nearby('cafe', near: shop)
      query = fake.requests.last.query
      assert_equal %w[cafe 1 jsonv2 1], query.values_at('amenity', 'bounded', 'format', 'extratags')
      left, top, right, bottom = query['viewbox'].split(',').map(&:to_f)
      assert_in_delta 0.0135, top - shop.lat, 0.0005
      assert_in_delta 0.027, right - shop.lon, 0.001
      assert_in_delta shop.lon, (left + right) / 2, 0.0001
      assert_in_delta shop.lat, (top + bottom) / 2, 0.0001
      biltema = cafes.first
      assert_equal 'Biltema Cafe (cafe), Akseli 3, 00750 Helsinki', biltema.label
      assert_equal 'Mo-Fr 08:00-19:00; Sa 09:00-17:00; Su 10:00-17:00', biltema.hours
      assert_equal 'node/14062411599', biltema.osm
    end
  end

  describe '#details' do
    it 'adds hours and websites in one lookup, by OSM id, and leaves a bare point alone' do
      fake.answer('/lookup', 'nominatim-lookup.json')
      point = pl::Place.new(name: nil, lat: 60.29, lon: 25.03)
      detailed = osm.details([shop, point, jumbo])
      assert_equal 'N9444805490,W25373590', fake.requests.last.query['osm_ids']
      assert_equal 'Mo-Fr 10:00-17:00; Sa 10:00-14:00', detailed.first.hours
      assert_equal 'https://www.vantaanmusiikki.fi/', detailed.first.website
      assert_same point, detailed[1]
    end

    it 'asks nothing for places with no OSM id' do
      point = pl::Place.new(name: nil, lat: 60.29, lon: 25.03)
      assert_equal [point], osm.details([point])
      assert_empty fake.requests
    end
  end

  describe '#reverse' do
    it 'names the address at a point, and keeps the point where it was given' do
      fake.answer('/reverse', 'nominatim-reverse.json')
      place = osm.reverse(60.2931, 25.0307)
      assert_equal pl::Place.new(name: nil, address: 'Peltolantie 2, 01300 Vantaa', lat: 60.2931, lon: 25.0307), place
    end
  end

  describe '#route' do
    it 'drives from one place to the other, the road as [lat, lon] points' do
      fake.answer('/route/v1/driving/', 'osrm-route.json')
      route = osm.route(jumbo, shop)
      assert_equal '/route/v1/driving/24.965678,60.291594;25.03075,60.29311', fake.requests.last.path
      assert_equal '6.3 km, 9 min', route.words
      assert_equal [60.291592, 24.966851], route.line.first
      assert_equal 29, route.line.size
    end

    it 'fails when no road joins them' do
      fake.answer('/route/', body: '{"code":"NoRoute","routes":[]}')
      error = assert_raises(Puri::Core::Http::Error) { osm.route(jumbo, shop) }
      assert_equal 'OSRM found no route: NoRoute', error.message
    end
  end

  describe '#drives' do
    it 'drives from one place to each of several in one request' do
      fake.answer('/table/v1/driving/', 'osrm-table.json')
      other = pl::Place.new(name: 'K-Lataus', lat: 60.2908148, lon: 24.9636868)
      drives = osm.drives(jumbo, [shop, other])
      assert_equal({ 'sources' => '0', 'annotations' => 'distance,duration' }, fake.requests.last.query)
      assert_equal ['6.3 km, 9 min', '940 m, 3 min'], drives.map(&:words)
    end

    it 'asks nothing for no places' do
      assert_empty osm.drives(jumbo, [])
      assert_empty fake.requests
    end
  end
end
