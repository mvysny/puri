# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../support/scratch_gsettings'

RSpec.describe Puri::Setup::SearchLocations do
  schema = described_class::SCHEMA
  key = described_class::KEY

  around do |example|
    Dir.mktmpdir('puri-locations') do |home|
      @home = home
      FileUtils.mkdir_p(%w[Documents Dokumenty Papers].map { File.join(home, _1) })
      ScratchGSettings.around(home) { example.run }
    end
  end

  let(:locations) { described_class.new(env: { 'HOME' => @home, 'XDG_CONFIG_HOME' => File.join(@home, 'config') }) }

  # @param lines [Array<String>]
  # @return [void]
  def user_dirs(*lines)
    FileUtils.mkdir_p(File.join(@home, 'config'))
    File.write(File.join(@home, 'config', 'user-dirs.dirs'), lines.map { "#{_1}\n" }.join)
  end

  it "covers the desktop's Documents by default, in the desktop's language, and nothing beside it" do
    assert locations.covers?(File.join(@home, 'Documents'))
    refute locations.covers?(File.join(@home, 'Papers'))

    user_dirs('XDG_DOCUMENTS_DIR="$HOME/Dokumenty"')
    assert locations.covers?(File.join(@home, 'Dokumenty', 'Taxes'))
    refute locations.covers?(File.join(@home, 'Documents'))
  end

  it 'covers everything under $HOME, or a path' do
    Puri::Setup::GSettings.set_strv(schema, key, ['$HOME'])
    assert locations.covers?(File.join(@home, 'Papers'))
    Puri::Setup::GSettings.set_strv(schema, key, [File.join(@home, 'Papers')])
    assert locations.covers?(File.join(@home, 'Papers'))
    refute locations.covers?("#{@home}/Papers2")
  end

  it 'adds a folder by its path, and the Documents folder by name, as Settings does' do
    Puri::Setup::GSettings.set_strv(schema, key, ['&MUSIC'])
    locations.add(File.join(@home, 'Papers'))
    locations.add(File.join(@home, 'Documents'))
    assert_equal ['&MUSIC', File.join(@home, 'Papers'), '&DOCUMENTS'], Puri::Setup::GSettings.strv(schema, key)
  end

  it "keeps a quote in a folder's name through gsettings" do
    folder = File.join(@home, "Ann's papers")
    Puri::Setup::GSettings.set_strv(schema, key, [])
    locations.add(folder)
    assert_equal [folder], Puri::Setup::GSettings.strv(schema, key)
    assert locations.covers?(folder)
  end
end
