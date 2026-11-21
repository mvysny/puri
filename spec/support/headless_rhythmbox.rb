# frozen_string_literal: true

require 'fileutils'
require 'socket'
require 'timeout'
require 'tmpdir'

# A real Rhythmbox for the music specs, shut away from the developer's own: a scratch home whose
# Music folder holds spec/fixtures/music, a private session bus that activates Rhythmbox on the
# first call, and GTK 3's Broadway as its display. No sound server: playback still reports
# `Playing`.
#
#   rhythmbox = HeadlessRhythmbox.start    # nil where rhythmbox or broadwayd is missing
#   Puri::Core::Music::Rhythmbox.new(rhythmbox.address)
#   rhythmbox.stop
#
# The scratch environment goes to the bus daemon itself, which hands its own environment to the
# Rhythmbox it activates: set any later, and Rhythmbox writes the real dconf and
# `~/.cache/rhythmbox` (`R_rhythmbox_dbus`).
class HeadlessRhythmbox
  # @return [String] the tagged tones the library is made of
  FIXTURES = File.expand_path('../fixtures/music', __dir__)

  # @return [Range<Integer>] Broadway displays tried in turn, below the GTK 4 specs' 90–99
  DISPLAYS = (80..89)

  # @return [Array<String>] the GStreamer audio sinks Rhythmbox must not reach
  SINKS = %w[pulsesink pipewiresink alsasink jackaudiosink oss4sink osssink].freeze

  # @return [Integer] seconds a spec's own call waits for Rhythmbox
  CALL_TIMEOUT = 10

  # @return [String]
  MPRIS = 'org.mpris.MediaPlayer2.rhythmbox'

  # @return [String] the private bus's address
  attr_reader :address

  # @return [String] the scratch home's Music folder
  attr_reader :music

  # @return [HeadlessRhythmbox, nil] nil, so the specs skip, where rhythmbox or broadwayd is missing
  def self.start
    return nil unless %w[rhythmbox broadwayd dbus-daemon].all? { |cmd| on_path?(cmd) }

    new.tap(&:boot)
  end

  # @param cmd [String]
  # @return [Boolean]
  def self.on_path?(cmd)
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { File.executable?(File.join(_1, cmd)) }
  end

  def initialize
    @home = Dir.mktmpdir('puri-rhythmbox')
    @music = File.join(@home, 'Music')
    @address = "unix:path=#{File.join(@home, 'bus')}"
    @pids = []
  end

  # @return [void]
  def boot
    FileUtils.mkdir_p(@music)
    FileUtils.cp(Dir.glob(File.join(FIXTURES, '*.ogg')), @music)
    write_settings
    display = DISPLAYS.find { |d| port_free?(8080 + d) } or raise "no free Broadway display in #{DISPLAYS}"
    @pids << Process.spawn(env, 'broadwayd', '--address', '127.0.0.1', ":#{display}", out: File::NULL,
                                                                                      err: File::NULL)
    @pids << Process.spawn(env.merge('BROADWAY_DISPLAY' => ":#{display}"), 'dbus-daemon', '--session', '--nofork',
                           "--address=#{@address}", out: File::NULL, err: File::NULL)
    wait_for { File.socket?(File.join(@home, 'bus')) }
  end

  # Calls Rhythmbox's MPRIS player, failing rather than hanging when Rhythmbox doesn't answer:
  #
  #   headless.player('Next')
  #
  # @param method [String]
  # @param args [Array<Object>]
  # @return [Object] its answer
  # @raise [Timeout::Error]
  def player(method, *args)
    call(MPRIS, '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player', method, *args)
  end

  # @param name [String] `Metadata`, `PlaybackStatus`, …
  # @return [Object]
  # @raise [Timeout::Error]
  def player_property(name)
    call(MPRIS, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties', 'Get', 'org.mpris.MediaPlayer2.Player',
         name)
  end

  # Quits Rhythmbox, or kills it when it doesn't, then stops the bus and the display and removes
  # the home.
  #
  # @return [void]
  def stop
    quit
    @pids.reverse_each do |pid|
      Process.kill('TERM', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
    FileUtils.rm_rf(@home)
  end

  private

  # @return [void]
  def quit
    pid = call('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
               'GetConnectionUnixProcessID', MPRIS)
    begin
      call(MPRIS, '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2', 'Quit')
      wait_for { !alive?(pid) }
    rescue DBus::Error, RuntimeError # Timeout::Error, and wait_for's
      Process.kill('KILL', pid) if alive?(pid)
    end
  rescue DBus::Error # never started
    nil
  end

  # @param pid [Integer] not our child: the bus daemon's
  # @return [Boolean]
  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  # @param service [String]
  # @param path [String]
  # @param interface [String]
  # @param method [String]
  # @param args [Array<Object>]
  # @return [Object]
  # @raise [Timeout::Error]
  def call(service, path, interface, method, *args)
    bus = DBus::BusConnection.new(@address)
    Timeout.timeout(CALL_TIMEOUT) { bus[service][path][interface].public_send(method, *args) }
  ensure
    bus&.message_queue&.socket&.close
  end

  # @return [Hash{String => String}] the scratch home, for broadwayd, the bus and what it activates
  def env
    {
      'HOME' => @home,
      'XDG_CONFIG_HOME' => File.join(@home, '.config'),
      'XDG_DATA_HOME' => File.join(@home, '.local', 'share'),
      'XDG_CACHE_HOME' => File.join(@home, '.cache'),
      'XDG_STATE_HOME' => File.join(@home, '.local', 'state'),
      'XDG_RUNTIME_DIR' => @home,
      'XDG_MUSIC_DIR' => @music,
      'GSETTINGS_BACKEND' => 'keyfile',
      # Else GIO starts gvfs on the private bus, whose FUSE mount outlives {#stop} in the home.
      'GIO_USE_VFS' => 'local',
      # Every real sink out of autoaudiosink's reach, so it falls back to a fake one: through
      # ALSA's PipeWire plugin, Rhythmbox deadlocked changing tracks now and then.
      'GST_PLUGIN_FEATURE_RANK' => SINKS.map { "#{_1}:NONE" }.join(','),
      'GDK_BACKEND' => 'broadway',
      'NO_AT_BRIDGE' => '1',
      'DBUS_SESSION_BUS_ADDRESS' => @address
    }
  end

  # Rhythmbox's library is the Music folder, scanned 10 s after start. Upstream's `monitor-library`
  # is `false`, which scans nothing; only Ubuntu's desktop turns it on (`R_rhythmbox_dbus`).
  #
  # @return [void]
  def write_settings
    dir = File.join(@home, '.config', 'glib-2.0', 'settings')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'keyfile'), <<~INI)
      [org/gnome/rhythmbox/rhythmdb]
      locations=['file://#{@music}']
      monitor-library=true
    INI
  end

  # @param port [Integer]
  # @return [Boolean]
  def port_free?(port)
    TCPServer.new('127.0.0.1', port).close
    true
  rescue Errno::EADDRINUSE
    false
  end

  # @param seconds [Numeric]
  # @return [void]
  def wait_for(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      raise "not ready after #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end
end
