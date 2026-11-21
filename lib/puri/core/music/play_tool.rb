# frozen_string_literal: true

module Puri
  module Core
    module Music
      # `play_music`: plays an artist, an album, a song or a genre from Rhythmbox's library, in
      # Rhythmbox, and raises its window.
      #
      #   tool = PlayTool.new(rhythmbox: Rhythmbox.find)
      #   tool.run('artist' => 'state azure').content
      #   # => Playing State Azure in Rhythmbox: 3 tracks, shuffled, round after round.
      #
      # Each kind plays its own way: an artist or a genre shuffled afresh each round until a
      # day's worth is queued, endless in practice; an album in track order, once; a song alone,
      # the library carrying on after it. The tool takes names, never a URI (*Search, never
      # fetch*), and asks no confirmation: local playback has no outbound leg, and a pause undoes
      # it (`D_music`).
      class PlayTool < Pikuri::Tool
        # @return [Integer] seconds of music an artist or a genre queues
        DAY = 86_400

        # @return [Integer] the most tracks queued, however short they are
        QUEUE_LIMIT = 1000

        # @return [String]
        DESCRIPTION = <<~DESC
          Plays music from the user's own library in Rhythmbox, the user's music player, and shows its window.

          Usage:
          - Pass the name the user gave as the kind it is: `genre` for a genre ("jazz", "ambient"), otherwise `artist`, `album` or `song`. Give two to narrow: an album or a song with its `artist`.
          - An artist or a genre plays shuffled, over and over; an album plays in order, once; a song plays once.
          - Names match the library's spelling, case aside. When nothing matches, the result says what the library has instead: call again with one of those names, or tell the user.
          - For "my favourite music", pass the favourite your memory names. If it names none, ask the user.
        DESC

        # @param rhythmbox [Puri::Core::Music::Rhythmbox]
        # @param random [Random] what shuffles
        def initialize(rhythmbox:, random: Random.new)
          @rhythmbox = rhythmbox
          @random = random
          super(
            name: 'play_music', description: DESCRIPTION,
            parameters: Pikuri::Tool::Parameters.build do |p|
              p.optional_string :artist, "An artist's or a band's name."
              p.optional_string :album, "An album's name."
              p.optional_string :song, "A song's title."
              p.optional_string :genre, 'A genre, like "jazz".'
            end,
            execute: lambda { |context:, artist: nil, album: nil, song: nil, genre: nil|
              play({ 'song' => song, 'album' => album, 'artist' => artist, 'genre' => genre }, context.cancellable)
            },
            # The library's names are whatever the files' tags say; nothing leaves the machine.
            trifecta_legs: Pikuri::Tool::TrifectaLegs.new(private: false, untrusted: :hard,
                                                          egress_payload_review: :no_egress),
            wants_context: true
          )
        end

        # @param arguments [Hash] the model's
        # @return [String] "Hurt, Johnny Cash"
        def describe_call(arguments)
          args = arguments.transform_keys(&:to_s)
          Pikuri::Tool.one_line(Finder::KINDS.filter_map { args[_1].to_s.strip.then { |s| s unless s.empty? } }
                                             .join(', '))
        end

        private

        # @param asked [Hash{String => String, nil}] a name per kind, nil where not given
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Pikuri::Tool::Result]
        def play(asked, cancellable)
          asked = asked.reject { |_, name| name.to_s.strip.empty? }
          return Pikuri::Tool::Result.error('give an artist, an album, a song or a genre') if asked.empty?

          @rhythmbox.open(cancellable:) do |session|
            tracks = Finder.new(session).find(asked)
            queue = queue(asked, tracks)
            session.play(queue.map(&:uri))
            answer(asked, tracks)
          end
        rescue Finder::Miss => e
          Pikuri::Tool::Result.new(content: e.message, summary: 'Not in the library')
        rescue Rhythmbox::Error => e
          Pikuri::Tool::Result.error("Rhythmbox: #{e.message}")
        end

        # @param asked [Hash{String => String}]
        # @param tracks [Array<Puri::Core::Music::Track>]
        # @return [Array<Puri::Core::Music::Track>] in the order they play
        def queue(asked, tracks)
          if asked.key?('song') then [tracks.first]
          elsif asked.key?('album') then tracks.sort_by { [_1.number, _1.title] }
          else rounds(tracks)
          end
        end

        # Fresh shuffles back to back, cut at a day's worth: the play queue never loops, and a
        # listener refilling it couldn't tell it running dry from the user picking other music.
        #
        # @param tracks [Array<Puri::Core::Music::Track>]
        # @return [Array<Puri::Core::Music::Track>]
        def rounds(tracks)
          queue = []
          seconds = 0
          loop do
            round = tracks.shuffle(random: @random)
            round.rotate! if round.size > 1 && round.first == queue.last
            round.each do |track|
              return queue if seconds >= DAY || queue.size >= QUEUE_LIMIT

              queue << track
              seconds += track.duration
            end
          end
        end

        # @param asked [Hash{String => String}]
        # @param tracks [Array<Puri::Core::Music::Track>]
        # @return [Pikuri::Tool::Result]
        def answer(asked, tracks)
          first = tracks.first
          count = Pikuri::Tool.pluralize(tracks.size, 'track')
          content, summary =
            if asked.key?('song')
              [%(Playing "#{first.title}" by #{first.artist} in Rhythmbox; the library carries on after it.),
               'Playing the song']
            elsif asked.key?('album')
              ["Playing the album #{first.album} by #{tracks.map(&:artist).uniq.join(', ')} in Rhythmbox: " \
               "#{count}, in order.", 'Playing the album']
            else
              what = asked.keys.map { |kind| kind == 'genre' ? "#{first.genre} music" : first[kind] }.join(', ')
              ["Playing #{what} in Rhythmbox: #{count}, shuffled, round after round.", 'Playing, shuffled']
            end
          Pikuri::Tool::Result.new(content:, summary:)
        end
      end
    end
  end
end
