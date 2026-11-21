# frozen_string_literal: true

RSpec.describe Puri::Core::Replay do
  history_class = Pikuri::Agent::History

  # @param role [String]
  # @param content [String]
  # @param kind [String]
  # @return [Pikuri::Agent::History::Message]
  def message(role, content, kind: 'user')
    Pikuri::Agent::History::Message.new(id: Pikuri::Agent::History.mint_id, role:, content:, kind:)
  end

  it 'shows the questions and the replies, and nothing the user never saw' do
    blocks = described_class.blocks(history_class.new(messages: [
                                                        message('user', 'avocado?'),
                                                        message('user', 'today is Thursday', kind: 'reference'),
                                                        message('assistant', 'Keep it **cold**.'),
                                                        message('assistant', '')
                                                      ]))
    assert_equal [Puri::Protocol::UserMessage.new(id: nil, text: 'avocado?'),
                  Puri::Protocol::Reply.new(id: nil, parts: Puri::Core::ReplyRenderer.render('Keep it **cold**.'))],
                 blocks
  end

  it 'words a tool line as it showed live, from the call the answer pairs with' do
    call = history_class::ToolCall.new(id: 't1', name: 'web_search', arguments: { 'query' => 'avocado' },
                                       display_name: 'WebSearch', argument: 'avocado')
    asked = Pikuri::Agent::History::Message.new(id: history_class.mint_id, role: 'assistant', content: '',
                                                tool_calls: [call])
    answered = Pikuri::Agent::History::Message.new(id: history_class.mint_id, role: 'tool', content: '1. Avocado …',
                                                   tool_call_id: 't1', summary: 'Returned 1 search result')
    blocks = described_class.blocks(history_class.new(messages: [message('user', 'avocado?'), asked, answered,
                                                                 message('assistant', 'Keep it cold.')]))
    assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::ToolLine, Puri::Protocol::Reply], blocks.map(&:class)
    assert_equal Puri::Protocol::ToolLine.new(id: nil, text: '🔍 Searched: "avocado"', error: false), blocks[1]
  end

  describe 'a place tool' do
    let(:notebook) { Puri::Core::Places::Notebook.new(tiles: 'https://tile.example/{z}/{x}/{y}.png') }

    # @param content [String] what the tool answered
    # @return [Array<Pikuri::Agent::History::Message>] its call and its answer
    def place_search(content)
      history = Pikuri::Agent::History
      call = history::ToolCall.new(id: content, name: 'place_search', arguments: {}, display_name: 'PlaceSearch',
                                   argument: 'cafe near home')
      [history::Message.new(id: history.mint_id, role: 'assistant', content: '', tool_calls: [call]),
       history::Message.new(id: history.mint_id, role: 'tool', content:, tool_call_id: content,
                            summary: 'Found 1 place')]
    end

    before do
      notebook.draw('Near: [1] …', pins: [Puri::Protocol::Pin.new(label: '1', name: 'Picnic', lat: 60.29, lon: 25.03,
                                                                  url: 'https://osm/1')])
    end

    it 'redraws the turn’s map under its answer, as it showed live' do
      blocks = described_class.blocks(history_class.new(messages: [
                                                          message('user', 'coffee?'), *place_search('Near: [1] …'),
                                                          message('assistant', '[1] Picnic.'), message('user', 'thanks')
                                                        ]), notebook:)
      assert_equal [Puri::Protocol::UserMessage, Puri::Protocol::ToolLine, Puri::Protocol::Reply, Puri::Protocol::Map,
                    Puri::Protocol::UserMessage], blocks.map(&:class)
      assert_equal 'Picnic', blocks[3].pins.first.name
    end

    it 'draws nothing for a turn that never answered' do
      blocks = described_class.blocks(history_class.new(messages: [message('user', 'coffee?'),
                                                                   *place_search('Near: [1] …')]), notebook:)
      assert_equal [], blocks.grep(Puri::Protocol::Map)
    end
  end
end
