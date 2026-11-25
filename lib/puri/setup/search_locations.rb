# frozen_string_literal: true

module Puri
  module Setup
    # The folders GNOME's file index reads, which Settings → Search → Search Locations lists:
    #
    #   locations = SearchLocations.new
    #   locations.covers?('/home/u/Documents')   # => true under the default '&DOCUMENTS'
    #   locations.add('/home/u/Papers')          # Puri's documents folder, indexed from now on
    #
    # An entry is a path, `$HOME` or `~`, or the name of one of the desktop's own folders,
    # `&DOCUMENTS`, as `~/.config/user-dirs.dirs` records it in the desktop's language.
    class SearchLocations
      # @return [String]
      SCHEMA = 'org.freedesktop.Tracker3.Miner.Files'

      # @return [String] the folders read with every folder under them
      KEY = 'index-recursive-directories'

      # @param env [#[]] where `HOME` and `XDG_CONFIG_HOME` come from
      def initialize(env: ENV)
        @home = env['HOME'].to_s.empty? ? Dir.home : env['HOME']
        config = env['XDG_CONFIG_HOME'].to_s.empty? ? File.join(@home, '.config') : env['XDG_CONFIG_HOME']
        @user_dirs = File.join(config, 'user-dirs.dirs')
      end

      # @param folder [String] absolute
      # @return [Boolean] whether the index reads it, being it or under one of its folders
      # @raise [Puri::Setup::GSettings::Error] without localsearch's settings
      def covers?(folder)
        folder = real(folder)
        GSettings.strv(SCHEMA, KEY).filter_map { resolve(_1) }.any? do |dir|
          dir = real(dir)
          folder == dir || folder.start_with?("#{dir.chomp('/')}/")
        end
      end

      # Adds `folder`, as `&DOCUMENTS` when it is the desktop's own Documents folder, as Settings
      # names it there.
      #
      # @param folder [String] absolute
      # @return [void]
      # @raise [Puri::Setup::GSettings::Error]
      def add(folder)
        entry = real(folder) == real(user_dir('DOCUMENTS') || '') ? '&DOCUMENTS' : folder
        GSettings.set_strv(SCHEMA, KEY, GSettings.strv(SCHEMA, KEY) | [entry])
      end

      private

      # @param entry [String]
      # @return [String, nil] the folder it names; nil for a desktop folder that isn't set
      def resolve(entry)
        case entry
        when '$HOME', '~' then @home
        when /\A&(\w+)\z/ then user_dir(Regexp.last_match(1).delete('_'))
        when %r{\A~/} then File.join(@home, entry.delete_prefix('~/'))
        else entry
        end
      end

      # @param name [String] `DOCUMENTS`, `DOWNLOAD`, `PUBLICSHARE`, …
      # @return [String, nil] the folder `user-dirs.dirs` gives it; `~/Documents` for Documents
      #   when the file doesn't say, as for Puri's own default, and nil for another; nil, too, when
      #   it names the home, which is how a folder is switched off
      def user_dir(name)
        line = File.file?(@user_dirs) && File.foreach(@user_dirs, encoding: 'UTF-8').find do
          _1.start_with?("XDG_#{name}_DIR=")
        end
        dir = line && line[/\A\w+="(.+)"/, 1]&.sub(%r{\A\$HOME(?=/|\z)}, @home)
        dir ||= File.join(@home, 'Documents') if name == 'DOCUMENTS'
        dir && real(dir) != real(@home) ? dir : nil
      end

      # @param path [String]
      # @return [String] its real path when it exists, so a link to a folder counts as the folder
      def real(path)
        File.realpath(path)
      rescue SystemCallError
        File.expand_path(path)
      end
    end
  end
end
