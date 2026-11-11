# frozen_string_literal: true

RSpec.describe Puri::Core::DummyCore do
  let(:events) { Thread::Queue.new }
  let(:core) { described_class.new(think: 0, pace: 0) { |event| events << event } }

  # @return [Array<Data>] every event emitted so far
  def drain
    Array.new(events.size) { events.pop }
  end

  it 'starts a new conversation and streams the reply from its own thread' do
    turn = core.handle(Puri::Protocol::Ask.new(conversation: nil, text: 'hi'))
    refute_same Thread.current, turn
    turn.join
    started, *deltas, finished = drain
    conversation = started.conversation
    refute_nil conversation
    assert_equal Puri::Protocol::TurnFinished.new(conversation:), finished
    assert_equal described_class::WORDS.join(' '), deltas.map(&:text).join
    assert(deltas.all? { |d| d.conversation == conversation })
  end

  it 'continues the conversation it is given' do
    core.handle(Puri::Protocol::Ask.new(conversation: 'c1', text: 'again')).join
    assert_equal ['c1'], drain.map(&:conversation).uniq
  end

  it 'rejects anything but a command' do
    err = assert_raises(ArgumentError) { core.handle(Puri::Protocol::TurnFinished.new(conversation: 'c1')) }
    assert_includes err.message, "can't handle"
  end
end
