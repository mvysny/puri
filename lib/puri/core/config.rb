# frozen_string_literal: true

require 'tomlrb'
require 'typemap'

module Puri
  module Core
    # Puri's `config.toml`: the model connections, and which one writes the titles. Loaded once
    # at startup, and required: there is no built-in connection, so a missing or incomplete file
    # raises {Error} with {EXAMPLE_CONFIG} and the path to write it to, and Puri does not start.
    #
    #   config = Config.load
    #   config.primary_llm   # => Llm(name:, server:, model:, api_key:, context_window:, params:)
    #   config.titler_llm    # => the [titler] connection, never nil
    #   config.servers       # => [Server(id:, url:, api_key:, max_concurrent_requests:)]
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
    #   max_concurrent_requests = 1      # optional; omitted, pikuri sizes it from the server's slots
    #
    #   [[llm]]                          # one model on a box; the first is the conversations'
    #   name           = "Ornith 1.5"
    #   server         = "local"         # a [[server]] id, never a URL
    #   model          = "Ornith-1.5"
    #   context_window = 65536           # optional; omitted, pikuri asks the server
    #   params         = { … }           # optional; merged into every request, verbatim
    #
    #   [titler]
    #   llm = "Ornith 1.5, no thinking"  # an [[llm]] name; required
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
      #   @return [Integer, nil] a `Pikuri::Agent::ServerPermits` limit, or nil to let pikuri size
      #     it from the server's own `total_slots`
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

      # The whole file. Every key defaults to empty, so {Config.load} rather than Typemap says
      # what is missing, with the example to paste.
      #
      # @!attribute [r] server
      #   @return [Array<Server>] the `[[server]]` entries, ids unique
      # @!attribute [r] llm
      #   @return [Array<LlmTable>] the `[[llm]]` entries, names unique
      # @!attribute [r] titler
      #   @return [TitlerTable, nil] the `[titler]` table
      class Root < Data.define(:server, :llm, :titler)
        extend Typemap::Constrain

        constrain :server, unique_by: :id
        constrain :llm, unique_by: :name

        # @param server [Array<Server>]
        # @param llm [Array<LlmTable>]
        # @param titler [TitlerTable, nil]
        def initialize(server: [], llm: [], titler: nil) = super
      end

      # A file that loads: Ornith 1.5 on a local llama-server, and the same model with its
      # thinking off for titles, which takes a title from ~30 s to ~1 s. Every "nothing
      # configured" error quotes it.
      #
      # @return [String] a paste-ready `config.toml`
      EXAMPLE_CONFIG = <<~TOML
        [[server]]
        id  = "local"
        url = "http://localhost:8080"

        [[llm]]
        name   = "Ornith 1.5"
        server = "local"
        model  = "Ornith-1.5"

        [[llm]]
        name   = "Ornith 1.5, no thinking"
        server = "local"
        model  = "Ornith-1.5"
        params = { chat_template_kwargs = { enable_thinking = false } }

        [titler]
        llm = "Ornith 1.5, no thinking"
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
      #   schema, or no `[[llm]]` or `[titler]` is defined
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
        new(llms:, servers: root.server, titler_llm: resolve_titler(root.titler, llms))
      end

      # @param llms [Array<Puri::Core::Config::Llm>] never empty
      # @param servers [Array<Puri::Core::Config::Server>] the `[[server]]` entries `llms` were
      #   resolved against
      # @param titler_llm [Puri::Core::Config::Llm]
      def initialize(llms:, servers:, titler_llm:)
        @llms = llms.freeze
        @servers = servers.freeze
        @titler_llm = titler_llm
        freeze
      end

      # @return [Array<Puri::Core::Config::Llm>] every connection, in file order; never empty
      attr_reader :llms

      # @return [Array<Puri::Core::Config::Server>] every `[[server]]`, in file order, those no
      #   `[[llm]]` names included
      attr_reader :servers

      # @return [Puri::Core::Config::Llm] the connection `[titler]` names
      attr_reader :titler_llm

      # @return [Puri::Core::Config::Llm] where conversations run: the first `[[llm]]`
      def primary_llm = @llms.first

      # @param env [#[]]
      # @return [Array<String>] the files to read, lowest priority first
      def self.candidate_paths(env)
        dirs = env['XDG_CONFIG_DIRS'].to_s.empty? ? '/etc/xdg' : env['XDG_CONFIG_DIRS']
        home = env['XDG_CONFIG_HOME'].to_s.empty? ? File.join(Dir.home, '.config') : env['XDG_CONFIG_HOME']
        [*dirs.split(':').reverse, home].map { |root| File.join(root, XDG_SUBDIR, FILENAME) }
      end

      # Warns on stderr, never fails, when a file holding an `api_key` is readable by others.
      #
      # @param path [String]
      # @param parsed [Hash{String => Object}] the file's raw TOML, unchecked
      # @return [void]
      def self.warn_loose_perms(path, parsed)
        servers = parsed['server']
        return unless servers.is_a?(Array) && servers.any? { |entry| entry.is_a?(Hash) && entry['api_key'] }

        mode = File.stat(path).mode & 0o777
        return if mode.nobits?(0o077)

        warn "puri: #{path} holds an api_key but is readable by others " \
             "(mode #{format('%04o', mode)}); run `chmod 600 #{path}`"
      rescue SystemCallError
        nil # a courtesy, never fatal
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

      # @param env [#[]]
      # @return [String] where to write the config, and what
      def self.write_example(env)
        "Puri has no built-in connection; write #{candidate_paths(env).last}, for example:\n\n#{EXAMPLE_CONFIG}"
      end

      private_class_method :candidate_paths, :warn_loose_perms, :parse_file, :deep_merge, :map, :resolve_llm,
                           :resolve_titler, :write_example
    end
  end
end
