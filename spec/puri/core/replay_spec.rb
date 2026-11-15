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
end
