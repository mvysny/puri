# frozen_string_literal: true

require 'tomlrb'
require 'typemap'

module Puri
  module Core
    # Puri's `config.toml`: the model connections, which one writes the titles, the search
    # engines' keys, the Thunderbird profile and the documents folder. Loaded once
    # at startup, and required: there is no built-in connection, so a missing or incomplete file
    # raises {Error} with {EXAMPLE_CONFIG} and the path to write it to, and Puri does not start.
    #
    #   config = Config.load
    #   config.primary_llm   # => Llm(name:, server:, model:, api_key:, context_window:, params:)
    #   config.titler_llm    # => the [titler] connection, never nil
    #   config.servers       # => [Server(id:, url:, api_key:, max_concurrent_requests:)]
    #   config.search        # => SearchTable(brave_key:, exa_key:, engines:), or nil with no key
    #   config.thunderbird   # => ThunderbirdTable(enabled:, profile_dir:), or nil when switched off
    #   config.documents     # => Documents(folder:), or nil without the table
    #   config.maps          # => MapsTable(tiles:), or nil without the table
    #   config.weather       # => WeatherTable(url:), or nil without the table
    #   config.dictation     # => DictationTable(url:, api_key:, model:), or nil without the table
    #
    # The file is Puri's own, `$XDG_CONFIG_HOME/puri/config.toml` (default `~/.config`), never
    # the `pikuri/config.toml` pikuri-tui and pikuri-web share; no other app writes it, so the
    # schema holds only what Puri reads and a key it doesn't know is an error. The schema is
    # pikuri-web's, cut down:
    #
    #   [[server]]                       # one box: its URL and key, stated once
    #   id      = "local"
    #   url     = "http://localhost:8080"
    #   api_key = "…"                    # optional; a local llama-server needs none
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
    #   folder = "~/Documents"           # optional, the default; notes go in its Notes/
    #
    #   [maps]                           # optional; omitted, the agent has no place tools
    #   tiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"   # required; the map's tiles
    #
    #   [weather]                        # optional, and only with [maps]; omitted, no weather tool
    #   url = "https://api.open-meteo.com"   # optional, the default; a self-hosted Open-Meteo
    #
    #   [dictation]                      # optional; omitted, the prompt has no mic
    #   url     = "http://127.0.0.1:8081"  # required; an OpenAI-style transcription server
    #   api_key = "…"                    # optional; a local whisper-server needs none
    #   model   = "whisper-1"            # optional, the default; whisper-server ignores it
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
      #   @return [String] base URL, with or without `/v1`; pikuri strips it either way
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
        # @param url [String]
        # @param api_key [String, nil]
        # @param max_concurrent_requests [Integer, nil]
        def initialize(id:, url:, api_key: nil, max_concurrent_requests: nil) = super

        # Names the entry in a schema error: `server[1] "local".url: required`.
        #
        # @param raw [Hash{String => Object}] the entry as written, unchecked
        # @return [Object] its `id`
        def self.entry_name(raw) = raw['id']
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
      #   @return [String] see {Documents#folder}, `~` unexpanded
      class DocumentsTable < Data.define(:folder)
        extend Typemap::Constrain

        constrain :folder, not_blank: true

        # @param folder [String]
        def initialize(folder: '~/Documents') = super
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

      # The `[dictation]` table, which turns on the mic in the prompt (`D_dictation`): an
      # OpenAI-style transcription server of the user's own, whisper.cpp's `whisper-server` on
      # this machine unless they opt into a hosted one. Its own URL, not a `[[server]]` id: those
      # are chat servers.
      #
      # @!attribute [r] url
      #   @return [String] base URL, with or without `/v1`
      # @!attribute [r] api_key
      #   @return [String, nil] the key, or nil for a server that needs none
      # @!attribute [r] model
      #   @return [String] what the request names; `whisper-server` ignores it
      class DictationTable < Data.define(:url, :api_key, :model)
        extend Typemap::Constrain

        constrain :url, :model, not_blank: true

        # @param url [String]
        # @param api_key [String, nil]
        # @param model [String]
        def initialize(url:, api_key: nil, model: 'whisper-1') = super
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

      # A file that loads: Qwen 3.5 4B on a local llama-server with its thinking on, and the
      # same model with it off for titles, each with its card's sampling, as the README's
      # `llama-server` line starts it. Every "nothing configured" error quotes it.
      #
      # @return [String] a paste-ready `config.toml`
      EXAMPLE_CONFIG = <<~TOML
        [[server]]
        id  = "local"
        url = "http://localhost:8080"

        [[llm]]
        name   = "Qwen 3.5 4B"
        server = "local"
        model  = "ggml-org/Qwen3.5-4B-GGUF:Q4_K_M"
        [llm.params]                     # the model card's sampling, thinking on
        temperature      = 1.0
        top_p            = 0.95
        top_k            = 20
        min_p            = 0.0
        presence_penalty = 1.5
        chat_template_kwargs = { enable_thinking = true }

        [[llm]]
        name   = "Qwen 3.5 4B, no thinking"
        server = "local"
        model  = "ggml-org/Qwen3.5-4B-GGUF:Q4_K_M"
        [llm.params]                     # and thinking off
        temperature      = 0.7
        top_p            = 0.8
        top_k            = 20
        min_p            = 0.0
        presence_penalty = 1.5
        chat_template_kwargs = { enable_thinking = false }

        [titler]
        llm = "Qwen 3.5 4B, no thinking"

        # Web search, through Brave or Exa; without a key, the agent has no web tools.
        # [search]
        # brave_key = "…"

        # Places, routes by car, and a map under the answer, on OpenStreetMap's public services.
        # [maps]
        # tiles = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"

        # The weather, from Open-Meteo (weather data by Open-Meteo.com, CC BY 4.0); needs [maps].
        # [weather]

        # The mic in the prompt (F5), transcribed by your own whisper-server; see the README.
        # [dictation]
        # url = "http://127.0.0.1:8081"
      TOML

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
      #   schema, no `[[llm]]` or `[titler]` is defined, `[search]` names an engine it can't use, or
      #   `[weather]` comes without `[maps]`
      def self.load(env: ENV)
        files = candidate_paths(env).select { |path| File.file?(path) }
        raise Error, "no config file found. #{write_example(env)}" if files.empty?

        merged = files.reduce({}) do |acc, path|
          parsed = parse_file(path)
          warn_loose_perms(path, parsed)
          deep_merge(acc, parsed)
        end
        root = map(merged)
        raise Error, "no [[llm]] is defined. #{write_example(env)}" if root.llm.empty?
        raise Error, "no [titler] names the connection that writes titles. #{write_example(env)}" unless root.titler

        servers = root.server.to_h { |server| [server.id, server] }
        llms = root.llm.map { |table| resolve_llm(table, servers) }
        new(llms:, servers: root.server, titler_llm: resolve_titler(root.titler, llms),
            search: resolve_search(root.search), thunderbird: resolve_thunderbird(root.thunderbird),
            documents: root.documents && resolve_documents(root.documents), maps: root.maps && resolve_maps(root.maps),
            weather: root.weather && resolve_weather(root.weather, root.maps),
            dictation: root.dictation && resolve_dictation(root.dictation))
      end

      # @param llms [Array<Puri::Core::Config::Llm>] never empty
      # @param servers [Array<Puri::Core::Config::Server>] the `[[server]]` entries `llms` were
      #   resolved against
      # @param titler_llm [Puri::Core::Config::Llm]
      # @param search [Puri::Core::Config::SearchTable, nil] a keyed `[search]`, or nil
      # @param thunderbird [Puri::Core::Config::ThunderbirdTable, nil] an enabled `[thunderbird]`,
      #   or nil; nil by default, so a config built in code reads no profile unless it says which
      # @param documents [Puri::Core::Config::Documents, nil] the `[documents]` folder, or nil
      # @param maps [Puri::Core::Config::MapsTable, nil] the `[maps]` table, or nil
      # @param weather [Puri::Core::Config::WeatherTable, nil] the `[weather]` table, or nil
      # @param dictation [Puri::Core::Config::DictationTable, nil] the `[dictation]` table, or nil
      def initialize(llms:, servers:, titler_llm:, search: nil, thunderbird: nil, documents: nil, maps: nil,
                     weather: nil, dictation: nil)
        @llms = llms.freeze
        @servers = servers.freeze
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

      # @return [Array<Puri::Core::Config::Server>] every `[[server]]`, in file order, those no
      #   `[[llm]]` names included
      attr_reader :servers

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
        home = env['XDG_CONFIG_HOME'].to_s.empty? ? File.join(Dir.home, '.config') : env['XDG_CONFIG_HOME']
        [*dirs.split(':').reverse, home].map { |root| File.join(root, XDG_SUBDIR, FILENAME) }
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
      # @return [Puri::Core::Config::Documents]
      # @raise [Error] when `folder` is no directory
      def self.resolve_documents(table)
        folder = File.expand_path(table.folder)
        raise Error, "documents.folder: #{folder} is not a directory" unless File.directory?(folder)

        Documents.new(folder:)
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
      # @return [Puri::Core::Config::DictationTable] `table`
      # @raise [Error] when `url` isn't http(s)
      def self.resolve_dictation(table)
        raise Error, "dictation.url: #{table.url} is no http(s) URL" unless table.url.match?(%r{\Ahttps?://}i)

        table
      end

      # @param env [#[]]
      # @return [String] where to write the config, and what
      def self.write_example(env)
        "Puri has no built-in connection; write #{candidate_paths(env).last}, for example:\n\n#{EXAMPLE_CONFIG}"
      end

      private_class_method :candidate_paths, :warn_loose_perms, :keys?, :parse_file, :deep_merge, :map,
                           :resolve_llm, :resolve_titler, :resolve_search, :resolve_thunderbird,
                           :resolve_documents, :resolve_maps, :resolve_weather, :resolve_dictation, :write_example
    end
  end
end
