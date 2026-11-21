# frozen_string_literal: true

module Puri
  module Core
    # "Play my favourite music": the `play_music` tool, which finds an artist, an album, a song or
    # a genre in Rhythmbox's library and plays it there (`D_music`).
    #
    #   rhythmbox = Music::Rhythmbox.find          # one per process; nil without Rhythmbox
    #   configurator.add_tool(Music::PlayTool.new(rhythmbox:))
    #
    # {Rhythmbox} speaks D-Bus, {Finder} turns the model's names into {Track}s, and {PlayTool}
    # orders them and words the answer.
    module Music
    end
  end
end
