# frozen_string_literal: true

RSpec.describe Puri::Protocol do
  p = described_class
  summary = p::ConversationSummary.new(id: 'c1', title: 'Avocados', started_at: '2026-11-11T14:05:00+01:00',
                                       running: true, last_question: nil, asked_at: nil)
  reply = p::Reply.new(id: 'b2', parts: [p::Prose.new(markup: '<b>cold</b>'), p::Code.new(text: 'x < y'),
                                         p::Table.new(header: %w[A B], rows: [%w[1 2]])])
  [
    p::Transcript.new(conversation: 'c1', title: 'Avocados', activity: p::Activity::IDLE,
                      status: p::Status.new(model: 'Ornith 1.5'), pending: ['and bananas?'],
                      blocks: [p::UserMessage.new(id: 'b1', text: 'avocado?'), reply,
                               p::ToolLine.new(id: 'b3', text: '🔍 Searched: "x"', error: false),
                               p::Confirmation.new(id: 'b4', question: 'Move?', approve_label: 'Update',
                                                   destructive: true, state: 'pending'),
                               p::Notice.new(id: 'b5', text: 'Cancelled', error: false)]),
    p::BlockChanged.new(conversation: 'c1', block: reply),
    p::BlockRemoved.new(conversation: 'c1', block: 'b2'),
    p::ActivityChanged.new(conversation: 'c1', activity: p::Activity.new(state: 'working', status: 'Thinking…')),
    p::ConversationsChanged.new(conversations: [summary]),
    p::PendingChanged.new(conversation: 'c1', texts: ['and bananas?', 'and limes?']),
    p::StatusChanged.new(conversation: 'c1', status: p::Status.new(model: 'Ornith 1.5', context: '7.4k of 64.0k tokens',
                                                                   fill: 0.116, detail: 'msg #2  Δ+1.6k')),
    p::Models.new(names: ['Ornith 1.5', 'Qwen 3.6'], selected: 'Qwen 3.6'),
    [summary, nil, 'c1', 3, 1.5, true]
  ].each do |value|
    it "round-trips #{value.class.name.split('::').last} through JSON" do
      copy = p.round_trip(value)
      assert_equal value, copy
      refute_same value, copy
    end
  end

  it 'names each type without the namespace' do
    json = p.encode(p::BlockRemoved.new(conversation: 'c1', block: 'b2'))
    assert_equal({ 'conversation' => 'c1', 'block' => 'b2', 'type' => 'BlockRemoved' }, JSON.parse(json))
  end

  it "refuses what JSON can't carry back" do
    [{ a: 1 }, :sym, Time.now].each do |value|
      err = assert_raises(ArgumentError) { p.encode(value) }
      assert_includes err.message, "can't carry"
    end
  end

  it 'decodes nothing but its own messages' do
    ['{"type":"Kernel"}', '{"type":"Backend"}', '{"type":"Nope"}', '{"text":"no type"}'].each do |json|
      err = assert_raises(ArgumentError) { p.decode(json) }
      assert_includes err.message, 'not a Puri::Protocol message'
    end
  end

  it 'knows only the activity states it names' do
    err = assert_raises(ArgumentError) { p::Activity.new(state: 'napping') }
    assert_includes err.message, 'napping'
    assert p::Activity.new(state: 'confirming').running?
    refute p::Activity::IDLE.running?
  end
end
