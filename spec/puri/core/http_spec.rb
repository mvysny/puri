# frozen_string_literal: true

RSpec.describe Puri::Core::Http do
  let(:osm) { FakeOsm.new }
  let(:http) { described_class.new(interval: 0) }

  after { osm.close }

  # @return [Float]
  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  it 'names Puri, with its contact, in every request' do
    osm.answer('/x', body: '{"a":1}')
    assert_equal({ 'a' => 1 }, http.get_json("#{osm.url}/x"))
    assert_equal 'Puri (+https://github.com/mvysny/puri)', osm.requests.last.user_agent
  end

  it 'asks once for the same URL, and hands out a frozen answer' do
    osm.answer('/x', body: '{"a":[1]}')
    first = http.get_json("#{osm.url}/x?q=1")
    assert_same first, http.get_json("#{osm.url}/x?q=1")
    assert_equal 1, osm.requests.size
    assert first.frozen? && first['a'].frozen?
  end

  it 'drops the least recently used answer beyond its size' do
    osm.answer('/x', body: '{}')
    small = described_class.new(interval: 0, cache_size: 2)
    %w[1 2 1 3 1 2].each { small.get_json("#{osm.url}/x?q=#{_1}") }
    assert_equal(%w[1 2 3 2], osm.requests.map { _1.query['q'] })
  end

  it 'asks again once a cached answer is older than its max_age' do
    osm.answer('/x', body: '{}')
    seconds = 100.0
    timed = described_class.new(interval: 0, clock: -> { seconds })
    timed.get_json("#{osm.url}/x", max_age: 60)
    seconds += 60
    timed.get_json("#{osm.url}/x", max_age: 60)
    assert_equal 1, osm.requests.size
    seconds += 1
    timed.get_json("#{osm.url}/x", max_age: 60)
    timed.get_json("#{osm.url}/x")
    assert_equal 2, osm.requests.size, 'a fresh answer is cached anew; no max_age takes any'
  end

  it 'keeps a second apart, or what it is given, between two requests to one host' do
    osm.answer('/x', body: '{}')
    paced = described_class.new(interval: 0.3)
    started = now
    paced.get_json("#{osm.url}/x?q=1")
    paced.get_json("#{osm.url}/x?q=2")
    assert_operator now - started, :>=, 0.29
  end

  it 'gives up a wait for its turn on a cancel' do
    osm.answer('/x', body: '{}')
    paced = described_class.new(interval: 30)
    paced.get_json("#{osm.url}/x?q=1")
    cancellable = Pikuri::Agent::Control::Cancellable.new
    cancellable.cancel!
    assert_raises(Pikuri::Agent::Control::Cancellable::Cancelled) do
      paced.get_json("#{osm.url}/x?q=2", cancellable:)
    end
    assert_equal 1, osm.requests.size
  end

  it 'says what the service said was wrong' do
    osm.answer('/x', status: 400, body: '{"code":"InvalidQuery","message":"Query string malformed"}')
    error = assert_raises(described_class::Error) { http.get_json("#{osm.url}/x") }
    assert_equal '127.0.0.1 answered HTTP 400: Query string malformed', error.message
  end

  it 'says what Open-Meteo said was wrong, beside its "error": true' do
    osm.answer('/x', status: 400, body: '{"error":true,"reason":"Forecast days is invalid."}')
    error = assert_raises(described_class::Error) { http.get_json("#{osm.url}/x") }
    assert_equal '127.0.0.1 answered HTTP 400: Forecast days is invalid.', error.message
  end

  it 'fails on a body that is no JSON, and caches nothing' do
    osm.answer('/x', body: '<html>busy</html>')
    2.times { assert_raises(described_class::Error) { http.get_json("#{osm.url}/x") } }
    assert_equal 2, osm.requests.size
  end

  it 'fails on a host it can’t reach' do
    closed = TCPServer.new('127.0.0.1', 0)
    port = closed.addr[1]
    closed.close
    error = assert_raises(described_class::Error) { http.get_json("http://127.0.0.1:#{port}/x") }
    assert_match(/\Acan't reach 127\.0\.0\.1: /, error.message)
  end
end
