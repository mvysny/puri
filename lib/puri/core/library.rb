# frozen_string_literal: true

require 'digest'
require 'fileutils'

module Puri
  module Core
    # The `[documents]` folder, for every conversation at once: its index in Qdrant beside an
    # SQLite FTS5 file, the watcher that keeps the index in step with the disk, and the `Notes/`
    # folder the agent writes in. Each agent gets an extension of its own over the one corpus.
    #
    #   library = Library.new(config.documents, cache_dir: PikuriCore.cache_dir)  # starts at once
    #   Pikuri::Rag::Extension.new(corpus: library.corpus, reranker: library.reranker)  # waits for it
    #   library.memory          # => Notes/PURI.md's text, "" when absent
    #   library.close           # the watcher, the corpus, then the container
    #
    # Starting runs on a thread of its own: Qdrant takes seconds to come up, and the extractors'
    # container minutes to build the first time, while the popup must come up at once. The first
    # embed of a real folder takes hours, and the watcher does it in the background, a file at a
    # time; search meanwhile finds what is indexed so far.
    #
    # The documents are declared private and untrusted, like the secretary's in pikuri: a
    # documents folder holds downloaded attachments and other people's files.
    #
    # Thread-safe.
    class Library
      # @return [Logger]
      LOGGER = Pikuri.logger_for('Library')

      # Longest {#close} waits for a start still in progress.
      #
      # @return [Integer] seconds
      CLOSE_SECONDS = 5

      # @return [Puri::Core::Config::Documents]
      attr_reader :documents

      # @return [Pikuri::VectorDb::Reranker::LlamaServer, nil] nil when the config names no
      #   reranker
      attr_reader :reranker

      # Creates `Notes/`, and starts the index.
      #
      # @param documents [Puri::Core::Config::Documents]
      # @param cache_dir [String] where the FTS5 file goes
      # @param server [Class] the vector server: `Pikuri::VectorDb::Server::Qdrant`, or a spec's
      #   `InMemory`
      # @param embedder [#embed, nil] nil for the one `documents` names
      # @param extractors [Boolean] whether to register the office-format extractors and build their
      #   image; specs leave the registry alone
      def initialize(documents, cache_dir:, server: Pikuri::VectorDb::Server::Qdrant, embedder: nil,
                     extractors: true)
        @documents = documents
        FileUtils.mkdir_p(documents.notes)
        @embedder = embedder || Pikuri::VectorDb::Embedder.new(server: documents.server, model: documents.embed_model,
                                                               api_key: documents.api_key || 'not-needed',
                                                               around_request: Pikuri::Conversations::Throttle)
        @reranker = documents.rerank_model && Pikuri::VectorDb::Reranker::LlamaServer.new(
          server: documents.server, model: documents.rerank_model, api_key: documents.api_key,
          around_request: Pikuri::Conversations::Throttle
        )
        @lock = Mutex.new
        @vector_server = nil
        @corpus = nil
        @watcher = nil
        @closed = false
        @start = Thread.new { start(server, cache_dir, extractors) }
        @start.name = 'puri-library'
        @start.report_on_exception = false
      end

      # @return [Pikuri::VectorDb::Corpus] once started; waits until it is
      # @raise [StandardError] what the start failed on: Qdrant not coming up, say
      def corpus = @start.value

      # @return [String] the memory note's text, stripped; "" when it doesn't exist yet
      def memory
        File.exist?(documents.memory) ? File.read(documents.memory).strip : ''
      end

      # Stops the watcher, its file in progress finished first, then closes the corpus and the
      # container. A start still in progress gets {CLOSE_SECONDS}, and whatever it opened later
      # closes as it does.
      #
      # @return [void]
      def close
        @lock.synchronize { @closed = true }
        @start.join(CLOSE_SECONDS)
        teardown
      end

      private

      # @param server_class [Class]
      # @param cache_dir [String]
      # @param extractors [Boolean]
      # @return [Pikuri::VectorDb::Corpus]
      def start(server_class, cache_dir, extractors)
        register_extractors if extractors
        collection = "puri-#{Digest::SHA256.hexdigest(File.realpath(documents.folder))[0, 12]}"
        @lock.synchronize { @vector_server = server_class.ensure_running }
        @lock.synchronize { @corpus = corpus_on(@vector_server.client(collection:), store(cache_dir, collection)) }
        @lock.synchronize { @watcher = Pikuri::VectorDb::Watcher.new(corpus: @corpus).start }
        LOGGER.info("#{documents.folder}: #{@corpus.backend.count} chunk(s) indexed, the watcher catching up")
        teardown if @lock.synchronize { @closed }
        @corpus
      rescue StandardError => e
        LOGGER.error("#{documents.folder}: can't start the index: #{e.class}: #{e.message}")
        raise
      end

      # The office formats and PDFs, converted in a networkless container; the image is built
      # here, the first time, rather than on the first document. A machine without docker falls
      # back to the host's pandoc and markitdown, or reads those formats not at all.
      #
      # @return [void]
      def register_extractors
        Pikuri::Extractors::DOCUMENTS.register
        Pikuri::Extractors::DOCUMENTS.ensure_image!
      rescue Pikuri::Extractor::Error => e
        LOGGER.warn("office formats: #{e.message}")
      end

      # @param vectors [Object] the vector server's client
      # @param store [String] the FTS5 file
      # @return [Pikuri::VectorDb::Corpus]
      def corpus_on(vectors, store)
        Pikuri::VectorDb::Corpus.new(
          backend: Pikuri::Rag::Backend::Hybrid.new(vectors:, keywords: Pikuri::Rag::Backend::Fts5.new(store:)),
          source: documents.folder, embedder: @embedder, private: true, trusted: false, exclude: documents.exclude
        )
      end

      # @param cache_dir [String]
      # @param collection [String]
      # @return [String] the FTS5 file, named as the Qdrant collection
      def store(cache_dir, collection)
        FileUtils.mkdir_p(cache_dir, mode: 0o700)
        File.join(cache_dir, "#{collection}.sqlite3")
      end

      # Closes what the start opened, each once.
      #
      # @return [void]
      def teardown
        watcher, corpus, server = @lock.synchronize do
          taken = [@watcher, @corpus, @vector_server]
          @watcher = @corpus = @vector_server = nil
          taken
        end
        watcher&.close
        corpus&.close
        server&.close
      end
    end
  end
end
