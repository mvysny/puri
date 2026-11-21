# frozen_string_literal: true

require 'dbus'
require 'timeout'

module Puri
  module Core
    module Music
      # Rhythmbox, over the session bus: its library through the `dbus-media-server` plugin, its
      # play queue, and MPRIS (`R_rhythmbox_dbus`). Each {#open} is a connection of its own,
      # which starts Rhythmbox when it isn't running:
      #
      #   rhythmbox = Rhythmbox.find                 # nil where the bus can't start Rhythmbox
      #   rhythmbox.open(cancellable:) do |session|
      #     artist = session.groups('artist').find { _1.name == 'State Azure' }
      #     session.play(session.tracks(artist.path).map(&:uri).shuffle)
      #   end
      #
      # Thread-safe: a call opens its own connection, since ruby-dbus' isn't safe to share.
      class Rhythmbox
        # Raised for anything that keeps Rhythmbox from answering: no bus, a start that failed, a
        # call that timed out.
        class Error < StandardError; end

        # An artist, album or genre, as the library lists it.
        #
        # @!attribute [r] name
        #   @return [String] as Rhythmbox shows it
        # @!attribute [r] path
        #   @return [String] its container's object path, for {Session#tracks}
        # @!attribute [r] count
        #   @return [Integer] how many tracks it has
        class Group < Data.define(:name, :path, :count); end

        # @return [String] what D-Bus activation starts
        APPLICATION = 'org.gnome.Rhythmbox3'

        # @return [String]
        MEDIA_SERVER = 'org.gnome.UPnP.MediaServer2.Rhythmbox'

        # @return [String]
        MPRIS = 'org.mpris.MediaPlayer2.rhythmbox'

        # @return [String] the local library: the music Rhythmbox's window shows, never radio or podcasts
        LIBRARY = '/org/gnome/UPnP/MediaServer2/Library'

        # @return [String]
        CONTAINER = 'org.gnome.UPnP.MediaContainer2'

        # @return [Integer] seconds an {#open} may take, Rhythmbox's start included
        TIMEOUT = 60

        # @return [Integer] seconds a start waits for the library to load; an empty one never does
        LOAD_TIMEOUT = 20

        # @param address [String, nil] the session bus's; nil for the user's own
        # @return [Puri::Core::Music::Rhythmbox, nil] nil where the bus can't start Rhythmbox, or
        #   there is no bus
        def self.find(address = nil)
          rhythmbox = new(address)
          rhythmbox.installed? ? rhythmbox : nil
        end

        # @param address [String, nil] the session bus's; nil for the user's own
        def initialize(address = nil)
          @address = address
        end

        # @return [Boolean] whether the bus can start Rhythmbox, or it runs already
        def installed?
          # The bus's own proxy answers every call in an array.
          connect do |bus|
            bus.proxy.ListActivatableNames.first.include?(APPLICATION) || bus.proxy.NameHasOwner(MEDIA_SERVER).first
          end
        rescue Error
          false
        end

        # Connects, starts Rhythmbox unless it runs, and yields the connection.
        #
        # @param cancellable [Pikuri::Agent::Control::Cancellable] polled while Rhythmbox starts
        # @yieldparam session [Puri::Core::Music::Rhythmbox::Session]
        # @yieldreturn [Object]
        # @return [Object] the block's value
        # @raise [Puri::Core::Music::Rhythmbox::Error]
        def open(cancellable:)
          connect do |bus|
            session = Session.new(bus, cancellable:)
            session.start
            yield session
          end
        end

        private

        # @yieldparam bus [DBus::BusConnection]
        # @yieldreturn [Object]
        # @return [Object] the block's value
        # @raise [Puri::Core::Music::Rhythmbox::Error]
        def connect
          bus = DBus::BusConnection.new(@address || DBus::ASessionBus.session_bus_address)
          # ruby-dbus has no timeouts: a Rhythmbox that never answers would hold the turn forever.
          Timeout.timeout(TIMEOUT, Error, "Rhythmbox didn't answer in #{TIMEOUT} s") { yield bus }
        rescue DBus::Error, SystemCallError, NotImplementedError, EOFError => e
          raise Error, e.message
        ensure
          bus&.message_queue&.socket&.close
        end

        # One connection to a running Rhythmbox.
        class Session
          # @param bus [DBus::BusConnection]
          # @param cancellable [Pikuri::Agent::Control::Cancellable]
          def initialize(bus, cancellable:)
            @bus = bus
            @cancellable = cancellable
          end

          # Starts Rhythmbox unless its media server is on the bus, and waits for its library.
          # D-Bus activation opens its window, which is wanted: the user sees the music start
          # even with the sound off (`D_music`).
          #
          # @return [void]
          # @raise [Puri::Core::Music::Rhythmbox::Error] when it doesn't come up
          def start
            return if owned?(MEDIA_SERVER) && owned?(MPRIS)

            @bus[APPLICATION]['/org/gnome/Rhythmbox3']['org.freedesktop.DBus.Peer'].Ping
            wait(LOAD_TIMEOUT) { owned?(MEDIA_SERVER) && owned?(MPRIS) } or
              raise Error, "Rhythmbox started, but its library isn't on the bus; is the 'D-Bus Media Server' " \
                           'plugin on?'
            wait_for_library
          end

          # @param kind [String] `artist`, `album` or `genre`
          # @return [Array<Puri::Core::Music::Rhythmbox::Group>] every one in the library
          def groups(kind)
            container("#{LIBRARY}/#{kind}").ListContainers(0, 0, %w[Path DisplayName ChildCount]).map do |c|
              Group.new(name: c['DisplayName'].to_s, path: c['Path'].to_s, count: c['ChildCount'].to_i)
            end
          end

          # @param path [String] a {Group}'s, or `nil` for the whole library
          # @return [Array<Puri::Core::Music::Track>]
          def tracks(path = nil)
            container(path || "#{LIBRARY}/all").ListItems(0, 0, Track::PROPERTIES).map { Track.from_item(_1) }
          end

          # Plays `uris` in order: the first at once, the rest from the play queue, which it
          # clears of whatever was queued before. Then raises Rhythmbox's window.
          #
          # @param uris [Array<String>] the library's own, never the model's: a URI Rhythmbox
          #   doesn't know is fetched
          # @return [void]
          def play(uris)
            queue = @bus[APPLICATION]['/org/gnome/Rhythmbox3/PlayQueue']['org.gnome.Rhythmbox3.PlayQueue']
            queue.ClearQueue
            uris.drop(1).each do |uri|
              @cancellable.check!
              queue.AddToQueue(uri)
            end
            # Not MPRIS Play: from stopped, that plays the sidebar's selected source, not the queue.
            mpris_player.OpenUri(uris.first)
            @bus[MPRIS]['/org/mpris/MediaPlayer2']['org.mpris.MediaPlayer2'].Raise
          end

          private

          # @return [DBus::ProxyObjectInterface]
          def mpris_player
            @bus[MPRIS]['/org/mpris/MediaPlayer2']['org.mpris.MediaPlayer2.Player']
          end

          # @param path [String]
          # @return [DBus::ProxyObjectInterface]
          def container(path)
            @bus[MEDIA_SERVER][path][CONTAINER]
          end

          # @param name [String]
          # @return [Boolean]
          def owned?(name)
            @bus.proxy.NameHasOwner(name).first
          end

          # A fresh Rhythmbox serves an empty library until its database has loaded, then all of
          # it at once; a count that holds for two polls is taken as loaded.
          #
          # @return [void]
          def wait_for_library
            last = nil
            wait(LOAD_TIMEOUT) do
              count = all_tracks_count
              (count.positive? && count == last).tap { last = count }
            end
          end

          # @return [Integer]
          def all_tracks_count
            all = container(LIBRARY).ListContainers(0, 0, %w[Path ChildCount]).find do
              _1['Path'] == "#{LIBRARY}/all"
            end
            all ? all['ChildCount'].to_i : 0
          end

          # @param seconds [Numeric]
          # @yieldreturn [Boolean]
          # @return [Boolean] whether the block came true in time
          def wait(seconds)
            deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
            until yield
              return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

              @cancellable.sleep(0.25)
            end
            true
          end
        end
      end
    end
  end
end
