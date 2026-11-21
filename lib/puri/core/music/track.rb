# frozen_string_literal: true

module Puri
  module Core
    module Music
      # One track of Rhythmbox's library, as its media server lists it.
      #
      # @!attribute [r] title
      #   @return [String]
      # @!attribute [r] artist
      #   @return [String]
      # @!attribute [r] album
      #   @return [String]
      # @!attribute [r] genre
      #   @return [String]
      # @!attribute [r] duration
      #   @return [Integer] seconds; 0 when Rhythmbox doesn't know
      # @!attribute [r] number
      #   @return [Integer] its track number on the album; 0 when untagged
      # @!attribute [r] uri
      #   @return [String] where Rhythmbox plays it from, a percent-encoded `file://` URI
      class Track < Data.define(:title, :artist, :album, :genre, :duration, :number, :uri)
        # The fields {Rhythmbox::Session#tracks} asks for, as the media server names them.
        #
        # @return [Array<String>]
        PROPERTIES = %w[DisplayName Artist Album Genre Duration TrackNumber URLs].freeze

        # @param item [Hash{String => Object}] one of `ListItems`' answers, with {PROPERTIES}
        # @return [Puri::Core::Music::Track]
        def self.from_item(item)
          new(title: item['DisplayName'].to_s, artist: item['Artist'].to_s, album: item['Album'].to_s,
              genre: item['Genre'].to_s, duration: item['Duration'].to_i, number: item['TrackNumber'].to_i,
              uri: Array(item['URLs']).first.to_s)
        end

        # @param kind [String] one of {Finder::KINDS}
        # @return [String] the field a kind names: the title for a song
        def [](kind)
          kind == 'song' ? title : public_send(kind)
        end
      end
    end
  end
end
