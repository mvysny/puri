# frozen_string_literal: true

require 'stringio'
require 'tmpdir'

# On pikuri's in-memory vector server and an embedder that needs no model: everything but Qdrant
# and the extractors' container.
RSpec.describe Puri::Core::Library do
  # @return [Object] an embedder whose vectors are only the texts' lengths
  def embedder
    Object.new.tap { |fake| def fake.embed(texts) = texts.map { [_1.length.to_f, 1.0] } }
  end

  # @param exclude [Array<String>] relative to the folder
  # @return [Puri::Core::Library]
  def library(exclude: [])
    documents = Puri::Core::Config::Documents.new(
      folder: @folder, exclude: exclude.map { File.join(@folder, _1) }, server: 'http://fake.invalid',
      api_key: nil, embed_model: 'nomic', rerank_model: nil
    )
    @library = described_class.new(documents, cache_dir: @cache, server: Pikuri::VectorDb::Server::InMemory,
                                              embedder:, extractors: false)
  end

  # @param relative [String]
  # @param text [String]
  # @return [void]
  def file(relative, text)
    path = File.join(@folder, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  # @return [Array<String>] the indexed files, relative, once the watcher has caught up
  def indexed
    corpus = @library.corpus
    deadline = Time.now + 5
    sleep 0.05 until corpus.reconcile_plan.values.all?(&:empty?) || Time.now > deadline
    corpus.backend.sources_with_hashes.keys.sort
  end

  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    Dir.mktmpdir('puri-library') do |root|
      @folder = File.join(root, 'Documents')
      @cache = File.join(root, 'cache')
      FileUtils.mkdir_p(@folder)
      example.run
    ensure
      @library&.close
    end
  ensure
    Pikuri.log_io = log
  end

  it 'creates the notes folder, and reads no memory until the agent writes one' do
    library
    assert File.directory?(File.join(@folder, 'Notes'))
    assert_equal '', @library.memory
    File.write(File.join(@folder, 'Notes', 'PURI.md'), "# Memory\n- signs as Alex\n\n")
    assert_equal "# Memory\n- signs as Alex", @library.memory
  end

  it 'indexes the folder but what it excludes, in an FTS5 file under the cache' do
    file('dentist.md', 'Bring the referral letter.')
    file('Books/novel.txt', 'Call me Ishmael.')
    library(exclude: ['Books'])
    assert_equal ['dentist.md'], indexed
    assert_equal 1, Dir.glob(File.join(@cache, 'puri-*.sqlite3')).size
  end

  it 'closes once, a second close doing nothing' do
    library.corpus
    @library.close
    @library.close
  end
end
