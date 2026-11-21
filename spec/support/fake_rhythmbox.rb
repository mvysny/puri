# frozen_string_literal: true

# A Rhythmbox for `play_music`'s specs: {open} yields itself as the session, its library is the
# tracks it was given, grouped as Rhythmbox's media server groups them, and {play} records what
# would have played. spec/puri/core/music/rhythmbox_spec.rb holds the real one to the same shape.
#
#   rhythmbox = FakeRhythmbox.new(FakeRhythmbox.track('Hurt', artist: 'Copper Wire'))
#   Puri::Core::Music::PlayTool.new(rhythmbox:).run('song' => 'hurt')
#   rhythmbox.played.map(&:title)   # => ["Hurt"]
class FakeRhythmbox
  # @return [Array<Puri::Core::Music::Track>] what {play} got, in order
  attr_reader :played

  # @param title [String]
  # @param artist [String]
  # @param album [String]
  # @param genre [String]
  # @param number [Integer]
  # @param duration [Integer]
  # @return [Puri::Core::Music::Track]
  def self.track(title, artist:, album: 'Singles', genre: 'Rock', number: 1, duration: 200)
    Puri::Core::Music::Track.new(title:, artist:, album:, genre:, duration:, number:,
                                 uri: "file:///music/#{artist}/#{title}.ogg".gsub(' ', '%20'))
  end

  # @param tracks [Array<Puri::Core::Music::Track>]
  def initialize(*tracks)
    @tracks = tracks
    @played = []
  end

  # @param cancellable [Pikuri::Agent::Control::Cancellable]
  # @yieldparam session [FakeRhythmbox]
  # @return [Object] the block's value
  def open(cancellable:)
    cancellable.check!
    yield self
  end

  # @param kind [String]
  # @return [Array<Puri::Core::Music::Rhythmbox::Group>]
  def groups(kind)
    @tracks.group_by { _1[kind] }.map do |name, tracks|
      Puri::Core::Music::Rhythmbox::Group.new(name:, path: "#{kind}/#{name}", count: tracks.size)
    end
  end

  # @param path [String, nil]
  # @return [Array<Puri::Core::Music::Track>]
  def tracks(path = nil)
    return @tracks unless path

    kind, name = path.split('/', 2)
    @tracks.select { _1[kind] == name }
  end

  # @param uris [Array<String>]
  # @return [void]
  def play(uris)
    @played = uris.map { |uri| @tracks.find { _1.uri == uri } }
  end
end
