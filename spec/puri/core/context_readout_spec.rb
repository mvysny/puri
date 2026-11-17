# frozen_string_literal: true

require 'stringio'

RSpec.describe Puri::Core::ContextReadout do
  e = Pikuri::Agent::Event
  c = Pikuri::Conversations::Event

  # @param input [Integer]
  # @param output [Integer]
  # @param cached [Integer]
  # @return [Pikuri::Agent::Event::Tokens]
  def tokens(input, output, cached: 0)
    Pikuri::Agent::Event::Tokens.new(input:, output:, cached:, cache_creation: nil, thinking: nil, model_id: 'm')
  end

  let(:readout) { described_class.new(cap: 65_536) }

  # TokenLog logs each count.
  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    example.run
  ensure
    Pikuri.log_io = log
  end

  it 'shows the window alone until a reply is counted' do
    assert_equal Puri::Protocol::Status.new(model: 'M', context: '64.0k token window'), readout.status('M')
    assert_equal Puri::Protocol::Status.new(model: 'M'), described_class.new.status('M')
  end

  it 'counts each reply against the window' do
    assert readout.on_event(tokens(6000, 500))
    assert readout.on_event(tokens(1024, 1024, cached: 6500))
    status = readout.status('M')
    assert_equal ['8.3k of 64.0k tokens', 'msg #2  Δ+2.0k  ↑1.0k  ↓1.0k'], [status.context, status.detail]
    assert_in_delta 8548.0 / 65_536, status.fill
  end

  it 'picks up a restored count, and starts over at a boot' do
    readout.on_event(e::HistoryLoaded.new(messages: 4, tokens: tokens(2048, 0)))
    assert_equal ['2.0k of 64.0k tokens', 'restored'], readout.status('M').to_h.values_at(:context, :detail)
    readout.on_event(c::Booting.new)
    assert_equal '64.0k token window', readout.status('M').context
  end

  it 'takes the window the gem learns, and ignores the rest' do
    assert readout.on_event(c::ContextCap.new(cap: nil))
    readout.on_event(tokens(1024, 0))
    assert_equal ['1.0k tokens', nil], readout.status('M').to_h.values_at(:context, :fill)
    refute readout.on_event(e::AssistantDelta.new(content: 'x'))
  end
end
