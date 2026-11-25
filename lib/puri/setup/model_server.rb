# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Puri
  module Setup
    # A model server the config gives a `url`, asked whether it serves a model:
    #
    #   server = ModelServer.new('http://192.168.122.1:9081')
    #   server.serves?('Ornith-1.5')   # => true
    #   server.models                  # => ["Granite-4.2-3B", "Ornith-1.5", …]
    #
    # One `GET /v1/models`, which every OpenAI-compatible server answers and which loads no model,
    # even on a llama.cpp router; a llama-server of one model serves whatever name Puri asks for
    # (`R_llama_models`). The key isn't checked: Puri's first answer says when it's wrong.
    class ModelServer
      # Raised when the server can't be asked, its message what the user reads after a colon:
      # "connection refused".
      class Error < StandardError; end

      # @return [Integer] seconds to connect, and again to read
      TIMEOUT = 5

      # @param url [String] as the config has it, with or without `/v1`
      # @param api_key [String, nil]
      def initialize(url, api_key: nil)
        @uri = URI("#{url.strip.chomp('/').delete_suffix('/v1')}/v1/models")
        @api_key = api_key
      end

      # @param model [String] an `[[llm]]`'s
      # @return [Boolean]
      # @raise [Puri::Setup::ModelServer::Error]
      def serves?(model)
        list = listing
        list.any? { _1['id'] == model || Array(_1['aliases']).include?(model) } ||
          (list.one? && list.first['owned_by'] == 'llamacpp' && !list.first.key?('status'))
      end

      # @return [Array<String>] each model's id, in the server's order
      # @raise [Puri::Setup::ModelServer::Error]
      def models = listing.map { _1['id'] }

      private

      # @return [Array<Hash{String => Object}>] the answer's `data`, asked for once
      # @raise [Puri::Setup::ModelServer::Error]
      def listing
        @listing ||= parse(fetch)
      end

      # @return [String] the body
      # @raise [Puri::Setup::ModelServer::Error]
      def fetch
        request = Net::HTTP::Get.new(@uri)
        request['Authorization'] = "Bearer #{@api_key}" if @api_key
        response = Net::HTTP.start(@uri.host, @uri.port, use_ssl: @uri.scheme == 'https',
                                                         open_timeout: TIMEOUT, read_timeout: TIMEOUT) do
          _1.request(request)
        end
        raise Error, "it answered #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      rescue Net::OpenTimeout, Net::ReadTimeout
        raise Error, "it didn't answer in #{TIMEOUT} seconds"
      rescue SystemCallError => e
        raise Error, SystemCallError.new(nil, e.errno).message.downcase # without Net::HTTP's wrapping
      rescue SocketError, IOError, OpenSSL::SSL::SSLError => e
        raise Error, e.message
      end

      # @param body [String]
      # @return [Array<Hash{String => Object}>]
      # @raise [Puri::Setup::ModelServer::Error] for anything but a list of models
      def parse(body)
        json = JSON.parse(body)
        data = json['data'] if json.is_a?(Hash)
        return data if data.is_a?(Array) && data.all? { _1.is_a?(Hash) && _1['id'].is_a?(String) }

        raise Error, "its answer to #{@uri.path} is no list of models"
      rescue JSON::ParserError
        raise Error, "its answer to #{@uri.path} isn't JSON"
      end
    end
  end
end
