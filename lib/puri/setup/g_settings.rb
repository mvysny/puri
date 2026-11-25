# frozen_string_literal: true

require 'open3'

module Puri
  module Setup
    # The `gsettings` command, for the keys the setup reads and writes, the GNOME shortcut and
    # localsearch's folders:
    #
    #   GSettings.strv('org.freedesktop.Tracker3.Miner.Files', 'index-recursive-directories')
    #   # => ["&DOCUMENTS", "/home/u/My 'Papers'"]
    #   GSettings.set_strv(schema, key, [*list, '/home/u/Papers'])
    #   GSettings.string("#{schema}.custom-keybinding:#{path}", 'binding')   # => "<Super>p", or nil for ''
    #
    # Values cross in GVariant's text form, which quotes a string in single quotes, or in double
    # ones when it holds a single quote.
    module GSettings
      # Raised when `gsettings` fails, its message gsettings' own: a schema that isn't installed,
      # or a key it lacks.
      class Error < StandardError; end

      # @param args [Array<String>] gsettings' arguments
      # @return [String] its stdout
      # @raise [Puri::Setup::GSettings::Error]
      def self.run(*args)
        out, err, status = Open3.capture3('gsettings', *args)
        raise Error, "gsettings #{args.first(3).join(' ')}: #{err.strip}" unless status.success?

        out
      rescue Errno::ENOENT
        raise Error, 'gsettings is missing: Puri needs GNOME'
      end

      # @param schema [String]
      # @param key [String] of type `as`
      # @return [Array<String>]
      # @raise [Puri::Setup::GSettings::Error]
      def self.strv(schema, key) = parse(run('get', schema, key))

      # @param schema [String]
      # @param key [String] of type `as`
      # @param list [Array<String>]
      # @return [void]
      # @raise [Puri::Setup::GSettings::Error]
      def self.set_strv(schema, key, list)
        run('set', schema, key, list.empty? ? '@as []' : "[#{list.map { quote(_1) }.join(', ')}]")
      end

      # @param schema [String]
      # @param key [String] of type `s`
      # @return [String, nil] nil for the empty string
      # @raise [Puri::Setup::GSettings::Error]
      def self.string(schema, key) = parse(run('get', schema, key)).first&.then { _1.empty? ? nil : _1 }

      # @param schema [String]
      # @param key [String] of type `s`
      # @param value [String]
      # @return [void]
      # @raise [Puri::Setup::GSettings::Error]
      def self.set_string(schema, key, value) = run('set', schema, key, quote(value))

      # @param schema [String]
      # @param key [String]
      # @return [void]
      # @raise [Puri::Setup::GSettings::Error]
      def self.reset(schema, key) = run('reset', schema, key)

      # @param value [String]
      # @return [String] a GVariant string
      def self.quote(value) = "'#{value.gsub(/[\\']/) { "\\#{_1}" }}'"

      # @param text [String] a GVariant string or array of strings, as `gsettings get` prints it
      # @return [Array<String>] every string in it, in order
      def self.parse(text)
        text.scan(/'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"/).map { (_1 || _2).gsub(/\\(.)/, '\1') }
      end
    end
  end
end
