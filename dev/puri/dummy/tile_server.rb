# frozen_string_literal: true

require 'socket'

module Puri
  module Dummy
    # Answers every tile a map asks for with the same grid square, from 127.0.0.1, so the dummy's
    # maps draw with no network: libshumate fetches tiles over HTTP only, never from a file.
    #
    #   TileServer.url   # => "http://127.0.0.1:41233/{z}/{x}/{y}.png"; started on first use
    #
    # Thread-safe.
    module TileServer
      # @return [String] a 256 px PNG
      TILE = File.binread(File.join(__dir__, 'tile.png'))

      @lock = Mutex.new
      @url = nil

      # @return [String] the tile URL template a {Protocol::Map} takes
      def self.url = @lock.synchronize { @url ||= start }

      # @return [String]
      def self.start
        server = TCPServer.new('127.0.0.1', 0)
        Thread.new { loop { serve(server.accept) } }
        "http://127.0.0.1:#{server.addr[1]}/{z}/{x}/{y}.png"
      end

      # @param client [TCPSocket]
      # @return [void]
      def self.serve(client)
        nil while (line = client.gets) && line != "\r\n"
        client.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{TILE.bytesize}\r\n" \
                     "Connection: close\r\n\r\n", TILE)
      rescue IOError, SystemCallError => e
        warn "dummy tile server: #{e.message}"
      ensure
        client.close
      end

      private_class_method :start, :serve
    end
  end
end
