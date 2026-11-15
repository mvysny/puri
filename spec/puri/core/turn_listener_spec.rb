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

  describe 'a tool call' do
    # @param name [String]
    # @param argument [String]
    # @param display_name [String]
    # @return [void]
    def call(name, argument, display_name: 'WebSearch')
      listener.on_event(Pikuri::Agent::Event::ToolCall.new(tool_call_id: 't1', name:, arguments: {}, display_name:,
                                                           argument:))
    end

    # @param content [String]
    # @param summary [String]
    # @return [void]
    def result(content, summary)
      listener.on_event(Pikuri::Agent::Event::ToolResult.new(tool_call_id: 't1', name: 'web_search', content:,
                                                             summary:))
    end

    # @return [Puri::Protocol::Activity]
    def activity = conversation.transcript.activity

    it 'shows what runs under the progress bar, then a line once it has answered' do
      call('web_search', 'avocado preservation')
      assert_equal Puri::Protocol::Activity.new(state: 'working', status: 'Searching the web…'), activity

      result('1. Avocado …', 'Returned 1 search result')
      assert_equal Puri::Protocol::ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado preservation"', error: false),
                   blocks.last
      assert_equal described_class::THINKING, activity
    end

    it 'shows a failed call in red, with the tool’s summary of it' do
      call('web_search', 'avocado')
      result('Error: every engine failed', 'Error: every engine failed')
      assert_equal Puri::Protocol::ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado" — Error: every engine failed',
                                                error: true), blocks.last
    end

    it 'keeps the reply before the call, and opens a new one after it' do
      delta('Let me look.')
      listener.on_event(e::Assistant.new(content: 'Let me look.'))
      call('web_read_cached', 'a3f9c21e')
      assert_equal 'Reading a page…', activity.status
      result('URL: …', 'Read 12.4 kB')
      delta('Keep it cold.')
      assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::Reply, Puri::Protocol::ToolLine,
                    Puri::Protocol::Reply], blocks.map(&:class)
      assert_equal '📄 Read a page the search found', blocks[2].text
    end

    it 'words a tool it doesn’t know by the tool’s own display strings' do
      call('calculator', '2 + 2', display_name: 'Calculator')
      assert_equal 'Calculator…', activity.status
      result('4', 'Computed 4')
      assert_equal '⚙ Calculator: 2 + 2', blocks.last.text
    end

    it 'says when a cancel cut the call short' do
      call('web_search', 'avocado')
      result(Pikuri::Agent::CANCELLED_RESULT, Pikuri::Agent::INTERRUPTED_SUMMARY)
      assert_equal Puri::Protocol::ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado" — Interrupted', error: false),
                   blocks.last
    end

    it 'shows an escape byte in the query, on one line, rather than letting it act' do
      call('web_search', "avo\e[2Kcado\nfresh")
      result('1. Avocado …', 'Returned 1 search result')
      assert_equal '🔍 Searched: "avo\\x1b[2Kcado fresh"', blocks.last.text
    end

    it 'shows nothing for an answer whose call never showed' do
      result('Error: interrupted', 'Interrupted')
      assert_equal [Puri::Protocol::UserMessage], blocks.map(&:class)
    end
  end
end
