# frozen_string_literal: true

require 'socket'
require 'uri'

# OpenStreetMap's services as a local HTTP server: each path answers with a fixture recorded from
# the real one (`spec/fixtures/places/`), and every request is kept.
#
#   osm = FakeOsm.new
#   osm.answer('/api/', 'photon-jumbo.json', q: 'Jumbo Vantaa')   # only for that query
#   osm.answer('/route/', 'osrm-route.json')
#   osm.places                       # => a Puri::Core::Places::Osm on it, unpaced
#   osm.requests.last.query          # => {"q" => "Jumbo Vantaa", "limit" => "1"}
#   osm.close
#
# An answer keyed by query wins over one that isn't; a path nothing answers gets a 404.
class FakeOsm
  # One request as the server read it.
  #
  # @!attribute [r] path
  #   @return [String]
  # @!attribute [r] query
  #   @return [Hash{String => String}]
  # @!attribute [r] user_agent
  #   @return [String, nil]
  class Request < Data.define(:path, :query, :user_agent); end

  # @return [String]
  FIXTURES = File.expand_path('../fixtures/places', __dir__)

  def initialize
    @server = TCPServer.new('127.0.0.1', 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @lock = Mutex.new
    @answers = []
    @requests = []
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  # @return [String] the base URL every service is at; still answers once closed, for a core built late
  attr_reader :url

  # @param path [String] a prefix of the request's path
  # @param fixture [String, nil] a file in {FIXTURES}
  # @param status [Integer]
  # @param body [String, nil] in place of a fixture
  # @param query [Hash{Symbol => String}] parameters the request must carry
  # @return [void]
  def answer(path, fixture = nil, status: 200, body: nil, **query)
    body ||= File.read(File.join(FIXTURES, fixture))
    @lock.synchronize { @answers << [path, query.transform_keys(&:to_s), status, body] }
  end

  # @return [Array<FakeOsm::Request>]
  def requests = @lock.synchronize { @requests.dup }

  # @param interval [Float] between two requests to it
  # @return [Puri::Core::Places::Osm] on this server
  def places(interval: 0)
    Puri::Core::Places::Osm.new(http: Puri::Core::Places::Http.new(interval:), photon: url, nominatim: url, osrm: url)
  end

  # @return [void]
  def close
    @thread.kill
    @server.close
  end

  private

  # @param client [TCPSocket]
  # @return [void]
  def serve(client)
    target = client.gets.to_s.split[1].to_s
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(':', 2)
      headers[name.downcase] = value.to_s.strip
    end
    path, query = target.split('?', 2)
    query = URI.decode_www_form(query.to_s).to_h
    status, body = @lock.synchronize do
      @requests << Request.new(path:, query:, user_agent: headers['user-agent'])
      found = @answers.select { |prefix, wanted, _, _| path.start_with?(prefix) && wanted <= query }
                      .max_by { |_, wanted, _, _| wanted.size }
      found ? found.last(2) : [404, '{"error":"no fixture"}']
    end
    client.write("HTTP/1.1 #{status} Fake\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n" \
                 "Connection: close\r\n\r\n#{body}")
  ensure
    client.close
  end
end
