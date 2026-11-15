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
    # The tool's strings are the model's arguments, so a line is flattened and defanged as
    # pikuri asks of every chrome: `Pikuri::Sanitizer` shows an escape byte, it never runs it.
    module ToolWording
      module_function

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @return [String] what the turn is doing while the call runs
      def status(call)
        case call.name
        when 'web_search' then 'Searching the web…'
        when 'web_read_cached' then 'Reading a page…'
        else "#{call.display_name}…"
        end
      end

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @param content [String] the observation the model got
      # @param summary [String, nil] the tool's one-line summary of it
      # @return [Puri::Protocol::ToolLine] with no id, for {Conversation#add} or
      #   {Conversation#restore} to assign
      def line(call, content:, summary:)
        error = content.start_with?('Error:')
        outcome = summary.to_s if error || summary == Pikuri::Agent::INTERRUPTED_SUMMARY
        text = Pikuri::Sanitizer.sanitize(Pikuri::Tool.one_line(text(call, outcome))).text
        Protocol::ToolLine.new(id: nil, text:, error:)
      end

      # @param call [Pikuri::Agent::Event::ToolCall, Pikuri::Agent::History::ToolCall]
      # @param outcome [String, nil] the tool's summary of a call that failed or was cut short;
      #   nil when it answered
      # @return [String]
      def text(call, outcome)
        line = case call.name
               when 'web_search' then %(🔍 Searched: "#{call.argument}")
               # The handle is all the call says, and the summary only a size: which page it was
               # waits on the tool's summary naming it.
               when 'web_read_cached' then '📄 Read a page the search found'
               else call.argument.to_s.empty? ? "⚙ #{call.display_name}" : "⚙ #{call.display_name}: #{call.argument}"
               end
        outcome ? "#{line} — #{outcome}" : line
      end
      private_class_method :text
    end
  end
end
