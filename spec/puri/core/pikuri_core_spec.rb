# frozen_string_literal: true

require 'pikuri/testing'
require 'stringio'
require 'tmpdir'

# The real pikuri loop against a scripted HTTP backend (`Pikuri::Testing`): no server, no mocks.
RSpec.describe Puri::Core::PikuriCore do
  p = Puri::Protocol

  # A gate that also says when a turn has reached the model: `await` runs inside each HTTP call,
  # after `run_loop` has reset the agent's Cancellable.
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
    Puri::Core::Titler.new(transport: titled, params_declared: true)
  end
  let(:store) { Puri::Core::Store.new(root: @root) }
  let(:core) { described_class.new(transport:, titler:, store:) { |event| events << p.round_trip(event) } }

  # The context-window probe dials the fake's `.invalid` host and warns that it failed.
  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
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

  # @param id [String]
  # @return [String]
  def title(id) = core.list_conversations.find { _1.id == id }.title

  it 'titles a new conversation while its first answer is still coming' do
    gate.block!
    id = core.ask(nil, 'how do I keep an avocado?')
    assert_equal 'New conversation', drain.grep(p::ConversationsChanged).first.conversations.first.title
    wait_until('the title arrives') { title(id) == 'Keeping An Avocado' }
    assert_predicate core.load_conversation(id).activity, :running?
  end

  context 'when the titler fails' do
    let(:titles) { [] }

    it 'logs it and keeps the name' do
      id = core.ask(nil, 'how do I keep an avocado?')
      wait_until('the failure is logged') { Pikuri.log_io.string.include?("can't title conversation #{id}") }
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

    it 'holds a message sent during a turn until that turn ends' do
      gate.block!
      id = core.ask(nil, "I'm Bob")
      gate.wait_arrived
      core.ask(id, "what's my name?")
      assert_equal [p::UserMessage], core.load_conversation(id).blocks.map(&:class)

      gate.release!
      wait_until('both turns end') { core.load_conversation(id).blocks.size == 4 }
      assert_equal "what's my name?", finished(id).blocks[2].text
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

    after { Pikuri::Agent::ServerPermits.reset! }

    it 'runs conversations on the first [[llm]]' do
      id = core.ask(nil, 'hi')
      assert_match %r{\ACan't reach the model at http://127\.0\.0\.1:9/v1: }, finished(id).blocks.last.text
    end

    it 'limits the servers that state max_concurrent_requests, and only those' do
      core
      assert_equal({ 'http://127.0.0.1:9' => 2 }, Pikuri::Agent::ServerPermits.sizes)
    end
  end

  context 'with a tool that asks before it acts' do
    let(:observations) { [] }
    let(:question) { 'Move “Dentist” (Personal) to Thursday 15:00?' }
    let(:script) { ->(llm) { llm.tool_call('move_event', question:).stream('Done.') } }
    let(:core) do
      tools = lambda do |confirmer|
        [Pikuri::Tool.new(
          name: 'move_event', description: 'Moves a calendar event.',
          parameters: Pikuri::Tool::Parameters.build { |params| params.required_string :question, 'what to ask' },
          execute: lambda { |question:|
            request = Pikuri::Workspace::Confirmer::Request.new(question:)
            result = case decision = confirmer.ask(request:)
                     in Pikuri::Workspace::Confirmer::Approved then Pikuri::Tool::Result.new(content: 'Moved.',
                                                                                             summary: 'Moved')
                     else decision.observation('the move')
                     end
            observations << result.content
            result
          }
        )]
      end
      described_class.new(transport:, titler:, store:, tools:) { |event| events << p.round_trip(event) }
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
      assert_equal [p::UserMessage, p::Confirmation, p::Reply], finished(id).blocks.map(&:class)
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
      assert_equal [p::UserMessage, p::Confirmation, p::UserMessage, p::Reply], blocks.map(&:class)
      assert_equal 'redirected', confirmation(id).state
      assert_equal ['The user declined the move and said: make it Wednesday'], observations
    end

    it 'ends the turn when it is cancelled while the question waits' do
      id = core.ask(nil, 'move my dentist to Thursday')
      pending_confirmation(id)
      core.cancel(id)
      assert_equal [p::UserMessage, p::Confirmation, p::Notice], finished(id).blocks.map(&:class)
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

  it 'forgets a deleted conversation' do
    id = core.ask(nil, 'how do I keep an avocado?')
    finished(id)
    core.delete_conversation(id)
    assert_empty core.list_conversations
    assert_raises(ArgumentError) { core.load_conversation(id) }
  end

  describe 'saving' do
    # Closes the core, and starts another on the same directory, as Puri starting again would.
    #
    # @yieldparam llm [Pikuri::Testing::Script] what the model answers now
    # @return [Puri::Core::PikuriCore]
    def restart(&script)
      core.close
      @restarted = described_class.new(transport: Pikuri::Testing.fake_transport(&script), titler:,
                                       store: Puri::Core::Store.new(root: @root)) { |_event| nil }
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
      assert_equal %w[user assistant user assistant], store.history(id).messages.map(&:role)
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

    it 'saves the title whether it comes before the first save or after' do
      gate.block!
      early = core.ask(nil, 'how do I keep an avocado?')
      wait_until('the title arrives') { title(early) == 'Keeping An Avocado' }
      gate.release!
      finished(early)
      assert_equal 'Keeping An Avocado', saved_title(early)
    end

    context 'when the title comes after the first save' do
      it 'renames the saved conversation' do
        title_gate.block!
        id = core.ask(nil, 'how do I keep an avocado?')
        finished(id)
        assert_equal 'New conversation', saved_title(id)

        title_gate.release!
        wait_until('the title is saved') { saved_title(id) == 'Keeping An Avocado' }
      end
    end

    it 'deletes a conversation from disk, and a turn still ending does not write it back' do
      gate.block!
      id = core.ask(nil, 'how do I keep an avocado?')
      gate.wait_arrived
      core.delete_conversation(id)
      gate.release!
      sleep 0.2
      assert_empty Dir.children(@root)
    end

    it 'deletes a saved conversation never opened' do
      id = core.ask(nil, 'how do I keep an avocado?')
      finished(id)
      restart {}.delete_conversation(id)
      assert_empty Dir.children(@root)
    end

    context 'when a save fails with something other than a SystemCallError' do
      let(:store) do
        Class.new(Puri::Core::Store) do
          def save(*, **) = raise(JSON::GeneratorError, 'source sequence is illegal/malformed utf-8')
        end.new(root: @root)
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
  end
end
