# frozen_string_literal: true

require 'stringio'
require 'tmpdir'

RSpec.describe Puri::Core::Library do
  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    Dir.mktmpdir('puri-library') do |folder|
      @documents = Puri::Core::Config::Documents.new(folder:)
      example.run
    end
  ensure
    Pikuri.log_io = log
  end

  it 'creates the notes folder, and reads no memory until the agent writes one' do
    library = described_class.new(@documents, backends: [])
    assert File.directory?(@documents.notes)
    assert_equal '', library.memory
    File.write(@documents.memory, "# Memory\n- signs as Alex\n\n")
    assert_equal "# Memory\n- signs as Alex", library.memory
  end

  it 'searches through the first index that answers' do
    library = described_class.new(@documents, backends: [FakeIndex.new(available: false), FakeIndex.new])
    assert_equal %w[fileindex_search fileindex_read], library.file_index_tools.map(&:name)
  end

  it 'goes without search, and says so, when no index answers' do
    library = described_class.new(@documents, backends: [FakeIndex.new(available: false)])
    assert_empty library.file_index_tools
    assert_match(/no desktop file index answers \(tried fake\)/, Pikuri.log_io.string)
  end
end
