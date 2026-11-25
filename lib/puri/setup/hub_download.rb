# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'openssl'
require 'pathname'
require 'uri'

module Puri
  module Setup
    # Downloads a model from Hugging Face into the {Core::HubCache}, laid out as `hf download` and
    # llama-server's `-hf` lay it out, so each finds what the others fetched (`R_hub_cache`):
    #
    #   download = HubDownload.new(Core::HubCache.new)
    #   plan = download.gguf('ggml-org/Qwen3.5-4B-GGUF:Q4_K_M')   # or .file('ggerganov/whisper.cpp:ggml-small.bin')
    #   plan.size        # => 3032091584
    #   plan.fetched     # => what an earlier run left, complete or not
    #   download.fetch(plan) { |fetched| bar.update(fetched) }
    #
    # {#gguf} picks the file `-hf` would ({Core::HubCache.pick_gguf}), a split model's every part;
    # {#file} takes one file by name. `HF_ENDPOINT`, as `hf` reads it, moves the server.
    #
    # == Implementation details
    #
    # The API lists the repo's commit and each file's size and SHA-256 (`?blobs=true`); a file comes
    # from `resolve/<commit>/<file>`, which redirects to a CDN. It goes to
    # `blobs/<sha256>.incomplete`, so a download that stopped halfway resumes with a `Range`
    # request, which `hf` doesn't do; it becomes `blobs/<sha256>` once its SHA-256 checks out, and
    # a blob already there is only linked. Then `snapshots/<commit>/<file>` links to it and
    # `refs/main` names the commit. Each file is `flock`ed at `hf`'s own lock path, so the two
    # never download one file at once.
    class HubDownload
      # Raised when Hugging Face can't be reached, lacks the model, or sends a file that doesn't
      # match its SHA-256; the message says which, for the user.
      class Error < StandardError; end

      # One file of a repo.
      #
      # @!attribute [r] name
      #   @return [String] its path in the repo
      # @!attribute [r] size
      #   @return [Integer] bytes
      # @!attribute [r] sha256
      #   @return [String] hex, which names its blob
      class RepoFile < Data.define(:name, :size, :sha256); end

      # What a model takes to download.
      #
      # @!attribute [r] repo
      #   @return [String] `org/repo`
      # @!attribute [r] commit
      #   @return [String] the revision every file comes from
      # @!attribute [r] files
      #   @return [Array<Puri::Setup::HubDownload::RepoFile>]
      # @!attribute [r] fetched
      #   @return [Integer] bytes in the cache already, a download stopped halfway included
      class Plan < Data.define(:repo, :commit, :files, :fetched)
        # @return [Integer] bytes in all
        def size = files.sum(&:size)
      end

      # @return [String]
      ENDPOINT = 'https://huggingface.co'

      # @return [Integer]
      REDIRECTS = 5

      # @param cache [Puri::Core::HubCache]
      # @param env [#[]] where `HF_ENDPOINT` comes from
      def initialize(cache, env: ENV)
        @cache = cache
        @endpoint = env['HF_ENDPOINT'].to_s.empty? ? ENDPOINT : env['HF_ENDPOINT'].chomp('/')
      end

      # @param model [String] `org/repo:quant`, matching {Core::HubCache::GGUF_MODEL}
      # @return [Puri::Setup::HubDownload::Plan]
      # @raise [Puri::Setup::HubDownload::Error]
      def gguf(model)
        repo, quant = model.split(':', 2)
        info = api(repo)
        names = info.fetch('siblings').map { _1['rfilename'] }
        first = Core::HubCache.pick_gguf(names, quant) or
          raise Error, "#{repo} on Hugging Face has no GGUF file for #{quant || Core::HubCache::DEFAULT_QUANT}"
        plan(repo, info, parts(first, names))
      end

      # @param model [String] `org/repo:file`, matching {Core::HubCache::FILE_MODEL}
      # @return [Puri::Setup::HubDownload::Plan]
      # @raise [Puri::Setup::HubDownload::Error]
      def file(model)
        repo, name = model.split(':', 2)
        info = api(repo)
        names = info.fetch('siblings').map { _1['rfilename'] }
        raise Error, "#{repo} on Hugging Face has no file #{name}" unless names.include?(name)

        plan(repo, info, [name])
      end

      # Downloads what isn't in the cache yet, then links the snapshot to it.
      #
      # @param plan [Puri::Setup::HubDownload::Plan]
      # @yieldparam fetched [Integer] bytes of the plan in the cache now, as each chunk lands
      # @return [void]
      # @raise [Puri::Setup::HubDownload::Error]; a download stopped by it, or by Ctrl+C, resumes
      #   on the next call
      def fetch(plan, &progress)
        before = 0
        plan.files.each do |file|
          fetch_file(plan, file) { |bytes| progress&.call(before + bytes) }
          before += file.size
        end
        link(plan)
      end

      private

      # @param repo [String]
      # @return [Hash{String => Object}] the API's answer
      # @raise [Puri::Setup::HubDownload::Error]
      def api(repo)
        body = nil
        get(URI("#{@endpoint}/api/models/#{repo}?blobs=true")) do |response|
          case response
          when Net::HTTPSuccess then body = response.body
          when Net::HTTPNotFound then raise Error, "Hugging Face has no model #{repo}"
          when Net::HTTPUnauthorized, Net::HTTPForbidden
            raise Error, "#{repo} on Hugging Face needs a login, which Puri's setup doesn't do"
          else raise Error, "Hugging Face answered #{response.code} #{response.message} for #{repo}"
          end
        end
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Error, "Hugging Face's answer for #{repo} isn't JSON: #{e.message}"
      end

      # @param first [String] a GGUF of the repo
      # @param names [Array<String>] the repo's files
      # @return [Array<String>] `first`, or every part of the split model it starts
      def parts(first, names)
        split = first.match(/\A(.*)-00001-of-(\d{5})\.gguf\z/i) or return [first]

        names.grep(/\A#{Regexp.escape(split[1])}-\d{5}-of-#{split[2]}\.gguf\z/i).sort
      end

      # @param repo [String]
      # @param info [Hash{String => Object}] the API's answer
      # @param names [Array<String>]
      # @return [Puri::Setup::HubDownload::Plan]
      # @raise [Puri::Setup::HubDownload::Error] for a file with no SHA-256 to check it by
      def plan(repo, info, names)
        files = names.map do |name|
          sibling = info.fetch('siblings').find { _1['rfilename'] == name }
          lfs = sibling['lfs'] or raise Error, "#{repo}'s #{name} has no SHA-256 on Hugging Face to check it by"
          RepoFile.new(name:, size: lfs.fetch('size'), sha256: lfs.fetch('sha256'))
        end
        fetched = files.sum { |file| [on_disk(blob(repo, file)), file.size].min }
        Plan.new(repo:, commit: info.fetch('sha'), files:, fetched:)
      end

      # @param blob [String]
      # @return [Integer] bytes of it on disk, or of its `.incomplete` file
      def on_disk(blob) = File.size?(blob) || File.size?("#{blob}.incomplete") || 0

      # @param repo [String]
      # @param file [Puri::Setup::HubDownload::RepoFile]
      # @return [String]
      def blob(repo, file) = File.join(@cache.repo_dir(repo), 'blobs', file.sha256)

      # @param plan [Puri::Setup::HubDownload::Plan]
      # @param file [Puri::Setup::HubDownload::RepoFile]
      # @yieldparam bytes [Integer] of the file on disk
      # @return [void]
      def fetch_file(plan, file, &progress)
        path = blob(plan.repo, file)
        return progress.call(file.size) if File.size?(path) == file.size

        FileUtils.mkdir_p(File.dirname(path))
        locked(plan.repo, file) do
          part = "#{path}.incomplete"
          digest = Digest::SHA256.new
          File.open(part, File::RDWR | File::CREAT | File::BINARY) do |sink|
            offset = resume(sink, file, digest)
            download(URI("#{@endpoint}/#{plan.repo}/resolve/#{plan.commit}/#{escape(file.name)}"), sink, offset,
                     file, digest, &progress)
          end
          unless File.size(part) == file.size && digest.hexdigest == file.sha256
            File.delete(part)
            raise Error, "#{file.name} came down damaged: it doesn't match Hugging Face's SHA-256. " \
                         'Run bin/setup again to download it anew.'
          end
          File.rename(part, path)
        end
      end

      # Hashes what an earlier run left, so the download carries on from its end.
      #
      # @param sink [File] the `.incomplete` file
      # @param file [Puri::Setup::HubDownload::RepoFile]
      # @param digest [Digest::SHA256]
      # @return [Integer] bytes kept
      def resume(sink, file, digest)
        sink.truncate(0) if sink.size > file.size
        while (chunk = sink.read(1 << 20))
          digest << chunk
        end
        sink.size
      end

      # @param uri [URI::Generic]
      # @param sink [File] at its end
      # @param offset [Integer] bytes in it
      # @param file [Puri::Setup::HubDownload::RepoFile]
      # @param digest [Digest::SHA256] of the bytes in it
      # @yieldparam bytes [Integer]
      # @return [void]
      def download(uri, sink, offset, file, digest)
        return if offset == file.size

        get(uri, offset.positive? ? { 'Range' => "bytes=#{offset}-" } : {}) do |response|
          case response
          when Net::HTTPPartialContent
            start = response['content-range'].to_s[/\Abytes (\d+)-/, 1]
            raise Error, "Hugging Face resumed #{file.name} at byte #{start}, not #{offset}" if start.to_i != offset
          when Net::HTTPOK
            sink.truncate(0)
            sink.rewind
            digest.reset
            offset = 0
          else raise Error, "Hugging Face answered #{response.code} #{response.message} for #{file.name}"
          end
          response.read_body do |chunk|
            sink.write(chunk)
            digest << chunk
            offset += chunk.bytesize
            yield offset
          end
        end
      end

      # Follows redirects, as `resolve/` sends a file to its CDN.
      #
      # @param uri [URI::Generic]
      # @param headers [Hash{String => String}]
      # @yieldparam response [Net::HTTPResponse] not a redirect, its body unread
      # @return [void]
      # @raise [Puri::Setup::HubDownload::Error] when the server can't be reached
      def get(uri, headers = {})
        REDIRECTS.times do
          location = nil
          ssl = uri.scheme == 'https'
          Net::HTTP.start(uri.host, uri.port, use_ssl: ssl, open_timeout: 15, read_timeout: 60) do |http|
            http.request(Net::HTTP::Get.new(uri, { 'User-Agent' => USER_AGENT }.merge(headers))) do |response|
              if response.is_a?(Net::HTTPRedirection)
                location = response['location']
              else
                yield response
              end
            end
          end
          return unless location

          uri = URI.join(uri.to_s, location)
        end
        raise Error, "#{uri.host} redirected #{REDIRECTS} times"
      rescue SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
        raise Error, "can't reach #{uri.host}: #{e.message}. Run bin/setup again to carry on where it stopped."
      end

      # @param repo [String]
      # @param file [Puri::Setup::HubDownload::RepoFile]
      # @return [void]
      # @raise [Puri::Setup::HubDownload::Error] while another download holds it
      def locked(repo, file)
        lock = File.join(@cache.root, '.locks', File.basename(@cache.repo_dir(repo)), "#{file.sha256}.lock")
        FileUtils.mkdir_p(File.dirname(lock))
        File.open(lock, File::RDWR | File::CREAT, 0o644) do |handle|
          raise Error, "#{file.name} is being downloaded by another program; let it finish" unless
            handle.flock(File::LOCK_EX | File::LOCK_NB)

          yield
        end
      end

      # @param plan [Puri::Setup::HubDownload::Plan]
      # @return [void]
      def link(plan)
        dir = @cache.repo_dir(plan.repo)
        plan.files.each do |file|
          link = File.join(dir, 'snapshots', plan.commit, file.name)
          FileUtils.mkdir_p(File.dirname(link))
          FileUtils.rm_f(link)
          File.symlink(Pathname(blob(plan.repo, file)).relative_path_from(File.dirname(link)).to_s, link)
        end
        FileUtils.mkdir_p(File.join(dir, 'refs'))
        File.write(File.join(dir, 'refs', 'main'), plan.commit)
      end

      # @param name [String] a path in the repo
      # @return [String] each segment escaped for a URL
      def escape(name) = name.split('/').map { URI.encode_uri_component(_1) }.join('/')
    end
  end
end
