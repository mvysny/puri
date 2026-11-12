# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'time'

module Puri
  module Core
    # The saved conversations, in pikuri-web's on-disk format (`D_port_pikuri_web`): one directory
    # per conversation, pikuri's `history.json` beside our `meta.json`.
    #
    #   store = Store.new(root: Store.default_root)
    #   id = store.mint                                   # "2026-11-12T09-14-03Z-3f9a"; no directory yet
    #   store.save(conversation.summary, agent.export_history, model: 'Ornith-1.5', server: 'http://…/v1')
    #   store.retitle(id, 'Keeping An Avocado')           # meta.json only, once saved
    #   store.list                                        # => [ConversationSummary], newest first
    #   agent.load_history!(store.history(id))
    #   store.delete(id)
    #
    # A directory without `meta.json` isn't listed: `meta.json` is written last, so it's the
    # commit point, and {#delete} removes it first. One whose `meta.json` is unreadable or of an
    # unknown schema is left out with a warning, and left alone on disk.
    #
    # Thread-safe for different conversations; one conversation's writes must not overlap, as both
    # files go through a fixed temp name.
    #
    # == Implementation details
    #
    # `meta.json` is pikuri-web's schema 1, plus `last_question` and `asked_at`, which a reader of
    # schema 1 ignores; they let {#list} build every {Protocol::ConversationSummary} without
    # opening a `history.json`. Directories are 0700 from the start: a conversation holds all the
    # user typed, unencrypted.
    class Store
      # @return [Integer] `meta.json`'s format version, bumped only for a change an old reader
      #   couldn't survive
      SCHEMA = 1
      # @return [String]
      META_FILE = 'meta.json'
      # @return [String] what `meta.json`'s `shell` says wrote it
      SHELL = 'puri'
      # @return [String] the id's start stamp, UTC
      ID_TIME = '%Y-%m-%dT%H-%M-%SZ'
      # @return [Regexp]
      ID = /\A\d{4}-\d\d-\d\dT\d\d-\d\d-\d\dZ-[0-9a-f]+\z/

      # @return [Logger]
      LOGGER = Pikuri.logger_for('Store')

      # @param env [#[]] where `XDG_STATE_HOME` comes from
      # @return [String] `$XDG_STATE_HOME/puri/conversations`, `~/.local/state` by default
      def self.default_root(env: ENV)
        state = env['XDG_STATE_HOME'].to_s.empty? ? File.join(Dir.home, '.local', 'state') : env['XDG_STATE_HOME']
        File.join(state, 'puri', 'conversations')
      end

      # Creates `root`, 0700, if it isn't there.
      #
      # @param root [String] one subdirectory per conversation
      def initialize(root:)
        @root = Pathname(root)
        mkdir_private(@root)
      end

      # A new conversation's id. It sorts and greps by date; the random suffix keeps two minted in
      # one second apart.
      #
      # @param at [Time] when the conversation starts
      # @return [String]
      def mint(at = Time.now) = "#{at.getutc.strftime(ID_TIME)}-#{SecureRandom.hex(2)}"

      # @return [Array<Puri::Protocol::ConversationSummary>] every saved conversation, newest
      #   first, none running
      def list
        @root.children.filter_map { |dir| summary(dir) }.sort_by(&:id).reverse
      end

      # @param id [String] a listed conversation's
      # @return [Pikuri::Agent::History]
      # @raise [Pikuri::Agent::History::Error] for a missing or broken `history.json`
      def history(id) = Pikuri::Agent::History.load(dir(id))

      # Writes the history, then `meta.json`.
      #
      # @param summary [Puri::Protocol::ConversationSummary] the title, timestamps and last
      #   question to store
      # @param history [Pikuri::Agent::History]
      # @param model [String] the model the agent is on
      # @param server [String] its transport's `api_base`
      # @return [void]
      # @raise [SystemCallError] when a write fails
      def save(summary, history, model:, server:)
        dir = dir(summary.id)
        mkdir_private(dir)
        history.save(dir)
        meta = {
          'schema' => SCHEMA, 'id' => summary.id, 'title' => summary.title,
          'created_at' => utc(summary.started_at), 'updated_at' => Time.now.utc.iso8601,
          'shell' => SHELL, 'model' => model, 'server' => server,
          'last_question' => summary.last_question, 'asked_at' => summary.asked_at && utc(summary.asked_at)
        }
        atomic_write(dir / META_FILE, meta)
      end

      # Renames a saved conversation; one not saved yet carries its title in its first {#save}.
      #
      # @param id [String]
      # @param title [String]
      # @return [void]
      # @raise [SystemCallError] when the write fails
      def retitle(id, title)
        path = dir(id) / META_FILE
        meta = read_meta(path)
        atomic_write(path, meta.merge('title' => title)) if meta.is_a?(Hash)
      end

      # Removes a conversation's directory, if it has one.
      #
      # @param id [String]
      # @return [void]
      def delete(id)
        dir = dir(id)
        FileUtils.rm_f(dir / META_FILE)
        FileUtils.rm_rf(dir)
      end

      private

      # @param id [String]
      # @return [Pathname]
      # @raise [ArgumentError] for anything not shaped like a minted id, so no id becomes a path
      #   outside the root
      def dir(id)
        raise ArgumentError, "not a conversation id: #{id.inspect}" unless ID.match?(id)

        @root / id
      end

      # @param dir [Pathname]
      # @return [Puri::Protocol::ConversationSummary, nil] nil for anything but a readable, saved
      #   conversation
      def summary(dir)
        return nil unless dir.directory? && ID.match?(dir.basename.to_s)

        meta = read_meta(dir / META_FILE)
        return nil if meta == :absent

        found = summary_of(dir.basename.to_s, meta)
        LOGGER.warn("skipping #{dir}: its #{META_FILE} can't be read") unless found
        found
      end

      # @param id [String]
      # @param meta [Hash{String => Object}, nil]
      # @return [Puri::Protocol::ConversationSummary, nil]
      def summary_of(id, meta)
        return nil unless meta.is_a?(Hash) && meta['title'].is_a?(String)

        Protocol::ConversationSummary.new(id:, title: meta['title'], started_at: local(meta['created_at']),
                                          running: false, last_question: meta['last_question']&.to_s,
                                          asked_at: meta['asked_at'] && local(meta['asked_at']))
      rescue ArgumentError, TypeError
        nil # a timestamp that doesn't parse
      end

      # @param path [Pathname]
      # @return [Hash{String => Object}, Symbol, nil] the envelope; nil when it can't be read or
      #   is of another schema, `:absent` when there is none
      def read_meta(path)
        meta = JSON.parse(path.read)
        meta if meta.is_a?(Hash) && meta['schema'] == SCHEMA
      rescue Errno::ENOENT
        :absent
      rescue JSON::ParserError, SystemCallError
        nil
      end

      # @param iso [String] ISO 8601, any offset
      # @return [String] the same instant in UTC, as pikuri-web writes it
      def utc(iso) = Time.iso8601(iso).utc.iso8601

      # @param iso [String] ISO 8601, any offset
      # @return [String] the same instant in local time, as {Protocol::ConversationSummary} carries it
      def local(iso) = Time.iso8601(iso).getlocal.iso8601

      # 0700 by chmod, since `mkdir_p`'s `mode:` goes through the umask.
      #
      # @param dir [Pathname]
      # @return [void]
      def mkdir_private(dir)
        FileUtils.mkdir_p(dir)
        FileUtils.chmod(0o700, dir)
      end

      # A sibling temp file and a rename, so a reader never sees half a `meta.json`.
      #
      # @param path [Pathname]
      # @param meta [Hash{String => Object}]
      # @return [void]
      def atomic_write(path, meta)
        tmp = path.dirname / ".#{path.basename}.tmp"
        tmp.write("#{JSON.pretty_generate(meta)}\n")
        tmp.rename(path)
      end
    end
  end
end
