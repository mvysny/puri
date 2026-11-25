# frozen_string_literal: true

require 'securerandom'
require 'shellwords'
require 'socket'
require 'tomlrb'
require 'typemap'

module Puri
  module Core
    # Puri's `config.toml`: the model connections, which one writes the titles, the search
    # engines' keys, the Thunderbird profile and the documents folder. Loaded once
    # at startup, and required: there is no built-in connection, so a missing or incomplete file
    # raises {Error} pointing at {EXAMPLE}, and Puri does not start.
    #
    #   config = Config.load
    #   config.primary_llm   # => Llm(name:, server:, model:, api_key:, context_window:, params:)
    #   config.titler_llm    # => the [titler] connection, never nil
    #   config.servers       # => [Server(id:, url:, api_key:, max_concurrent_requests:)]
    #   config.embedded_server   # => EmbeddedServer(id:, model:, port:, api_key:), or nil
    #   config.search        # => SearchTable(brave_key:, exa_key:, engines:), or nil with no key
    #   config.thunderbird   # => ThunderbirdTable(enabled:, profile_dir:), or nil when switched off
    #   config.documents     # => Documents(folder:), or nil without the table
    #   config.maps          # => MapsTable(tiles:), or nil without the table
    #   config.weather       # => WeatherTable(url:), or nil without the table
    #   config.dictation     # => DictationTable(url:, api_key:, model:, language:), or nil without the table
    #
    # The file is Puri's own, `$XDG_CONFIG_HOME/puri/config.toml` (default `~/.config`), never
    # the `pikuri/config.toml` pikuri-tui and pikuri-web share; no other app writes it, so the
    # schema holds only what Puri reads and a key it doesn't know is an error. The schema is
    # pikuri-web's, cut down:
    #
    #   [[server]]                       # one box: its URL and key, stated once
    #   id      = "local"
    #   url     = "http://localhost:8080"  # optional; omitted, Puri runs llama-server itself
    #   api_key = "…"                    # optional, and only with a url; a local llama-server needs none
    #   max_concurrent_requests = 1      # optional; omitted, sized from the server's slots
    #
    #   [[llm]]                          # one model on a box; the first is the conversations'
    #   name           = "Qwen 3.5 4B"
    #   server         = "local"         # a [[server]] id, never a URL
    #   model          = "ggml-org/Qwen3.5-4B-GGUF:Q4_K_M"
    #   context_window = 65536           # optional; omitted, pikuri asks the server
    #   params         = { … }           # optional; merged into every request, verbatim
    #
    #   [titler]
    #   llm = "Qwen 3.5 4B, no thinking" # an [[llm]] name; required
    #
    #   [search]                         # optional; without a key, the agent has no web tools
    #   brave_key = "…"                  # Brave's, Exa's or both: only they return page text
    #   exa_key   = "…"
    #   engines   = ["brave"]            # optional; omitted, every engine with a key
    #
    #   [thunderbird]                    # optional; omitted, the profile is discovered
    #   enabled     = false              # optional; false, the agent has no mail or calendar
    #   profile_dir = "~/.thunderbird/x" # optional; omitted, discovered (snap, then apt)
    #
    #   [documents]                      # optional; omitted, the agent has no files
    #   folder = "~/Documents"           # optional; omitted, the desktop's own, in its language
    #
    #   [maps]                           # optional; omitted, the agent has no place tools
    #   tiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"   # required; the map's tiles
    #
    #   [weather]                        # optional, and only with [maps]; omitted, no weather tool
    #   url = "https://api.open-meteo.com"   # optional, the default; a self-hosted Open-Meteo
    #
    #   [dictation]                      # optional; omitted, the prompt has no mic
    #   url      = "http://127.0.0.1:8081"  # optional; an OpenAI-style transcription server, and
    #                                       # without it Puri runs whisper-cli once per clip
    #   api_key  = "…"                   # optional, and only with a url
    #   model    = "whisper-1"           # with a url, optional, the default, which whisper-server
    #                                    # ignores; without, required: the file whisper-cli loads,
    #                                    # "ggerganov/whisper.cpp:ggml-small.bin"
    #   language = "auto"                # optional, the default; or a code such as "de"
    #
    # A `[[server]]` without a `url` is the llama-server Puri runs itself (`D_embedded`), on the one
    # model every `[[llm]]` on it names, `org/repo:quant` as `-hf` takes it; at most one may lack
    # a `url`.
    #
    # `params` is a passthrough, since how to switch thinking off differs per server and per chat
    # template; only its shape is checked here.
    #
    # == Layers
    #
    # Lowest to highest: each `$XDG_CONFIG_DIRS` entry (default `/etc/xdg`, earlier ranks
    # higher), then `$XDG_CONFIG_HOME`. Tables merge key by key; arrays (`[[server]]`, `[[llm]]`)
    # are replaced whole by the nearest file that has them. `server` references resolve after the
    # merge, so a user file may add an `[[llm]]` on a system file's `[[server]]`.
    #
    # == Implementation details
    #
    # Typemap maps the merged TOML onto {Root} and the classes in it, checking each value against
    # the type its YARD tag gives, read back from `sig/puri.rbs`: a stale `sig/` means stale
    # config types, so `rake sig` after changing a tag. {.load} then resolves each {LlmTable}
    # against its {Server} into an {Llm}.
    #
    # Immutable.
    class Config
      # Raised for a missing, unreadable, malformed or incomplete config; the message names the
      # file or the offending key, and says what to write.
      class Error < StandardError; end

      # One inference server, referenced by {#id} from any number of `[[llm]]` entries.
      #
      # @!attribute [r] id
      #   @return [String] what an `[[llm]]`'s `server` names; never shown, never stored
      # @!attribute [r] url
      #   @return [String, nil] base URL, with or without `/v1`; pikuri strips it either way. Nil
      #     only as the file writes the server Puri runs itself: {Config.load} fills in its
      #     {EmbeddedServer#url}.
      # @!attribute [r] api_key
      #   @return [String, nil] the key, stored literally, or nil for a server that needs none.
      #     In this file rather than an env var, which every subprocess would inherit.
      # @!attribute [r] max_concurrent_requests
      #   @return [Integer, nil] a `Pikuri::Conversations::Throttle` limit, or nil to size it from
      #     the server's own `total_slots`
      class Server < Data.define(:id, :url, :api_key, :max_concurrent_requests)
        extend Typemap::Constrain

        constrain :id, :url, not_blank: true
        constrain :max_concurrent_requests, in: (1..)

        # @param id [String]
        # @param url [String, nil]
        # @param api_key [String, nil]
        # @param max_concurrent_requests [Integer, nil]
        def initialize(id:, url: nil, api_key: nil, max_concurrent_requests: nil) = super

        # Names the entry in a schema error: `server[1] "local".url: required`.
        #
        # @param raw [Hash{String => Object}] the entry as written, unchecked
        # @return [Object] its `id`
        def self.entry_name(raw) = raw['id']
      end

      # The llama-server Puri runs itself, for the `[[server]]` with no `url` (`D_embedded`): the
      # one model its `[[llm]]`s name, and the loopback port and key {Config.load} picks for this
      # run, the same for every restart within it.
      #
      #   config.embedded_server.url   # => "http://127.0.0.1:41235"
      #
      # @!attribute [r] id
      #   @return [String] its `[[server]]`'s
      # @!attribute [r] model
      #   @return [String] `org/repo:quant`, what `-hf` loads
      # @!attribute [r] port
      #   @return [Integer] a free one on 127.0.0.1
      # @!attribute [r] api_key
      #   @return [String] fresh each run, so nothing else on the machine may use the model
      class EmbeddedServer < Data.define(:id, :model, :port, :api_key)
        # @return [String] what its `[[llm]]`s connect to
        def url = "http://127.0.0.1:#{port}"

        # Data's own would print the key into any log line.
        #
        # @return [String]
        def inspect = "#<#{self.class} id=#{id.inspect} model=#{model.inspect} port=#{port} api_key=[REDACTED]>"
        alias to_s inspect
      end

      # One model connection, its `[[server]]` resolved into it; its fields are
      # `Pikuri::Agent::ChatTransport.from_openai_server`'s keywords.
      #
      # @!attribute [r] name
      #   @return [String] unique, e.g. `"Ornith 1.5"`
      # @!attribute [r] server
      #   @return [String] the {Server#url}, never the id the file wrote
      # @!attribute [r] model
      #   @return [String] the model id sent to the server
      # @!attribute [r] api_key
      #   @return [String, nil] the {Server#api_key}
      # @!attribute [r] context_window
      #   @return [Integer, nil] the stated cap, or nil to let pikuri ask the server
      # @!attribute [r] params
      #   @return [Hash{String => Object}] merged into every request on this connection, e.g.
      #     `{"chat_template_kwargs" => {"enable_thinking" => false}}`; frozen, `{}` when omitted
      class Llm < Data.define(:name, :server, :model, :api_key, :context_window, :params)
        # @param name [String]
        # @param server [String]
        # @param model [String]
        # @param api_key [String, nil]
        # @param context_window [Integer, nil]
        # @param params [Hash{String => Object}]
        def initialize(name:, server:, model:, api_key: nil, context_window: nil, params: {})
          super(name:, server:, model:, api_key:, context_window:, params: params.freeze)
        end

        # The connection an agent rides; `params` go with it, so a connection stays
        # non-thinking wherever its transport goes. No `with_detected_modalities`: Puri sends no
        # attachments, so probing the model's modalities would buy two requests at startup for
        # nothing.
        #
        #   Pikuri::Agent.new(transport: config.primary_llm.transport, system_prompt:)
        #
        # @return [Pikuri::Agent::ChatTransport]
        def transport
          Pikuri::Agent::ChatTransport.from_openai_server(server:, model:, api_key: api_key || 'not-needed',
                                                          context_window:, params:)
        end
      end

      # One `[[llm]]` table as the file writes it; {Config.load} resolves it into an {Llm}.
      #
      # @!attribute [r] name
      #   @return [String] see {Llm#name}
      # @!attribute [r] server
      #   @return [String] the {Server#id} it runs on
      # @!attribute [r] model
      #   @return [String] see {Llm#model}
      # @!attribute [r] context_window
      #   @return [Integer, nil] see {Llm#context_window}
      # @!attribute [r] params
      #   @return [Hash{String => Object}] see {Llm#params}; checked to be a table, its contents
      #     the server's business
      class LlmTable < Data.define(:name, :server, :model, :context_window, :params)
        extend Typemap::Constrain

        constrain :name, :server, :model, not_blank: true
        constrain :context_window, in: (1..)

        # @param name [String]
        # @param server [String]
        # @param model [String]
        # @param context_window [Integer, nil]
        # @param params [Hash{String => Object}]
        def initialize(name:, server:, model:, context_window: nil, params: {}) = super

        # @param raw [Hash{String => Object}] see {Server.entry_name}
        # @return [Object] its `name`
        def self.entry_name(raw) = raw['name']
      end

      # The `[titler]` table.
      #
      # @!attribute [r] llm
      #   @return [String] the {Llm#name} that writes conversation titles
      class TitlerTable < Data.define(:llm)
        extend Typemap::Constrain

        constrain :llm, not_blank: true
      end

      # The `[search]` table: the keys `Pikuri::Web::Search.build` takes, and its engines. Only
      # Brave and Exa: `web_read_cached` reads the page text an engine returns with its results,
      # and DuckDuckGo returns none (`D_search_engines`).
      #
      # @!attribute [r] brave_key
      #   @return [String, nil] a Brave Search API key, https://api-dashboard.search.brave.com
      # @!attribute [r] exa_key
      #   @return [String, nil] an Exa key, https://exa.ai
      # @!attribute [r] engines
      #   @return [Array<String>, nil] `brave`, `exa` or both, each with its key; a set, since
      #     pikuri shuffles them per query. Nil for every engine with a key.
      class SearchTable < Data.define(:brave_key, :exa_key, :engines)
        # @param brave_key [String, nil]
        # @param exa_key [String, nil]
        # @param engines [Array<String>, nil]
        def initialize(brave_key: nil, exa_key: nil, engines: nil) = super

        # @return [Boolean] whether a key is set, Brave's or Exa's
        def keyed? = [brave_key, exa_key].any? { !_1.to_s.strip.empty? }
      end

      # The `[thunderbird]` table: which local profile `Pikuri::Thunderbird::Extension` reads.
      #
      # @!attribute [r] enabled
      #   @return [Boolean] false leaves the agent without mail, contacts and calendar
      # @!attribute [r] profile_dir
      #   @return [String, nil] the profile directory, `~` expanded; nil to discover it, which
      #     fails, naming both, when two installs hold a mail account
      class ThunderbirdTable < Data.define(:enabled, :profile_dir)
        extend Typemap::Constrain

        constrain :profile_dir, not_blank: true

        # @param enabled [Boolean]
        # @param profile_dir [String, nil]
        def initialize(enabled: true, profile_dir: nil) = super
      end

      # The `[documents]` table as the file writes it; {Config.load} resolves it into a
      # {Documents}.
      #
      # @!attribute [r] folder
      #   @return [String, nil] see {Documents#folder}, `~` unexpanded; nil for the desktop's own
      #     Documents folder
      class DocumentsTable < Data.define(:folder)
        extend Typemap::Constrain

        constrain :folder, not_blank: true

        # @param folder [String, nil]
        def initialize(folder: nil) = super
      end

      # The `[maps]` table, which turns on `place_search`, `route` and the map under an answer.
      # Their services are fixed, OSM's own; the tiles are a setting, as OSM's terms ask an app not
      # to hard-code its tile server.
      #
      # @!attribute [r] tiles
      #   @return [String] the tile server's URL template, with `{z}`, `{x}` and `{y}` in it
      class MapsTable < Data.define(:tiles)
        extend Typemap::Constrain

        constrain :tiles, not_blank: true
      end

      # The `[weather]` table, which turns on the `weather` tool (`D_weather`). It finds its place
      # through the place tools, so it needs `[maps]` too. The forecast is Open-Meteo's, whose server
      # is open source, so the URL is a setting.
      #
      # @!attribute [r] url
      #   @return [String] the API's base, without `/v1`
      class WeatherTable < Data.define(:url)
        extend Typemap::Constrain

        constrain :url, not_blank: true

        # @param url [String]
        def initialize(url: Weather::OpenMeteo::URL) = super
      end

      # The `[dictation]` table, which turns on the mic in the prompt (`D_dictation`): with a
      # `url`, an OpenAI-style transcription server of the user's own, whisper.cpp's
      # `whisper-server` unless they opt into a hosted one; without, `whisper-cli` on this
      # machine, run once per clip (`D_embedded`). Its own URL, not a `[[server]]` id: those are
      # chat servers.
      #
      # @!attribute [r] url
      #   @return [String, nil] base URL, with or without `/v1`; nil for `whisper-cli`
      # @!attribute [r] api_key
      #   @return [String, nil] the key, or nil for a server that needs none
      # @!attribute [r] model
      #   @return [String, nil] with a `url`, what the request names, which `whisper-server`
      #     ignores; without, the file `whisper-cli` loads, `org/repo:file` in the {HubCache}.
      #     Nil only as the file writes it: {Config.load} fills in `whisper-1` for a server.
      # @!attribute [r] language
      #   @return [String] what is spoken, a code such as `de`, or {AUTO}
      class DictationTable < Data.define(:url, :api_key, :model, :language)
        extend Typemap::Constrain

        # Whisper detects the language: `whisper-cli` at the price of a second encoder pass,
        # 4.6 s more for a clip on a CPU (`R_whisper_cli`); a server is left its own `-l`.
        #
        # @return [String]
        AUTO = 'auto'

        constrain :url, :model, :language, not_blank: true

        # @param url [String, nil]
        # @param api_key [String, nil]
        # @param model [String, nil]
        # @param language [String]
        def initialize(url: nil, api_key: nil, model: nil, language: AUTO) = super
      end

      # The folder the agent searches and reads, and writes only in its {#notes}. Search goes
      # through the desktop's own file index, bounded to this folder.
      #
      # @!attribute [r] folder
      #   @return [String] an existing directory, absolute
      class Documents < Data.define(:folder)
        # @return [String] where the agent writes, and keeps its memory
        def notes = File.join(folder, 'Notes')

        # @return [String] the memory note, read into each agent's system prompt
        def memory = File.join(notes, 'PURI.md')
      end

      # The whole file. Every key defaults to empty, so {Config.load} rather than Typemap says
      # what is missing, with the example to paste.
      #
      # @!attribute [r] server
      #   @return [Array<Server>] the `[[server]]` entries, ids unique
      # @!attribute [r] llm
      #   @return [Array<LlmTable>] the `[[llm]]` entries, names unique
      # @!attribute [r] titler
      #   @return [TitlerTable, nil] the `[titler]` table
      # @!attribute [r] search
      #   @return [SearchTable, nil] the `[search]` table
      # @!attribute [r] thunderbird
      #   @return [ThunderbirdTable, nil] the `[thunderbird]` table
      # @!attribute [r] documents
      #   @return [DocumentsTable, nil] the `[documents]` table
      # @!attribute [r] maps
      #   @return [MapsTable, nil] the `[maps]` table
      # @!attribute [r] weather
      #   @return [WeatherTable, nil] the `[weather]` table
      # @!attribute [r] dictation
      #   @return [DictationTable, nil] the `[dictation]` table
      class Root < Data.define(:server, :llm, :titler, :search, :thunderbird, :documents, :maps, :weather,
                               :dictation)
        extend Typemap::Constrain

        constrain :server, unique_by: :id
        constrain :llm, unique_by: :name

        # @param server [Array<Server>]
        # @param llm [Array<LlmTable>]
        # @param titler [TitlerTable, nil]
        # @param search [SearchTable, nil]
        # @param thunderbird [ThunderbirdTable, nil]
        # @param documents [DocumentsTable, nil]
        # @param maps [MapsTable, nil]
        # @param weather [WeatherTable, nil]
        # @param dictation [DictationTable, nil]
        def initialize(server: [], llm: [], titler: nil, search: nil, thunderbird: nil, documents: nil,
                       maps: nil, weather: nil, dictation: nil) = super
      end

      # The commented `config.toml` the install guide has the user copy, every feature on but web
      # search; the "nothing configured" errors point at it. A path into this checkout, which Puri
      # always runs from.
      #
      # @return [String]
      EXAMPLE = File.expand_path('../../../docs/config.toml', __dir__)

      # The file's name, and its directory under each XDG config root.
      #
      # @return [String]
      FILENAME = 'config.toml'
      # @return [String]
      XDG_SUBDIR = 'puri'

      # Types come from sig/ (the YARD tags, through sord), so each is written once.
      #
      # @return [Typemap::Mapper]
      MAPPER = Typemap::Mapper.new(types: Typemap::Mapper::RBSTypes.new)
      private_constant :MAPPER

      # Reads and resolves the layered configuration.
      #
      # @param env [#[]] where `XDG_CONFIG_HOME` and `XDG_CONFIG_DIRS` come from; specs pass
      #   their own
      # @return [Puri::Core::Config]
      # @raise [Error] when no file exists, a file can't be read or parsed, a value breaks the
      #   schema, no `[[llm]]` or `[titler]` is defined, the `[[server]]` Puri runs itself breaks
      #   its rules, `[search]` names an engine it can't use, or `[weather]` comes without `[maps]`
      def self.load(env: ENV)
        files = candidate_paths(env).select { |path| File.file?(path) }
        raise Error, "no config file found. #{copy_example(env)}" if files.empty?

        merged = files.reduce({}) do |acc, path|
          parsed = parse_file(path)
          warn_loose_perms(path, parsed)
          deep_merge(acc, parsed)
        end
        root = map(merged)
        raise Error, "no [[llm]] is defined; #{EXAMPLE} has one, commented" if root.llm.empty?
        raise Error, "no [titler] names the connection that writes titles; #{EXAMPLE} has one" unless root.titler

        embedded = resolve_embedded(root.server, root.llm)
        servers = root.server.filter_map do |server|
          next server if server.url

          server.with(url: embedded.url, api_key: embedded.api_key) if embedded
        end
        llms = root.llm.map { |table| resolve_llm(table, servers.to_h { [_1.id, _1] }) }
        new(llms:, servers:, embedded_server: embedded, titler_llm: resolve_titler(root.titler, llms),
            search: resolve_search(root.search), thunderbird: resolve_thunderbird(root.thunderbird),
            documents: root.documents && resolve_documents(root.documents, env),
            maps: root.maps && resolve_maps(root.maps),
            weather: root.weather && resolve_weather(root.weather, root.maps),
            dictation: root.dictation && resolve_dictation(root.dictation))
      end

      # @param llms [Array<Puri::Core::Config::Llm>] never empty
      # @param servers [Array<Puri::Core::Config::Server>] the `[[server]]` entries `llms` were
      #   resolved against
      # @param embedded_server [Puri::Core::Config::EmbeddedServer, nil] the llama-server Puri runs
      #   itself, or nil
      # @param titler_llm [Puri::Core::Config::Llm]
      # @param search [Puri::Core::Config::SearchTable, nil] a keyed `[search]`, or nil
      # @param thunderbird [Puri::Core::Config::ThunderbirdTable, nil] an enabled `[thunderbird]`,
      #   or nil; nil by default, so a config built in code reads no profile unless it says which
      # @param documents [Puri::Core::Config::Documents, nil] the `[documents]` folder, or nil
      # @param maps [Puri::Core::Config::MapsTable, nil] the `[maps]` table, or nil
      # @param weather [Puri::Core::Config::WeatherTable, nil] the `[weather]` table, or nil
      # @param dictation [Puri::Core::Config::DictationTable, nil] the `[dictation]` table, or nil
      def initialize(llms:, servers:, titler_llm:, embedded_server: nil, search: nil, thunderbird: nil,
                     documents: nil, maps: nil, weather: nil, dictation: nil)
        @llms = llms.freeze
        @servers = servers.freeze
        @embedded_server = embedded_server
        @titler_llm = titler_llm
        @search = search
        @thunderbird = thunderbird
        @documents = documents
        @maps = maps
        @weather = weather
        @dictation = dictation
        freeze
      end

      # @return [Array<Puri::Core::Config::Llm>] every connection, in file order; never empty
      attr_reader :llms

      # @return [Array<Puri::Core::Config::Server>] every `[[server]]`, in file order, with a
      #   `url` each: those no `[[llm]]` names included, but not one with no `url` that none names,
      #   since Puri runs no server without a model
      attr_reader :servers

      # @return [Puri::Core::Config::EmbeddedServer, nil] the llama-server Puri runs itself; nil
      #   when every `[[server]]` an `[[llm]]` names has a `url`
      attr_reader :embedded_server

      # @return [Puri::Core::Config::Llm] the connection `[titler]` names
      attr_reader :titler_llm

      # @return [Puri::Core::Config::SearchTable, nil] the engines `web_search` uses; nil when
      #   `[search]` sets neither Brave's key nor Exa's, and the agent goes without web tools
      attr_reader :search

      # @return [Puri::Core::Config::ThunderbirdTable, nil] the profile the agent reads mail and
      #   calendar from; nil when `[thunderbird]` says `enabled = false`
      attr_reader :thunderbird

      # @return [Puri::Core::Config::Documents, nil] the folder the agent searches, reads and keeps
      #   its notes in; nil without a `[documents]` table, and the agent has no files
      attr_reader :documents

      # @return [Puri::Core::Config::MapsTable, nil] the tiles the map under an answer draws; nil
      #   without a `[maps]` table, and the agent has no place tools
      attr_reader :maps

      # @return [Puri::Core::Config::WeatherTable, nil] where the forecast comes from; nil without a
      #   `[weather]` table, and the agent has no weather tool
      attr_reader :weather

      # @return [Puri::Core::Config::DictationTable, nil] the server the mic's clips go to; nil
      #   without a `[dictation]` table, and the prompt has no mic
      attr_reader :dictation

      # @return [Puri::Core::Config::Llm] where conversations run: the first `[[llm]]`
      def primary_llm = @llms.first

      # @param env [#[]]
      # @return [Array<String>] the files to read, lowest priority first
      def self.candidate_paths(env)
        dirs = env['XDG_CONFIG_DIRS'].to_s.empty? ? '/etc/xdg' : env['XDG_CONFIG_DIRS']
        [*dirs.split(':').reverse, config_home(env)].map { |root| File.join(root, XDG_SUBDIR, FILENAME) }
      end

      # @param env [#[]]
      # @return [String] `$HOME`
      def self.home(env) = env['HOME'].to_s.empty? ? Dir.home : env['HOME']

      # @param env [#[]]
      # @return [String] `$XDG_CONFIG_HOME`, `~/.config` when unset
      def self.config_home(env)
        env['XDG_CONFIG_HOME'].to_s.empty? ? File.join(home(env), '.config') : env['XDG_CONFIG_HOME']
      end

      # Warns on stderr, never fails, when a file holding a key — a `[[server]]`'s `api_key`, a
      # search engine's, `[dictation]`'s — is readable by others.
      #
      # @param path [String]
      # @param parsed [Hash{String => Object}] the file's raw TOML, unchecked
      # @return [void]
      def self.warn_loose_perms(path, parsed)
        return unless keys?(parsed)

        mode = File.stat(path).mode & 0o777
        return if mode.nobits?(0o077)

        warn "puri: #{path} holds a key but is readable by others " \
             "(mode #{format('%04o', mode)}); run `chmod 600 #{path}`"
      rescue SystemCallError
        nil # a courtesy, never fatal
      end

      # @param parsed [Hash{String => Object}] a file's raw TOML, unchecked
      # @return [Boolean] whether it holds a key
      def self.keys?(parsed)
        servers = parsed['server']
        search = parsed['search']
        dictation = parsed['dictation']
        (servers.is_a?(Array) && servers.any? { |entry| entry.is_a?(Hash) && entry['api_key'] }) ||
          (search.is_a?(Hash) && (search['brave_key'] || search['exa_key'])) ||
          (dictation.is_a?(Hash) && dictation['api_key']) || false
      end

      # @param path [String]
      # @return [Hash{String => Object}]
      # @raise [Error] on a read failure or a TOML syntax error
      def self.parse_file(path)
        Tomlrb.parse(File.read(path))
      rescue StandardError => e
        raise Error, "can't read #{path}: #{e.class}: #{e.message}"
      end

      # Tables merge key by key; scalars and arrays take the higher layer's value whole.
      #
      # @param lower [Hash{String => Object}]
      # @param higher [Hash{String => Object}]
      # @return [Hash{String => Object}] a new Hash
      def self.deep_merge(lower, higher)
        lower.merge(higher) { |_key, lo, hi| lo.is_a?(Hash) && hi.is_a?(Hash) ? deep_merge(lo, hi) : hi }
      end

      # @param merged [Hash{String => Object}]
      # @return [Puri::Core::Config::Root]
      # @raise [Error] its message starting with the offending value's path
      def self.map(merged)
        MAPPER.load(Root, merged, source: :toml)
      rescue Typemap::DataError => e
        raise Error, e.message
      end

      # The `[[server]]` with no `url`, if any `[[llm]]` names it, given a free port on loopback and
      # a fresh key.
      #
      # @param servers [Array<Puri::Core::Config::Server>] as the file writes them
      # @param llms [Array<Puri::Core::Config::LlmTable>]
      # @return [Puri::Core::Config::EmbeddedServer, nil]
      # @raise [Error] for two servers with no `url`, a key on one, or its `[[llm]]`s naming two
      #   models, or one `-hf` can't take
      def self.resolve_embedded(servers, llms)
        bare = servers.reject(&:url)
        if bare.size > 1
          raise Error, "#{bare.map { "server #{_1.id.inspect}" }.join(' and ')} have no url, and Puri runs " \
                       'one llama-server of its own; give all but one a url'
        end
        server = bare.first or return nil
        if server.api_key
          raise Error, "server #{server.id.inspect}: an api_key goes with a url; Puri makes its own key " \
                       'for the llama-server it runs'
        end
        on = llms.select { _1.server == server.id }
        models = on.map(&:model).uniq
        return nil if models.empty?

        unless models.one?
          raise Error, "#{on.map { "llm #{_1.name.inspect}" }.join(', ')}: server #{server.id.inspect} is the " \
                       'llama-server Puri runs, on one model; name the same model'
        end
        unless models.first.match?(HubCache::GGUF_MODEL)
          raise Error, "llm #{on.first.name.inspect}: #{models.first.inspect} is no Hugging Face repo, " \
                       'org/repo:quant, for the llama-server Puri runs on server ' \
                       "#{server.id.inspect}; e.g. ggml-org/Qwen3.5-4B-GGUF:Q4_K_M"
        end
        EmbeddedServer.new(id: server.id, model: models.first, port: free_port, api_key: SecureRandom.hex(32))
      end

      # @return [Integer] a port on 127.0.0.1 nothing listens on, as of now
      def self.free_port
        socket = TCPServer.new('127.0.0.1', 0)
        socket.addr[1]
      ensure
        socket&.close
      end

      # @param table [Puri::Core::Config::LlmTable]
      # @param servers [Hash{String => Puri::Core::Config::Server}] every `[[server]]`, by id
      # @return [Puri::Core::Config::Llm]
      # @raise [Error] when `server` names no `[[server]]`
      def self.resolve_llm(table, servers)
        server = servers[table.server] or
          raise Error, "llm #{table.name.inspect}: no [[server]] has id #{table.server.inspect}; " \
                       "known: #{servers.keys.map(&:inspect).join(', ').then { |s| s.empty? ? 'none' : s }}"
        Llm.new(name: table.name, server: server.url, model: table.model, api_key: server.api_key,
                context_window: table.context_window, params: table.params)
      end

      # @param table [Puri::Core::Config::TitlerTable]
      # @param llms [Array<Puri::Core::Config::Llm>]
      # @return [Puri::Core::Config::Llm]
      # @raise [Error] when `llm` names no `[[llm]]`
      def self.resolve_titler(table, llms)
        llms.find { |llm| llm.name == table.llm } or
          raise Error, "titler.llm: no [[llm]] is named #{table.llm.inspect}; " \
                       "known: #{llms.map { |llm| llm.name.inspect }.join(', ')}"
      end

      # A table with no key is no table: the agent goes without web tools, which {PikuriCore}
      # logs. One with a key must name only engines that have theirs, and neither DuckDuckGo
      # nor an engine pikuri doesn't know.
      #
      # @param table [Puri::Core::Config::SearchTable, nil]
      # @return [Puri::Core::Config::SearchTable, nil] `table`, or nil without a key
      # @raise [Error] for an engine `table` can't use
      def self.resolve_search(table)
        return nil unless table&.keyed?

        names = Pikuri::Web::Search::Engines.resolve(engines: table.engines, brave_key: table.brave_key,
                                                     exa_key: table.exa_key)
        if table.engines && names.include?(:duckduckgo)
          raise Error, 'search.engines: duckduckgo returns no page text to read; name brave or exa'
        end

        table
      rescue ArgumentError => e
        raise Error, e.message
      end

      # Thunderbird is on unless switched off: with no profile on the machine, pikuri wires
      # nothing and says so in the log.
      #
      # @param table [Puri::Core::Config::ThunderbirdTable, nil]
      # @return [Puri::Core::Config::ThunderbirdTable, nil] nil when `enabled = false`, the
      #   defaults when the table is absent, `profile_dir` expanded
      def self.resolve_thunderbird(table)
        table ||= ThunderbirdTable.new
        return nil unless table.enabled

        table.profile_dir ? table.with(profile_dir: File.expand_path(table.profile_dir)) : table
      end

      # @param table [Puri::Core::Config::DocumentsTable]
      # @param env [#[]]
      # @return [Puri::Core::Config::Documents]
      # @raise [Error] when the folder is no directory
      def self.resolve_documents(table, env)
        folder = File.expand_path(table.folder || desktop_documents(env))
        raise Error, "documents.folder: #{folder} is not a directory" unless File.directory?(folder)

        Documents.new(folder:)
      end

      # The desktop's own Documents folder, named in its language, as xdg-user-dirs records it:
      #
      #   XDG_DOCUMENTS_DIR="$HOME/Dokumenty"   # in ~/.config/user-dirs.dirs => ~/Dokumenty
      #
      # `~/Documents` without that line, and when it names the home itself, which is how
      # xdg-user-dirs switches a folder off: reading all of home needs a `folder` that says so.
      #
      # @param env [#[]]
      # @return [String] absolute, and perhaps missing
      def self.desktop_documents(env)
        home = home(env)
        file = File.join(config_home(env), 'user-dirs.dirs')
        line = File.file?(file) && File.foreach(file, encoding: 'UTF-8').find { _1.start_with?('XDG_DOCUMENTS_DIR=') }
        dir = line && line[/\AXDG_DOCUMENTS_DIR="(.+)"/, 1]&.sub(%r{\A\$HOME(?=/|\z)}, home)
        dir && File.expand_path(dir) != File.expand_path(home) ? File.expand_path(dir) : File.join(home, 'Documents')
      end

      # @param table [Puri::Core::Config::MapsTable]
      # @return [Puri::Core::Config::MapsTable] `table`
      # @raise [Error] when `tiles` lacks a placeholder or isn't http(s)
      def self.resolve_maps(table)
        missing = %w[{z} {x} {y}].reject { table.tiles.include?(_1) }
        raise Error, "maps.tiles: #{table.tiles} has no #{missing.join(', ')}" unless missing.empty?
        raise Error, "maps.tiles: #{table.tiles} is no http(s) URL" unless table.tiles.match?(%r{\Ahttps?://}i)

        table
      end

      # @param table [Puri::Core::Config::WeatherTable]
      # @param maps [Puri::Core::Config::MapsTable, nil] the `[maps]` table, which it needs
      # @return [Puri::Core::Config::WeatherTable] `table`
      # @raise [Error] without `[maps]`, or when `url` isn't http(s)
      def self.resolve_weather(table, maps)
        raise Error, '[weather] needs [maps]: the weather tool finds its place on OpenStreetMap' unless maps
        raise Error, "weather.url: #{table.url} is no http(s) URL" unless table.url.match?(%r{\Ahttps?://}i)

        table
      end

      # @param table [Puri::Core::Config::DictationTable]
      # @return [Puri::Core::Config::DictationTable] `table`, `model` filled in for a server
      # @raise [Error] for a language that's no code, a `url` that isn't http(s), or, without
      #   one, a key, or a `model` that names no file of a repo
      def self.resolve_dictation(table)
        unless table.language.match?(/\A(?:#{DictationTable::AUTO}|[a-z]{2,3})\z/o)
          raise Error, "dictation.language: #{table.language.inspect} is no language code such as en or de, " \
                       "nor #{DictationTable::AUTO}"
        end
        if table.url
          raise Error, "dictation.url: #{table.url} is no http(s) URL" unless table.url.match?(%r{\Ahttps?://}i)

          return table.with(model: table.model || 'whisper-1')
        end
        raise Error, 'dictation.api_key: a key goes with a url; whisper-cli here takes none' if table.api_key
        unless table.model&.match?(HubCache::FILE_MODEL)
          raise Error, 'dictation.model: without a url, Puri runs whisper-cli, which needs the model it loads, ' \
                       'org/repo:file, e.g. ggerganov/whisper.cpp:ggml-small.bin'
        end

        table
      end

      # @param env [#[]]
      # @return [String] the commands that copy {EXAMPLE} to where Puri reads it
      def self.copy_example(env)
        target = candidate_paths(env).last
        "Puri has no built-in connection; copy the example, which says what each part does:\n\n  " \
          "mkdir -p #{File.dirname(target).shellescape}\n  cp #{EXAMPLE.shellescape} #{target.shellescape}"
      end

      private_class_method :candidate_paths, :home, :config_home, :warn_loose_perms, :keys?, :parse_file,
                           :deep_merge, :map, :resolve_embedded, :free_port, :resolve_llm, :resolve_titler,
                           :resolve_search,
                           :resolve_thunderbird, :resolve_documents, :desktop_documents, :resolve_maps,
                           :resolve_weather, :resolve_dictation, :copy_example
    end
  end
end
