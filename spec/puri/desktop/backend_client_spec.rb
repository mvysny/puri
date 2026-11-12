# frozen_string_literal: true

require 'gtk_helper'

RSpec.describe 'Puri::Desktop::BackendClient' do
  p = Puri::Protocol

  let(:core) { Puri::Dummy::Backend.new(think: 0, pace: 0, title_delay: 0) { |event| client.deliver(event) } }
  let(:client) { Puri::Desktop::BackendClient.new(core) }

  after { core.close }

  it 'implements every Backend method' do
    p::Backend.instance_methods.each do |name|
      refute_equal p::Backend, Puri::Desktop::BackendClient.instance_method(name).owner, "#{name} is not implemented"
    end
  end

  it "hands Core's events to subscribers on the main loop, as copies" do
    seen = []
    client.subscribe { seen << [_1, Thread.current] }
    id = client.ask(nil, 'hi')
    wait_until('the turn ends') { seen.any? { |event, _| event.is_a?(p::ActivityChanged) && !event.activity.running? } }
    assert(seen.all? { |_, thread| thread == Thread.main })
    assert(seen.grep(Array).map(&:first).select { _1.respond_to?(:conversation) }.all? { _1.conversation == id })
  end

  it 'returns copies, never the objects Core holds' do
    id = client.ask(nil, 'hi')
    refute_same core.list_conversations.first.title, client.list_conversations.first.title
    assert_equal core.load_conversation(id).conversation, client.load_conversation(id).conversation
  end
end
