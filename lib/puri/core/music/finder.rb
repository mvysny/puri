# frozen_string_literal: true

require 'did_you_mean'

module Puri
  module Core
    module Music
      # Turns the model's names into the library's tracks, or into a {Miss} that tells the model
      # what is there instead:
      #
      #   Finder.new(session).find('artist' => 'state azure')            # => State Azure's tracks
      #   Finder.new(session).find('artist' => 'Johnny Cash', 'song' => 'Hurt')   # => his "Hurt"
      #   Finder.new(session).find('artist' => 'Ambient')
      #   # raises Miss: No artist "Ambient" in the library. Genre "Ambient" has 3 tracks. …
      #
      # A name matches case-folded and exactly; a near miss comes back as candidates, never
      # played. Several names narrow: the most specific kind given picks the tracks, and every
      # other must match each one's own field.
      class Finder
        # Raised when the names find nothing to play; the message is for the model.
        class Miss < StandardError; end

        # Most specific first.
        #
        # @return [Array<String>]
        KINDS = %w[song album artist genre].freeze

        # @return [Integer] how many near names a {Miss} offers
        NEAREST = 5

        # @param session [Puri::Core::Music::Rhythmbox::Session]
        def initialize(session)
          @session = session
          @groups = {}
        end

        # @param asked [Hash{String => String}] a name per kind of {KINDS}, at least one
        # @return [Array<Puri::Core::Music::Track>] never empty
        # @raise [Miss]
        def find(asked)
          names = asked.to_h { |kind, name| [kind, resolve(kind, name)] }
          primary = KINDS.find { names.key?(_1) }
          tracks = primary_tracks(primary, names[primary])
          found = tracks.select { |track| names.all? { |kind, name| track[kind] == name } }
          raise Miss, apart(primary, names, tracks) if found.empty?
          raise Miss, several(found) if primary == 'song' && found.map(&:artist).uniq.size > 1

          found
        end

        private

        # @param kind [String]
        # @param name [String] the model's
        # @return [String] the library's spelling
        # @raise [Miss]
        def resolve(kind, name)
          names(kind).find { fold(_1) == fold(name) } or raise Miss, missing(kind, name)
        end

        # @param kind [String]
        # @param name [String]
        # @return [String]
        def missing(kind, name)
          lines = [%(No #{kind} "#{name}" in the library.)]
          lines += (KINDS - [kind]).filter_map { |other| elsewhere(other, name) }
          near = nearest(names(kind), name)
          lines << "Nearest #{kind}s: #{quoted(near)}." unless near.empty?
          lines << 'Nothing else comes close.' if lines.size == 1
          lines.join(' ')
        end

        # @param kind [String]
        # @param name [String]
        # @return [String, nil] "Genre "Jazz" has 214 tracks.", when the name is one of this kind
        def elsewhere(kind, name)
          hit = names(kind).find { fold(_1) == fold(name) } or return nil
          count = kind == 'song' ? library.count { _1.title == hit } : group(kind, hit).count
          %(#{kind.capitalize} "#{hit}" has #{Pikuri::Tool.pluralize(count, 'track')}.)
        end

        # @param primary [String] the kind that picked `tracks`
        # @param names [Hash{String => String}]
        # @param tracks [Array<Puri::Core::Music::Track>]
        # @return [String]
        def apart(primary, names, tracks)
          asked = names.map { |kind, name| %(#{kind} "#{name}") }.join(' and ')
          has = (names.keys - [primary]).map do |kind|
            values = quoted(tracks.map { _1[kind] }.uniq.first(NEAREST))
            %(#{primary.capitalize} "#{names[primary]}" has #{kind} #{values}.)
          end
          "No track is #{asked} at once. #{has.join(' ')}"
        end

        # @param found [Array<Puri::Core::Music::Track>] one title by several artists
        # @return [String]
        def several(found)
          each = found.uniq(&:artist).map { %(by "#{_1.artist}" (#{_1.album})) }.join(', ')
          %(Several songs are called "#{found.first.title}": #{each}. Pass the artist too, or ask the user which one.)
        end

        # @param candidates [Array<String>]
        # @param name [String]
        # @return [Array<String>] those containing it or contained in it, then the near spellings
        def nearest(candidates, name)
          folded = fold(name)
          containing = candidates.select do
            other = fold(_1)
            other.include?(folded) || (other.size >= 3 && folded.include?(other))
          end
          (containing + DidYouMean::SpellChecker.new(dictionary: candidates).correct(name)).uniq.first(NEAREST)
        end

        # @param kind [String]
        # @return [Array<String>] every name of a kind in the library
        def names(kind)
          kind == 'song' ? library.map(&:title).uniq : groups(kind).map(&:name)
        end

        # @param kind [String]
        # @param name [String] the library's spelling
        # @return [Array<Puri::Core::Music::Track>] every track of that name: a song's, from the
        #   whole library, since songs have no container of their own
        def primary_tracks(kind, name)
          return library.select { _1.title == name } if kind == 'song'

          @session.tracks(group(kind, name).path)
        end

        # @param kind [String] not `song`
        # @param name [String] the library's spelling
        # @return [Puri::Core::Music::Rhythmbox::Group]
        def group(kind, name)
          groups(kind).find { _1.name == name }
        end

        # @param kind [String] not `song`
        # @return [Array<Puri::Core::Music::Rhythmbox::Group>]
        def groups(kind)
          @groups[kind] ||= @session.groups(kind)
        end

        # Every track, read once and only when a song is asked for, or a name is missing: a big
        # library is one long answer.
        #
        # @return [Array<Puri::Core::Music::Track>]
        def library
          @library ||= @session.tracks
        end

        # @param names [Array<String>]
        # @return [String] "\"a\", \"b\""
        def quoted(names)
          names.map { %("#{_1}") }.join(', ')
        end

        # @param name [String]
        # @return [String]
        def fold(name)
          name.strip.squeeze(' ').downcase(:fold)
        end
      end
    end
  end
end
