# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative 'support/broadway'

# `rake install` against a scratch home: the XDG dirs point into a temp dir and gsettings writes a
# keyfile there, so no example touches the desktop it runs on.
RSpec.describe 'rake install' do
  root = File.expand_path('..', __dir__)
  app_id = 'io.github.mvysny.Puri'
  media_keys = 'org.gnome.settings-daemon.plugins.media-keys'
  puri_keybinding = '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/puri/'
  other_keybinding = '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/'

  around do |example|
    Dir.mktmpdir('puri-install') do |home|
      @home = home
      example.run
    end
  end

  # @param extra [Hash{String => String, nil}] nil unsets
  # @return [Hash{String => String, nil}]
  def env(extra = {})
    { 'XDG_DATA_HOME' => "#{@home}/data", 'XDG_CONFIG_HOME' => "#{@home}/config",
      'XDG_STATE_HOME' => "#{@home}/state", 'GSETTINGS_BACKEND' => 'keyfile', 'HOTKEY' => nil,
      'AUTOSTART' => nil, 'DBUS_SESSION_BUS_ADDRESS' => "unix:path=#{@home}/no-bus" }.merge(extra)
  end

  # @param task [String]
  # @param vars [Hash{String => String}]
  # @return [Array(String, String, Process::Status)]
  def rake(task, vars = {})
    Open3.capture3(env(vars), RbConfig.ruby, Gem.bin_path('rake', 'rake'), task,
                   chdir: File.expand_path('..', __dir__))
  end

  # @param task [String]
  # @param vars [Hash{String => String}]
  # @return [String] stdout
  def rake!(task, vars = {})
    out, err, status = rake(task, vars)
    assert status.success?, "rake #{task} failed:\n#{out}#{err}"
    out
  end

  # @param args [Array<String>]
  # @return [String] stdout, stripped
  def gsettings(*args)
    out, err, status = Open3.capture3(env, 'gsettings', *args)
    assert status.success?, err
    out.strip
  end

  # @param schema [String]
  # @param key [String]
  # @return [Array<String>]
  def strv(schema, key) = gsettings('get', schema, key).scan(/'([^']*)'/).flatten

  # @param path [String]
  # @return [void]
  def assert_valid_desktop_entry(path)
    out, status = Open3.capture2e('desktop-file-validate', path)
    assert status.success?, "#{path}:\n#{out}"
  end

  let(:desktop) { "#{@home}/data/applications/#{app_id}.desktop" }
  let(:service) { "#{@home}/data/dbus-1/services/#{app_id}.service" }
  let(:autostart) { "#{@home}/config/autostart/#{app_id}.desktop" }

  it 'writes a D-Bus-activatable desktop entry and a service that runs exe/puri' do
    rake!('install')
    assert_valid_desktop_entry desktop
    assert_includes File.read(desktop), "\nDBusActivatable=true\n"
    assert_includes File.read(service), %(\nExec="#{root}/exe/puri" --gapplication-service\n)
    refute File.exist?(autostart), 'autostart is opt-in'
  end

  it 'binds Super+Alt+Space beside existing custom shortcuts' do
    gsettings('set', media_keys, 'custom-keybindings', "['#{other_keybinding}']")
    out = rake!('install')
    assert_includes out, '<Super><Alt>space opens Puri'

    assert_equal [other_keybinding, puri_keybinding], strv(media_keys, 'custom-keybindings')
    entry = "#{media_keys}.custom-keybinding:#{puri_keybinding}"
    assert_equal "'<Super><Alt>space'", gsettings('get', entry, 'binding')
    assert_equal "'gapplication launch #{app_id}'", gsettings('get', entry, 'command')
  end

  it 'rebinds for another HOTKEY, and uninstall undoes everything' do
    gsettings('set', media_keys, 'custom-keybindings', "['#{other_keybinding}']")
    rake!('install')

    rake!('install', 'HOTKEY' => '<Super>p')
    assert_equal "'<Super>p'", gsettings('get', "#{media_keys}.custom-keybinding:#{puri_keybinding}", 'binding')

    assert_includes rake!('install', 'HOTKEY' => ''), 'No shortcut bound'
    assert_equal [other_keybinding], strv(media_keys, 'custom-keybindings')

    rake!('install')
    rake!('uninstall')
    refute File.exist?(desktop)
    refute File.exist?(service)
    assert_equal [other_keybinding], strv(media_keys, 'custom-keybindings')
  end

  it 'adds a valid autostart entry for AUTOSTART=1, and a plain install takes it away' do
    rake!('install', 'AUTOSTART' => '1')
    assert_valid_desktop_entry autostart
    assert_includes File.read(autostart), '--gapplication-service'

    rake!('install')
    refute File.exist?(autostart)
  end

  it 'refuses a HOTKEY that is no accelerator, before writing anything' do
    _, err, status = rake('install', 'HOTKEY' => "x'; rm")
    refute status.success?
    assert_includes err, "isn't an accelerator"
    refute File.exist?(desktop)
  end

  it 'warns, and still installs, with no session bus to reload' do
    out, err, status = rake('install')
    assert status.success?, "#{out}#{err}"
    assert_includes err, "The session bus didn't reload"
    assert File.exist?(service)
  end

  connection = <<~TOML
    [[server]]
    id  = "local"
    url = "http://localhost:8080"

    [[llm]]
    name   = "Local"
    server = "local"
    model  = "qwen"
  TOML

  # The whole path a shortcut takes, on a private session bus that reads the services from the
  # scratch home: `gapplication launch` with no Puri running makes the bus start one. The bus
  # starts before the install, as the login session's does, so the install has one to reload,
  # though dbus-daemon would find the file without it (`R_gnome_activation`). A config starts the
  # real backend; nothing asks, so nothing dials the server. A broken one, with no `[titler]`,
  # starts none: Puri stays up for its failure dialog rather than exiting unseen.
  { 'a config' => "#{connection}\n[titler]\nllm = \"Local\"\n", 'a broken config' => connection }.each do |what, toml|
    it "lets the session bus start Puri on `gapplication launch` with #{what}, and its quit action end it" do
      Broadway.start
      FileUtils.mkdir_p("#{@home}/config/puri")
      File.write("#{@home}/config/puri/config.toml", toml)
      launch_and_quit(app_id)
    end
  end

  # Installs Puri on a bus of its own, launches it as the shortcut does, and quits it as Ctrl+Q
  # does, failing unless it ran in between and ended after.
  #
  # @param app_id [String]
  # @return [void]
  def launch_and_quit(app_id)
    # The bus hands its own environment to the Puri it starts. Local GIO, or that Puri asks the bus
    # for gvfs, which can't mount here; err: quiets the bus's activation log.
    bus = IO.popen([env('GIO_USE_VFS' => 'local'), 'dbus-daemon', '--session', '--nofork', '--print-address'],
                   err: File::NULL)
    begin
      address = bus.gets&.strip or raise 'dbus-daemon printed no address'
      on_bus = env('DBUS_SESSION_BUS_ADDRESS' => address)
      out, err, status = rake('install', 'HOTKEY' => '', 'DBUS_SESSION_BUS_ADDRESS' => address)
      assert status.success?, "#{out}#{err}"
      refute_includes err, "didn't reload"

      _, err, status = Open3.capture3(on_bus, 'gapplication', 'launch', app_id)
      assert status.success?, err

      owner = Open3.capture2(on_bus, 'gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
                             '--object-path', '/org/freedesktop/DBus',
                             '--method', 'org.freedesktop.DBus.GetConnectionUnixProcessID', app_id).first
      pid = owner[/\(uint32 (\d+),\)/, 1] or raise "nobody owns #{app_id}: #{owner.inspect}"

      # Ctrl+Q's action, from a terminal: the resident Puri ends and lets go of its name.
      _, err, status = Open3.capture3(on_bus, 'gapplication', 'action', app_id, 'quit')
      assert status.success?, err
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      until (gone = !name_owned?(on_bus, app_id))
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

        sleep 0.1
      end
      assert gone, "#{app_id} still runs after its quit action"
    ensure
      Process.kill('KILL', Integer(pid)) if pid && !gone
      Process.kill('TERM', bus.pid)
      bus.close
    end
  end

  # @param bus_env [Hash{String => String, nil}] an {#env} whose bus to ask
  # @param name [String]
  # @return [Boolean] whether anyone on that bus owns `name`
  def name_owned?(bus_env, name)
    Open3.capture2(bus_env, 'gdbus', 'call', '--session', '--dest', 'org.freedesktop.DBus',
                   '--object-path', '/org/freedesktop/DBus',
                   '--method', 'org.freedesktop.DBus.NameHasOwner', name).first.include?('true')
  end
end
