# frozen_string_literal: true

require 'erb'
require 'yaml'

module Puri
  module Eval
    # One request the eval makes: its turns, its tier, and what its checks expect ({Grader}).
    # `tasks.yml` beside this file holds them all, ERB over the demo world's facts first, so a
    # task can't drift from the world:
    #
    #   tasks = Task.load(facts)
    #   tasks.first.id      # => "thursday"
    #   tasks.first.expect  # => {"tools_any" => ["thunderbird_calendar"], "answer_has" => […]}
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] tier
    #   @return [String] simple, medium or hard
    # @!attribute [r] turns
    #   @return [Array<String>] the user's messages, one per turn
    # @!attribute [r] memory
    #   @return [Boolean] whether `Notes/PURI.md` holds the home address when it starts
    # @!attribute [r] expect
    #   @return [Hash{String => Object}] the checks, as {Grader} reads them
    class Task < Data.define(:id, :tier, :turns, :memory, :expect)
      # @return [String]
      FILE = File.expand_path('tasks.yml', __dir__)

      # @return [Array<String>]
      TIERS = %w[simple medium hard].freeze

      # What the tasks' ERB sees: the facts as `f`, and the tags {Matcher} reads.
      class Context
        # @return [Pikuri::Demo::Facts]
        attr_reader :f

        # @param facts [Pikuri::Demo::Facts]
        def initialize(facts)
          @f = facts
        end

        # @param offset [Integer] days from the build day
        # @return [String] a date in any common form
        def date(offset) = "@date:#{f.iso(offset)}"

        # @param hhmm [String] "17:00"
        # @return [String] a time of day in any common form
        def time(hhmm) = "@time:#{hhmm}"

        # @param value [Numeric]
        # @return [String] a number in any grouping
        def num(value) = "@num:#{value}"

        # @param value [String]
        # @return [String] an IBAN, spaced or not
        def iban(value) = "@iban:#{value}"

        # @param value [String]
        # @return [String] a phone number, its digits alone compared
        def digits(value) = "@digits:#{value}"

        # @param weekday [String] "thursday"
        # @return [Integer] days from the build day to the next one
        def next_weekday(weekday) = f.next_weekday(weekday)

        # @return [Binding]
        def scope = binding
      end

      # @param facts [Pikuri::Demo::Facts]
      # @return [Array<Puri::Eval::Task>]
      def self.load(facts)
        yaml = ERB.new(File.read(FILE), trim_mode: '-').result(Context.new(facts).scope)
        YAML.safe_load(yaml).map do |raw|
          new(id: raw.fetch('id'), tier: raw.fetch('tier'), turns: Array(raw.fetch('turns')),
              memory: raw.fetch('memory', true), expect: raw.fetch('expect', {}))
        end
      end
    end
  end
end
