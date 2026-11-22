# frozen_string_literal: true

module Puri
  module Dummy
    # What {Backend} answers, picked by words in the question, so every path through the UI
    # can be walked by hand:
    #
    #   (anything else)            thinks, streams a short Markdown answer
    #   search                     a search step, then an answer with a list
    #   note                       reads a note, answers with a checklist
    #   calendar + reschedule      asks to move an event: Update / Cancel / type a correction
    #   mail                       asks to hand a draft to the mail app (a harmless confirmation)
    #   table                      an answer with a table and a code block
    #   long                       a long answer, for scrolling and Escape while it streams
    #   coffee                     a place search, then cafés on a map under the answer
    #   drive                      a route, then the road on a map
    #   weather                    a forecast, its step crediting Open-Meteo with a link
    #   fail                       streams a little, then the turn fails
    module Script
      # @return [Array<String>]
      WEEKDAYS = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

      # @return [Puri::Protocol::Pin] where {CAFES} were searched from
      SHOP = Protocol::Pin.new(label: nil, name: 'Musiikki Silfverberg Oy Vantaan Musiikki, Peltolantie 2',
                               lat: 60.2931102, lon: 25.0307498, url: 'https://www.openstreetmap.org/node/9444805490')

      # @return [Array<Puri::Protocol::Pin>]
      CAFES = [['1', 'Teehetki Teahouseshop (cafe), Neilikkatie 17a', 60.2908706, 25.0331958, 14_062_506_557],
               ['2', 'Cafe Silkki (cafe), Tikkurilantie 44', 60.2891746, 25.0370343, 10_253_894_367],
               ['3', 'Tiksin Sea Cafe (cafe), Läntinen Valkoisenlähteentie 50', 60.2989261, 25.0303820, 1_412_396_183]]
              .map do |label, name, lat, lon, node|
                Protocol::Pin.new(label:, name:, lat:, lon:, url: "https://www.openstreetmap.org/node/#{node}")
              end.freeze

      # @return [Array<Array<Float>>] OSRM's road from Jumbo to the shop
      ROAD = [[60.29159, 24.96685], [60.29223, 24.96675], [60.29267, 24.96523], [60.29283, 24.96186],
              [60.29211, 24.96182], [60.29206, 24.96082], [60.29316, 24.96011], [60.29336, 24.96317],
              [60.29306, 24.96542], [60.29241, 24.96779], [60.28901, 24.97614], [60.28759, 24.9819],
              [60.28714, 24.98513], [60.28696, 24.9883], [60.28735, 24.99936], [60.28714, 25.00312],
              [60.2866, 25.00794], [60.2858, 25.01265], [60.28366, 25.02096], [60.2824, 25.0291],
              [60.28188, 25.02951], [60.28156, 25.02858], [60.28255, 25.02858], [60.2838, 25.02969],
              [60.2867, 25.03134], [60.2871, 25.03078], [60.28979, 25.0306], [60.29286, 25.0323],
              [60.29291, 25.03073]].freeze

      module_function

      # @param turn [Puri::Dummy::Turn]
      # @param text [String] the user's message
      # @return [void]
      def run(turn, text)
        said = ->(*words) { words.all? { text.match?(/\b#{_1}/i) } }
        if said.call('calendar', 'reschedul') then reschedule(turn, 'Thursday')
        elsif said.call('mail') then mail(turn)
        elsif said.call('search') then search(turn, text)
        elsif said.call('note') then note(turn)
        elsif said.call('table') then table(turn)
        elsif said.call('long') then long(turn)
        elsif said.call('coffee') then coffee(turn)
        elsif said.call('drive') then drive(turn)
        elsif said.call('weather') then weather(turn)
        elsif said.call('fail') then failure(turn)
        else plain(turn)
        end
      end

      # The title Core gives a conversation from its opening question.
      #
      #   Script.title('how do I keep an avocado from browning?')   # => "How do I keep an avocado"
      #
      # @param text [String]
      # @return [String]
      def title(text)
        words = text.gsub(/[^\p{Word}\s'-]/, ' ').split.first(6)
        return 'New conversation' if words.empty?

        words.join(' ').sub(/\A\p{Ll}/, &:upcase)
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def plain(turn)
        turn.think('Thinking…')
        turn.stream(<<~MD)
          Here's a **short answer**, streamed word by word the way the model would send it.

          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor
          incididunt ut labore et *dolore magna aliqua*. Try a question with `search`, `note`,
          `table`, `long`, `coffee`, `drive`, `weather`, `fail`, `mail`, or `reschedule` plus `calendar`
          in it.
        MD
      end

      # @param turn [Puri::Dummy::Turn]
      # @param text [String]
      # @return [void]
      def search(turn, text)
        query = text.sub(/\bsearch\b( for)?/i, '').strip
        query = 'avocado preservation' if query.empty?
        turn.think('Thinking…')
        turn.think('Searching the web…')
        turn.tool(%(🔍 Searched: "#{query}"))
        turn.think('Reading the results…')
        turn.stream(<<~MD)
          ## What the search turned up

          Three sources agree on the basics:

          - **Cold slows it down.** The fridge buys you two to three days.
          - **Air is the enemy.** Press plastic wrap right onto the cut surface.
          - **Acid helps.** A little lemon or lime juice keeps the colour.

          None of them recommends the "leave the pit in" trick; it only protects the bit it covers.
        MD
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def note(turn)
        turn.think('Searching your documents…')
        turn.tool('🗂 Searched documents: shopping list')
        turn.think('Reading a document…')
        turn.tool('📄 Read: Notes/shopping.md')
        turn.stream(<<~MD)
          Your **Shopping** note has four things on it:

          1. Avocados (*ripe ones*)
          2. Limes
          3. Coffee beans
          4. Batteries, AA

          Want me to add anything?
        MD
      end

      # @param turn [Puri::Dummy::Turn]
      # @param day [String] when to move the appointment
      # @return [void]
      def reschedule(turn, day)
        turn.think('Reading your calendar…')
        turn.tool('📅 Read calendar: Personal, this week')
        turn.stream("Your **Dentist** appointment is on Tuesday at 10:00. I'll move it to #{day} at 10:00.")
        answer = turn.confirm(
          "Move “Dentist” in your Personal calendar from Tuesday 10:00 to #{day} 10:00?",
          'Update', destructive: true
        )
        case answer
        in :approved
          turn.think('Updating your calendar…')
          turn.tool("📅 Moved: Dentist → #{day} 10:00")
          turn.stream("Done. **Dentist** is now on #{day} at 10:00.")
        in :rejected
          turn.stream("OK. I won't make any changes to your appointment.")
        in [:redirected, said]
          reschedule(turn, WEEKDAYS.find { said.match?(/\b#{_1}\b/i) } || day)
        end
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def mail(turn)
        turn.think('Writing the draft…')
        turn.stream(<<~MD)
          Here's a draft to **Jana**:

          > Hi Jana, could we move Thursday's call to Friday morning? Thanks!
        MD
        case turn.confirm('Open this draft to Jana in your mail app? Nothing is sent until you send it.',
                          'Open draft', destructive: false)
        in :approved
          turn.tool('✉️ Opened draft: To Jana, "Thursday call"')
          turn.stream('The draft is open in your mail app.')
        in :rejected
          turn.stream("OK, I've left it here.")
        in [:redirected, _]
          mail(turn)
        end
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def table(turn)
        turn.think('Thinking…')
        turn.stream(<<~MD)
          How long a cut avocado keeps:

          | Where | Covered | Days |
          |---|---|---|
          | Counter | no | under 1 |
          | Fridge | plastic wrap | 1–2 |
          | Fridge | lemon juice + wrap | 2–3 |
          | Freezer | mashed, airtight | 90+ |

          And the same as code, if you want to sort it yourself:

          ```ruby
          keeps = { counter: 0.5, fridge: 2, freezer: 90 }
          keeps.max_by { |_, days| days }   # => [:freezer, 90]
          ```
        MD
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def long(turn)
        turn.think('Thinking…')
        paragraphs = (1..12).map do |i|
          "**Part #{i}.** Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod " \
            'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud ' \
            'exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.'
        end
        turn.stream(paragraphs.join("\n\n"))
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def coffee(turn)
        turn.think('Thinking…')
        turn.think('Looking up places…')
        turn.tool('📍 Looked up: cafe near Peltolantie 2, Vantaa')
        turn.stream(<<~MD)
          Three cafés near **Peltolantie 2**:

          - **[1] Teehetki Teahouseshop**, Neilikkatie 17a — 430 m.
          - **[2] Cafe Silkki**, Tikkurilantie 44 — 880 m.
          - **[3] Tiksin Sea Cafe**, Läntinen Valkoisenlähteentie 50 — 1.1 km.
        MD
        turn.map([SHOP, *CAFES])
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def drive(turn)
        turn.think('Thinking…')
        turn.think('Finding a route…')
        turn.tool('🚗 Route: Jumbo Vantaa → Peltolantie 2, Vantaa')
        turn.stream('From **Jumbo** to **Vantaan Musiikki** is **6.3 km** by car, about **9 minutes** without traffic.')
        jumbo = Protocol::Pin.new(label: '1', name: 'Jumbo (mall), Vantaanportinkatu 3', lat: 60.2915942,
                                  lon: 24.9656777, url: 'https://www.openstreetmap.org/way/25373590')
        turn.map([jumbo, SHOP.with(label: '2')], line: ROAD, note: Core::Places::RouteTool::NOTE)
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      def weather(turn)
        turn.think('Thinking…')
        turn.think('Checking the weather…')
        credit = Core::Weather::CREDIT
        turn.tool("🌦 Weather from #{credit}: Vantaa",
                  markup: %(🌦 Weather from <a href="#{Core::Weather::CREDIT_URL}">#{credit}</a>: Vantaa))
        turn.stream(<<~MD)
          In **Vantaa** it's **0 °C** and partly cloudy, feeling like −5 °C in the wind.

          - **Tomorrow:** light drizzle, 1 to 2 °C.
          - **Then:** overcast and colder, down to −6 °C by Saturday.
        MD
      end

      # @param turn [Puri::Dummy::Turn]
      # @return [void]
      # @raise [RuntimeError] always, halfway
      def failure(turn)
        turn.think('Thinking…')
        turn.stream('Let me look into that. The first thing to')
        raise 'The model stopped answering: llama-server closed the connection.'
      end
    end
  end
end
