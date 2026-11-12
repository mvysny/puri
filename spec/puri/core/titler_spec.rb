# frozen_string_literal: true

require 'pikuri/testing'
require 'stringio'

# The real titling path, a pikuri agent on a scripted HTTP backend. What a unit spec can't show,
# that the <opener> wrapper gets an imperative opener titled rather than obeyed and that the
# prompt yields 3-7 words, takes a live model: pikuri-web's bin/probe-titler.
RSpec.describe Puri::Core::Titler do
  # The context-window probe dials the fake's `.invalid` host and warns that it failed.
  around do |example|
    log = Pikuri.log_io
    Pikuri.log_io = StringIO.new
    example.run
  ensure
    Pikuri.log_io = log
  end

  # @param replies [Array<String>] one per title
  # @param params_declared [Boolean]
  # @return [Puri::Core::Titler]
  def titler(*replies, params_declared: true)
    transport = Pikuri::Testing.fake_transport { |llm| replies.each { llm.reply(_1) } }
    described_class.new(transport:, params_declared:)
  end

  describe '#title_for' do
    it 'returns the model line as the title' do
      assert_equal 'Sinatra Versus Roda For SSE',
                   titler('Sinatra Versus Roda For SSE').title_for('Compare Sinatra and Roda')
    end

    it 'caps a long-winded answer at MAX_WORDS' do
      assert_equal 'One Two Three Four Five Six Seven',
                   titler('One Two Three Four Five Six Seven Eight Nine').title_for('x')
    end

    # The measured failure: a thinking model dumping its reasoning where a title belongs.
    it 'caps at MAX_CHARS even within MAX_WORDS' do
      assert_equal described_class::MAX_CHARS, titler("#{'x' * 40} #{'y' * 60}").title_for('x').length
    end

    it 'keeps only the first line' do
      assert_equal 'First Line Only', titler("First Line Only\nand a second").title_for('x')
    end

    it 'drops everything up to a leaked reasoning close tag' do
      assert_equal 'Sinatra Versus Roda',
                   titler("<think>Let me consider the options.</think>\nSinatra Versus Roda").title_for('x')
      assert_equal 'Sinatra Versus Roda', titler("</think>\n\n  Sinatra Versus Roda\n").title_for('x')
    end

    it 'answers nil for a reply with nothing usable in it' do
      assert_nil titler("   \n  ").title_for('x')
      assert_nil titler('</think>').title_for('x')
    end

    # The title reaches the history list as plain text, where escaping stops markup but not a
    # bidi override.
    it 'sanitizes the title' do
      override = "\u202E"
      refute_includes titler("Report#{override}fdp.txt").title_for('x'), override
    end

    it 'starts each title from nothing' do
      one = titler('First Title', 'Second Title')
      assert_equal 'First Title', one.title_for('a')
      assert_equal 'Second Title', one.title_for('b')
    end
  end

  # The canary never changes the title. Driven through the private reporter, because pikuri's
  # fake reports no reasoning tokens.
  describe 'the reasoning canary' do
    # @param thinking [Integer]
    # @return [Puri::Core::Titler::Tally]
    def tally(thinking)
      described_class::Tally.new.tap do |tally|
        tally.on_event(Pikuri::Agent::Event::Tokens.new(input: 10, output: 8, cached: 0, cache_creation: 0,
                                                        thinking:, model_id: 'fake'))
      end
    end

    # @param titler [Puri::Core::Titler]
    # @param thinking [Integer]
    # @return [String] what it logged
    def logged(titler, thinking)
      Pikuri.log_io = StringIO.new
      titler.send(:report_reasoning, tally(thinking), 1.2)
      Pikuri.log_io.string
    end

    it 'says nothing when the model did not reason' do
      assert_empty logged(titler, 0)
    end

    it 'warns when a declared params table did not take effect' do
      output = logged(titler(params_declared: true), 640)
      assert_includes output, 'WARN'
      assert_includes output, '`params` did not take effect'
      assert_includes output, '640 reasoning tokens'
    end

    it 'only informs when nobody asked for thinking to be off' do
      output = logged(titler(params_declared: false), 640)
      assert_includes output, 'INFO'
      refute_includes output, 'did not take effect'
    end

    it 'says it once, not once per title' do
      one = titler
      refute_empty logged(one, 640)
      assert_empty logged(one, 640)
    end
  end

  describe described_class::Tally do
    it 'sums reasoning and output tokens, treating an absent count as none' do
      tally = described_class.new
      [3, nil].each do |thinking|
        tally.on_event(Pikuri::Agent::Event::Tokens.new(input: 1, output: 4, cached: nil, cache_creation: nil,
                                                        thinking:, model_id: 'fake'))
      end
      tally.on_event(Pikuri::Agent::Event::Assistant.new(content: 'ignored'))
      assert_equal 3, tally.thinking
      assert_equal 8, tally.output
    end
  end
end
