# frozen_string_literal: true

RSpec.describe Puri::Core::Weather::OpenMeteo do
  let(:fake) { FakeOsm.new }
  let(:open_meteo) { described_class.new(http: Puri::Core::Http.new(interval: 0), url: fake.url) }
  let(:metric) { Puri::Core::Weather::Units.from({}, imperial: false) }

  after { fake.close }

  before do
    fake.answer('/v1/forecast', body: File.read(File.join(__dir__, '../../../fixtures/weather/open-meteo-vantaa.json')))
  end

  it 'asks for the whole forecast at a point rounded to about a kilometre, in the units given' do
    open_meteo.forecast(lat: 60.2915942, lon: 24.9656777, units: Puri::Core::Weather::Units.from({}, imperial: true),
                        past_days: 200)
    query = fake.requests.last.query
    assert_equal %w[60.29 24.97 auto 16 92], query.values_at('latitude', 'longitude', 'timezone', 'forecast_days',
                                                             'past_days')
    assert_equal %w[fahrenheit mph inch], query.values_at('temperature_unit', 'wind_speed_unit', 'precipitation_unit')
  end

  it 'reads now, the days and the hours, in words and the place’s own time' do
    forecast = open_meteo.forecast(lat: 60.29, lon: 24.97, units: metric)
    assert_equal 'Europe/Helsinki', forecast.timezone
    assert_equal Puri::Core::Weather::Forecast::Now.new(time: '2026-11-22T16:45', condition: 'partly cloudy',
                                                        temperature: 0.3, feels_like: -4.5, wind: 17),
                 forecast.now
    assert_equal Date.new(2026, 11, 22), forecast.today
    today = forecast.day(forecast.today)
    assert_equal ['light drizzle', 1.1, -0.3, 0.7, 61, 18, '08:36', '15:35'],
                 today.to_h.values_at(:condition, :high, :low, :precipitation, :chance, :wind, :sunrise, :sunset)
    assert_equal 24, forecast.hours_of(forecast.today).size
    assert_equal '00:00', forecast.hours_of(forecast.today).first.clock
  end

  it 'drops the last day the weather models left empty' do
    forecast = open_meteo.forecast(lat: 60.29, lon: 24.97, units: metric)
    assert_equal [Date.new(2026, 11, 20), Date.new(2026, 12, 6)], [forecast.days.first.date, forecast.days.last.date]
    assert_equal '2026-12-07T04:00', forecast.hours.last.time, 'its first hours still have data'
  end

  it 'reuses a forecast for a while, for any point that rounds alike' do
    2.times { open_meteo.forecast(lat: 60.2915942, lon: 24.9656777, units: metric) }
    open_meteo.forecast(lat: 60.2915, lon: 24.9656, units: metric)
    assert_equal 1, fake.requests.size
  end

  it 'passes on what Open-Meteo said was wrong' do
    fake.answer('/v1/forecast', status: 400, body: '{"error":true,"reason":"Latitude must be in range of -90 to 90°."}',
                                latitude: '91.0')
    error = assert_raises(Puri::Core::Http::Error) { open_meteo.forecast(lat: 91.0, lon: 0.0, units: metric) }
    assert_equal '127.0.0.1 answered HTTP 400: Latitude must be in range of -90 to 90°.', error.message
  end

  it 'fails on an answer with no days' do
    empty = '{"current":{"time":"2026-11-22T16:45"},"daily":{"time":[]},"hourly":{"time":[]}}'
    fake.answer('/v1/forecast', body: empty, latitude: '1.0')
    error = assert_raises(Puri::Core::Http::Error) { open_meteo.forecast(lat: 1.0, lon: 0.0, units: metric) }
    assert_equal 'Open-Meteo has no forecast for this place', error.message
  end
end
