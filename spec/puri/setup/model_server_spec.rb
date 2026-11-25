# frozen_string_literal: true

require 'socket'
require_relative '../../support/fake_model_server'

RSpec.describe Puri::Setup::ModelServer do
  # @param body [String]
  # @param status [String]
  # @yieldparam server [FakeModelServer]
  # @return [void]
  def serving(body, status: '200 OK')
    server = FakeModelServer.new(body, status:)
    yield server
  ensure
    server&.close
  end

  it 'serves what its list names, by id or alias, asking once with the key' do
    body = JSON.generate(data: [{ id: 'Ornith-1.5', aliases: ['ornith'] }, { id: 'Qwen3.5-4B' }])
    serving(body) do |fake|
      server = described_class.new("#{fake.url}/v1/", api_key: 'k3y')
      assert server.serves?('Ornith-1.5')
      assert server.serves?('ornith')
      refute server.serves?('Granite-4.2-3B')
      assert_equal %w[Ornith-1.5 Qwen3.5-4B], server.models
      assert_equal ['/v1/models Bearer k3y'], fake.requests
    end
  end

  it 'serves any model on a llama-server of one, but not on a router of one' do
    serving(FakeModelServer.single('SmolLM2-135M-Q4_K_M.gguf')) do |fake|
      assert described_class.new(fake.url).serves?('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M')
      assert_equal ['/v1/models'], fake.requests, 'no key, no Authorization'
    end
    serving(FakeModelServer.router('Ornith-1.5')) do |fake|
      refute described_class.new(fake.url).serves?('Qwen3.5-4B')
    end
  end

  it "says why it can't ask" do
    port = TCPServer.open('127.0.0.1', 0) { _1.addr[1] }
    err = assert_raises(described_class::Error) { described_class.new("http://127.0.0.1:#{port}").models }
    assert_equal 'connection refused', err.message
    serving('', status: '404 Not Found') do |fake|
      err = assert_raises(described_class::Error) { described_class.new(fake.url).models }
      assert_equal 'it answered 404 Not Found', err.message
    end
    serving('<html>') do |fake|
      err = assert_raises(described_class::Error) { described_class.new(fake.url).models }
      assert_equal "its answer to /v1/models isn't JSON", err.message
    end
    serving('{"data": 3}') do |fake|
      err = assert_raises(described_class::Error) { described_class.new(fake.url).models }
      assert_equal 'its answer to /v1/models is no list of models', err.message
    end
  end
end
