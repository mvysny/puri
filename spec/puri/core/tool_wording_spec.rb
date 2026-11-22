# frozen_string_literal: true

RSpec.describe Puri::Core::ToolWording do
  # @param name [String]
  # @param argument [String]
  # @return [Pikuri::Agent::History::ToolCall]
  def call(name, argument)
    Pikuri::Agent::History::ToolCall.new(id: 't1', name:, arguments: {}, display_name: name, argument:)
  end

  it "links the weather line's credit to Open-Meteo, as its licence asks" do
    line = described_class.line(call('weather', 'Lisbon, 3–6 Dec'), content: 'Weather for …', summary: '4 days')
    assert_equal '🌦 Weather from Open-Meteo: Lisbon, 3–6 Dec', line.text
    assert_equal '🌦 Weather from <a href="https://open-meteo.com/">Open-Meteo</a>: Lisbon, 3–6 Dec', line.markup
  end

  it 'escapes the rest of a linked line, which is the model’s' do
    line = described_class.line(call('weather', 'A&B <i>'), content: 'Error: nothing matches', summary: 'Error: x')
    assert_equal '🌦 Weather from <a href="https://open-meteo.com/">Open-Meteo</a>: A&amp;B &lt;i&gt; — Error: x',
                 line.markup
    assert line.error
  end

  it 'leaves any other line plain' do
    assert_nil described_class.line(call('route', '1 → 2'), content: 'From: …', summary: '6 km by car').markup
  end
end
