# frozen_string_literal: true

require 'cgi'
require 'date'
require 'fileutils'
require 'json'

module Puri
  module Eval
    # Runs the tasks through Puri's own Core, once per configuration, each task {#repeats} times
    # in a fresh conversation, and writes one JSON line per run into today's `results.jsonl`.
    #
    #   Runner.new(configurations: Runner::CONFIGURATIONS, tasks:, repeats: 3, world:, day_dir:).run
    #
    # Core is built as `exe/puri` builds it, minus the titler (it would share the box's one slot
    # and skew the timings) and Rhythmbox, with the place and weather tools on a {Recorder}.
    # Before each configuration every eval preset is unloaded and this one loaded, and one
    # throwaway turn is timed as the cold start. A run already in `results.jsonl` is skipped, so a
    # stopped run resumes where it stopped. One run, one day: a configuration that wouldn't end
    # before midnight isn't started, and none goes on past it.
    class Runner
      # One model, one way of asking it.
      #
      # @!attribute [r] name
      #   @return [String]
      # @!attribute [r] model
      #   @return [String] the router's preset
      # @!attribute [r] kwargs
      #   @return [Hash{String => Object}] the chat template's arguments, as the `[[llm]]`'s
      #     `params` sends them
      # @!attribute [r] params
      #   @return [Hash{String => Object}] sent with every request over the preset's own: the
      #     card's sampling for this mode, where it differs from the preset's, and whatever else
      #     the server needs
      # @!attribute [r] server
      #   @return [String, nil] the id of the user's `[[server]]` it runs on; nil for the one
      #     their first `[[llm]]` uses
      class Configuration < Data.define(:name, :model, :kwargs, :params, :server)
        # @param name [String]
        # @param model [String]
        # @param kwargs [Hash{String => Object}]
        # @param params [Hash{String => Object}]
        # @param server [String, nil]
        def initialize(name:, model:, kwargs:, params: {}, server: nil) = super

        # @return [String] the configuration's name, as a file name
        def slug = name.downcase.gsub(/[^a-z0-9.]+/, '-').delete_suffix('-')
      end

      OFF = { 'enable_thinking' => false }.freeze
      ON = { 'enable_thinking' => true }.freeze
      private_constant :OFF, :ON

      # Each model thinking off, the baseline first and the slowest last; then the small tier
      # thinking on, since without it the small models mostly failed to act (`R_model_eval`).
      # `model` names a preset in `presets.ini`.
      #
      # @return [Array<Puri::Eval::Runner::Configuration>]
      CONFIGURATIONS = [
        Configuration.new(name: 'Ornith-1.5, no thinking', model: 'Ornith-1.5', kwargs: OFF),
        Configuration.new(name: 'Qwen3.5-4B', model: 'Qwen3.5-4B', kwargs: OFF),
        Configuration.new(name: 'Granite-4.2-3B', model: 'Granite-4.2-3B', kwargs: OFF),
        Configuration.new(name: 'Nemotron-3.5-Bolt-E4B', model: 'Nemotron-3.5-Bolt-E4B', kwargs: OFF),
        Configuration.new(name: 'LFM3-1.7B', model: 'LFM3-1.7B', kwargs: OFF),
        Configuration.new(name: 'gpt-oss-20b, low', model: 'gpt-oss-20b', kwargs: { 'reasoning_effort' => 'low' }),
        Configuration.new(name: 'Ornith-1.5, thinking', model: 'Ornith-1.5', kwargs: {}),
        Configuration.new(name: 'Qwen3.5-4B, thinking', model: 'Qwen3.5-4B', kwargs: ON,
                          params: { 'temperature' => 1.0, 'top_p' => 0.95 }),
        Configuration.new(name: 'Nemotron-3.5-Bolt-E4B, thinking', model: 'Nemotron-3.5-Bolt-E4B', kwargs: ON),
        Configuration.new(name: 'Granite-4.2-3B, thinking', model: 'Granite-4.2-3B', kwargs: ON),
        # Qwen on the NPU, through Lemonade's FastFlowLM, which has no preset: the router preset's
        # sampling goes whole, and `think` too, since in FastFlowLM 1.0.11 an earlier request's
        # `think: false` outlasts `enable_thinking`.
        Configuration.new(name: 'Qwen3.5-4B on the NPU, thinking', model: 'qwen3.5-4b-FLM', kwargs: ON,
                          server: 'lemonade',
                          params: { 'temperature' => 1.0, 'top_p' => 0.95, 'top_k' => 20, 'min_p' => 0.0,
                                    'presence_penalty' => 1.5, 'think' => true })
      ].freeze

      # @return [Integer] seconds a turn may take before it's cancelled
      TURN_SECONDS = 600

      # @return [Integer] a run's seconds, guessed before any has run
      GUESS_SECONDS = 45

      # @param configurations [Array<Puri::Eval::Runner::Configuration>]
      # @param tasks [Array<Puri::Eval::Task>]
      # @param repeats [Integer]
      # @param world [Puri::Eval::World]
      # @param day_dir [String] today's results folder
      # @param log [IO]
      def initialize(configurations:, tasks:, repeats:, world:, day_dir:, log: $stdout)
        @configurations = configurations
        @tasks = tasks
        @repeats = repeats
        @world = world
        @day_dir = day_dir
        @log = log
        @day = Date.today
        @recorder = Recorder.new(path: File.join(day_dir, 'http.json'))
        @grader = Grader.new(world.facts, recording: -> { @recorder.recorded })
        FileUtils.mkdir_p(day_dir)
        @done = read_jsonl('results.jsonl').to_set { [_1['configuration'], _1['task'], _1['run']] }
      end

      # @return [void]
      def run
        @world.guard!
        # The hand-off spawns Thunderbird on the environment this process started with
        # (`Pikuri::BundlerEnv.clean_delta`), so setting these here would never reach it.
        unless ENV['DISPLAY'] == @world.display && ENV['DISABLE_WAYLAND']
          raise World::Error, "start it with DISPLAY=#{@world.display} DISABLE_WAYLAND=1, so the hand-offs " \
                              'open in the testbed session'
        end
        @configurations.each do |configuration|
          left = @tasks.sum { |task| (1..@repeats).count { !@done.include?([configuration.name, task.id, _1]) } }
          next say("#{configuration.name}: done already") if left.zero?

          eta = Time.now + (left * average_seconds(configuration))
          if eta.to_date != @day
            say("#{configuration.name}: #{left} runs wouldn't end before midnight (#{eta.strftime('%H:%M')}); stopping")
            break
          end
          run_configuration(configuration)
        end
        say('all done')
      end

      private

      # @param configuration [Puri::Eval::Runner::Configuration]
      # @return [void]
      def run_configuration(configuration)
        say("=== #{configuration.name}")
        box, core, events = start(configuration)
        return unless core

        @tasks.each do |task|
          (1..@repeats).each do |n|
            next if @done.include?([configuration.name, task.id, n])
            raise "midnight: #{configuration.name} stops at #{task.id} ##{n}" if Date.today != @day

            row = run_task(configuration, task, n, core, events, box)
            append('results.jsonl', row)
            @done << [configuration.name, task.id, n]
            failed = row['checks'].reject { _1['pass'] }.map { _1['check'] }
            say(format('  %<task>-18s #%<n>d %<verdict>-4s %<secs>5.1f s %<failed>s',
                       task: task.id, n:, verdict: row['pass'] ? 'pass' : 'FAIL', secs: row['seconds'],
                       failed: failed.join(' ')))
          end
        end
      ensure
        core&.close
      end

      # Every eval preset unloaded, this one loaded afresh, Core built on it, one throwaway turn.
      #
      # @param configuration [Puri::Eval::Runner::Configuration]
      # @return [Array(Puri::Eval::Box, Puri::Core::PikuriCore, Thread::Queue), Array(Puri::Eval::Box, nil, nil)]
      def start(configuration)
        config = config_for(configuration)
        llm = config.primary_llm
        box = Box.at(url: llm.server, api_key: llm.api_key)
        presets = CONFIGURATIONS.map(&:model).uniq
        box.unload(configuration.model) unless box.status(configuration.model)['value'] == 'unloaded'
        loading = Time.now
        loaded = box.only(configuration.model, among: presets)
        row = { 'configuration' => configuration.name, 'model' => configuration.model, 'build' => box.build,
                'loaded' => loaded, 'load_seconds' => (Time.now - loading).round(1),
                'status' => box.status(configuration.model), 'at' => Time.now.iso8601 }
        unless loaded
          append('configurations.jsonl', row)
          say("  #{configuration.model} did not load: #{row['status']}")
          return [box, nil, nil]
        end

        events = Thread::Queue.new
        core = build_core(config) { events << _1 }
        cold = turns(core, events, ['Hello!'])
        row['cold'] = cold[:turns].first.slice('first_stream', 'seconds', 'completed')
        core.delete_conversation(cold[:id])
        append('configurations.jsonl', row)
        say("  loaded in #{row['load_seconds']} s; cold start #{row['cold']}")
        [box, core, events]
      end

      # @param configuration [Puri::Eval::Runner::Configuration]
      # @param task [Puri::Eval::Task]
      # @param run [Integer] which of the task's runs
      # @param core [Puri::Core::PikuriCore]
      # @param events [Thread::Queue]
      # @param box [Puri::Eval::Box]
      # @return [Hash{String => Object}] the results.jsonl row
      def run_task(configuration, task, run, core, events, box)
        @world.reset(memory: task.memory)
        @recorder.begin_run
        before = box.metrics(configuration.model)
        started = Time.now
        done = turns(core, events, task.turns)
        seconds = (Time.now - started).round(1)
        after = box.metrics(configuration.model)
        history = history(done[:id], task.turns.size)
        turns = split(done[:turns], core.load_conversation(done[:id]).blocks, history)
        composed = turns.sum { |t| t['tools'].count { _1['name'] == 'thunderbird_mail_compose' } }
        obs = Grader::Observation.new(turns:, notes: @world.notes, memory: @world.memory, drafts: drafts(composed),
                                      events: @world.events, answers: @recorder.answers)
        checks = @grader.grade(task, obs)
        keep(configuration, task, run, history)
        core.delete_conversation(done[:id])
        { 'configuration' => configuration.name, 'model' => configuration.model, 'task' => task.id,
          'tier' => task.tier, 'run' => run, 'pass' => checks.all? { _1['pass'] }, 'checks' => checks,
          'seconds' => seconds, 'turns' => turns, 'first_prompt' => first_prompt(history),
          'box' => delta(before, after), 'observation' => observed(obs), 'at' => started.iso8601 }
      end

      # What {Grader#regrade} needs beside the turns; the answers by URL alone, since the
      # recording keeps them.
      #
      # @param obs [Puri::Eval::Grader::Observation]
      # @return [Hash{String => Object}]
      def observed(obs)
        { 'notes' => obs.notes, 'memory' => obs.memory, 'drafts' => obs.drafts, 'events' => obs.events,
          'answer_urls' => obs.answers.keys }
      end

      # The hand-off returns once it has launched `thunderbird mailto:…`, and the compose window
      # opens a moment later, so this waits for as many as were composed, 15 s at most.
      #
      # @param composed [Integer] how many times the run called `thunderbird_mail_compose`
      # @return [Array<Hash{String => String}>] the open compose windows
      def drafts(composed)
        deadline = Time.now + 15
        loop do
          open = @world.drafts
          return open if open.size >= composed || Time.now > deadline

          sleep 0.5
        end
      end

      # Asks each message in turn in one new conversation, each once the one before has ended.
      #
      # @param core [Puri::Core::PikuriCore]
      # @param events [Thread::Queue]
      # @param messages [Array<String>]
      # @return [Hash{Symbol => Object}] :id, the conversation's; :turns, each one's timings
      def turns(core, events, messages)
        events.clear
        id = nil
        timings = messages.map do |text|
          asked = Time.now
          id = core.ask(id, text)
          wait(core, events, id, asked)
        end
        { id:, turns: timings }
      end

      # @param core [Puri::Core::PikuriCore]
      # @param events [Thread::Queue]
      # @param id [String]
      # @param asked [Time]
      # @return [Hash{String => Object}] "first_stream" and "seconds", from the ask; "completed";
      #   "confirming", when a tool asked
      def wait(core, events, id, asked)
        out = { 'completed' => false, 'first_stream' => nil }
        ran = false
        deadline = asked + TURN_SECONDS
        loop do
          event = events.pop(timeout: [deadline - Time.now, 0].max)
          if event.nil?
            core.cancel(id)
            deadline = Time.now + 30
            next out['timed_out'] = true unless out['timed_out']

            break
          end
          next unless event.is_a?(Protocol::ActivityChanged) && event.conversation == id

          state = event.activity.state
          out['first_stream'] ||= (Time.now - asked).round(2) if state == 'streaming'
          if state == 'confirming'
            out['confirming'] = true
            core.cancel(id)
          end
          ran ||= event.activity.running?
          next unless ran && !event.activity.running?

          out['completed'] = !out['timed_out'] && !out['confirming']
          break
        end
        out.merge('seconds' => (Time.now - asked).round(2))
      end

      # The conversation's saved history, once its last turn is in it.
      #
      # @param id [String]
      # @param asked [Integer] how many messages the user sent
      # @return [Array<Hash{String => Object}>] its messages
      def history(id, asked)
        path = File.join(@day_dir, 'state', 'puri', 'conversations', id, 'history.json')
        deadline = Time.now + 15
        loop do
          messages = (JSON.parse(File.read(path))['messages'] if File.exist?(path)) || []
          return messages if messages.count { _1['role'] == 'user' } >= asked || Time.now > deadline

          sleep 0.5
        end
      end

      # Each turn's answer, tool calls, failures and tokens, from the transcript and the history.
      #
      # @param timings [Array<Hash{String => Object}>] from {#wait}, one per turn
      # @param blocks [Array<Data>] the transcript's
      # @param history [Array<Hash{String => Object}>]
      # @return [Array<Hash{String => Object}>]
      def split(timings, blocks, history)
        by_turn = slice(blocks, Protocol::UserMessage)
        messages = slice(history, ->(m) { m['role'] == 'user' })
        timings.each_with_index.map do |timing, i|
          own = by_turn[i] || []
          said = messages[i] || []
          assistant = said.select { _1['role'] == 'assistant' }
          timing.merge(
            'answer' => own.grep(Protocol::Reply).map { reply_text(_1) }.join("\n").strip,
            'tools' => assistant.flat_map { |m| Array(m['tool_calls']).map { _1.slice('name', 'arguments') } },
            'errors' => own.count { (_1.is_a?(Protocol::ToolLine) || _1.is_a?(Protocol::Notice)) && _1.error },
            'notices' => own.grep(Protocol::Notice).map(&:text),
            'tokens' => %w[input output cached].to_h { |k| [k, assistant.sum { _1.dig('tokens', k).to_i }] }
          )
        end
      end

      # @param items [Array<Object>]
      # @param starts [Class, Proc] what begins a turn
      # @return [Array<Array<Object>>] the items after each start, up to the next
      def slice(items, starts)
        items.each_with_object([]) do |item, turns|
          if starts === item # rubocop:disable Style/CaseEquality
            turns << []
          else
            turns.last&.push(item)
          end
        end
      end

      # @param reply [Puri::Protocol::Reply]
      # @return [String] its text, Prose's markup unescaped
      def reply_text(reply)
        reply.parts.map do |part|
          case part
          when Protocol::Prose then CGI.unescapeHTML(part.markup.gsub(/<[^>]+>/, ''))
          when Protocol::Table then [part.header, *part.rows].map { Array(_1).join(' | ') }.join("\n")
          when Protocol::Code then part.text
          else ''
          end
        end.join("\n")
      end

      # @param history [Array<Hash{String => Object}>]
      # @return [Integer, nil] the first request's prompt tokens: system prompt, tools, memory and the
      #   first message
      def first_prompt(history)
        tokens = history.find { _1['role'] == 'assistant' }&.dig('tokens') or return nil
        tokens['input'].to_i + tokens['cached'].to_i
      end

      # @param before [Hash{String => Float}]
      # @param after [Hash{String => Float}]
      # @return [Hash{String => Float}] the run's own share of the box's counters
      def delta(before, after)
        %w[prompt_tokens_total prompt_seconds_total tokens_predicted_total tokens_predicted_seconds_total]
          .to_h { [_1.delete_suffix('_total'), (after[_1].to_f - before[_1].to_f).round(3)] }
      end

      # @param configuration [Puri::Eval::Runner::Configuration]
      # @param task [Puri::Eval::Task]
      # @param run [Integer]
      # @param history [Array<Hash{String => Object}>]
      # @return [void]
      def keep(configuration, task, run, history)
        dir = File.join(@day_dir, 'runs', configuration.slug)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "#{task.id}-#{run}.json"), JSON.pretty_generate(history))
      end

      # @param configuration [Puri::Eval::Runner::Configuration]
      # @return [Float] seconds per run: this configuration's so far, else every one's, else a guess
      def average_seconds(configuration)
        rows = read_jsonl('results.jsonl')
        own = rows.select { _1['configuration'] == configuration.name }
        pick = own.empty? ? rows : own
        pick.empty? ? GUESS_SECONDS : pick.sum { _1['seconds'] } / pick.size
      end

      # The config each run reads: the `[[server]]` and `[search]` from the user's own config
      # file, under one that names this configuration's connection, the demo documents, and the
      # place and weather tools.
      #
      # @param configuration [Puri::Eval::Runner::Configuration]
      # @return [Puri::Core::Config]
      def config_for(configuration)
        dir = File.join(@day_dir, 'config', configuration.slug)
        FileUtils.mkdir_p(File.join(dir, 'puri'))
        own = Core::Config.load
        server = configuration.server || own.servers.find { _1.url == own.primary_llm.server }.id
        kwargs = configuration.kwargs.map { |k, v| "#{k} = #{v.inspect}" }.join(', ')
        pairs = configuration.params.map { |k, v| "#{k} = #{v.inspect}" }
        pairs << "chat_template_kwargs = { #{kwargs} }" unless kwargs.empty?
        params = pairs.empty? ? '' : "params = { #{pairs.join(', ')} }"
        File.write(File.join(dir, 'puri', 'config.toml'), <<~TOML)
          [[llm]]
          name   = #{configuration.name.inspect}
          server = #{server.inspect}
          model  = #{configuration.model.inspect}
          #{params}

          [titler]
          llm = #{configuration.name.inspect}

          [documents]
          folder = "~/Documents"

          [maps]
          tiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

          [weather]
        TOML
        Core::Config.load(env: { 'XDG_CONFIG_DIRS' => File.expand_path('~/.config'), 'XDG_CONFIG_HOME' => dir })
      end

      # @param config [Puri::Core::Config]
      # @yieldparam event [Data]
      # @return [Puri::Core::PikuriCore]
      def build_core(config, &)
        Core::PikuriCore.register_extractors
        store = Core::PikuriCore.store(env: { 'XDG_STATE_HOME' => File.join(@day_dir, 'state') })
        Core::PikuriCore.new(config:, models: Core::Models.from_config(config), titler: nil, store:,
                             library: Core::Library.new(config.documents), osm: Core::Places::Osm.new(http: @recorder),
                             open_meteo: Core::Weather::OpenMeteo.new(http: @recorder, url: config.weather.url), &)
      end

      # @param message [String]
      # @return [void]
      def say(message)
        @log.puts("#{Time.now.strftime('%H:%M:%S')} #{message}")
        @log.flush
      end

      # @param file [String] under today's folder
      # @param row [Hash{String => Object}]
      # @return [void]
      def append(file, row) = File.open(File.join(@day_dir, file), 'a') { _1.puts(JSON.generate(row)) }

      # @param file [String] under today's folder
      # @return [Array<Hash{String => Object}>]
      def read_jsonl(file)
        path = File.join(@day_dir, file)
        File.exist?(path) ? File.readlines(path).map { JSON.parse(_1) } : []
      end
    end
  end
end
