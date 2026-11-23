# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'
require 'open3'

module Puri
  module Eval
    # Pikuri's demo world, as the eval runs in it: `~/Documents` from `dev/demo-home/build` and
    # the Thunderbird testbed, both built today, and a testbed session on its own display, which
    # the hand-offs open in and Marionette reads back.
    #
    #   world = World.new(pikuri: '~/work/my/pikuri', documents: '~/Documents')
    #   world.guard!                  # raises unless built today and the session runs on a display
    #   world.reset(memory: true)     # Notes/ as built, plus the seeded PURI.md; no hand-off open
    #   world.drafts                  # => [{"to" => …, "subject" => …, "body" => …}]
    #   world.events                  # => [the .ics text of each event handed off since the reset]
    #   world.notes                   # => {"Notes/shopping.md" => "…"}, what changed since the reset
    class World
      # A world the eval can't run in.
      class Error < StandardError; end

      # @return [String] where `calendar_create` stages its `.ics` for the snap Thunderbird
      OUTBOX = File.expand_path('~/snap/thunderbird/common/pikuri-outbox')

      # @return [Pikuri::Demo::Facts] the facts the world was built from
      attr_reader :facts

      # @return [String] the testbed session's X display, e.g. ":99"
      attr_reader :display

      # @param pikuri [String] pikuri's source checkout
      # @param documents [String] the demo home's documents folder
      def initialize(pikuri:, documents:)
        @pikuri = File.expand_path(pikuri)
        @documents = File.expand_path(documents)
        require File.join(@pikuri, 'dev/demo-home/builder/facts')
        @facts = Pikuri::Demo::Facts.new(today: Date.today)
        @baseline = read_notes
        @outbox = []
        state = File.expand_path('~/.cache/pikuri/thunderbird-testbed/session.json')
        @display = (JSON.parse(File.read(state))['display'] if File.exist?(state))
      end

      # @return [void]
      # @raise [Error] unless the world was built today and a session runs on a display
      def guard!
        marker = File.join(@documents, '.pikuri-demo')
        raise Error, "#{@documents} isn't pikuri's demo home" unless File.exist?(marker)

        built = File.mtime(marker).to_date
        raise Error, "the demo world was built on #{built}; rebuild it today (one run, one day)" if built != Date.today

        running = @display && session('status').start_with?('Running')
        raise Error, 'no testbed session on a display: DISABLE_WAYLAND=1 session start --display' unless running
      end

      # The home address, as the seeded memory note states it.
      #
      # @return [String]
      def memory_note = "# Memory\n\n- Home address: #{facts.owner.address}\n"

      # Puts the world back as built: `Notes/` as the build wrote it, the memory note seeded
      # unless `memory` is false, and every compose window and import wizard closed.
      #
      # @param memory [Boolean] whether `Notes/PURI.md` holds the home address
      # @return [void]
      def reset(memory:)
        session('js', script('close-handoffs.js'))
        notes = File.join(@documents, 'Notes')
        read_notes.each_key { |path| FileUtils.rm_f(File.join(@documents, path)) unless @baseline.key?(path) }
        @baseline.each { |path, text| File.write(File.join(@documents, path), text) }
        File.write(File.join(notes, 'PURI.md'), memory_note) if memory
        @seeded = memory ? @baseline.merge('Notes/PURI.md' => memory_note) : @baseline
        @outbox = Dir.glob(File.join(OUTBOX, '*.ics'))
      end

      # @return [Hash{String => String}] each note added or changed since {#reset}, by its path
      #   under the documents folder
      def notes = read_notes.reject { |path, text| @seeded[path] == text }

      # @return [String] `Notes/PURI.md`'s text, "" when there is none
      def memory = read_notes.fetch('Notes/PURI.md', '')

      # @return [Array<Hash{String => String}>] the open compose windows, as Thunderbird parsed them
      def drafts = JSON.parse(session('js', script('compose-windows.js')))

      # @return [Array<String>] the `.ics` of each event handed off since {#reset}
      def events = (Dir.glob(File.join(OUTBOX, '*.ics')) - @outbox).map { File.read(_1) }

      private

      # @return [Hash{String => String}] every file under Notes/, by its path under the documents folder
      def read_notes
        Dir.glob(File.join(@documents, 'Notes', '**', '*')).select { File.file?(_1) }.to_h do |file|
          [file.delete_prefix("#{@documents}/"), File.read(file, encoding: 'UTF-8', invalid: :replace)]
        end
      end

      # @param name [String]
      # @return [String] the testbed's chrome-context script of that name
      def script(name) = File.join(@pikuri, 'pikuri-thunderbird/dev/testbed/js', name)

      # Runs the testbed's `session` command on pikuri's own bundle.
      #
      # @param args [Array<String>]
      # @return [String] its output
      # @raise [Error] when it fails
      def session(*args)
        command = File.join(@pikuri, 'pikuri-thunderbird/dev/testbed/session')
        out, err, status = Bundler.with_unbundled_env { Open3.capture3(command, *args, chdir: @pikuri) }
        raise Error, "session #{args.first} failed: #{err.strip[-300..] || err}" unless status.success?

        out
      end
    end
  end
end
