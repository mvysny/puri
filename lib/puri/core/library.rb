# frozen_string_literal: true

require 'fileutils'

module Puri
  module Core
    # The `[documents]` folder, for every conversation at once: the `Notes/` folder the agent
    # writes in, its memory note, and the desktop's own file index the agent searches it through.
    #
    #   library = Library.new(config.documents)   # creates Notes/, picks the file index
    #   library.file_index_tools   # => [fileindex_search, fileindex_read], or [] with no index
    #   library.memory             # => Notes/PURI.md's text, "" when absent
    #
    # The index is the desktop's, not ours (`D_documents`): localsearch, else recoll, as
    # `Pikuri::Fileindex.pick` picks it. Both tools reach only the documents folder, though the
    # index usually covers the whole home. It holds every PDF's and office file's text already, so
    # `fileindex_read` reads those too. No index holding the folder leaves the agent the file tools
    # alone, and a warning in the log.
    #
    # Thread-safe.
    class Library
      # @return [Logger]
      LOGGER = Pikuri.logger_for('Library')

      # @return [Puri::Core::Config::Documents]
      attr_reader :documents

      # @return [Array<Pikuri::Tool>] `fileindex_search` and `fileindex_read`, stateless, so every
      #   agent shares them; empty when no index holds the folder
      attr_reader :file_index_tools

      # Creates `Notes/`, and asks each backend in turn whether its index holds the folder.
      #
      # @param documents [Puri::Core::Config::Documents]
      # @param backends [Array<Module>] file-index backends, most preferred first; a spec passes
      #   its own
      def initialize(documents, backends: Pikuri::Fileindex::BACKENDS)
        @documents = documents
        FileUtils.mkdir_p(documents.notes)
        # Untrusted: the agent quotes the user's mail into Notes/.
        roots = Pikuri::Fileindex::Roots.new(dirs: [documents.folder], private: true, trusted: false)
        backend = begin
          Pikuri::Fileindex.pick(roots, backends:)
        rescue Pikuri::Fileindex::Unavailable => e
          LOGGER.warn("no desktop file index answers for #{documents.folder} " \
                      "(tried #{backends.map(&:label).join(', ')}): the agent reads the documents only by " \
                      "their paths; #{e.message}")
          nil
        end
        @file_index_tools = (backend ? [Pikuri::Fileindex::Search, Pikuri::Fileindex::Read] : [])
                            .map { _1.new(backend:, roots:) }.freeze
      end

      # @return [String] the memory note's text, stripped; "" when it doesn't exist yet
      def memory
        File.exist?(documents.memory) ? File.read(documents.memory).strip : ''
      end
    end
  end
end
