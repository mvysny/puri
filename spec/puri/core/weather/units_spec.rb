# frozen_string_literal: true

RSpec.describe Puri::Core::Weather::Units do
  it 'follows the locale where GNOME says default, or nothing' do
    assert_equal described_class.new(temperature: :celsius, wind: :kmh, precipitation: :mm),
                 described_class.from({ 'temperature-unit' => 'default' }, imperial: false)
    assert_equal described_class.new(temperature: :fahrenheit, wind: :mph, precipitation: :inch),
                 described_class.from({}, imperial: true)
  end

  it "takes GNOME's own choice over the locale's" do
    units = described_class.from({ 'temperature-unit' => 'centigrade', 'speed-unit' => 'knots',
                                   'distance-unit' => 'km' }, imperial: true)
    assert_equal described_class.new(temperature: :celsius, wind: :kn, precipitation: :mm), units
    assert_equal :fahrenheit, described_class.from({ 'temperature-unit' => 'fahrenheit' }, imperial: false).temperature
    assert_equal :celsius, described_class.from({ 'temperature-unit' => 'kelvin' }, imperial: true).temperature
    assert_equal :inch, described_class.from({ 'distance-unit' => 'miles' }, imperial: false).precipitation
  end

  it 'labels each unit, and asks Open-Meteo in its own words' do
    units = described_class.new(temperature: :fahrenheit, wind: :ms, precipitation: :inch)
    assert_equal %w[°F m/s in], [units.temperature_label, units.wind_label, units.precipitation_label]
    assert_equal %w[fahrenheit ms inch],
                 [units.open_meteo_temperature, units.open_meteo_wind, units.open_meteo_precipitation]
  end

  it 'asks for Beaufort as m/s, and turns it into a force' do
    units = described_class.from({ 'speed-unit' => 'bft' }, imperial: false)
    assert_equal %w[ms Bft], [units.open_meteo_wind, units.wind_label]
    assert_equal([0, 1, 5, 12], [0.2, 0.5, 9.2, 40.0].map { units.wind_speed(_1) })
    assert_nil units.wind_speed(nil)
    assert_equal 17, described_class.from({}, imperial: false).wind_speed(17.24)
  end
end
