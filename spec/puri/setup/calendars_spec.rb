# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Puri::Setup::Calendars do
  it 'names each calendar Thunderbird keeps no copy of on disk, skipping local and disabled ones' do
    Dir.mktmpdir do |dir|
      File.write(prefs = File.join(dir, 'prefs.js'), <<~JS)
        // Mozilla User Preferences
        user_pref("calendar.registry.a1.cache.enabled", true);
        user_pref("calendar.registry.a1.name", "Work");
        user_pref("calendar.registry.a1.type", "caldav");
        user_pref("calendar.registry.b2.name", "Holidays \\"\\u00e9t\\u00e9\\"");
        user_pref("calendar.registry.b2.type", "ics");
        user_pref("calendar.registry.c3.name", "Home");
        user_pref("calendar.registry.c3.type", "storage");
        user_pref("calendar.registry.d4.disabled", true);
        user_pref("calendar.registry.d4.type", "caldav");
        user_pref("calendar.registry.e5.cache.enabled", false);
        user_pref("calendar.registry.e5.type", "caldav");
        user_pref("mail.server.server1.type", "imap");
      JS
      assert_equal ['Holidays "été"', 'e5'], described_class.uncached(prefs)
    end
  end

  it 'finds none without a prefs.js' do
    assert_empty described_class.uncached('/nonexistent/prefs.js')
  end
end
