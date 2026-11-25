# frozen_string_literal: true

require 'tmpdir'
require_relative '../../support/fake_hugging_face'

RSpec.describe Puri::Setup::HubDownload do
  gguf = "GGUF#{'q' * 5000}"
  whisper = "lmgg#{'w' * 3000}"
  let(:repos) do
    {
      'ggml-org/Tiny-GGUF' => { 'Tiny-Q4_K_M.gguf' => gguf, 'Tiny-Q8_0.gguf' => 'GGUF8',
                                'mmproj-Tiny-Q4_K_M.gguf' => 'x', 'README.md' => '# Tiny' },
      'unsloth/Big-GGUF' => { 'Q4_K_M/Big-Q4_K_M-00002-of-00002.gguf' => 'part two', 'Big-Q8_0.gguf' => 'q8',
                              'Q4_K_M/Big-Q4_K_M-00001-of-00002.gguf' => 'part one' },
      'ggerganov/whisper.cpp' => { 'ggml-small.bin' => whisper, 'ggml-base.bin' => 'base' }
    }
  end

  around do |example|
    Dir.mktmpdir('puri-hub') do |root|
      @root = root
      example.run
    ensure
      @hf&.close
    end
  end

  let(:cache) { Puri::Core::HubCache.new(env: { 'LLAMA_CACHE' => @root }) }

  # @param options [Hash{Symbol => Object}] {FakeHuggingFace}'s
  # @return [Puri::Setup::HubDownload]
  def download(**options)
    @hf = FakeHuggingFace.new(repos, **options)
    described_class.new(cache, env: { 'HF_ENDPOINT' => @hf.url })
  end

  # @param repo [String]
  # @return [String] the `.incomplete` file of `content`'s blob
  def partial(repo, content)
    File.join(cache.repo_dir(repo), 'blobs', "#{Digest::SHA256.hexdigest(content)}.incomplete")
  end

  it 'downloads the file -hf would load into the cache, where HubCache finds it, reporting its progress' do
    hub = download
    plan = hub.gguf('ggml-org/Tiny-GGUF:q4_k_m')
    assert_equal ['Tiny-Q4_K_M.gguf'], plan.files.map(&:name)
    assert_equal [gguf.bytesize, 0], [plan.size, plan.fetched]

    seen = []
    hub.fetch(plan) { seen << _1 }
    path = cache.gguf('ggml-org/Tiny-GGUF:Q4_K_M')
    assert_equal gguf, File.read(path)
    assert File.symlink?(path), 'the snapshot links to the blob, as huggingface_hub lays it out'
    assert_equal FakeHuggingFace::COMMIT, File.read(File.join(cache.repo_dir('ggml-org/Tiny-GGUF'), 'refs', 'main'))
    assert_equal gguf.bytesize, seen.last
    assert_equal seen.sort, seen
  end

  it "downloads every part of a split model, which the API's commit pins" do
    hub = download
    hub.fetch(hub.gguf('unsloth/Big-GGUF:Q4_K_M'))
    first = cache.gguf('unsloth/Big-GGUF:Q4_K_M')
    assert_equal 'part one', File.read(first)
    assert_equal 'part two', File.read(first.sub('00001-of', '00002-of'))
    assert_includes @hf.requests, "/unsloth/Big-GGUF/resolve/#{FakeHuggingFace::COMMIT}/Q4_K_M/Big-Q4_K_M-00002-of-00002.gguf"
  end

  it 'downloads one file by name' do
    hub = download
    hub.fetch(hub.file('ggerganov/whisper.cpp:ggml-small.bin'))
    assert_equal whisper, File.read(cache.file('ggerganov/whisper.cpp:ggml-small.bin'))
    assert_nil cache.file('ggerganov/whisper.cpp:ggml-base.bin')
  end

  it 'carries on from where a download stopped, with a Range' do
    FileUtils.mkdir_p(File.dirname(partial('ggml-org/Tiny-GGUF', gguf)))
    File.write(partial('ggml-org/Tiny-GGUF', gguf), gguf[0, 1000])
    hub = download
    plan = hub.gguf('ggml-org/Tiny-GGUF:Q4_K_M')
    assert_equal 1000, plan.fetched

    hub.fetch(plan)
    assert_equal gguf, File.read(cache.gguf('ggml-org/Tiny-GGUF:Q4_K_M'))
    assert_includes @hf.requests, '/cdn/ggml-org/Tiny-GGUF/Tiny-Q4_K_M.gguf bytes=1000-'
    refute File.exist?(partial('ggml-org/Tiny-GGUF', gguf))
  end

  it 'starts over when the server sends the whole file for a Range' do
    FileUtils.mkdir_p(File.dirname(partial('ggml-org/Tiny-GGUF', gguf)))
    File.write(partial('ggml-org/Tiny-GGUF', gguf), gguf[0, 1000])
    hub = download(ranges: false)
    hub.fetch(hub.gguf('ggml-org/Tiny-GGUF:Q4_K_M'))
    assert_equal gguf, File.read(cache.gguf('ggml-org/Tiny-GGUF:Q4_K_M'))
  end

  it 'throws away a file that came down damaged, saying so' do
    hub = download(damaged: ['Tiny-Q4_K_M.gguf'])
    plan = hub.gguf('ggml-org/Tiny-GGUF:Q4_K_M')
    error = assert_raises(described_class::Error) { hub.fetch(plan) }
    assert_includes error.message, "doesn't match Hugging Face's SHA-256"
    refute File.exist?(partial('ggml-org/Tiny-GGUF', gguf)), 'the next run starts over'
    assert_nil cache.gguf('ggml-org/Tiny-GGUF:Q4_K_M')
  end

  it 'only links a blob it has, as after the repo moved on to another commit' do
    hub = download
    hub.fetch(hub.file('ggerganov/whisper.cpp:ggml-small.bin'))
    File.write(File.join(cache.repo_dir('ggerganov/whisper.cpp'), 'refs', 'main'), 'older')
    assert_nil cache.file('ggerganov/whisper.cpp:ggml-small.bin')

    plan = hub.file('ggerganov/whisper.cpp:ggml-small.bin')
    assert_equal plan.size, plan.fetched
    hub.fetch(plan)
    assert_equal whisper, File.read(cache.file('ggerganov/whisper.cpp:ggml-small.bin'))
    assert_equal(1, @hf.requests.count { _1.start_with?('/cdn/') })
  end

  it 'says what Hugging Face lacks' do
    hub = download
    assert_includes assert_raises(described_class::Error) { hub.gguf('ggml-org/None-GGUF:Q4_K_M') }.message,
                    'Hugging Face has no model ggml-org/None-GGUF'
    assert_includes assert_raises(described_class::Error) { hub.gguf('ggml-org/Tiny-GGUF:Q2_K') }.message,
                    'has no GGUF file for Q2_K'
    assert_includes assert_raises(described_class::Error) { hub.file('ggerganov/whisper.cpp:ggml-tiny.bin') }.message,
                    'has no file ggml-tiny.bin'
  end

  it "says it can't reach a server that isn't there" do
    port = TCPServer.open('127.0.0.1', 0) { _1.addr[1] }
    hub = described_class.new(cache, env: { 'HF_ENDPOINT' => "http://127.0.0.1:#{port}" })
    assert_includes assert_raises(described_class::Error) { hub.gguf('ggml-org/Tiny-GGUF') }.message,
                    "can't reach 127.0.0.1"
  end
end
