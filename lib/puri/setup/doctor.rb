# frozen_string_literal: true

require 'fileutils'

module Puri
  module Setup
    # The checks `bin/setup` runs once the packages and the gems are in, each with its fix:
    #
    #   ✓ Puri is on your desktop: Super+Alt+Space opens it
    #   ✓ The config, ~/.config/puri/config.toml
    #   ✓ The model, ggml-org/Qwen3.5-4B-GGUF:Q4_K_M
    #   ✓ Dictation's model, ggerganov/whisper.cpp:ggml-small.bin
    #   ✗ Thunderbird's global search is off, so Puri finds no mail: in Thunderbird, …
    #   ✓ Your documents, ~/Documents, in GNOME's file index
    #
    #   One thing above, marked ✗, needs you. Run bin/setup again once it's done.
    #
    #   exit Doctor.new.run
    #
    # The config decides the rest: the models are the ones it names, downloaded where it runs them
    # here and asked of the server where it gives one a `url` ({ModelServer}), and Thunderbird and
    # the documents are checked where it turns them on. A broken config
    # stops the checks after it. The config is written only when there is none, the install guide's
    # `docs/config.toml` as it is.
    class Doctor
      # @return [String] the web page, whose `models.html` the advice links to
      SITE = 'https://puri-ai.de'

      # @return [String] the install guide's model, which a better-equipped computer may outgrow
      QWEN = 'ggml-org/Qwen3.5-4B-GGUF'

      # @return [String] where `bin/setup` and Puri live
      ROOT = File.expand_path('../../..', __dir__)

      # @param terminal [Puri::Setup::Terminal]
      # @param env [#[]] where the XDG folders, `HOME`, the hub cache's and `HF_ENDPOINT` come from
      def initialize(terminal: Terminal.new, env: ENV)
        @terminal = terminal
        @env = env
        @hotkey = nil
      end

      # @return [Integer] the exit status: 0 when nothing needs the user, 1 when something does,
      #   130 after Ctrl+C
      def run
        desktop
        config = self.config
        if config
          models(config)
          mail(config.thunderbird) if config.thunderbird
          documents(config.documents.folder) if config.documents
        end
        finish
      rescue Interrupt
        @terminal.say("\nStopped. Run bin/setup again to carry on where it stopped.")
        130
      end

      private

      # @return [void]
      def desktop
        install = Install.new(env: @env)
        if install.installed?
          @hotkey = install.hotkey
          return @terminal.done('Puri is on your desktop, with no shortcut to open it') unless @hotkey

          return @terminal.done("Puri is on your desktop: #{Install.label(@hotkey)} opens it")
        end
        elsewhere = install.present?
        hotkey = elsewhere ? install.hotkey : Install::DEFAULT_HOTKEY
        question = if elsewhere
                     "Puri's shortcut starts another copy of Puri. Point it at this one, in #{tilde(ROOT)}?"
                   else
                     "Put Puri on your desktop? #{Install.label(hotkey)} will open it, and it starts, hidden, " \
                       'when you log in, so even the first press is quick.'
                   end
        unless @terminal.ask?(question)
          return @terminal.note("Puri's shortcut starts another copy of Puri.") if elsewhere

          return @terminal.todo('Puri isn\'t on your desktop: bundle exec rake install AUTOSTART=1, in ' \
                                "#{tilde(ROOT)}, puts it there.")
        end
        written = install.write(hotkey:, autostart: elsewhere ? install.autostart? : true)
        @hotkey = hotkey
        @terminal.done("Puri is on your desktop#{": #{Install.label(hotkey)} opens it" if hotkey}. " \
                       "Wrote #{written.map { tilde(_1) }.join(', ')}.")
      rescue GSettings::Error, ArgumentError => e
        @terminal.todo("Puri can't go on your desktop: #{e.message}")
      end

      # @return [Puri::Core::Config, nil] nil when it is broken
      def config
        path = Core::Config.user_path(env: @env)
        wrote = !Core::Config.exists?(env: @env)
        if wrote
          FileUtils.mkdir_p(File.dirname(path))
          FileUtils.cp(Core::Config::EXAMPLE, path)
        end
        config = Core::Config.load(env: @env)
        if wrote
          @terminal.done("Wrote the config, #{tilde(path)}: every feature is on but web search, and each part says " \
                         'what it does and what it sends out of your computer. To read it: ' \
                         "gnome-text-editor #{tilde(path)}")
        else
          @terminal.done(File.file?(path) ? "The config, #{tilde(path)}" : 'The config')
        end
        config
      rescue Core::Config::Error => e
        @terminal.todo("The config has a mistake, so Puri won't start: #{e.message}")
        nil
      end

      # @param config [Puri::Core::Config]
      # @return [void]
      def models(config)
        cache = Core::HubCache.new(env: @env)
        download = HubDownload.new(cache, env: @env)
        if (embedded = config.embedded_server)
          hardware = probe
          path = cache.gguf(embedded.model)
          gpu(hardware) unless path # before the question whether to download it
          model('The model', embedded.model, path, download) { download.gguf(embedded.model) }
          gpu(hardware) if path
          ornith(hardware) if embedded.model.start_with?("#{QWEN}:")
        end
        served(config)
        dictation = config.dictation
        return unless dictation && !dictation.url

        model("Dictation's model", dictation.model, cache.file(dictation.model), download) do
          download.file(dictation.model)
        end
      end

      # The models a server with a `url` runs, each asked of its server.
      #
      # @param config [Puri::Core::Config]
      # @return [void]
      def served(config)
        embedded = config.embedded_server&.url
        config.llms.reject { _1.server == embedded }.group_by { [_1.server, _1.api_key] }.each do |(url, key), llms|
          server = ModelServer.new(url, api_key: key)
          llms.map(&:model).uniq.each do |model|
            next @terminal.done("The model, #{model}, on #{url}") if server.serves?(model)

            others = server.models
            only = ", only #{some(others)}" unless others.empty?
            @terminal.todo("The model's server, #{url}, has no #{model}#{only}; the config names it under [[llm]].")
          end
        rescue ModelServer::Error => e
          @terminal.todo("Puri can't ask the model's server, #{url}, for its models: #{e.message}.")
        end
      end

      # @param names [Array<String>]
      # @return [String] the first few, and how many more
      def some(names) = names.size > 4 ? "#{names.first(3).join(', ')} and #{names.size - 3} more" : names.join(', ')

      # @return [Puri::Setup::Hardware, nil] nil when llama-server can't say
      def probe
        Hardware.probe
      rescue SystemCallError => e
        @terminal.note("Can't tell what the model runs on here: #{e.message}")
        nil
      end

      # @param hardware [Puri::Setup::Hardware, nil]
      # @return [void]
      def gpu(hardware)
        return if hardware.nil? || hardware.gpu?

        @terminal.note('No graphics for the model to run on, so it runs on the processor alone: Puri works, but ' \
                       'answers will be very slow, the first after it starts taking minutes. A model on another ' \
                       "computer of yours is faster: #{SITE}/models.html#no-gpu")
      end

      # @param title [String]
      # @param model [String]
      # @param path [String, nil] where the cache has it; nil when it hasn't
      # @param download [Puri::Setup::HubDownload]
      # @yieldreturn [Puri::Setup::HubDownload::Plan]
      # @return [void]
      def model(title, model, path, download)
        return @terminal.done("#{title}, #{model}") if path

        plan = yield
        left = plan.size - plan.fetched
        size = Terminal.size(left)
        size = "#{size} of #{Terminal.size(plan.size)} left" if plan.fetched.positive?
        unless @terminal.ask?("#{title}, #{model}, isn't downloaded. Download it from Hugging Face, #{size}?")
          return @terminal.todo("#{title}, #{model}, isn't downloaded: bin/setup downloads it.")
        end

        bar = @terminal.progress(plan.size, plan.fetched)
        download.fetch(plan) { bar.update(_1) }
        bar.finish
        @terminal.done("#{title}, #{model}, downloaded")
      rescue HubDownload::Error => e
        bar&.stop
        @terminal.todo("#{title}, #{model}, didn't download: #{e.message}")
      end

      # @param hardware [Puri::Setup::Hardware, nil]
      # @return [void]
      def ornith(hardware)
        return unless hardware

        if hardware.ornith?
          @terminal.tip("This computer's graphics have the memory for Ornith 1.5, a smarter model than Qwen, a 23 GB " \
                        "download: #{SITE}/models.html#ornith says what to change in the config, and bin/setup " \
                        'then downloads it.')
        elsif (share = hardware.ornith_share)
          kernel = hardware.ttm ? '' : " On this Radeon, that's two kernel options: #{Hardware.ttm_options(share)}"
          @terminal.tip("With #{hardware.ram_gb} GB of memory, this computer can run Ornith 1.5, a smarter model " \
                        "than Qwen, once its graphics may use #{share} GB of it: #{SITE}/models.html#igpu.#{kernel}")
        end
      end

      # @param table [Puri::Core::Config::ThunderbirdTable]
      # @return [void]
      def mail(table)
        profile = Pikuri::Thunderbird::Profile.discover(profile_dir: table.profile_dir)
        unless profile&.mail_account?
          return @terminal.note('Thunderbird has no mail account here, so Puri reads no mail, contacts or calendar. ' \
                                'Add yours in Thunderbird, then run bin/setup again; or, to go without, put ' \
                                'enabled = false under [thunderbird] in the config.')
        end

        if !profile.gloda_indexing?
          @terminal.todo("Thunderbird's global search is off, so Puri finds no mail: in Thunderbird, Settings → " \
                         'General → Enable Global Search and Indexer.')
        elsif !profile.gloda?
          @terminal.note("Thunderbird hasn't indexed your mail yet, so Puri finds none: leave Thunderbird open a " \
                         'while, then run bin/setup again.')
        else
          @terminal.done("Thunderbird's mail index, in #{tilde(profile.dir)}")
        end
        Calendars.uncached(profile.prefs_path).each do |name|
          @terminal.todo("The calendar “#{name}” keeps no copy on your disk, so Puri can't read it: in Thunderbird, " \
                         'right-click it, then Properties → Offline Support.')
        end
      rescue Pikuri::Thunderbird::Profile::DiscoveryError => e
        @terminal.todo("Puri can't tell which Thunderbird profile to read: #{e.message} In the config, profile_dir " \
                       'under [thunderbird] names the one you use.')
      end

      # @param folder [String] the config's documents folder
      # @return [void]
      def documents(folder)
        locations = SearchLocations.new(env: @env)
        unless locations.covers?(folder)
          unless @terminal.ask?("GNOME's file index leaves out #{tilde(folder)}, your documents folder, so Puri " \
                                "can't search it. Add it to the index's Search Locations?")
            return @terminal.todo("GNOME's file index leaves out #{tilde(folder)}, so Puri can't search it: in " \
                                  "GNOME's Settings, Search → Search Locations, add it.")
          end
          locations.add(folder)
          return @terminal.note("Added #{tilde(folder)} to GNOME's Search Locations. The index takes a while to read " \
                                'it: run bin/setup again later to check.')
        end
        index_text(FileIndex.new, folder)
      rescue GSettings::Error => e
        @terminal.todo("Can't tell which folders GNOME's file index reads: #{e.message}")
      end

      # @param index [Puri::Setup::FileIndex]
      # @param folder [String]
      # @return [void]
      def index_text(index, folder)
        if (reason = index.unavailable_reason(folder))
          return @terminal.todo("Puri can't search #{tilde(folder)} yet: #{reason}")
        end
        unless index.idle?
          return @terminal.note("GNOME's file index is still reading your files, so Puri may miss the newest. Run " \
                                "bin/setup again once `localsearch status` says it's idle.")
        end
        return @terminal.done("Your documents, #{tilde(folder)}, in GNOME's file index") unless
          (file = index.office_without_text(folder))

        unless @terminal.ask?("Your office files, such as #{tilde(file)}, are in GNOME's file index without their " \
                              "text, so Puri finds them only by name. Have the index read #{tilde(folder)} anew? " \
                              'That takes it a while.')
          return @terminal.todo("Your office files are in GNOME's file index without their text: localsearch reset " \
                                "--file #{tilde(folder)} has it read them anew.")
        end
        if index.reindex(folder)
          @terminal.note("GNOME's file index is reading #{tilde(folder)} anew: run bin/setup again later to check.")
        else
          @terminal.todo("localsearch reset --file #{tilde(folder)} failed: localsearch status may say why.")
        end
      end

      # @return [Integer] the exit status
      def finish
        @terminal.say('')
        todos = @terminal.todos
        if todos.zero?
          how = @hotkey ? "press #{Install.label(@hotkey)}" : "run gapplication launch #{Install::APP_ID}"
          @terminal.say("Puri is ready: #{how}, and ask it something.")
          return 0
        end
        @terminal.say("#{todos == 1 ? 'One thing' : "#{todos} things"} above, marked ✗, need#{'s' if todos == 1} " \
                      "you. Run bin/setup again once #{todos == 1 ? "it's" : "they're"} done.")
        1
      end

      # @param path [String]
      # @return [String]
      def tilde(path) = Terminal.tilde(path)
    end
  end
end
