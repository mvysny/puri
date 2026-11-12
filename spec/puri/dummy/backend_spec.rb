# frozen_string_literal: true

RSpec.describe Puri::Dummy::Backend do
  p = Puri::Protocol

  let(:events) { Thread::Queue.new }
  let(:pace) { 0 }
  let(:core) { described_class.new(think: 0, pace:, title_delay: 0) { |event| events << p.round_trip(event) } }
  after { core.close }

  # Waits for Core's threads, the way a UI waits for events.
  #
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

  # @param id [String]
  # @return [Puri::Protocol::Confirmation] the one waiting
  def pending_confirmation(id)
    wait_until('a confirmation waits') { core.load_conversation(id).activity.state == 'confirming' }
    core.load_conversation(id).blocks.grep(Puri::Protocol::Confirmation).find(&:pending?)
  end

  # @return [Array<Data>] every event emitted so far
  def drain = Array.new(events.size) { events.pop }

  it 'implements every Backend method' do
    p::Backend.instance_methods.each do |name|
      refute_equal p::Backend, described_class.instance_method(name).owner, "#{name} is not implemented"
    end
  end

  it 'starts a conversation, streams the answer, then names it' do
    id = core.ask(nil, 'how do I keep an avocado?')
    transcript = finished(id)
    user, reply = transcript.blocks
    assert_equal p::UserMessage.new(id: 'b1', text: 'how do I keep an avocado?'), user
    assert_includes reply.parts.first.markup, '<b>short answer</b>'
    wait_until('the title lands') { core.list_conversations.first.title == 'How do I keep an avocado' }

    seen = drain
    states = seen.grep(p::ActivityChanged).map { _1.activity.state }
    assert_equal %w[working working streaming idle], states.chunk_while { _1 == _2 && _1 != 'working' }.map(&:first)
    replies = seen.grep(p::BlockChanged).select { _1.block.id == reply.id }
    assert_operator replies.size, :>, 10, 'a reply streams, re-sent per word'
    assert(seen.grep(p::ConversationsChanged).any? { _1.conversations.first.running })
  end

  it 'continues the conversation it is given' do
    id = core.ask(nil, 'hi')
    finished(id)
    assert_equal id, core.ask(id, 'and again')
    assert_equal(['hi', 'and again'], finished(id).blocks.grep(p::UserMessage).map(&:text))
    assert_equal 'and again', core.list_conversations.first.last_question
  end

  it 'searches, then answers' do
    id = core.ask(nil, 'search for avocado tips')
    tool = finished(id).blocks.grep(p::ToolLine).first
    assert_equal '🔍 Searched: "avocado tips"', tool.text
  end

  context 'with a confirmation pending' do
    let(:id) { core.ask(nil, 'reschedule my dentist in the calendar') }
    let!(:confirmation) { pending_confirmation(id) }

    it 'asks naming the calendar, destructively' do
      assert_includes confirmation.question, 'Personal calendar'
      assert_equal 'Update', confirmation.approve_label
      assert confirmation.destructive
    end

    it 'carries on when approved' do
      core.answer(id, confirmation.id, true)
      blocks = finished(id).blocks
      assert_equal 'approved', blocks.find { _1.id == confirmation.id }.state
      assert_includes blocks.last.parts.first.markup, 'Done.'
    end

    it "says it won't when rejected" do
      core.answer(id, confirmation.id, false)
      blocks = finished(id).blocks
      assert_equal 'rejected', blocks.find { _1.id == confirmation.id }.state
      assert_includes blocks.last.parts.first.markup, 'won’t make any changes'
    end

    it 'follows typed words and asks again' do
      core.ask(id, 'make it Wednesday')
      wait_until('it asks again') { pending_confirmation(id)&.id != confirmation.id }
      blocks = core.load_conversation(id).blocks
      assert_equal 'redirected', blocks.find { _1.id == confirmation.id }.state
      assert_includes blocks.grep(p::UserMessage).map(&:text), 'make it Wednesday'
      assert_includes pending_confirmation(id).question, 'Wednesday 10:00'
    end

    it 'ignores an answer to a confirmation already answered' do
      core.answer(id, confirmation.id, false)
      finished(id)
      core.answer(id, confirmation.id, true)
      assert_equal 'rejected', core.load_conversation(id).blocks.find { _1.id == confirmation.id }.state
    end

    it 'ends it as cancelled on Cancel' do
      core.cancel(id)
      blocks = finished(id).blocks
      assert_equal 'cancelled', blocks.find { _1.id == confirmation.id }.state
      assert_equal p::Notice.new(id: blocks.last.id, text: 'Cancelled', error: false), blocks.last
    end
  end

  context 'with a slow stream' do
    let(:pace) { 0.01 }

    it 'cancels mid-answer and keeps what streamed' do
      id = core.ask(nil, 'something long')
      wait_until('words arrive') do
        core.load_conversation(id).blocks.grep(p::Reply).first&.parts&.first&.markup.to_s.include?('Part 1.')
      end
      core.cancel(id)
      blocks = finished(id).blocks
      assert_includes blocks.grep(p::Reply).first.parts.first.markup, 'Part 1.'
      assert_equal 'Cancelled', blocks.last.text
    end

    it 'holds a message sent while it works until the turn ends' do
      id = core.ask(nil, 'hi')
      core.ask(id, 'and then?')
      assert_equal 1, core.load_conversation(id).blocks.grep(p::UserMessage).size
      wait_until('the second turn ends') { finished(id).blocks.grep(p::UserMessage).size == 2 }
      assert_kind_of p::Reply, finished(id).blocks.last
    end
  end

  it 'reports a failed turn' do
    id = core.ask(nil, 'please fail')
    notice = finished(id).blocks.last
    assert notice.error
    assert_includes notice.text, 'llama-server'
  end

  it 'kills its running turns on close, and the message that waited for one' do
    core = described_class.new(think: 5, title_delay: 5) { |_| nil }
    before = Thread.list
    id = core.ask(nil, 'hi')
    core.ask(id, 'and then?')
    refute_empty Thread.list - before
    core.close
    assert_empty Thread.list - before
  end

  it 'deletes a conversation' do
    id = core.ask(nil, 'hi')
    finished(id)
    core.delete_conversation(id)
    assert_empty core.list_conversations
    err = assert_raises(ArgumentError) { core.load_conversation(id) }
    assert_includes err.message, id
  end

  it 'starts with earlier conversations when seeded, newest first' do
    core = described_class.new(seed: true) { |_| nil }
    seeded = core.list_conversations
    core.close
    assert_equal ['When is the dentist', 'What is on my shopping note', 'How do I keep an avocado'], seeded.map(&:title)
    refute(seeded.any?(&:running))
    assert_equal 'when is the dentist?', seeded.first.last_question
  end
end
