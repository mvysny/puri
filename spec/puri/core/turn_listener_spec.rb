# frozen_string_literal: true

require 'monitor'

RSpec.describe Puri::Core::TurnListener do
  e = Pikuri::Agent::Event
  c = Pikuri::Conversations::Event

  let(:events) { [] }
  let(:conversation) do
    Puri::Core::Conversation.new(id: 'c1', lock: Monitor.new, emit: ->(event) { events << event }, changed: -> {})
  end
  let(:now) { [0.0] }
  let(:listener) { described_class.new(conversation, server: 'http://llm/v1', fps: 10, clock: -> { now.first }) }

  # @param seconds [Float]
  # @param content [String]
  # @return [void]
  def delta_at(seconds, content)
    now[0] = seconds
    listener.on_event(Pikuri::Agent::Event::AssistantDelta.new(content:))
  end

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
    delta_at(0.0, 'Keep it cold.')
    listener.on_event(e::Assistant.new(content: 'Keep it cold.'))
    listener.on_event(e::UserTurn.new(content: 'How long?', attachments: [], mid_loop: true))
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply, Puri::Protocol::UserMessage], blocks.map(&:class)
    assert_equal 'How long?', blocks.last.text
  end

  it 'ends a cancelled turn in a notice, and goes idle' do
    listener.on_event(c::TurnEnded.new(outcome: :cancelled, error: nil, restarting: false))
    assert_equal Puri::Protocol::Notice.new(id: 'b2', text: 'Cancelled', error: false), blocks.last
    assert_equal 'idle', conversation.transcript.activity.state
  end

  it 'names the server in a failure it could not reach' do
    error = RubyLLM::ConnectionError.new('refused')
    listener.on_event(c::TurnEnded.new(outcome: :failed, error:, restarting: false))
    assert_equal "Can't reach the model at http://llm/v1: refused", blocks.last.text
    assert blocks.last.error
  end

  it 'stays busy when another turn follows' do
    listener.on_event(c::TurnEnded.new(outcome: :completed, error: nil, restarting: true))
    assert_equal 'working', conversation.transcript.activity.state
  end

  it 'shows the first delta at once, then at most one re-render a frame' do
    delta_at(0.0, 'Keep ')
    delta_at(0.03, 'it ')
    delta_at(0.06, 'cold')
    delta_at(0.1, '.')
    assert_equal ['', 'Keep', 'Keep it cold.'], shown
  end

  it 'renders the final text whole, dropping the held deltas' do
    delta_at(0.0, 'Keep ')
    delta_at(0.03, 'it cold')
    listener.on_event(e::Assistant.new(content: 'Keep it cold.'))
    assert_equal ['', 'Keep', 'Keep it cold.'], shown
  end

  it 'shows the held deltas when the turn is cancelled' do
    delta_at(0.0, 'Keep ')
    delta_at(0.03, 'it cold')
    listener.on_event(e::Cancelled.new)
    assert_equal 'Keep it cold', shown.last
  end

  it 'shows the next turn’s first delta at once' do
    delta_at(0.0, 'Keep it cold.')
    listener.on_event(e::Assistant.new(content: 'Keep it cold.'))
    listener.on_event(c::TurnStarted.new(user_message: 'How long?', attachments: []))
    listener.on_event(e::UserTurn.new(content: 'How long?', attachments: [], mid_loop: false))
    delta_at(0.01, 'Days.')
    assert_equal 'Days.', shown.last
  end
end
