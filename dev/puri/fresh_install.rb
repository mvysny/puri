# frozen_string_literal: true

require 'pty'
require 'tmpdir'
require 'puri/setup/packages'
require 'puri/setup/terminal'

module Puri
  # The install guide's Super-quick path, run by a new user on a fresh Ubuntu 26.04 in podman, and
  # checked: the guide's apt line, `git clone`, `bin/setup`, then `bin/setup` again as the doctor.
  # It answers yes to every question but the models' download, 3.5 GB, unless told to:
  #
  #   FreshInstall.new.run                 # => [] when it passed; else what went wrong, a line each
  #   FreshInstall.new(models: true).run   # downloads them too, and expects "Puri is ready"
  #
  # Development only, like {Eval}; `rake fresh_install` runs it.
  #
  # The image is a layer of what Ubuntu Desktop has and the bare image lacks ({DESKTOP}), then the
  # guide's apt line ({Setup::Packages::LIST}), recommends and all, as `sudo apt install` installs
  # it; podman reuses it until either list changes. Each run then logs the user in, as GNOME
  # would: their folders, a session bus, a document the file index has read. There's no display,
  # so nothing starts Puri itself.
  #
  # == Implementation details
  #
  # The home is a volume: on podman's overlay filesystem localsearch gets no file handles
  # ("Operation not supported") and indexes nothing. `bin/setup` runs on a terminal, as the user
  # runs it, and each answer goes in once its question is up.
  class FreshInstall
    # @return [String] the bare Ubuntu the image starts from
    BASE = 'docker.io/library/ubuntu:26.04'

    # @return [String] the base with the packages in
    IMAGE = 'localhost/puri-fresh-install:26.04'

    # @return [String] the container, one at a time
    NAME = 'puri-fresh-install'

    # @return [String] the base image's first user, uid 1000, as on a fresh install
    USER = 'ubuntu'

    # @return [String]
    HOME = "/home/#{USER}".freeze

    # @return [Hash{String => String}] the login session, which every command as {USER} runs in
    SESSION = { 'XDG_RUNTIME_DIR' => '/run/user/1000',
                'DBUS_SESSION_BUS_ADDRESS' => 'unix:path=/run/user/1000/bus' }.freeze

    # @return [Array<String>] what Ubuntu Desktop has and the bare image lacks, that `bin/setup`
    #   leans on: the session bus, gsettings and its dconf store, the custom keybindings' schema,
    #   the file index, the user's folders
    DESKTOP = %w[dbus-daemon libglib2.0-bin dconf-gsettings-backend gnome-settings-daemon-common localsearch
                 tinysparql xdg-user-dirs].freeze

    # @return [Array<Regexp>] a line each run prints once Puri is installed, the models aside
    DONE = [/^✓ The packages from Ubuntu's archive$/, /^✓ Puri's Ruby libraries$/,
            /^✓ Puri is on your desktop: Super\+Alt\+Space opens it/,
            %r{^✓ (?:Wrote the|The) config, ~/\.config/puri/config\.toml},
            %r{^✓ Your documents, ~/Documents, in GNOME's file index$}].freeze

    # @return [Array<Regexp>] the lines each run prints once the models are in, too
    READY = [/^✓ The model, /, /^✓ Dictation's model, /, /^Puri is ready: press Super\+Alt\+Space/].freeze

    # @return [Regexp] a model the user declined, the one ✗ allowed then
    DECLINED = /^✗ (?:The|Dictation's) model, \S+, isn't downloaded/

    # @return [Integer] seconds `bin/setup` may print nothing before it counts as hung
    IDLE = 600

    # One `bin/setup` run, as the terminal showed it.
    #
    # @!attribute [r] output
    #   @return [String] see {.plain}
    # @!attribute [r] status
    #   @return [Integer] its exit status
    # @!attribute [r] questions
    #   @return [Array<String>] what it asked, in order
    class Round < Data.define(:output, :status, :questions)
      # @param raw [String] what the terminal got, CRs, redrawn progress bars and all
      # @return [String] each line as it stands last, a message wrapped over several joined into one
      def self.plain(raw)
        raw.dup.force_encoding(Encoding::UTF_8).gsub("\r\n", "\n").lines(chomp: true)
           .map { _1.split("\r").last.to_s }.join("\n").gsub(/\n {2}(?=\S)/, ' ')
      end
    end

    # @param models [Boolean] whether to download the models when asked
    # @param repo [String, nil] what to clone, the guide's GitHub URL say; nil for this checkout's
    #   HEAD, uncommitted changes left out
    # @param fresh [Boolean] whether to build the image anew, from today's base and archive
    # @param keep [Boolean] whether to leave the container running, to look around in
    # @param root [String] this checkout
    def initialize(models: false, repo: nil, fresh: false, keep: false, root: File.expand_path('../..', __dir__))
      @models = models
      @repo = repo
      @fresh = fresh
      @keep = keep
      @root = root
    end

    # @return [Array<String>] what didn't go as a user's install should; empty when it passed
    def run
      build
      remove
      podman('run', '--detach', '--name', NAME, '--volume', HOME, IMAGE, 'sleep', 'infinity')
      login
      clone
      first = round('bin/setup')
      second = round('bin/setup again, the doctor')
      check({ 'first' => first, 'second' => second })
    ensure
      @keep ? keep : remove
    end

    private

    # @return [void]
    def build
      Dir.mktmpdir('puri-fresh-install') do |context|
        File.write(File.join(context, 'Containerfile'), <<~CONTAINERFILE)
          FROM #{BASE}
          ENV LANG=C.UTF-8
          ARG DEBIAN_FRONTEND=noninteractive
          RUN apt-get update && apt-get install -y #{DESKTOP.join(' ')}
          RUN apt-get update && apt-get install -y #{Setup::Packages::LIST.join(' ')}
        CONTAINERFILE
        podman('build', *(%w[--no-cache --pull=always] if @fresh), '--tag', IMAGE, context)
      end
    end

    # @return [void]
    def login
      podman('exec', NAME, 'install', '-d', '-o', USER, '-g', USER, '-m', '700', SESSION['XDG_RUNTIME_DIR'])
      as_user('sh', '-c', <<~SH)
        set -e
        xdg-user-dirs-update
        dbus-daemon --session --fork --nopidfile --address="$DBUS_SESSION_BUS_ADDRESS" \\
          >/dev/null 2>"$XDG_RUNTIME_DIR/bus.log"
        echo 'The lease ends in March.' > ~/Documents/lease.txt
        for i in $(seq 120); do
          localsearch info ~/Documents/lease.txt >/dev/null 2>&1 && exit 0
          sleep 1
        done
        echo "localsearch hasn't indexed ~/Documents/lease.txt in two minutes" >&2
        exit 1
      SH
    end

    # @return [void]
    def clone
      return as_user('git', 'clone', @repo, "#{HOME}/puri") if @repo

      unless git('status', '--porcelain').empty?
        warn "Uncommitted changes aren't in the test: it clones #{Setup::Terminal.tilde(@root)} at HEAD."
      end
      Dir.mktmpdir('puri-fresh-install') do |dir|
        bundle = File.join(dir, 'puri.bundle')
        system('git', '-C', @root, 'bundle', 'create', '--quiet', bundle, 'HEAD',
               *git('branch', '--show-current').split, exception: true)
        podman('cp', bundle, "#{NAME}:/tmp/puri.bundle")
      end
      podman('exec', NAME, 'chmod', '644', '/tmp/puri.bundle')
      as_user('git', 'clone', '--quiet', '/tmp/puri.bundle', "#{HOME}/puri")
    end

    # @param title [String]
    # @return [Puri::FreshInstall::Round]
    def round(title)
      puts "\n== #{title}\n\n"
      output = String.new # binary: a chunk may end inside a character
      questions = []
      reader, writer, pid = PTY.spawn('podman', *user_exec(tty: true), "#{HOME}/puri/bin/setup")
      loop do
        raise "bin/setup printed nothing for #{IDLE} s" unless reader.wait_readable(IDLE)

        chunk = reader.readpartial(4096)
        $stdout.write(chunk)
        output << chunk
        next unless output.match?(%r{\[(?:Y/n|y/N)\] \z})

        questions << Round.plain(output[output.rindex(/^\? /)..])
        writer.write(answer?(questions.last) ? "y\n" : "n\n")
      rescue EOFError, Errno::EIO # Linux's EOF on a terminal
        break
      end
      Round.new(output: Round.plain(output), status: Process.wait2(pid).last.exitstatus, questions:)
    ensure
      reader&.close
      writer&.close
    end

    # @param question [String]
    # @return [Boolean]
    def answer?(question) = @models || !question.include?('Hugging Face')

    # @param rounds [Hash{String => Puri::FreshInstall::Round}] by name
    # @return [Array<String>]
    def check(rounds)
      status = @models ? 0 : 1
      rounds.flat_map do |name, round|
        failures = []
        failures << "The #{name} run exited #{round.status}, not #{status}" unless round.status == status
        (@models ? DONE + READY : DONE).each do |line|
          failures << "The #{name} run printed no line like /#{line.source}/" unless round.output.match?(line)
        end
        round.output.lines(chomp: true).grep(/^✗ /).each do |line|
          failures << "The #{name} run says: #{line}" unless !@models && line.match?(DECLINED)
        end
        failures
      end + rounds.fetch('second').questions.filter_map do |question|
        "The second run asked: #{question}" unless !@models && question.include?('Hugging Face')
      end
    end

    # @return [void]
    def keep
      puts "\nThe container is #{NAME}. A shell in it, as the user:\n\n  " \
           "podman #{user_exec(tty: true).join(' ')} bash\n\nRemove it: podman rm --force --volumes #{NAME}"
    end

    # @return [void]
    def remove
      system('podman', 'rm', '--force', '--volumes', '--time', '0', NAME, out: File::NULL, err: File::NULL)
    end

    # @param command [Array<String>]
    # @return [void]
    def as_user(*command) = podman(*user_exec, *command)

    # @param tty [Boolean]
    # @return [Array<String>] `podman exec`'s arguments up to the command, which runs as {USER}, at
    #   home, in the login session
    def user_exec(tty: false)
      ['exec', *(%w[--interactive --tty] if tty), '--user', USER, '--workdir', HOME,
       *SESSION.flat_map { ['--env', "#{_1}=#{_2}"] }, NAME]
    end

    # @param args [Array<String>]
    # @return [void]
    # @raise [RuntimeError] when podman fails
    def podman(*args)
      system('podman', *args, exception: true)
    end

    # @param args [Array<String>]
    # @return [String] its stdout
    def git(*args) = IO.popen(['git', '-C', @root, *args], &:read)
  end
end
