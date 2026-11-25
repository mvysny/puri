# frozen_string_literal: true

require 'stringio'

RSpec.describe Puri::Setup::Terminal do
  # @param answers [String] what the user types
  # @return [Array(Puri::Setup::Terminal, StringIO)]
  def terminal(answers = '')
    out = StringIO.new
    [described_class.new(input: StringIO.new(answers), output: out), out]
  end

  it 'marks each line, counts the todos, and wraps under the mark, leaving a command whole' do
    term, out = terminal
    term.done('The packages')
    term.note('word ' * 30)
    term.todo("Install them:\n\n    sudo apt install #{(['pkg'] * 30).join(' ')}")
    lines = out.string.lines(chomp: true)
    assert_equal '✓ The packages', lines[0]
    assert lines[1].start_with?('! word word'), lines[1]
    assert lines[2].start_with?('  word'), 'a wrapped line goes under the text, not the mark'
    assert(lines.all? { _1.size <= described_class::WIDTH || _1.include?('sudo') })
    assert_includes lines, "      sudo apt install #{(['pkg'] * 30).join(' ')}"
    assert_equal 1, term.todos
  end

  it 'takes Enter for the default, y or n, asks again otherwise, and no at the end of input' do
    term, out = terminal("\nmaybe\nN\nyes\n")
    assert term.ask?('Download it?')
    refute term.ask?('Download it?')
    assert term.ask?('Download it?', default: false)
    refute term.ask?('Download it?')
    assert_includes out.string, '? Download it? [Y/n] '
    assert_includes out.string, '? Download it? [y/N] '
  end

  it "leaves a pipe's later answers in it, for the doctor bin/setup execs into" do
    reader, writer = IO.pipe
    writer.write("y\nn\n")
    writer.close
    assert described_class.new(input: reader, output: StringIO.new).ask?('Fetch them?')
    # A second IO on the same pipe, as the doctor's $stdin is: no buffer shared with the first.
    assert_equal "n\n", IO.new(reader.fileno, autoclose: false).read
  ensure
    reader&.close
  end

  it 'says a path from home with ~, and a size as the site does' do
    assert_equal '~/puri', described_class.tilde(File.join(Dir.home, 'puri'))
    assert_equal '/opt/puri', described_class.tilde('/opt/puri')
    assert_equal '3.0 GB', described_class.size(3_032_091_584)
    assert_equal '488 MB', described_class.size(487_601_967)
  end

  it 'draws no progress bar where the output is no terminal' do
    term, out = terminal
    bar = term.progress(100, 10)
    bar.update(50)
    bar.finish
    assert_equal '', out.string
  end
end
