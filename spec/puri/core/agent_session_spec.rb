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
    config = Puri::Core::Config.new(llms: [], servers: [], titler_llm: nil)
    described_class.new(conversation, entry: store.create, store:, conversations: Pikuri::Conversations.new,
                                      transport: Pikuri::Testing.fake_transport { nil }, config:, lock:, saved: false)
  end

  describe 'Initializer.system_prompt' do
    it 'says what the agent can reach' do
      assert_includes described_class::Initializer.system_prompt(web: true), 'You can search the web'
      assert_includes described_class::Initializer.system_prompt(web: false), "You can't search the web"
      assert described_class::Initializer.system_prompt(web: true).start_with?('You are Puri')
    end
  end

  describe 'Initializer.time_zone' do
    let(:now) { Time.new(2026, 11, 17, 9, 0, 0, '+02:00') }

    it 'names the zone TZ gives, with its offset' do
      assert_equal 'Europe/Helsinki (UTC+02:00)',
                   described_class::Initializer.time_zone(now, tz_env: ':Europe/Helsinki')
    end

    it 'reads the zone off the /etc/localtime link when TZ is unset' do
      Dir.mktmpdir('puri-tz') do |dir|
        File.symlink('/usr/share/zoneinfo/Europe/Helsinki', link = File.join(dir, 'localtime'))
        assert_equal 'Europe/Helsinki (UTC+02:00)',
                     described_class::Initializer.time_zone(now, tz_env: nil, localtime: link)
      end
    end

    it 'falls back to the offset alone when nothing names the zone' do
      assert_equal 'UTC+02:00', described_class::Initializer.time_zone(now, tz_env: nil, localtime: '/nonexistent')
    end
  end

  describe 'Initializer#configure' do
    # @param thunderbird [Puri::Core::Config::ThunderbirdTable, nil]
    # @return [Pikuri::Agent] built as a session's, its tools wired
    def agent(thunderbird)
      config = Puri::Core::Config.new(llms: [], servers: [], titler_llm: nil, thunderbird:)
      initializer = described_class::Initializer.new(config, conversation, lock:, cache_dir: @cache)
      Pikuri::Agent.new(transport: Pikuri::Testing.fake_transport { nil }, system_prompt: '') do |c|
        initializer.configure(c, nil)
      end
    end

    around do |example|
      log = Pikuri.log_io
      Pikuri.log_io = StringIO.new
      Dir.mktmpdir('puri-cache') do |cache|
        @cache = File.join(cache, 'puri')
        example.run
      end
    ensure
      Pikuri.log_io = log
    end

    it "keeps each agent's Thunderbird snapshots in a folder of its own, until it closes" do
      Dir.mktmpdir('puri-thunderbird') do |profile_dir|
        table = Puri::Core::Config::ThunderbirdTable.new(profile_dir:)
        first = agent(table)
        second = agent(table)
        assert_equal 2, Dir.children(@cache).size
        assert_equal 0o700, File.stat(@cache).mode & 0o777
        first.close
        second.close
        assert_empty Dir.children(@cache)
      end
    end

    it 'wires the calendar and both hand-offs from the profile [thunderbird] names' do
      Dir.mktmpdir('puri-thunderbird') do |profile_dir|
        built = agent(Puri::Core::Config::ThunderbirdTable.new(profile_dir:))
        # No Gloda index in an empty profile, so no mail tools; the calendar says it is empty.
        assert_equal %w[thunderbird_calendar_search thunderbird_calendar_read thunderbird_mail_compose
                        thunderbird_calendar_create], built.tools.map(&:name)
        assert_includes built.system_prompt, '<thunderbird_usage>'
      ensure
        built&.close
      end
    end

    it 'wires no Thunderbird tool when [thunderbird] is off' do
      built = agent(nil)
      assert_empty built.tools.map(&:name).grep(/thunderbird/)
    ensure
      built&.close
    end
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
