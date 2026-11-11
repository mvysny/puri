# frozen_string_literal: true

require 'socket'
require 'tmpdir'

# A Broadway display for code that loads GTK on a machine without one: the specs, and the sig
# task, which loads the app to resolve its type names. GTK reads the display at
# `require 'gtk4'`, so {start} runs before {Puri.require_gtk}.
module Broadway
  # @return [Range<Integer>] displays tried in turn; Broadway serves HTTP on 8080 + display
  DISPLAYS = (90..99)

  # Starts `gtk4-broadwayd` on the first free display of {DISPLAYS}, points GTK at it, and stops
  # it when the process exits. Does nothing when the caller already chose a display through
  # `GDK_BACKEND`, so a developer can watch the specs on their own Broadway page.
  #
  # @return [void]
  def self.start
    return if ENV['GDK_BACKEND']

    # GTK finds broadwayd's socket in the runtime dir; a container has none, so both get a private one.
    ENV['XDG_RUNTIME_DIR'] ||= Dir.mktmpdir('puri-runtime')
    display = DISPLAYS.find { |d| port_free?(8080 + d) } or raise "no free Broadway display in #{DISPLAYS}"
    pid = spawn_broadwayd(display)
    at_exit do
      Process.kill('TERM', pid)
      Process.wait(pid)
    end
    wait_for_port(8080 + display, pid)
    ENV.update('GDK_BACKEND' => 'broadway', 'BROADWAY_DISPLAY' => ":#{display}", 'ADW_DISABLE_PORTAL' => '1')
  end

  # @param display [Integer]
  # @return [Integer] the pid
  def self.spawn_broadwayd(display)
    Process.spawn('gtk4-broadwayd', '--address', '127.0.0.1', ":#{display}", out: File::NULL, err: File::NULL)
  rescue Errno::ENOENT
    raise 'gtk4-broadwayd is missing: sudo apt install libgtk-4-bin'
  end

  # @param port [Integer]
  # @return [Boolean]
  def self.port_free?(port)
    TCPServer.new('127.0.0.1', port).close
    true
  rescue Errno::EADDRINUSE
    false
  end

  # @param port [Integer]
  # @param pid [Integer] broadwayd, which dying means it won't come up
  # @return [void]
  def self.wait_for_port(port, pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      TCPSocket.new('127.0.0.1', port).close
      return
    rescue Errno::ECONNREFUSED
      raise "gtk4-broadwayd exited before listening on #{port}" if Process.wait(pid, Process::WNOHANG)
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "gtk4-broadwayd isn't listening on #{port} after 10 s"
      end

      sleep 0.05
    end
  end
end
