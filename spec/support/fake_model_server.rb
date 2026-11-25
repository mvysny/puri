# frozen_string_literal: true

require 'json'
require 'socket'

# A model server's `GET /v1/models` on 127.0.0.1, answering with what it's given, in the shapes
# `R_llama_models` recorded:
#
#   server = FakeModelServer.new(FakeModelServer.router('Ornith-1.5', 'Qwen3.5-4B'))
#   Puri::Setup::ModelServer.new("#{server.url}/v1", api_key: 'k3y').serves?('Ornith-1.5')   # => true
#   server.requests   # => ["/v1/models Bearer k3y"]
#   server.close
class FakeModelServer
  # @return [String] where it listens
  attr_reader :url

  # @return [Array<String>] each request's path, its key after it
  attr_reader :requests

  # @param ids [Array<String>]
  # @return [String] a llama.cpp router's list
  def self.router(*ids)
    JSON.generate(object: 'list',
                  data: ids.map { { id: _1, aliases: [], owned_by: 'llamacpp', status: { value: 'unloaded' } } })
  end

  # @param id [String]
  # @return [String] a llama-server's of one model, which answers to any name
  def self.single(id) = JSON.generate(object: 'list', data: [{ id:, aliases: [], owned_by: 'llamacpp' }])

  # @param body [String]
  # @param status [String]
  def initialize(body, status: '200 OK')
    @requests = []
    @server = TCPServer.new('127.0.0.1', 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new { loop { serve(@server.accept, body, status) } }
  end

  # @return [void]
  def close
    @thread.kill.join
    @server.close
  end

  private

  # @param client [TCPSocket]
  # @param body [String]
  # @param status [String]
  # @return [void]
  def serve(client, body, status)
    path = client.gets.to_s.split[1]
    key = nil
    while (line = client.gets) && line != "\r\n"
      key = line[/\AAuthorization: (.+)\r\n\z/i, 1] || key
    end
    @requests << [path, key].compact.join(' ')
    client.write("HTTP/1.1 #{status}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  ensure
    client.close
  end
end
