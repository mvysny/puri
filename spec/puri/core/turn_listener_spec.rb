# frozen_string_literal: true

require 'monitor'

RSpec.describe Puri::Core::TurnListener do
  e = Pikuri::Agent::Event

  let(:events) { [] }
  let(:conversation) do
    Puri::Core::Conversation.new(id: 'c1', lock: Monitor.new, emit: ->(event) { events << event }, changed: -> {},
                                 threads: ThreadGroup.new, turns: ->(_) {})
  end
  let(:now) { [0.0] }
  let(:listener) { described_class.new(conversation, fps: 10, clock: -> { now.first }) }

  # @param seconds [Float]
  # @param content [String]
  # @return [void]
  def delta_at(seconds, content)
    now[0] = seconds
    listener.on_event(Pikuri::Agent::Event::AssistantDelta.new(content:))
  end

  # @return [Array<String>] the reply's text as each BlockChanged carried it
  def shown
    events.grep(Puri::Protocol::BlockChanged).map { |change| change.block.parts.map(&:markup).join }
  end

  before { listener.on_event(e::UserTurn.new(content: 'Avocado?', attachments: [], mid_loop: false)) }

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
    listener.on_event(e::UserTurn.new(content: 'How long?', attachments: [], mid_loop: false))
    delta_at(0.01, 'Days.')
    assert_equal 'Days.', shown.last
  end
end
