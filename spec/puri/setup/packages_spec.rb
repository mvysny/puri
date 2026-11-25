# frozen_string_literal: true

require 'open3'
require 'rbconfig'
require 'stringio'

RSpec.describe Puri::Setup::Packages do
  # A dpkg-query that knows every package asked about but those `missing` names.
  #
  # @param missing [Array<String>]
  # @return [Array<String>]
  def dpkg_query(*missing)
    script = <<~SH
      shift 3
      for p; do
        case " #{missing.join(' ')} " in *" $p "*) ;; *) echo "$p installed" ;; esac
      done
    SH
    ['sh', '-c', script, 'dpkg-query']
  end

  it 'lists what dpkg-query says is missing, in the list\'s order, and prints the one apt line' do
    packages = described_class.new(command: dpkg_query('rhythmbox', 'whisper.cpp'))
    assert_equal %w[whisper.cpp rhythmbox], packages.missing

    out = StringIO.new
    refute packages.check(Puri::Setup::Terminal.new(output: out))
    assert_includes out.string, "\n      sudo apt install whisper.cpp rhythmbox\n"
  end

  it 'passes once everything is installed' do
    out = StringIO.new
    assert described_class.new(command: dpkg_query).check(Puri::Setup::Terminal.new(output: out))
    assert_equal "✓ The packages from Ubuntu's archive\n", out.string
  end

  # bin/setup loads these before `bundle install`, when no gem is there to load.
  it 'loads, with the terminal and the bundle check, on Ruby without its gems' do
    lib = File.expand_path('../../../lib/puri', __dir__)
    script = %w[setup setup/terminal setup/packages setup/bundle].map { "require '#{lib}/#{_1}'" }.join(';')
    _, err, status = Open3.capture3(RbConfig.ruby, '--disable=gems', '-e', "#{script}; Puri::Setup::Bundle")
    assert status.success?, err
  end
end
