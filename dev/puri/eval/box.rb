# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module Puri
  module Eval
    # The test box: llama.cpp's router, reached as the config's `[[server]]` says.
    #
    #   box = Box.new(url: server.url, api_key: server.api_key)
    #   box.only('Qwen3.5-4B', among: presets)   # unloads the others, loads this one
    #   box.metrics('Qwen3.5-4B')                 # => {"prompt_tokens_total" => 16.0, …}
    #   box.build                                 # => "b10438-Debian"
    class Box
      # The box at `url`: a {Lemonade} when the server answers as one, else the router.
      #
      # @param url [String] the server's base URL
      # @param api_key [String, nil]
      # @return [Puri::Eval::Box, Puri::Eval::Lemonade]
      def self.at(url:, api_key:)
        lemonade = Lemonade.new(url:, api_key:)
        lemonade.answers? ? lemonade : new(url:, api_key:)
      end

      # @param url [String] the server's base URL, without `/v1`
      # @param api_key [String, nil]
      def initialize(url:, api_key:)
        @base = URI(url.delete_suffix('/').delete_suffix('/v1'))
        @api_key = api_key
      end

      # Leaves `model` the only one of `among` loaded, loading it if it isn't; a model outside
      # `among`, another user's, is left alone.
      #
      # @param model [String]
      # @param among [Array<String>]
      # @return [Boolean] whether it loaded
      def only(model, among:)
        models.each do |m|
          next if m['id'] == model || !among.include?(m['id']) || m['status']['value'] == 'unloaded'

          call(:post, '/models/unload', model: m['id'])
          wait(m['id'], timeout: 300) { _1['value'] == 'unloaded' }
        end
        return true if status(model)['value'] == 'loaded'

        call(:post, '/models/load', model:)
        wait(model, timeout: 3600) { _1['value'] == 'loaded' || _1['failed'] }
        status(model)['value'] == 'loaded'
      end

      # @param model [String]
      # @return [void]
      def unload(model)
        call(:post, '/models/unload', model:)
        wait(model, timeout: 300) { _1['value'] == 'unloaded' }
      end

      # @param model [String]
      # @return [Hash{String => Float}] its llama-server's counters, without the `llamacpp:` prefix
      def metrics(model)
        text = call(:get, "/metrics?model=#{URI.encode_www_form_component(model)}", raw: true)
        text.lines.filter_map do |line|
          name, value = line.split
          [name.delete_prefix('llamacpp:'), Float(value)] if name&.start_with?('llamacpp:') && value
        end.to_h
      rescue StandardError
        {}
      end

      # @return [String] the router's llama.cpp build
      def build = call(:get, '/props')['build_info'].to_s

      # @param model [String]
      # @return [Hash{String => Object}] its status, without the arguments
      def status(model) = models.find { _1['id'] == model }&.dig('status')&.except('args', 'preset') || {}

      private

      # @return [Array<Hash{String => Object}>]
      def models = call(:get, '/v1/models')['data']

      # @param model [String]
      # @param timeout [Integer] seconds
      # @yieldparam status [Hash{String => Object}]
      # @yieldreturn [Boolean] whether to stop waiting
      # @return [void]
      def wait(model, timeout:)
        deadline = Time.now + timeout
        sleep 2 until yield(status(model)) || Time.now > deadline
      end

      # @param verb [Symbol] :get or :post
      # @param path [String]
      # @param raw [Boolean] the body as text, not JSON
      # @param body [Hash{Symbol => Object}]
      # @return [Object]
      def call(verb, path, raw: false, **body)
        http = Net::HTTP.new(@base.host, @base.port)
        http.use_ssl = @base.scheme == 'https'
        http.read_timeout = 120
        request = (verb == :get ? Net::HTTP::Get : Net::HTTP::Post).new(path)
        request['Authorization'] = "Bearer #{@api_key}" if @api_key
        unless body.empty?
          request['Content-Type'] = 'application/json'
          request.body = JSON.generate(body)
        end
        text = http.request(request).body
        raw ? text : JSON.parse(text)
      end
    end
  end
end
