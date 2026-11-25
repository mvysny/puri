# frozen_string_literal: true

require 'json'

module Puri
  module Setup
    # Thunderbird's calendars, as its `prefs.js` registers them, for the one thing Puri needs of
    # each: a copy on disk, which only Offline Support keeps of a calendar on a server or in a file.
    #
    #   user_pref("calendar.registry.3f2a….name", "Work");
    #   user_pref("calendar.registry.3f2a….type", "caldav");
    #   user_pref("calendar.registry.3f2a….cache.enabled", true);
    #
    #   Calendars.uncached(profile.prefs_path)   # => ["Holidays"]
    #
    # A local calendar, Thunderbird's own `storage`, always has its copy, and a disabled one is
    # skipped.
    module Calendars
      # @param prefs [String] a profile's `prefs.js`
      # @return [Array<String>] the names of the calendars Puri can't read, in the file's order;
      #   empty when there is no file
      def self.uncached(prefs)
        registry(prefs).filter_map do |id, props|
          next if props['type'] == 'storage' || props['disabled'] == true || props['cache.enabled'] == true

          props['name'] || id
        end
      end

      # @param prefs [String]
      # @return [Hash{String => Hash{String => Object}}] each calendar's properties, by its id
      def self.registry(prefs)
        return {} unless File.file?(prefs)

        File.foreach(prefs, encoding: 'UTF-8').each_with_object({}) do |line, calendars|
          match = line.match(/\Auser_pref\("calendar\.registry\.([^."]+)\.([^"]+)",\s*(.+)\);\s*\z/) or next
          (calendars[match[1]] ||= {})[match[2]] = value(match[3])
        end
      end

      # @param literal [String] a pref's value as `prefs.js` writes it
      # @return [Object] a String, a Boolean or an Integer; the literal itself when it is none
      def self.value(literal)
        JSON.parse(literal)
      rescue JSON::ParserError
        literal
      end
      private_class_method :registry, :value
    end
  end
end
