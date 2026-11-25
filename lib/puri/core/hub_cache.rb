# frozen_string_literal: true

module Puri
  module Core
    # Hugging Face's hub cache, where llama-server's `-hf` keeps the models it downloads: Puri
    # looks there for the models it runs itself, llama-server's and whisper-cli's alike.
    #
    #   cache = HubCache.new
    #   cache.gguf('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M')      # => ".../snapshots/8d43…/Qwen3.5-4B-Q4_K_M.gguf"
    #   cache.file('ggerganov/whisper.cpp:ggml-small.bin')  # => ".../snapshots/5359…/ggml-small.bin"
    #   cache.file('ggerganov/whisper.cpp:ggml-base.bin')   # => nil: not downloaded
    #
    # The layout is `huggingface_hub`'s: `models--<org>--<repo>/refs/main` names a commit, and
    # `snapshots/<commit>/<file>` links to the file's blob. Offline, llama.cpp finds a file the
    # same way (`R_hub_cache`).
    #
    # Immutable.
    class HubCache
      # What `-hf` takes: `org/repo`, then the quant after a colon, which defaults to
      # {DEFAULT_QUANT}.
      #
      # @return [Regexp]
      GGUF_MODEL = %r{\A[^/\s:]+/[^/\s:]+(?::[^/\s:]+)?\z}

      # One file of a repo, `org/repo:file`: whisper.cpp's repo has no quant tags, a quant being
      # part of the file's name.
      #
      # @return [Regexp]
      FILE_MODEL = %r{\A[^/\s:]+/[^/\s:]+:[^/\s]+\z}

      # @return [String] llama.cpp's own default
      DEFAULT_QUANT = 'Q4_K_M'

      # @return [String] the cache's directory, perhaps missing
      attr_reader :root

      # @param env [#[]] where `LLAMA_CACHE`, `HF_HUB_CACHE`, `HF_HOME`, `XDG_CACHE_HOME` and `HOME`
      #   come from, in that order, as llama.cpp reads them; specs pass their own
      def initialize(env: ENV)
        @root = HubCache.root(env)
        freeze
      end

      # @param env [#[]]
      # @return [String]
      def self.root(env)
        return env['LLAMA_CACHE'] unless env['LLAMA_CACHE'].to_s.empty?
        return env['HF_HUB_CACHE'] unless env['HF_HUB_CACHE'].to_s.empty?
        return File.join(env['HF_HOME'], 'hub') unless env['HF_HOME'].to_s.empty?

        cache = env['XDG_CACHE_HOME'].to_s.empty? ? File.join(env['HOME'] || Dir.home, '.cache') : env['XDG_CACHE_HOME']
        File.join(cache, 'huggingface', 'hub')
      end

      # Which of a repo's files `-hf org/repo:quant` loads: the first GGUF, sorted, whose path holds
      # the quant, case aside, never a vision projector. A big model's split parts may sit in a
      # folder named for the quant, `UD-Q4_K_XL/…-00001-of-00003.gguf`.
      #
      #   HubCache.pick_gguf(%w[mmproj-Q4_K_M.gguf Qwen-Q4_K_M.gguf Qwen-Q8_0.gguf], 'q4_k_m')   # => "Qwen-Q4_K_M.gguf"
      #
      # @param paths [Array<String>] the repo's files, relative to it
      # @param quant [String, nil] nil for {DEFAULT_QUANT}
      # @return [String, nil] one of `paths`; nil when none fits
      def self.pick_gguf(paths, quant)
        quant = (quant || DEFAULT_QUANT).downcase
        paths.sort.find do |path|
          lower = path.downcase
          lower.end_with?('.gguf') && lower.include?(quant) && !File.basename(lower).include?('mmproj')
        end
      end

      # The GGUF file `-hf model` loads, by {.pick_gguf}.
      #
      # @param model [String] matching {GGUF_MODEL}
      # @return [String, nil] its path; nil when it isn't downloaded
      def gguf(model)
        repo, quant = model.split(':', 2)
        dir = snapshot(repo) or return nil
        files = Dir.glob('**/*.gguf', File::FNM_CASEFOLD, base: dir).select { File.file?(File.join(dir, _1)) }
        name = HubCache.pick_gguf(files, quant)
        name && File.join(dir, name)
      end

      # @param model [String] matching {FILE_MODEL}
      # @return [String, nil] its path; nil when it isn't downloaded
      def file(model)
        repo, name = model.split(':', 2)
        dir = snapshot(repo) or return nil
        path = File.join(dir, name)
        File.file?(path) ? path : nil
      end

      # @param repo [String] `org/repo`
      # @return [String] the repo's folder in the cache, perhaps missing
      def repo_dir(repo) = File.join(@root, "models--#{repo.sub('/', '--')}")

      private

      # @param repo [String] `org/repo`
      # @return [String, nil] the snapshot `refs/main` names, when it exists
      def snapshot(repo)
        base = repo_dir(repo)
        dir = File.join(base, 'snapshots', File.read(File.join(base, 'refs', 'main')).strip)
        File.directory?(dir) ? dir : nil
      rescue Errno::ENOENT, Errno::ENOTDIR
        nil
      end
    end
  end
end
