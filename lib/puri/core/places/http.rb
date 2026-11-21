# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

module Puri
  module Core
    module Places
      # GETs JSON from OpenStreetMap's public services as their terms ask: Puri's own User-Agent,
      # at most one request a second to each host, and answers cached.
      #
      #   http = Http.new
      #   http.get_json('https://photon.komoot.io/api/?q=Jumbo', cancellable:)   # => {"features" => […]}
      #
      # A cached answer costs no request and no wait. A request to a host asked less than an
      # interval ago waits its turn on `cancellable`, so a cancel lands during the wait.
      #
      # Thread-safe: one per process, or two agents would each send their own one a second.
      class Http
        # A request that failed: the network, a timeout, a status other than 200, or a body that
        # isn't JSON. Its message says which host, and why.
        class Error < StandardError; end

        # @param interval [Float] seconds between two requests to one host
        # @param cache_size [Integer] answers kept, the least recently used dropped first
        # @param timeout [Integer] seconds to connect, and again to read
        def initialize(interval: 1.0, cache_size: 256, timeout: 10)
          @interval = interval
          @cache_size = cache_size
          @timeout = timeout
          @lock = Mutex.new
          @cache = {}
          @next_slot = Hash.new(0.0)
        end

        # @param url [String]
        # @param cancellable [Pikuri::Agent::Control::Cancellable] the turn's
        # @return [Hash{String => Object}, Array<Object>] the parsed JSON
        # @raise [Error]
        # @raise [Pikuri::Agent::Control::Cancellable::Cancelled] when cancelled while it waits
        def get_json(url, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
          cached = @lock.synchronize { hit(url) }
          return cached if cached

          uri = URI(url)
          cancellable.sleep(reserve(uri.host) - now)
          fetch(uri).tap { |json| @lock.synchronize { remember(url, json) } }
        end

        private

        # Books the host's next free slot, so two callers waiting at once go a second apart.
        #
        # @param host [String]
        # @return [Float] when this request may go, on the monotonic clock
        def reserve(host)
          @lock.synchronize do
            slot = [now, @next_slot[host]].max
            @next_slot[host] = slot + @interval
            slot
          end
        end

        # @param uri [URI::HTTP]
        # @return [Hash{String => Object}, Array<Object>]
        # @raise [Error]
        def fetch(uri)
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: @timeout,
                                                         read_timeout: @timeout) do |http|
            http.get(uri.request_uri, 'User-Agent' => USER_AGENT, 'Accept' => 'application/json')
          end
          unless response.code == '200'
            raise Error, "#{uri.host} answered HTTP #{response.code}#{reason(response.body)}"
          end

          # Frozen: the cache hands the same answer to every caller.
          JSON.parse(response.body, freeze: true)
        rescue JSON::ParserError => e
          raise Error, "#{uri.host} answered with no JSON: #{e.message[0, 80]}"
        rescue SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
          raise Error, "can't reach #{uri.host}: #{e.message}"
        end

        # OSRM and Nominatim say what was wrong in a JSON `message` or `error`.
        #
        # @param body [String, nil]
        # @return [String] ": the message", or "" for none
        def reason(body)
          json = JSON.parse(body.to_s)
          said = json['message'] || json['error'] if json.is_a?(Hash)
          said.is_a?(String) ? ": #{said[0, 200]}" : ''
        rescue JSON::ParserError
          ''
        end

        # @param url [String]
        # @return [Hash{String => Object}, Array<Object>, nil] moved to the most recently used
        def hit(url)
          json = @cache.delete(url) or return nil
          @cache[url] = json
        end

        # @param url [String]
        # @param json [Hash{String => Object}, Array<Object>]
        # @return [void]
        def remember(url, json)
          @cache.delete(url)
          @cache[url] = json
          @cache.delete(@cache.each_key.first) while @cache.size > @cache_size
        end

        # @return [Float]
        def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
