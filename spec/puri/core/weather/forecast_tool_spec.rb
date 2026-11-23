# frozen_string_literal: true

RSpec.describe Puri::Core::Weather::ForecastTool do
  w = Puri::Core::Weather

  let(:fake) { FakeOsm.new }
  let(:notebook) { Puri::Core::Places::Notebook.new(tiles: nil) }
  let(:units) { w::Units.from({}, imperial: false) }
  let(:tool) do
    described_class.new(open_meteo: w::OpenMeteo.new(http: Puri::Core::Http.new(interval: 0), url: fake.url),
                        osm: fake.places, notebook:, units:, today: Date.new(2026, 11, 22))
  end
  let(:head) do
    'Weather for [1] Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa, in its local time (Europe/Helsinki).'
  end

  before do
    fake.answer('/api/', 'photon-jumbo.json', q: 'Jumbo Vantaa')
    fake.answer('/v1/forecast', body: File.read(File.expand_path('../../../fixtures/weather/open-meteo-vantaa.json',
                                                                 __dir__)))
  end

  after { fake.close }

  # @param arguments [Hash{String => String}] besides the place
  # @return [Pikuri::Tool::Result]
  def run(**arguments) = tool.run({ 'place' => 'Jumbo Vantaa' }.merge(arguments.transform_keys(&:to_s)))

  it 'gives now and a week, a line a day, without dates' do
    result = run
    assert_equal <<~TEXT.chomp, result.content
      #{head}

      Now, 16:45: partly cloudy, 0 °C, feels like -5 °C, wind 17 km/h.
      Sun 22 Nov: light drizzle, 0 to 1 °C, precipitation 0.7 mm, 61 % chance, wind up to 18 km/h.
      Mon 23 Nov: light drizzle, 1 to 2 °C, precipitation 2.5 mm, 98 % chance, wind up to 26 km/h.
      Tue 24 Nov: overcast, -1 to 1 °C, precipitation 0 mm, 2 % chance, wind up to 25 km/h.
      Wed 25 Nov: overcast, -2 to 0 °C, precipitation 0 mm, 0 % chance, wind up to 17 km/h.
      Thu 26 Nov: overcast, -5 to 0 °C, precipitation 0 mm, 0 % chance, wind up to 16 km/h.
      Fri 27 Nov: overcast, -5 to -3 °C, precipitation 0 mm, 0 % chance, wind up to 15 km/h.
      Sat 28 Nov: overcast, -6 to -4 °C, precipitation 0 mm, 2 % chance, wind up to 7 km/h.
    TEXT
    assert_equal '7 days, -6 to 2 °C', result.summary
  end

  it 'gives one day every three hours, with its sun' do
    result = run(from: '2026-11-23')
    lines = result.content.lines(chomp: true)
    assert_equal 'Mon 23 Nov: light drizzle, 1 to 2 °C, precipitation 2.5 mm, 98 % chance, wind up to 26 km/h.',
                 lines[2]
    assert_equal '00:00: light drizzle, 1 °C, precipitation 0.2 mm, 71 % chance, wind 17 km/h.', lines[3]
    assert_equal(%w[00:00 03:00 06:00 09:00 12:00 15:00 18:00 21:00], lines[3..10].map { _1[0, 5] })
    assert_equal 'Sunrise 08:39, sunset 15:33.', lines.last
    assert_equal 'Light drizzle, 1 to 2 °C', result.summary
  end

  it 'gives today from now on, after the weather now' do
    lines = run(from: '2026-11-22').content.lines(chomp: true)
    assert lines[2].start_with?('Now, 16:45:')
    assert_equal(%w[18:00 21:00], lines[4..5].map { _1[0, 5] })
  end

  it 'cuts a range at the forecast’s last day, and says so' do
    result = run(from: '2026-12-04', to: '2026-12-12')
    assert_equal <<~TEXT.chomp, result.content
      #{head}

      Fri 4 Dec: slight snowfall, -8 to -6 °C, precipitation 1.5 mm, 17 % chance, wind up to 14 km/h.
      Sat 5 Dec: slight snow showers, -10 to -5 °C, precipitation 3.3 mm, 16 % chance, wind up to 20 km/h.
      Sun 6 Dec: moderate snowfall, -11 to -6 °C, precipitation 8.1 mm, 18 % chance, wind up to 21 km/h.

      The forecast reaches only Sun 6 Dec; later days can't be forecast yet.
    TEXT
    assert_equal '3 days, -11 to -5 °C', result.summary
  end

  it 'refuses a day past the forecast, naming its last' do
    assert_equal 'Error: Sun 20 Dec is past the forecast, which reaches Sun 6 Dec: ask again nearer the time',
                 run(from: '2026-12-20').content
  end

  it 'asks for the past days a past date needs, and gives what there is' do
    result = run(from: '2026-11-15', to: '2026-11-20')
    assert_operator Integer(fake.requests.last.query['past_days']), :>=, 8
    assert_includes result.content, 'Fri 20 Nov: slight rain, 3 to 6 °C'
    assert result.content.end_with?('Past days reach back only to Fri 20 Nov.')
  end

  it 'reads `to` alone as today until then, or as that one day when it’s past' do
    lines = run(to: '2026-11-24').content.lines(chomp: true)
    assert_equal(['Now, 16:45', 'Sun 22 Nov', 'Mon 23 Nov', 'Tue 24 Nov'], lines[2..].map { _1[0, 10] })
    result = run(to: '2026-11-21')
    assert_operator Integer(fake.requests.last.query['past_days']), :>=, 2
    lines = result.content.lines(chomp: true)
    assert lines[2].start_with?('Sat 21 Nov: ')
    assert_equal(%w[00:00 03:00 06:00 09:00 12:00 15:00 18:00 21:00], lines[3..10].map { _1[0, 5] })
  end

  it 'numbers the place, for route' do
    run
    assert_equal 'Jumbo', notebook[1].name
  end

  it 'tells the model a date it can’t read, or a range backwards' do
    assert_equal 'Error: from: "next week" is no date; write it as YYYY-MM-DD', run(from: 'next week').content
    assert_equal 'Error: to is before from', run(from: '2026-11-25', to: '2026-11-23').content
    assert_empty fake.requests, 'neither asked anything'
  end

  it 'tells the model a place it can’t find' do
    assert_equal 'Error: place: no place is numbered 9 in this conversation: pass a number place_search gave, ' \
                 'or an address', tool.run('place' => '9').content
  end

  it 'names the last day of the forecast in its description' do
    assert_includes tool.description, 'The forecast reaches 2026-12-06;'
  end

  it 'says where, and when' do
    assert_equal 'Lisbon', tool.describe_call('place' => 'Lisbon')
    assert_equal 'Lisbon, 3 Dec', tool.describe_call('place' => 'Lisbon', 'from' => '2026-12-03')
    assert_equal 'Lisbon, 3–6 Dec',
                 tool.describe_call('place' => 'Lisbon', 'from' => '2026-12-03', 'to' => '2026-12-06')
    assert_equal 'Lisbon, 30 Nov – 2 Dec', tool.describe_call('place' => 'Lisbon', 'from' => '2026-11-30',
                                                              'to' => '2026-12-02')
    assert_equal 'Lisbon, until 6 Dec', tool.describe_call('place' => 'Lisbon', 'to' => '2026-12-06')
    assert_equal 'Lisbon, soon', tool.describe_call('place' => 'Lisbon', 'from' => 'soon')
  end
end
