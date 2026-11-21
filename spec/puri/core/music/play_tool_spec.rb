# frozen_string_literal: true

RSpec.describe Puri::Core::Music::PlayTool do
  mu = Puri::Core::Music

  stellar = ['Low Orbit', 'Event Horizon', 'Drift'].each_with_index.map do |title, i|
    FakeRhythmbox.track(title, artist: 'State Azure', album: 'Stellar Descent', genre: 'Ambient', number: i + 1)
  end
  library = [
    *stellar.reverse,
    FakeRhythmbox.track('Hurt', artist: 'Copper Wire', album: 'Greatest Hits', number: 4),
    FakeRhythmbox.track('Hurt', artist: 'Paper Lanterns', album: 'Greatest Hits', number: 1),
    FakeRhythmbox.track('Hum', artist: 'Ambient Drones', album: 'Hum', genre: 'Drone')
  ]

  let(:rhythmbox) { FakeRhythmbox.new(*library) }
  let(:tool) { described_class.new(rhythmbox:, random: Random.new(7)) }

  describe 'an artist' do
    let(:result) { tool.run('artist' => ' state  azure ') }

    it 'matches case aside, and plays it shuffled' do
      assert_equal 'Playing State Azure in Rhythmbox: 3 tracks, shuffled, round after round.', result.content
      assert_equal 'Playing, shuffled', result.summary
    end

    it 'queues fresh shuffles back to back until a day is full' do
      result
      played = rhythmbox.played
      assert_equal described_class::DAY / 200, played.size
      played.each_slice(3) { assert_equal stellar.map(&:title).sort, _1.map(&:title).sort }
      refute(played.each_cons(2).any? { _1 == _2 }, 'a track twice in a row')
      refute_equal 1, played.each_slice(3).map { _1.map(&:title) }.uniq.size
    end

    it 'queues no more than the limit of short tracks' do
      short = FakeRhythmbox.new(FakeRhythmbox.track('Blip', artist: 'Tiny', duration: 1))
      described_class.new(rhythmbox: short).run('artist' => 'Tiny')
      assert_equal described_class::QUEUE_LIMIT, short.played.size
    end
  end

  it 'plays a genre shuffled' do
    assert_equal 'Playing Ambient music in Rhythmbox: 3 tracks, shuffled, round after round.',
                 tool.run('genre' => 'ambient').content
  end

  it 'plays an album once, in track order' do
    result = tool.run('album' => 'stellar descent')
    assert_equal 'Playing the album Stellar Descent by State Azure in Rhythmbox: 3 tracks, in order.', result.content
    assert_equal stellar, rhythmbox.played
  end

  it 'narrows an album shared by several artists to the one asked' do
    tool.run('album' => 'Greatest Hits', 'artist' => 'paper lanterns')
    assert_equal [library[4]], rhythmbox.played
  end

  describe 'a song' do
    it 'plays it alone' do
      result = tool.run('song' => 'hurt', 'artist' => 'Copper Wire')
      assert_equal 'Playing "Hurt" by Copper Wire in Rhythmbox; the library carries on after it.', result.content
      assert_equal 'Playing the song', result.summary
      assert_equal [library[3]], rhythmbox.played
    end

    it 'sung by several artists comes back as candidates, playing nothing' do
      result = tool.run('song' => 'Hurt')
      assert_equal 'Several songs are called "Hurt": by "Copper Wire" (Greatest Hits), by "Paper Lanterns" ' \
                   '(Greatest Hits). Pass the artist too, or ask the user which one.', result.content
      assert_equal 'Not in the library', result.summary
      assert_empty rhythmbox.played
    end
  end

  describe 'a name the library lacks' do
    it 'says where it is when it is another kind, and the near names of its own' do
      assert_equal 'No artist "ambient" in the library. Genre "Ambient" has 3 tracks. Nearest artists: ' \
                   '"Ambient Drones".', tool.run('artist' => 'ambient').content
      assert_empty rhythmbox.played
    end

    it 'offers the near spellings' do
      assert_equal 'No artist "State Azur" in the library. Nearest artists: "State Azure".',
                   tool.run('artist' => 'State Azur').content
    end

    it 'says so when nothing comes close' do
      assert_equal 'No artist "Metallica" in the library. Nothing else comes close.',
                   tool.run('artist' => 'Metallica').content
    end

    it 'says what the first name has when two never meet' do
      assert_equal 'No track is album "Greatest Hits" and artist "State Azure" at once. Album "Greatest Hits" has ' \
                   'artist "Copper Wire", "Paper Lanterns".',
                   tool.run('album' => 'Greatest Hits', 'artist' => 'State Azure').content
    end
  end

  it 'wants a name' do
    assert_equal 'Error: give an artist, an album, a song or a genre', tool.run('artist' => ' ').content
  end

  it "fails when Rhythmbox can't be reached" do
    dead = mu::Rhythmbox.new("unix:path=#{Dir.tmpdir}/puri-no-such-bus")
    result = described_class.new(rhythmbox: dead).run('artist' => 'State Azure')
    assert_match(/\AError: Rhythmbox: /, result.content)
  end

  it 'names the call by what it asks for, most specific first' do
    assert_equal 'Hurt, Copper Wire', tool.describe_call(artist: 'Copper Wire', song: 'Hurt')
  end
end
