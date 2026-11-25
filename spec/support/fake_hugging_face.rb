# frozen_string_literal: true

require 'digest'
require 'json'
require 'socket'

# Hugging Face for `Puri::Setup::HubDownload`, on 127.0.0.1: the API's listing of a repo, and
# `resolve/`, which redirects to `/cdn/` as the real one redirects to its CDN, and answers a
# `Range` with the rest of the file.
#
#   hf = FakeHuggingFace.new({ 'ggml-org/Tiny-GGUF' => { 'Tiny-Q4_K_M.gguf' => 'GGUF tiny' } })
#   Puri::Setup::HubDownload.new(cache, env: { 'HF_ENDPOINT' => hf.url })
#   hf.requests   # => ["/api/models/ggml-org/Tiny-GGUF?blobs=true", "/ggml-org/Tiny-GGUF/resolve/…", "/cdn/… bytes=4-"]
#   hf.close
#
# `damaged:` serves those files with their last byte changed, under the right SHA-256; `ranges:
# false` answers a `Range` with the whole file, as a server that ignores it does.
class FakeHuggingFace
  # @return [String]
  COMMIT = 'c0ffee0123456789abcdef0123456789abcdef01'

  # @return [String] where the server listens
  attr_reader :url

  # @param repos [Hash{String => Hash{String => String}}] each repo's files and their contents
  # @param damaged [Array<String>] files served altered
  # @param ranges [Boolean] whether it honours `Range`
  def initialize(repos, damaged: [], ranges: true)
    @repos = repos
    @damaged = damaged
    @ranges = ranges
    @requests = Queue.new
    @server = TCPServer.new('127.0.0.1', 0)
    @url = "http://127.0.0.1:#{@server.addr[1]}"
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  # @return [Array<String>] each request's path, a `Range` after it, in order
  def requests
    list = []
    list << @requests.pop until @requests.empty?
    list.each { @requests << _1 }
    list
  end

  # @return [void]
  def close
    @thread.kill.join
    @server.close
  end

  private

  # @param client [TCPSocket]
  # @return [void]
  def serve(client)
    path = client.gets.to_s.split[1]
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(':', 2)
      headers[name.downcase] = value.strip
    end
    range = headers['range'][/\Abytes=(\d+)-\z/, 1]&.to_i if headers['range']
    @requests << [path, headers['range']].compact.join(' ')
    client.write(answer(path, range))
  rescue IOError, SystemCallError
    nil # the client went away mid-answer, as a stopped download does
  ensure
    client.close
  end

  # @param path [String]
  # @param range [Integer, nil] the first byte asked for
  # @return [String] the whole HTTP response
  def answer(path, range)
    case path
    when %r{\A/api/models/([^/]+/[^/?]+)\?blobs=true\z}
      files = @repos[Regexp.last_match(1)] or return response('404 Not Found', '{"error":"Repository not found"}')
      response('200 OK', JSON.generate(sha: COMMIT, siblings: siblings(files)))
    when %r{\A/([^/]+/[^/]+)/resolve/#{COMMIT}/(.+)\z}o
      response('302 Found', '', 'Location' => "/cdn/#{Regexp.last_match(1)}/#{Regexp.last_match(2)}")
    when %r{\A/cdn/([^/]+/[^/]+)/(.+)\z}
      content = @repos.fetch(Regexp.last_match(1)).fetch(Regexp.last_match(2))
      content = "#{content[0...-1]}#{(content[-1].ord ^ 1).chr}" if @damaged.include?(Regexp.last_match(2))
      return response('200 OK', content) unless range && @ranges

      response('206 Partial Content', content.byteslice(range..),
               'Content-Range' => "bytes #{range}-#{content.bytesize - 1}/#{content.bytesize}")
    else response('404 Not Found', '')
    end
  end

  # @param files [Hash{String => String}]
  # @return [Array<Hash{Symbol => Object}>] as the API lists them
  def siblings(files)
    files.map do |name, content|
      { rfilename: name, size: content.bytesize, lfs: { sha256: Digest::SHA256.hexdigest(content), size: content.bytesize } }
    end
  end

  # @param status [String]
  # @param body [String]
  # @param headers [Hash{String => String}]
  # @return [String]
  def response(status, body, headers = {})
    head = { 'Content-Length' => body.bytesize, 'Connection' => 'close', **headers }.map { "#{_1}: #{_2}\r\n" }.join
    "HTTP/1.1 #{status}\r\n#{head}\r\n#{body}"
  end
end
