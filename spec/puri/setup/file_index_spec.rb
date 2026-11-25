# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe Puri::Setup::FileIndex do
  around do |example|
    Dir.mktmpdir('puri-index') do |folder|
      @folder = folder
      example.run
    end
  end

  # A localsearch whose `info` knows the files named `*indexed*`, and whose `status` says `status`.
  #
  # @param status [String]
  # @return [Array<String>]
  def localsearch(status = 'Indexer is idle')
    ['sh', '-c', <<~SH, 'localsearch']
      case "$1" in
        status) echo "Currently indexed: 3 files"; echo "#{status}" ;;
        info) case "$2" in *indexed*) echo "urn:fileid:1" ;; *) echo "No metadata available"; exit 1 ;; esac ;;
        reset) [ "$2" = --file ] ;;
      esac
    SH
  end

  # @param text [Boolean] whether the index holds the files' text
  # @return [Module] an index backend
  def backend(text:)
    Module.new do
      define_singleton_method(:unavailable_reason) { |folders:| folders.one? ? nil : 'two' }
      define_singleton_method(:read_text) { |path| text ? File.read(path) : nil }
    end
  end

  # @param names [Array<String>]
  # @return [void]
  def files(*names)
    names.each do |name|
      FileUtils.mkdir_p(File.dirname(File.join(@folder, name)))
      File.write(File.join(@folder, name), name)
    end
  end

  it 'finds an office file the index holds without its text' do
    files('Work/notes-indexed.docx', 'lease.odt', 'scan.pdf')
    index = described_class.new(backend: backend(text: false), command: localsearch)
    assert_equal File.join(@folder, 'Work/notes-indexed.docx'), index.office_without_text(@folder)
    assert index.reindex(@folder)
  end

  it 'finds none once an office file has its text, or when the index holds none of them' do
    files('Work/notes-indexed.DOCX', 'scan-indexed.pdf')
    assert_nil described_class.new(backend: backend(text: true), command: localsearch).office_without_text(@folder)
    FileUtils.rm(File.join(@folder, 'Work/notes-indexed.DOCX'))
    files('in-a-git-checkout.xlsx')
    assert_nil described_class.new(backend: backend(text: false), command: localsearch).office_without_text(@folder)
  end

  it "is idle only once localsearch says so, in English whatever the desktop's language" do
    assert described_class.new(backend: backend(text: true), command: localsearch).idle?
    refute described_class.new(backend: backend(text: true), command: localsearch('Indexer is busy')).idle?
  end
end
