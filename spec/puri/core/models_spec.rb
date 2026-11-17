# frozen_string_literal: true

RSpec.describe Puri::Core::Models do
  let(:thinking) { Pikuri::Agent::ChatTransport.from_openai_server(server: 'http://box:8080', model: 'm') }
  let(:quiet) { thinking.with(params: { 'enable_thinking' => false }) }
  let(:models) do
    described_class.new([described_class::Choice.new(name: 'M', transport: thinking),
                         described_class::Choice.new(name: 'M, quiet', transport: quiet)])
  end

  it 'names a transport by its connection, params included, whatever its window' do
    assert_equal 'M, quiet', models.name_for(quiet.with(context_window: 4096))
    assert_equal 'M', models.name_for(thinking)
    assert_equal 'gone', models.name_for(thinking.with(model: 'gone'))
  end

  it 'resumes a saved conversation on the first connection with its model and server' do
    entry = Pikuri::Conversations::Store::Entry.new(id: 'c1', dir: '/x', title: 't', created_at: Time.now,
                                                    supported: true, model: 'm', server: thinking.api_base)
    assert_equal 'M', models.saved(entry).name
    assert_nil models.saved(entry.with(server: 'http://elsewhere'))
  end

  it 'finds by name, and refuses one it lacks' do
    assert_same quiet, models.find('M, quiet').transport
    assert_raises(ArgumentError) { models.find('nope') }
    assert_raises(ArgumentError) { described_class.new([]) }
  end
end
