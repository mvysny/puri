# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Puri
  module Eval
    # A test box that is AMD's Lemonade, running a model on the NPU through FastFlowLM, with
    # {Box}'s methods, so the runner drives either:
    #
    #   box = Box.at(url: server.url, api_key: server.api_key)   # a Lemonade when it answers as one
    #   box.only('qwen3.5-4b-FLM', among: presets)               # loads it; Lemonade's others stay
    #   box.build                                                # => "FastFlowLM v1.0.11"
    #
    # Lemonade keeps no per-model timings, so {#metrics} is empty and the report's tokens-a-second
    # columns read "–".
    class Lemonade
      # @param url [String] the server's base URL, without `/v1`
      # @param api_key [String, nil]
      def initialize(url:, api_key:)
        @base = URI(url.delete_suffix('/').delete_suffix('/v1'))
        @api_key = api_key
      end

      # @return [Boolean] whether the server answers Lemonade's health check
      def answers?
        call(:get, '/api/v1/health').key?('all_models_loaded')
      rescue StandardError
        false
      end

      # Loads `model` unless it is loaded; Lemonade answers once it is.
      #
      # @param model [String]
      # @return [Boolean] whether it loaded
      def only(model, **)
        call(:post, '/api/v1/load', model_name: model) unless loaded?(model)
        loaded?(model)
      end

      # @param model [String]
      # @return [void]
      def unload(model)
        call(:post, '/api/v1/unload', model_name: model)
      end

      # @param _model [String]
      # @return [Hash{String => Float}] always empty
      def metrics(_model) = {}

      # @return [String] its FastFlowLM's version
      def build
        "FastFlowLM #{call(:get, '/api/v1/system-info').dig('recipes', 'flm', 'backends', 'npu', 'version')}"
      end

      # @param model [String]
      # @return [Hash{String => String}] "value", "loaded" or "unloaded", as the router says it
      def status(model) = { 'value' => loaded?(model) ? 'loaded' : 'unloaded' }

      private

      # @param model [String]
      # @return [Boolean]
      def loaded?(model)
        Array(call(:get, '/api/v1/health')['all_models_loaded']).any? { _1['model_name'] == model }
      end

      # @param verb [Symbol] :get or :post
      # @param path [String]
      # @param body [Hash{Symbol => Object}]
      # @return [Hash{String => Object}]
      def call(verb, path, **body)
        http = Net::HTTP.new(@base.host, @base.port)
        http.use_ssl = @base.scheme == 'https'
        http.read_timeout = 600
        request = (verb == :get ? Net::HTTP::Get : Net::HTTP::Post).new(path)
        request['Authorization'] = "Bearer #{@api_key}" if @api_key
        unless body.empty?
          request['Content-Type'] = 'application/json'
          request.body = JSON.generate(body)
        end
        JSON.parse(http.request(request).body)
      end
    end
  end
end
