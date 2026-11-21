# frozen_string_literal: true

require_relative '../../../support/headless_rhythmbox'

# The real Rhythmbox, headless (HeadlessRhythmbox): what the spec of `play_music` fakes, held to
# what Rhythmbox does. Its first call starts Rhythmbox, which imports the fixtures' five silent
# minutes in about ten seconds.
RSpec.describe Puri::Core::Music::Rhythmbox do
  mu = Puri::Core::Music

  before(:all) { @headless = HeadlessRhythmbox.start }
  after(:all) { @headless&.stop }

  before { skip 'rhythmbox or broadwayd is not installed' unless headless }

  let(:headless) { @headless }
  let(:rhythmbox) { described_class.new(headless.address) }
  let(:cancellable) { Pikuri::Agent::Control::Cancellable.new }

  # @yieldreturn [Boolean]
  # @return [void]
  def eventually
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.05 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  it 'is installed where the bus can start it' do
    assert rhythmbox.installed?
  end

  it 'lists the library by artist, album and genre, an album shared by two artists as one' do
    groups = rhythmbox.open(cancellable:) { |s| %w[artist album genre].to_h { [_1, s.groups(_1)] } }
    assert_equal({ 'Copper Wire' => 1, 'Paper Lanterns' => 1, 'State Azure' => 3 },
                 groups['artist'].to_h { [_1.name, _1.count] })
    assert_equal({ 'Greatest Hits' => 2, 'Stellar Descent' => 3 }, groups['album'].to_h { [_1.name, _1.count] })
    assert_equal %w[Ambient Rock], groups['genre'].map(&:name).sort
    assert_equal '/org/gnome/UPnP/MediaServer2/Library/artist/State_20Azure', groups['artist'].last.path
  end

  it "reads each track's tags" do
    tracks = rhythmbox.open(cancellable:) do |s|
      s.tracks(s.groups('artist').find { _1.name == 'State Azure' }.path)
    end
    assert_equal ['Low Orbit', 'Event Horizon', 'Drift'], tracks.sort_by(&:number).map(&:title)
    track = tracks.min_by(&:number)
    assert_equal ['State Azure', 'Stellar Descent', 'Ambient', 1, 60],
                 [track.artist, track.album, track.genre, track.number, track.duration]
    assert_equal "file://#{headless.music}/state-azure-low-orbit.ogg", track.uri
    assert_equal 5, rhythmbox.open(cancellable:) { |s| s.tracks.size }
  end

  it 'plays what play_music picks, the rest queued after it' do
    result = mu::PlayTool.new(rhythmbox:).run('album' => 'stellar descent')
    assert_equal 'Playing the album Stellar Descent by State Azure in Rhythmbox: 3 tracks, in order.', result.content
    eventually { headless.player_property('Metadata')['xesam:title'] == 'Low Orbit' }
    assert_equal 'Low Orbit', headless.player_property('Metadata')['xesam:title']
    assert_equal 'Playing', headless.player_property('PlaybackStatus')
    headless.player('Next')
    eventually { headless.player_property('Metadata')['xesam:title'] == 'Event Horizon' }
    assert_equal 'Event Horizon', headless.player_property('Metadata')['xesam:title']
  end
end
