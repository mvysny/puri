# frozen_string_literal: true

require 'stringio'
require 'tmpdir'

RSpec.describe Puri::Core::Store do
  history_class = Pikuri::Agent::History

  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    Dir.mktmpdir('puri-store') do |dir|
      @root = File.join(dir, 'conversations')
      example.run
    end
  ensure
    Pikuri.log_io = log
  end

  let(:store) { described_class.new(root: @root) }
  let(:history) do
    history_class.new(messages: [
                        history_class::Message.new(id: history_class.mint_id, role: 'user', content: 'avocado?'),
                        history_class::Message.new(id: history_class.mint_id, role: 'assistant', content: 'Cold.')
                      ])
  end

  # @param id [String]
  # @param title [String]
  # @return [Puri::Protocol::ConversationSummary]
  def summary(id, title: 'Avocados')
    Puri::Protocol::ConversationSummary.new(id:, title:, started_at: Time.utc(2026, 11, 12, 9, 14, 3).getlocal.iso8601,
                                            running: false, last_question: 'avocado?',
                                            asked_at: Time.utc(2026, 11, 12, 9, 15).getlocal.iso8601)
  end

  # @param id [String]
  # @return [String]
  def meta(id) = File.join(@root, id, 'meta.json')

  it 'mints ids that sort by their start' do
    assert_match described_class::ID, store.mint
    assert_operator store.mint(Time.utc(2026, 11, 12, 9, 14, 3)), :<, store.mint(Time.utc(2026, 11, 12, 9, 14, 4))
    assert_match(/\A2026-11-12T09-14-03Z-/, store.mint(Time.utc(2026, 11, 12, 9, 14, 3)))
  end

  it 'lists a saved conversation as it was saved, newest first' do
    older = store.mint(Time.now - 60)
    newer = store.mint
    [older, newer].each { store.save(summary(_1), history, model: 'Ornith-1.5', server: 'http://x/v1') }
    assert_equal [summary(newer), summary(older)], store.list
    assert_equal %w[user assistant], store.history(older).messages.map(&:role)
  end

  it "writes pikuri-web's meta.json, private" do
    id = store.mint
    store.save(summary(id), history, model: 'Ornith-1.5', server: 'http://x/v1')
    written = JSON.parse(File.read(meta(id)))
    assert_equal [1, 'puri', 'Ornith-1.5', 'http://x/v1'], written.values_at('schema', 'shell', 'model', 'server')
    assert written['created_at'].end_with?('Z')
    assert_equal 0o700, File.stat(File.dirname(meta(id))).mode & 0o777
    assert_equal 0o700, File.stat(@root).mode & 0o777
  end

  it 'renames a saved conversation, and leaves an unsaved one to its first save' do
    id = store.mint
    store.retitle(id, 'Too Early')
    refute File.exist?(meta(id))

    store.save(summary(id), history, model: 'm', server: 's')
    store.retitle(id, 'Keeping An Avocado')
    assert_equal 'Keeping An Avocado', store.list.first.title
    assert_equal 'm', JSON.parse(File.read(meta(id)))['model']
  end

  it 'skips a directory with no meta.json, or one it cannot read' do
    saved = store.mint
    store.save(summary(saved), history, model: 'm', server: 's')
    unfinished = store.mint
    FileUtils.mkdir_p(File.join(@root, unfinished))
    broken = store.mint
    FileUtils.mkdir_p(File.join(@root, broken))
    File.write(meta(broken), '{"schema": 2}')
    FileUtils.mkdir_p(File.join(@root, 'notes'))

    assert_equal [saved], store.list.map(&:id)
    assert_includes Pikuri.log_io.string, "skipping #{File.join(@root, broken)}"
    refute_includes Pikuri.log_io.string, unfinished
  end

  it 'deletes a conversation from disk' do
    id = store.mint
    store.save(summary(id), history, model: 'm', server: 's')
    store.delete(id)
    assert_empty Dir.children(@root)
    store.delete(store.mint) # never saved: nothing to do
  end

  it 'refuses an id that is not one it minted' do
    assert_raises(ArgumentError) { store.delete('../../etc') }
  end

  it 'lives under XDG_STATE_HOME' do
    assert_equal '/s/puri/conversations', described_class.default_root(env: { 'XDG_STATE_HOME' => '/s' })
    assert_equal File.join(Dir.home, '.local/state/puri/conversations'), described_class.default_root(env: {})
  end
end

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
                                                        message('assistant', '<think>hmm</think>Keep it **cold**.'),
                                                        message('assistant', '')
                                                      ]))
    assert_equal [Puri::Protocol::UserMessage.new(id: nil, text: 'avocado?'),
                  Puri::Protocol::Reply.new(id: nil, parts: Puri::Core::ReplyRenderer.render('Keep it **cold**.'))],
                 blocks
  end
end
