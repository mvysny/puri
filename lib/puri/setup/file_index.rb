# frozen_string_literal: true

require 'open3'

module Puri
  module Setup
    # GNOME's file index, localsearch, asked what the setup needs to know of the documents folder:
    #
    #   index = FileIndex.new
    #   index.unavailable_reason('/home/u/Documents')   # => nil once anything under it is indexed
    #   index.idle?                                     # => false while it reads files
    #   index.office_without_text('/home/u/Documents')  # => ".../lease.docx": indexed, no text
    #   index.reindex('/home/u/Documents')              # reads the folder anew, office text and all
    #
    # An office file indexed without its text is what `localsearch-extractor-office` installed
    # after the index read it leaves: localsearch never reads it again by itself.
    class FileIndex
      # @return [Array<String>] the extensions only `localsearch-extractor-office` reads the text of
      OFFICE = %w[docx xlsx pptx odt ods odp epub].freeze

      # @return [Integer] office files {#office_without_text} asks about at most, the newest
      SAMPLE = 5

      # @param backend [Module] answers `unavailable_reason(folders:)` and `read_text(path)`, as
      #   pikuri-fileindex's do; specs pass a fake
      # @param command [Array<String>] what runs `localsearch`; specs run a stand-in
      def initialize(backend: Pikuri::Fileindex::LocalSearch, command: %w[localsearch])
        @backend = backend
        @command = command
      end

      # @param folder [String] absolute
      # @return [String, nil] why a search there finds nothing, for the user; nil when it can
      def unavailable_reason(folder) = @backend.unavailable_reason(folders: [File.realpath(folder)])

      # @return [Boolean] whether localsearch has read every file it knows of
      def idle?
        out, status = localsearch('status')
        status.success? && out.include?('Indexer is idle')
      end

      # @param folder [String] absolute
      # @return [String, nil] an office file under it that the index holds without its text; nil
      #   when one of the newest has its text, or none is indexed
      def office_without_text(folder)
        files = Dir.glob("**/*.{#{OFFICE.join(',')}}", File::FNM_CASEFOLD, base: folder)
                   .map { File.join(folder, _1) }.select { File.file?(_1) }
        indexed = files.max_by(SAMPLE * 4) { File.mtime(_1) }.select { localsearch('info', _1).last.success? }
                       .first(SAMPLE)
        indexed.none? { @backend.read_text(_1) } ? indexed.first : nil
      end

      # @param folder [String] absolute
      # @return [Boolean] whether localsearch took the request
      def reindex(folder) = localsearch('reset', '--file', folder).last.success?

      private

      # In English whatever the desktop's language, since {#idle?} reads its words.
      #
      # @param args [Array<String>]
      # @return [Array(String, Process::Status)] stdout and stderr, and how it ended
      def localsearch(*args)
        Open3.capture2e({ 'LC_ALL' => 'C.UTF-8' }, *@command, *args)
      end
    end
  end
end
