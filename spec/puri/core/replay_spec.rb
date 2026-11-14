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
end
