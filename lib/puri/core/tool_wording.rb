# frozen_string_literal: true

module Puri
  module Core
    # How a tool call reads in the transcript: the status under the progress bar while it runs,
    # and the {Protocol::ToolLine} that stays once it has answered.
    #
    #   ToolWording.status(call)                          # => "Searching the web…"
    #   ToolWording.line(call, content:, summary:)        # => ToolLine(text: '🔍 Searched: "avocado"')
    #
    # `call` is the live `Pikuri::Agent::Event::ToolCall` or the saved
    # `Pikuri::Agent::History::ToolCall`, so {TurnListener} and {Replay} word a line alike. Only the
    # icon and the verb are ours: what follows them is the tool's own `argument` or `summary`
    # (pikuri's display-line seam, `Pikuri::Tool`'s *Display lines*), never the model's text.
    #
    # A failed call is the tool's `Error:` observation, and its line is red with the tool's
    # summary, which for a failure is that message. A call a cancel cut short says so, not red.
    # A call the user declined isn't an `Error:`, so it reads as done: no tool here asks yet, and
    # the first that does needs pikuri to say the outcome, not a match on the observation's words.
    # The tool's strings are the model's arguments, so a line is flattened and defanged as
    # pikuri asks of every chrome: `Pikuri::Sanitizer` shows an escape byte, it never runs it.
    module ToolWording
      module_function

      # One tool's wording.
      #
      # @!attribute [r] status
      #   @return [String] what the turn is doing while the call runs
      # @!attribute [r] line
      #   @return [String] the line once it answered, the call's argument after a colon when
      #     there is one
      class Wording < Data.define(:status, :line); end

      # Every tool Puri wires but the web's, by name; a tool missing here reads as pikuri names it.
      # The ids `*_read` takes say nothing to a human, so those lines drop the argument.
      #
      # @return [Hash{String => Wording}]
      WORDINGS = {
        'thunderbird_mail_search' => Wording.new('Searching your mail…', '📧 Searched mail'),
        'thunderbird_mail_read' => Wording.new('Reading a mail…', '📧 Read a mail'),
        'thunderbird_mail_attachment_read' => Wording.new('Reading an attachment…', '📎 Read an attachment'),
        'thunderbird_contact_search' => Wording.new('Looking up a contact…', '👤 Looked up'),
        'thunderbird_calendar_search' => Wording.new('Searching your calendar…', '📅 Searched the calendar'),
        'thunderbird_calendar_read' => Wording.new('Reading an event…', '📅 Read an event'),
        'thunderbird_mail_compose' => Wording.new('Drafting a mail…', '✉ Draft opened in Thunderbird'),
        'thunderbird_calendar_create' => Wording.new('Drafting an event…', '📅 Event opened in Thunderbird'),
        'fileindex_search' => Wording.new('Searching your files…', '🗂 Searched files'),
        'fileindex_read' => Wording.new('Reading a document…', '📄 Read'),
        'read' => Wording.new('Reading a file…', '📄 Read'),
        'glob' => Wording.new('Looking for files…', '🗂 Looked for files'),
        'file_list' => Wording.new('Listing a folder…', '🗂 Listed'),
        'write' => Wording.new('Writing a note…', '📝 Wrote'),
        'edit' => Wording.new('Editing a note…', '📝 Edited'),
        'calculator' => Wording.new('Calculating…', '🧮 Calculated'),
        'place_search' => Wording.new('Looking up places…', '📍 Looked up'),
        'route' => Wording.new('Finding a route…', '🚗 Route')
      }.freeze

      # Whose argument a line leaves out.
      #
      # @return [Array<String>]
      BARE = %w[thunderbird_mail_read thunderbird_mail_attachment_read thunderbird_calendar_read].freeze

      # Whose line ends in the tool's summary even when it answered: a note written unasked is
      # what the user checks, so its line says what changed.
      #
      # @return [Array<String>]
      SUMMED = %w[write edit].freeze

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @return [String] what the turn is doing while the call runs
      def status(call)
        case call.name
        when 'web_search' then 'Searching the web…'
        when 'web_read_cached' then 'Reading a page…'
        else WORDINGS[call.name]&.status || "#{call.display_name}…"
        end
      end

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @param content [String] the observation the model got
      # @param summary [String, nil] the tool's one-line summary of it
      # @return [Puri::Protocol::ToolLine] with no id, for {Conversation#add} or
      #   {Conversation#restore} to assign
      def line(call, content:, summary:)
        error = content.start_with?('Error:')
        outcome = summary.to_s if error || summary == Pikuri::Agent::INTERRUPTED_SUMMARY ||
                                  (SUMMED.include?(call.name) && !summary.to_s.empty?)
        text = Pikuri::Sanitizer.sanitize(Pikuri::Tool.one_line(text(call, outcome))).text
        Protocol::ToolLine.new(id: nil, text:, error:)
      end

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @param outcome [String, nil] the tool's summary of a call that failed or was cut short, or
      #   of a {SUMMED} one; nil for any other that answered
      # @return [String]
      def text(call, outcome)
        line = case call.name
               when 'web_search' then %(🔍 Searched: "#{call.argument}")
               # The handle is all the call says, and the summary only a size: which page it was
               # waits on the tool's summary naming it.
               when 'web_read_cached' then '📄 Read a page the search found'
               else worded(call)
               end
        outcome ? "#{line} — #{outcome}" : line
      end
      private_class_method :text

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @return [String] its {WORDINGS} line, or pikuri's name behind a gear
      def worded(call)
        head = WORDINGS[call.name]&.line || "⚙ #{call.display_name}"
        argument = call.argument.to_s unless BARE.include?(call.name)
        argument.to_s.empty? ? head : "#{head}: #{argument}"
      end
      private_class_method :worded
    end
  end
end
