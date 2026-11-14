# frozen_string_literal: true

require 'monitor'

RSpec.describe Puri::Core::TurnListener do
  e = Pikuri::Agent::Event
  c = Pikuri::Conversations::Event

  let(:events) { [] }
  let(:conversation) do
    Puri::Core::Conversation.new(id: 'c1', lock: Monitor.new, emit: ->(event) { events << event }, changed: -> {})
  end
  let(:listener) { described_class.new(conversation, server: 'http://llm/v1') }

  # @param content [String]
  # @return [void]
  def delta(content) = listener.on_event(Pikuri::Agent::Event::AssistantDelta.new(content:))

  # @return [Array<String>] the reply's text as each BlockChanged carried it
  def shown
    events.grep(Puri::Protocol::BlockChanged).map(&:block).grep(Puri::Protocol::Reply).map { _1.parts.map(&:markup).join }
  end

  # @return [Array<Puri::Protocol::Block>] the conversation's blocks now
  def blocks = conversation.transcript.blocks

  before do
    listener.on_event(c::TurnStarted.new(user_message: 'Avocado?', attachments: []))
    listener.on_event(e::UserTurn.new(content: 'Avocado?', attachments: [], mid_loop: false))
  end

  it 'shows the turn’s message as the turn starts, once' do
    assert_equal [Puri::Protocol::UserMessage.new(id: 'b1', text: 'Avocado?')], blocks
    assert_equal 'working', conversation.transcript.activity.state
  end

  it 'shows a message sent during the turn where the model reads it' do
    delta('Keep it cold.')
    listener.on_event(e::Assistant.new(content: 'Keep it cold.'))
    listener.on_event(e::UserTurn.new(content: 'How long?', attachments: [], mid_loop: true))
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply, Puri::Protocol::UserMessage], blocks.map(&:class)
    assert_equal 'How long?', blocks.last.text
  end

  it 'ends a cancelled turn in a notice' do
    listener.on_event(c::TurnEnded.new(outcome: :cancelled, error: nil, restarting: false))
    assert_equal Puri::Protocol::Notice.new(id: 'b2', text: 'Cancelled', error: false), blocks.last
  end

  it 'names the server in a failure it could not reach' do
    error = RubyLLM::ConnectionError.new('refused')
    listener.on_event(c::TurnEnded.new(outcome: :failed, error:, restarting: false))
    assert_equal "Can't reach the model at http://llm/v1: refused", blocks.last.text
    assert blocks.last.error
  end

  it 'shows every delta in one reply, then the final text whole' do
    delta('Keep ')
    delta('it cold')
    listener.on_event(e::Assistant.new(content: 'Keep it cold.'))
    assert_equal ['', 'Keep', 'Keep it cold', 'Keep it cold.'], shown
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply], blocks.map(&:class)
    assert_equal 'streaming', conversation.transcript.activity.state
  end

  it 'renders a reply that came with no delta' do
    listener.on_event(e::Assistant.new(content: 'Keep it **cold**.'))
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply], blocks.map(&:class)
    assert_equal 'Keep it <b>cold</b>.', shown.last
  end

  it 'leaves the reply alone on any other conversation event' do
    delta('Keep ')
    [c::PendingChanged.new(count: 1), c::CancelRequested.new, c::Cleared.new].each { listener.on_event(_1) }
    delta('it cold.')
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply], blocks.map(&:class)
    assert_equal ['', 'Keep', 'Keep it cold.'], shown
  end

  it 'opens the next turn’s reply anew' do
    delta('Keep it cold.')
    listener.on_event(e::Assistant.new(content: 'Keep it cold.'))
    listener.on_event(c::TurnStarted.new(user_message: 'How long?', attachments: []))
    listener.on_event(e::UserTurn.new(content: 'How long?', attachments: [], mid_loop: false))
    delta('Days.')
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply] * 2, blocks.map(&:class)
    assert_equal 'Days.', blocks.last.parts.map(&:markup).join
  end
end
