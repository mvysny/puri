# frozen_string_literal: true

RSpec.describe Puri::Protocol do
  [
    Puri::Protocol::Ask.new(conversation: nil, text: 'avocado?'),
    Puri::Protocol::Ask.new(conversation: 'c1', text: 'and bananas?'),
    Puri::Protocol::TurnStarted.new(conversation: 'c1'),
    Puri::Protocol::TextDelta.new(conversation: 'c1', text: ' Lorem'),
    Puri::Protocol::TurnFinished.new(conversation: 'c1')
  ].each do |message|
    it "round-trips #{message.inspect} through JSON" do
      copy = Puri::Protocol.round_trip(message)
      assert_equal message, copy
      refute_same message, copy
    end
  end

  it 'names the type without the namespace' do
    json = Puri::Protocol.encode(Puri::Protocol::TurnFinished.new(conversation: 'c1'))
    assert_equal({ 'conversation' => 'c1', 'type' => 'TurnFinished' }, JSON.parse(json))
  end

  it 'decodes nothing but its own messages' do
    ['{"type":"Kernel"}', '{"type":"Puri::Core"}', '{"type":"Nope"}', '{"text":"no type"}'].each do |json|
      err = assert_raises(ArgumentError) { Puri::Protocol.decode(json) }
      assert_includes err.message, 'not a Puri::Protocol message'
    end
  end
end
