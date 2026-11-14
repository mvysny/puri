# frozen_string_literal: true

require 'monitor'
require 'pikuri/testing'
require 'tmpdir'

# The events a live conversation hands its session, fed in directly: the gem's limiter and
# {Puri::Core::TurnListener} behind it, as the session wires them.
RSpec.describe Puri::Core::AgentSession do
  e = Pikuri::Agent::Event
  c = Pikuri::Conversations::Event

  let(:events) { [] }
  let(:lock) { Monitor.new }
  let(:conversation) do
    Puri::Core::Conversation.new(id: 'c1', lock:, emit: ->(event) { events << event }, changed: -> {})
  end
  let(:session) do
    store = Pikuri::Conversations::Store.new(root: @root, shell: 'puri')
    described_class.new(conversation, entry: store.create, store:,
                                      conversations: Pikuri::Conversations.new(system_prompt: ->(_) { '' }),
                                      transport: Pikuri::Testing.fake_transport { nil }, tools: ->(_) { [] },
                                      lock:, saved: false)
  end

  around do |example|
    Dir.mktmpdir('puri-session') do |root|
      @root = root
      example.run
    end
  end

  # @return [Array<String>] the reply's text as each BlockChanged carried it
  def shown
    events.grep(Puri::Protocol::BlockChanged).map(&:block).grep(Puri::Protocol::Reply).map { _1.parts.map(&:markup).join }
  end

  # @return [Array<Puri::Protocol::Block>] the conversation's blocks now
  def blocks = conversation.transcript.blocks

  # The first delta shows at once; the second, within the same frame, is held.
  before do
    session.on_event(c::TurnStarted.new(user_message: 'Avocado?', attachments: []))
    session.on_event(e::UserTurn.new(content: 'Avocado?', attachments: [], mid_loop: false))
    session.on_event(e::AssistantDelta.new(content: 'Keep '))
    session.on_event(e::AssistantDelta.new(content: 'it cold'))
  end

  it 'holds a delta past a conversation event, in the one reply' do
    session.on_event(c::PendingChanged.new(count: 1))
    assert_equal ['', 'Keep'], shown
    session.on_event(e::Assistant.new(content: 'Keep it cold.'))
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply], blocks.map(&:class)
    assert_equal 'Keep it cold.', shown.last
  end

  it 'shows a failed turn’s tail, then the failure' do
    session.on_event(c::TurnEnded.new(outcome: :failed, error: RuntimeError.new('boom'), restarting: false))
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply, Puri::Protocol::Notice], blocks.map(&:class)
    assert_equal 'Keep it cold', shown.last
    assert blocks.last.error
  end
end
