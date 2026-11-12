# frozen_string_literal: true

require 'pikuri/testing'
require 'stringio'

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
  let(:core) { described_class.new(transport:) { |event| events << p.round_trip(event) } }

  # The context-window probe dials the fake's `.invalid` host and warns that it failed.
  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    example.run
  ensure
    gate.release!
    core.close
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
  # @return [Puri::Protocol::Transcript] once the turn is over
  def finished(id)
    wait_until('the turn ends') { !core.load_conversation(id).activity.running? }
    core.load_conversation(id)
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

    seen = drain
    assert_equal %w[working streaming idle], seen.grep(p::ActivityChanged).map { _1.activity.state }.uniq
    assert_equal 'New conversation', seen.grep(p::ConversationsChanged).last.conversations.first.title
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

  it 'forgets a deleted conversation' do
    id = core.ask(nil, 'how do I keep an avocado?')
    finished(id)
    core.delete_conversation(id)
    assert_empty core.list_conversations
    assert_raises(ArgumentError) { core.load_conversation(id) }
  end
end
