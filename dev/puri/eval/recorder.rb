# frozen_string_literal: true

require 'json'

module Puri
  module Eval
    # A {Core::Http} that answers each URL as it did the first time it was asked: the first ask
    # goes out and is saved, every later one is replayed from the file. Every configuration then
    # sees the same tool results, and "will it rain tomorrow?" is graded against the recorded
    # forecast. A URL not recorded yet, a place a model spells differently, goes live and joins.
    #
    #   recorder = Recorder.new(path: "#{day}/http.json")
    #   Core::Places::Osm.new(http: recorder)
    #   recorder.begin_run
    #   recorder.answers   # => {url => json}, what this run asked
    #
    # Thread-safe.
    class Recorder
      # @param path [String] the recording, created on the first answer
      # @param http [Puri::Core::Http] what a URL not recorded yet goes to
      def initialize(path:, http: Core::Http.new)
        @path = path
        @http = http
        @lock = Mutex.new
        @recorded = File.exist?(path) ? JSON.parse(File.read(path), freeze: true) : {}
        @asked = {}
      end

      # (see Puri::Core::Http#get_json)
      def get_json(url, max_age: nil, cancellable: Pikuri::Agent::Control::Cancellable::NEVER)
        _ = max_age
        json = @lock.synchronize { @recorded[url] } || record(url, @http.get_json(url, cancellable:))
        @lock.synchronize { @asked[url] = json }
        json
      end

      # Starts a run: {#answers} forgets what the last one asked.
      #
      # @return [void]
      def begin_run = @lock.synchronize { @asked = {} }

      # @return [Hash{String => Object}] what this run asked, by URL
      def answers = @lock.synchronize { @asked.dup }

      # @return [Hash{String => Object}] the whole recording
      def recorded = @lock.synchronize { @recorded.dup }

      private

      # @param url [String]
      # @param json [Object]
      # @return [Object] `json`
      def record(url, json)
        @lock.synchronize do
          @recorded = @recorded.merge(url => json)
          File.write("#{@path}.tmp", JSON.pretty_generate(@recorded))
          File.rename("#{@path}.tmp", @path)
        end
        json
      end
    end
  end
end
