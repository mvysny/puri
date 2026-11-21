# frozen_string_literal: true

module Puri
  module Desktop
    # Opens a place's openstreetmap.org URL where the user can look around it: in GNOME Maps,
    # which reads the URL and shows the place itself, or in the browser where Maps isn't installed.
    #
    #   MapsLauncher.open('https://www.openstreetmap.org/node/9444805490')
    #
    # Maps by its desktop file, never as the URL's default handler, which is the browser.
    module MapsLauncher
      # @return [String]
      MAPS = 'org.gnome.Maps.desktop'

      # A failure is printed, never raised: a click has no one to tell.
      #
      # @param url [String]
      # @return [void]
      def self.open(url)
        maps = Gio::AppInfo.all.find { _1.id == MAPS }
        if maps
          maps.launch_uris([url], nil)
        else
          Gio::AppInfo.launch_default_for_uri(url, nil)
        end
      rescue GLib::Error => e
        warn "puri: can't open #{url}: #{e.message}"
      end
    end
  end
end
