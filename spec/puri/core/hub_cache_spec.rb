# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# A hand-built cache in `huggingface_hub`'s layout, as llama-server's `-hf` writes it.
RSpec.describe Puri::Core::HubCache do
  around do |example|
    Dir.mktmpdir('puri-hub') do |root|
      @root = root
      example.run
    end
  end

  let(:cache) { described_class.new(env: { 'LLAMA_CACHE' => @root }) }

  # @param repo [String] `org/repo`
  # @param files [Array<String>] each a link to a blob of its own
  # @param commit [String]
  # @return [String] the snapshot's folder
  def download(repo, *files, commit: 'abc123')
    base = File.join(@root, "models--#{repo.sub('/', '--')}")
    snapshot = File.join(base, 'snapshots', commit)
    FileUtils.mkdir_p([snapshot, File.join(base, 'blobs'), File.join(base, 'refs')])
    files.each_with_index do |name, i|
      File.write(File.join(base, 'blobs', "blob#{i}"), name)
      File.symlink("../../blobs/blob#{i}", File.join(snapshot, name))
    end
    File.write(File.join(base, 'refs', 'main'), commit)
    snapshot
  end

  describe '#gguf' do
    it 'finds the quant, case aside, never the vision projector' do
      dir = download('ggml-org/Qwen3.5-4B-GGUF', 'mmproj-Qwen3.5-4B-Q4_K_M.gguf', 'Qwen3.5-4B-Q4_K_M.gguf',
                     'Qwen3.5-4B-Q8_0.gguf')
      assert_equal File.join(dir, 'Qwen3.5-4B-Q4_K_M.gguf'), cache.gguf('ggml-org/Qwen3.5-4B-GGUF:q4_k_m')
      assert_equal File.join(dir, 'Qwen3.5-4B-Q8_0.gguf'), cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q8_0')
    end

    it "defaults to llama.cpp's Q4_K_M" do
      dir = download('ggml-org/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf')
      assert_equal File.join(dir, 'Qwen3.5-4B-Q4_K_M.gguf'), cache.gguf('ggml-org/Qwen3.5-4B-GGUF')
    end

    it 'is nil for a quant, a repo or a blob not downloaded' do
      dir = download('ggml-org/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf')
      assert_nil cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q8_0')
      assert_nil cache.gguf('ggml-org/other:Q4_K_M')
      File.delete(File.realpath(File.join(dir, 'Qwen3.5-4B-Q4_K_M.gguf')))
      assert_nil cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M'), 'a link to a missing blob is no file'
    end

    it 'follows refs/main, not any snapshot' do
      download('ggml-org/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q4_K_M.gguf', commit: 'old')
      download('ggml-org/Qwen3.5-4B-GGUF', 'Qwen3.5-4B-Q8_0.gguf', commit: 'new')
      assert_nil cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M')
    end
  end

  describe '#file' do
    it 'finds a file of the repo by its name' do
      dir = download('ggerganov/whisper.cpp', 'ggml-small.bin')
      assert_equal File.join(dir, 'ggml-small.bin'), cache.file('ggerganov/whisper.cpp:ggml-small.bin')
      assert_nil cache.file('ggerganov/whisper.cpp:ggml-base.bin')
    end
  end

  describe '.root' do
    it 'reads the variables in the order llama.cpp does' do
      assert_equal '/l', described_class.root({ 'LLAMA_CACHE' => '/l', 'HF_HUB_CACHE' => '/h' })
      assert_equal '/h', described_class.root({ 'HF_HUB_CACHE' => '/h', 'HF_HOME' => '/hf' })
      assert_equal '/hf/hub', described_class.root({ 'HF_HOME' => '/hf', 'XDG_CACHE_HOME' => '/x' })
      assert_equal '/x/huggingface/hub', described_class.root({ 'XDG_CACHE_HOME' => '/x', 'HOME' => '/home/u' })
      assert_equal '/home/u/.cache/huggingface/hub', described_class.root({ 'HOME' => '/home/u' })
    end
  end
end
