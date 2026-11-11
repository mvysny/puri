# frozen_string_literal: true

module Puri
  module Core
    # What {DummyCore} answers, picked by words in the question, so every path through the UI
    # can be walked by hand:
    #
    #   (anything else)            thinks, streams a short Markdown answer
    #   search                     a search step, then an answer with a list
    #   note                       reads a note, answers with a checklist
    #   calendar + reschedule      asks to move an event: Update / Cancel / type a correction
    #   mail                       asks to hand a draft to the mail app (a harmless confirmation)
    #   table                      an answer with a table and a code block
    #   long                       a long answer, for scrolling and Escape while it streams
    #   fail                       streams a little, then the turn fails
    module DummyScript
      # @return [Array<String>]
      WEEKDAYS = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

      module_function

      # @param turn [Puri::Core::DummyTurn]
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
        elsif said.call('fail') then failure(turn)
        else plain(turn)
        end
      end

      # The title Core gives a conversation from its opening question.
      #
      #   DummyScript.title('how do I keep an avocado from browning?')   # => "How do I keep an avocado"
      #
      # @param text [String]
      # @return [String]
      def title(text)
        words = text.gsub(/[^\p{Word}\s'-]/, ' ').split.first(6)
        return 'New conversation' if words.empty?

        words.join(' ').sub(/\A\p{Ll}/, &:upcase)
      end

      # @param turn [Puri::Core::DummyTurn]
      # @return [void]
      def plain(turn)
        turn.think('Thinking…')
        turn.stream(<<~MD)
          Here's a **short answer**, streamed word by word the way the model would send it.

          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor
          incididunt ut labore et *dolore magna aliqua*. Try a question with `search`, `note`,
          `table`, `long`, `fail`, `mail`, or `reschedule` plus `calendar` in it.
        MD
      end

      # @param turn [Puri::Core::DummyTurn]
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

      # @param turn [Puri::Core::DummyTurn]
      # @return [void]
      def note(turn)
        turn.think('Reading your notes…')
        turn.tool('📝 Read note: Shopping')
        turn.stream(<<~MD)
          Your **Shopping** note has four things on it:

          1. Avocados (*ripe ones*)
          2. Limes
          3. Coffee beans
          4. Batteries, AA

          Want me to add anything?
        MD
      end

      # @param turn [Puri::Core::DummyTurn]
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

      # @param turn [Puri::Core::DummyTurn]
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

      # @param turn [Puri::Core::DummyTurn]
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

      # @param turn [Puri::Core::DummyTurn]
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

      # @param turn [Puri::Core::DummyTurn]
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
