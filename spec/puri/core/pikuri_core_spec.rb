# frozen_string_literal: true

require 'pikuri/testing'
require 'stringio'
require 'tmpdir'

# The real pikuri loop against a scripted HTTP backend (`Pikuri::Testing`): no server, no mocks.
RSpec.describe Puri::Core::PikuriCore do
  p = Puri::Protocol

  # A gate that also says when a turn has reached the model: `await` runs inside each HTTP call.
  parking_gate = Class.new(Pikuri::Testing::Gate) do
    def initialize
      super
      @arrived = Thread::Queue.new
    end

    def await
      @arrived << true
      super
    end

    def wait_arrived = @arrived.pop(timeout: 5) || raise('no request reached the model')
  end

  let(:events) { Thread::Queue.new }
  let(:gate) { parking_gate.new }
  let(:script) { ->(llm) { llm.stream('Keep it ', '**cold**', '.') } }
  let(:transport) { Pikuri::Testing.fake_transport(gate:, &script) }
  let(:title_gate) { Pikuri::Testing::Gate.new }
  let(:titles) { ['Keeping An Avocado'] }
  let(:titler) do
    titled = Pikuri::Testing.fake_transport(gate: title_gate) { |llm| titles.each { llm.reply(_1) } }
    Pikuri::Conversations::Titler.new(transport: titled, params_declared: true)
  end
  let(:store) { Pikuri::Conversations::Store.new(root: @root, shell: 'puri') }
  let(:config) { Puri::Core::Config.new(llms: [], servers: [], titler_llm: nil) }
  let(:models) { Puri::Core::Models.new([Puri::Core::Models::Choice.new(name: 'Fake', transport:)]) }
  let(:core) { described_class.new(config:, models:, titler:, store:) { |event| events << p.round_trip(event) } }

  # A core whose every agent also gets what the block adds: Puri wires no tool that asks, no slow
  # boot, and no web_search that answers offline, so a spec that needs one brings its own.
  #
  # @yieldparam configurator [Pikuri::Agent::Configurator]
  # @yieldparam confirmer [Puri::Core::Confirmer] the agent's
  # @yieldreturn [void]
  # @return [Puri::Core::PikuriCore]
  def core_with(&extra)
    initializer = Class.new(Puri::Core::AgentSession::Initializer) do
      define_method(:configure) do |configurator, conversation|
        super(configurator, conversation)
        extra.call(configurator, confirmer)
      end
    end
    session = Class.new(Puri::Core::AgentSession) { const_set(:Initializer, initializer) }
    core = Class.new(described_class) do
      define_method(:agent_session) do |conversation, entry, saved:|
        session.new(conversation, entry:, store: @store, conversations: @live,
                                  transport: start_on(entry, saved:).transport, models: @models, config: @config,
                                  lock: @lock, saved:)
      end
      private :agent_session
    end
    core.new(config:, models:, titler:, store:) { |event| events << Puri::Protocol.round_trip(event) }
  end

  # The fake states its context window and modalities; sizing its server too leaves the probe
  # nothing to ask. A server not sized is probed, and the probe warns that it failed.
  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    Pikuri::Conversations::Throttle.limit('http://fake.invalid', nil)
    Dir.mktmpdir('puri-conversations') do |root|
      @root = root
      example.run
    ensure
      gate.release!
      title_gate.release!
      core.close
      @restarted&.close
    end
  ensure
    Pikuri::Conversations::Throttle.reset!
    Pikuri::Conversations::Probe.reset!
    Pikuri.log_io = log
  end

  # @param message [String] what was awaited, for the failure
  # @return [void]
  def wait_until(message)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until yield
      raise "timed out waiting until #{message}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.005
    end
  end

  # @param id [String]
  # @param backend [Puri::Core::PikuriCore]
  # @return [Puri::Protocol::Transcript] once the turn is over
  def finished(id, backend = core)
    wait_until('the turn ends') { !backend.load_conversation(id).activity.running? }
    backend.load_conversation(id)
  end

  # @return [Array<Data>] every event emitted so far
  def drain = Array.new(events.size) { events.pop }

  it 'implements every Backend method' do
    p::Backend.instance_methods.each do |name|
      refute_equal p::Backend, described_class.instance_method(name).owner, "#{name} is not implemented"
    end
  end

  it 'streams the answer into a Reply, then goes idle' do
    id = core.ask(nil, 'how do I keep an avocado?')
    user, reply = finished(id).blocks
    assert_equal p::UserMessage.new(id: 'b1', text: 'how do I keep an avocado?'), user
    assert_equal ['Keep it <b>cold</b>.'], reply.parts.map(&:markup)

    assert_equal %w[working streaming idle], drain.grep(p::ActivityChanged).map { _1.activity.state }.uniq
  end

  it 'counts the reply’s tokens into the status' do
    gate.block!
    id = core.ask(nil, 'hi')
    assert_equal p::Status.new(model: 'Fake', context: '8.0k token window'), core.load_conversation(id).status
    gate.release!
    wait_until('the tokens are counted') { finished(id).status.detail.start_with?('msg #1') }
    status = core.load_conversation(id).status
    assert_equal ['Fake', '0.0k of 8.0k tokens', 15.0 / 8192], [status.model, status.context, status.fill]
    assert_equal 'msg #1  Δ+0.0k  ↑0.0k  ↓0.0k', status.detail
    assert_equal status, drain.grep(p::StatusChanged).last.status
  end

  context 'with two models' do
    let(:other) { Pikuri::Testing.fake_transport(model: 'other', context_window: 4096) { |llm| 2.times { llm.reply('Other.') } } }
    let(:models) do
      Puri::Core::Models.new([Puri::Core::Models::Choice.new(name: 'Fake', transport:),
                              Puri::Core::Models::Choice.new(name: 'Other', transport: other)])
    end

    it 'runs the next turn on the model picked, and starts new conversations on it' do
      assert_equal p::Models.new(names: %w[Fake Other], selected: 'Fake'), core.list_models
      id = core.ask(nil, 'hi')
      finished(id)
      core.select_model(id, 'Other')
      wait_until('the status follows the pick') { core.load_conversation(id).status.model == 'Other' }
      core.ask(id, 'again')
      assert_equal ['Other.'], finished(id).blocks.last.parts.map(&:markup)

      assert_equal 'Other', core.list_models.selected
      fresh = core.ask(nil, 'and you?')
      assert_equal ['Other.'], finished(fresh).blocks.last.parts.map(&:markup)
    end

    it 'picks for new conversations alone, given none' do
      core.select_model(nil, 'Other')
      id = core.ask(nil, 'hi')
      assert_equal p::Status.new(model: 'Other', context: '4.0k token window'), core.load_conversation(id).status
    end

    it 'refuses a model it lacks' do
      assert_raises(ArgumentError) { core.select_model(nil, 'Nope') }
    end
  end

  # @param id [String]
  # @return [String]
  def title(id) = core.list_conversations.find { _1.id == id }.title

  it 'titles a new conversation once its first answer is in' do
    gate.block!
    id = core.ask(nil, 'how do I keep an avocado?')
    assert_equal 'New conversation', drain.grep(p::ConversationsChanged).first.conversations.first.title
    gate.wait_arrived
    sleep 0.1
    assert_equal 'New conversation', title(id)

    gate.release!
    wait_until('the title arrives') { title(id) == 'Keeping An Avocado' }
  end

  context 'when the titler fails' do
    let(:titles) { [] }

    it 'logs it and keeps the name' do
      id = core.ask(nil, 'how do I keep an avocado?')
      wait_until('the failure is logged') { Pikuri.log_io.string.include?("conversation #{id}: titling failed") }
      assert_equal 'New conversation', title(finished(id).conversation)
    end
  end

  it 'drops the title of a conversation deleted meanwhile' do
    title_gate.block!
    id = core.ask(nil, 'how do I keep an avocado?')
    finished(id)
    core.delete_conversation(id)
    drain
    title_gate.release!
    sleep 0.2
    assert_empty drain.grep(p::ConversationsChanged)
  end

  context 'with two answers scripted' do
    let(:script) { ->(llm) { llm.stream('Hi, Bob.').stream('Your name is **Bob**.') } }

    it 'carries one agent across the turns of a conversation' do
      id = core.ask(nil, "I'm Bob")
      finished(id)
      core.ask(id, "what's my name?")
      blocks = finished(id).blocks
      assert_equal [p::UserMessage, p::Reply, p::UserMessage, p::Reply], blocks.map(&:class)
      assert_equal 'Your name is <b>Bob</b>.', blocks.last.parts.first.markup
    end

    it 'shows a message sent during a turn once the model reads it, and answers it' do
      gate.block!
      id = core.ask(nil, "I'm Bob")
      gate.wait_arrived
      core.ask(id, "what's my name?")
      assert_equal [p::UserMessage], core.load_conversation(id).blocks.map(&:class)

      gate.release!
      wait_until('both answers are in') { core.load_conversation(id).blocks.size == 4 }
      assert_equal "what's my name?", finished(id).blocks[2].text
    end

    it 'shows a message a cancel dropped before the model read it' do
      gate.block!
      id = core.ask(nil, "I'm Bob")
      gate.wait_arrived
      core.ask(id, "what's my name?")
      core.cancel(id)
      gate.release!
      assert_equal [p::UserMessage, p::UserMessage, p::Notice], finished(id).blocks.map(&:class)
      assert_equal %w[user], store.history(store.find(id)).messages.map(&:role)
    end

    it 'ends a cancelled turn in a notice, and takes the next question' do
      gate.block!
      id = core.ask(nil, "I'm Bob")
      gate.wait_arrived
      core.cancel(id)
      gate.release!
      assert_equal [p::UserMessage, p::Notice], finished(id).blocks.map(&:class)
      assert_equal 'Cancelled', core.load_conversation(id).blocks.last.text

      core.ask(id, 'hello again')
      assert_equal p::Reply, finished(id).blocks.last.class
    end

    # Return, then Escape at once: the agent is usually still booting, and a boot goes idle on
    # the cancel, its notice following once the boot is over. Wherever it is, the cancel ends it.
    it 'ends a turn cancelled before its thread reaches the model' do
      gate.block!
      id = core.ask(nil, 'wrong question')
      core.cancel(id)
      gate.release!

      wait_until('the notice shows') { core.load_conversation(id).blocks.last.is_a?(p::Notice) }
      assert_equal [p::UserMessage, p::Notice], finished(id).blocks.map(&:class)
    end
  end

  context 'with no server listening' do
    let(:transport) { Pikuri::Agent::ChatTransport.from_openai_server(server: 'http://127.0.0.1:9', model: 'x') }

    it 'ends the turn in an error notice naming the server' do
      id = core.ask(nil, 'hi')
      notice = finished(id).blocks.last
      assert notice.error
      assert_match %r{\ACan't reach the model at http://127\.0\.0\.1:9/v1: }, notice.text
    end
  end

  describe '.from_config' do
    c = Puri::Core::Config
    let(:config) do
      titles = c::Llm.new(name: 'Titles', server: 'http://127.0.0.1:9', model: 'x', params: { 'a' => 1 })
      c.new(llms: [c::Llm.new(name: 'Main', server: 'http://127.0.0.1:9', model: 'x'), titles],
            servers: [c::Server.new(id: 'local', url: 'http://127.0.0.1:9/v1', max_concurrent_requests: 2),
                      c::Server.new(id: 'cloud', url: 'http://127.0.0.1:19')],
            titler_llm: titles)
    end
    let(:core) { described_class.from_config(config, store:) { |event| events << p.round_trip(event) } }

    it 'runs conversations on the first [[llm]], and titles them on the [titler]' do
      id = core.ask(nil, 'hi')
      assert_match %r{\ACan't reach the model at http://127\.0\.0\.1:9/v1: }, finished(id).blocks.last.text
      wait_until('the title fails') { Pikuri.log_io.string.include?('titling failed: RubyLLM::ConnectionError') }
    end

    it 'logs that the agent has no web tools, with no search key' do
      core
      assert_includes Pikuri.log_io.string, 'sets no Brave or Exa key: the agent has no web tools'
    end

    context 'with a Brave key' do
      let(:config) do
        main = c::Llm.new(name: 'Main', server: 'http://127.0.0.1:9', model: 'x')
        c.new(llms: [main], servers: [], titler_llm: main, search: c::SearchTable.new(brave_key: 'B'))
      end

      it 'wires the web tools without a word' do
        core
        refute_includes Pikuri.log_io.string, 'no web tools'
      end
    end

    it 'limits the servers that state max_concurrent_requests, and only those' do
      core
      assert_equal({ 'http://127.0.0.1:9' => 2, 'http://fake.invalid' => nil },
                   Pikuri::Conversations::Throttle.sizes)
    end
  end

  context 'with a tool that asks before it acts' do
    let(:observations) { [] }
    let(:question) { 'Move “Dentist” (Personal) to Thursday 15:00?' }
    let(:script) { ->(llm) { llm.tool_call('move_event', question:).stream('Done.') } }
    # A calendar extension in miniature: it builds its tool around the confirmer it is given.
    let(:calendar) do
      move_event = method(:move_event)
      Class.new do
        include Pikuri::Agent::Extension

        define_method(:initialize) { |confirmer| @confirmer = confirmer }
        define_method(:configure) { |c| c.add_tool(move_event.call(@confirmer)) }
      end
    end
    let(:core) do
      calendar = self.calendar
      core_with { |c, confirmer| c.add_extension(calendar.new(confirmer)) }
    end

    # @param confirmer [Puri::Core::Confirmer]
    # @return [Pikuri::Tool]
    def move_event(confirmer)
      Pikuri::Tool.new(
        name: 'move_event', description: 'Moves a calendar event.',
        parameters: Pikuri::Tool::Parameters.build { |params| params.required_string :question, 'what to ask' },
        wants_context: true,
        execute: lambda { |question:, context:|
          request = Pikuri::Workspace::Confirmer::Request.new(question:)
          result = case decision = confirmer.ask(request:, cancellable: context.cancellable)
                   in Pikuri::Workspace::Confirmer::Approved then Pikuri::Tool::Result.new(content: 'Moved.',
                                                                                           summary: 'Moved')
                   else decision.observation('the move')
                   end
          observations << result.content
          result
        }
      )
    end

    # @param id [String]
    # @return [Puri::Protocol::Confirmation] the one waiting
    def pending_confirmation(id)
      wait_until('a confirmation waits') { core.load_conversation(id).activity.state == 'confirming' }
      core.load_conversation(id).blocks.grep(Puri::Protocol::Confirmation).find(&:pending?)
    end

    # @param id [String]
    # @return [Puri::Protocol::Confirmation] the conversation's only one
    def confirmation(id)
      confirmations = core.load_conversation(id).blocks.grep(Puri::Protocol::Confirmation)
      assert_equal 1, confirmations.size
      confirmations.first
    end

    it 'shows the question, and approves on the approve button' do
      id = core.ask(nil, 'move my dentist to Thursday')
      waiting = pending_confirmation(id)
      assert_equal p::Confirmation.new(id: waiting.id, question:, approve_label: 'Approve', destructive: false,
                                       state: 'pending'), waiting

      core.answer(id, waiting.id, true)
      assert_equal [p::UserMessage, p::Confirmation, p::ToolLine, p::Reply], finished(id).blocks.map(&:class)
      assert_equal 'approved', confirmation(id).state
      assert_equal ['Moved.'], observations
    end

    it 'tells the model the user declined, on Cancel' do
      id = core.ask(nil, 'move my dentist to Thursday')
      core.answer(id, pending_confirmation(id).id, false)
      finished(id)
      assert_equal 'rejected', confirmation(id).state
      assert_equal 1, observations.size
      assert_match(/\AError: user declined the move\. Don't retry it/, observations.first)
    end

    it 'passes typed words to the model as a redirect' do
      id = core.ask(nil, 'move my dentist to Thursday')
      pending_confirmation(id)
      core.ask(id, 'make it Wednesday')
      blocks = finished(id).blocks
      assert_equal [p::UserMessage, p::Confirmation, p::UserMessage, p::ToolLine, p::Reply], blocks.map(&:class)
      assert_equal 'redirected', confirmation(id).state
      assert_equal ['The user declined the move and said: make it Wednesday'], observations
    end

    it 'ends the turn when it is cancelled while the question waits' do
      id = core.ask(nil, 'move my dentist to Thursday')
      pending_confirmation(id)
      core.cancel(id)
      blocks = finished(id).blocks
      assert_equal [p::UserMessage, p::Confirmation, p::ToolLine, p::Notice], blocks.map(&:class)
      assert_match(/ — Interrupted\z/, blocks[2].text)
      assert_equal 'cancelled', confirmation(id).state
      assert_empty observations
    end

    it 'drops an answer meant for another confirmation' do
      id = core.ask(nil, 'move my dentist to Thursday')
      waiting = pending_confirmation(id)
      core.answer(id, 'b99', true)
      sleep 0.2
      assert_predicate confirmation(id), :pending?

      core.answer(id, waiting.id, true)
      finished(id)
    end

    context 'when the question hides control bytes' do
      let(:question) { "Move \e[2KDentist?" }

      it 'shows them escaped, under a warning' do
        id = core.ask(nil, 'move my dentist')
        waiting = pending_confirmation(id)
        warning, shown = waiting.question.split("\n\n")
        assert_match(/\A⚠ /, warning)
        assert_equal 'Move \x1b[2KDentist?', shown
        core.answer(id, waiting.id, true)
        finished(id)
      end
    end
  end

  context 'when cancelled while the agent boots' do
    let(:booting) { Thread::Queue.new }
    let(:boot) { Thread::Queue.new }
    let(:core) do
      booting = self.booting
      boot = self.boot
      core_with do
        booting << true
        boot.pop(timeout: 5)
      end
    end

    it 'goes idle at once, and ends in a notice once the boot is over' do
      id = core.ask(nil, 'wrong question')
      booting.pop(timeout: 5) or raise('the agent never booted')
      core.cancel(id)
      refute core.load_conversation(id).activity.running?
      refute core.list_conversations.first.running

      boot << true
      wait_until('the notice shows') { core.load_conversation(id).blocks.last.is_a?(p::Notice) }
      sleep 0.1
      transcript = core.load_conversation(id)
      assert_equal [p::UserMessage, p::Notice], transcript.blocks.map(&:class)
      assert_equal 'Cancelled', transcript.blocks.last.text
      refute transcript.activity.running?
      assert_equal 'idle', drain.grep(p::ActivityChanged).last.activity.state
    end
  end

  it 'forgets a deleted conversation' do
    id = core.ask(nil, 'how do I keep an avocado?')
    finished(id)
    core.delete_conversation(id)
    assert_empty core.list_conversations
    assert_raises(ArgumentError) { core.load_conversation(id) }
  end

  it 'keeps its conversations under XDG_STATE_HOME' do
    Dir.mktmpdir do |state|
      assert_equal "#{state}/puri/conversations", described_class.store(env: { 'XDG_STATE_HOME' => state }).root.to_s
    end
  end

  describe 'saving' do
    # Closes the core, and starts another on the same directory, as Puri starting again would.
    #
    # @param titles [Pikuri::Conversations::Titler] the restarted core's
    # @yieldparam llm [Pikuri::Testing::Script] what the model answers now
    # @return [Puri::Core::PikuriCore]
    def restart(titles = titler, &script)
      core.close
      fake = Pikuri::Testing.fake_transport(&script)
      again = Puri::Core::Models.new([Puri::Core::Models::Choice.new(name: 'Fake', transport: fake)])
      @restarted = described_class.new(config:, models: again, titler: titles,
                                       store: Pikuri::Conversations::Store.new(root: @root, shell: 'puri')) { nil }
    end

    # @param id [String]
    # @return [String, nil] its title on disk
    def saved_title(id) = store.list.find { _1.id == id }&.title

    it 'lists a saved conversation after a restart, shows it, and carries on with it' do
      id = core.ask(nil, 'how do I keep an avocado?')
      finished(id)
      wait_until('the title is saved') { saved_title(id) == 'Keeping An Avocado' }

      again = restart { |llm| llm.stream('Still cold.') }
      summary = again.list_conversations.first
      assert_equal [id, 'Keeping An Avocado', 'how do I keep an avocado?', false],
                   [summary.id, summary.title, summary.last_question, summary.running]
      user, reply = again.load_conversation(id).blocks
      assert_equal p::UserMessage.new(id: 'b1', text: 'how do I keep an avocado?'), user
      assert_equal ['Keep it <b>cold</b>.'], reply.parts.map(&:markup)

      again.ask(id, 'and a cut one?')
      assert_equal [p::UserMessage, p::Reply, p::UserMessage, p::Reply], finished(id, again).blocks.map(&:class)
      assert_equal %w[user assistant user assistant], store.history(store.find(id)).messages.map(&:role)
    end

    it 'saves a cancelled turn too' do
      gate.block!
      id = core.ask(nil, "I'm Bob")
      gate.wait_arrived
      core.cancel(id)
      gate.release!
      finished(id)

      assert_equal [p::UserMessage], restart {}.load_conversation(id).blocks.map(&:class)
    end

    it 'renames the saved conversation once its title arrives' do
      title_gate.block!
      id = core.ask(nil, 'how do I keep an avocado?')
      finished(id)
      assert store.stamp_titled?(store.find(id))

      title_gate.release!
      wait_until('the title is saved') { saved_title(id) == 'Keeping An Avocado' }
    end

    context 'when the titler failed the first time' do
      let(:titles) { [] }

      it 'titles the conversation at its next turn after a restart' do
        id = core.ask(nil, 'how do I keep an avocado?')
        finished(id)
        wait_until('the failure is logged') { Pikuri.log_io.string.include?('titling failed') }

        titled = Pikuri::Testing.fake_transport { |llm| llm.reply('Keeping An Avocado') }
        again = restart(Pikuri::Conversations::Titler.new(transport: titled)) { |llm| llm.stream('Still cold.') }
        assert_equal 'New conversation', again.list_conversations.first.title
        again.ask(id, 'and a cut one?')
        wait_until('the title is saved') { saved_title(id) == 'Keeping An Avocado' }
      end
    end

    context 'when a conversation is deleted while its turn runs' do
      let(:saves) { Thread::Queue.new }
      let(:store) do
        saves = self.saves
        Class.new(Pikuri::Conversations::Store) do
          define_method(:save) { |*args, **kwargs| super(*args, **kwargs).tap { |dir| saves << [dir] } }
        end.new(root: @root, shell: 'puri')
      end

      it 'stays gone: the turn still saves, and that writes nothing' do
        gate.block!
        id = core.ask(nil, 'how do I keep an avocado?')
        gate.wait_arrived
        core.delete_conversation(id)
        gate.release!
        assert_equal [nil], saves.pop(timeout: 5)
        assert_empty Dir.children(@root)
      end
    end

    it 'saves the question of a turn cut short by quitting' do
      gate.block!
      id = core.ask(nil, "I'm Bob")
      gate.wait_arrived
      closing = Thread.new { core.close }
      sleep 0.1
      gate.release!
      closing.join

      first, = restart {}.load_conversation(id).blocks
      assert_equal p::UserMessage.new(id: 'b1', text: "I'm Bob"), first
    end

    it 'deletes a saved conversation never opened' do
      id = core.ask(nil, 'how do I keep an avocado?')
      finished(id)
      restart {}.delete_conversation(id)
      assert_empty Dir.children(@root)
    end

    context 'when a save fails with something other than a SystemCallError' do
      let(:store) do
        Class.new(Pikuri::Conversations::Store) do
          def save(*, **) = raise(JSON::GeneratorError, 'source sequence is illegal/malformed utf-8')
        end.new(root: @root, shell: 'puri')
      end
      let(:script) { ->(llm) { llm.stream('Keep it cold.').stream('Wrap it.') } }

      it 'ends the turn in an error notice, and takes the next question' do
        id = core.ask(nil, 'how do I keep an avocado?')
        notice = finished(id).blocks.last
        assert notice.error
        assert_equal "Can't save this conversation: source sequence is illegal/malformed utf-8", notice.text

        core.ask(id, 'and a cut one?')
        assert_equal [p::UserMessage, p::Reply, p::Notice, p::UserMessage, p::Reply, p::Notice],
                     finished(id).blocks.map(&:class)
      end
    end

    it 'shows a history it cannot read as an error, and never saves over it' do
      id = core.ask(nil, 'how do I keep an avocado?')
      finished(id)
      history = File.join(@root, id, 'history.json')
      File.write(history, 'not json')

      again = restart { |llm| llm.stream('Hello.') }
      notice, = again.load_conversation(id).blocks
      assert notice.error
      assert_match(/\ACan't read this conversation: /, notice.text)
      again.ask(id, 'hello?')
      assert_equal p::Reply, finished(id, again).blocks.last.class
      assert_equal 'not json', File.read(history)
    end

    context 'with a web search' do
      let(:script) { ->(llm) { llm.tool_call('web_search', query: 'avocado').stream('Keep it cold.') } }
      let(:core) do
        search = Pikuri::Tool.new(
          name: 'web_search', description: 'Searches the web.',
          parameters: Pikuri::Tool::Parameters.build { |params| params.required_string :query, 'what to search' },
          execute: ->(query:) { Pikuri::Tool::Result.new(content: "1. #{query} …", summary: 'Returned 1 search result') }
        )
        core_with { |c, _confirmer| c.add_tool(search) }
      end

      it 'shows the search as a line, while it runs and after a restart' do
        id = core.ask(nil, 'how do I keep an avocado?')
        line = p::ToolLine.new(id: 'b2', text: '🔍 Searched: "avocado"', error: false)
        assert_equal [p::UserMessage, p::ToolLine, p::Reply], finished(id).blocks.map(&:class)
        assert_equal line, core.load_conversation(id).blocks[1]
        assert_includes drain.grep(p::ActivityChanged).map { _1.activity.status }, 'Searching the web…'

        assert_equal line, restart { |llm| llm.stream('Still cold.') }.load_conversation(id).blocks[1]
      end
    end
  end
end
