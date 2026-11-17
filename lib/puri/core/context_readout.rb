# frozen_string_literal: true

module Puri
  module Core
    # A conversation's context use, worded for its {Protocol::Status}. Fed the agent's and the
    # gem's events; the counting is pikuri's `TokenLog`, as in pikuri-tui and pikuri-web:
    #
    #   readout = ContextReadout.new
    #   readout.on_event(event)          # Tokens, HistoryLoaded, ContextCap; Booting zeroes it
    #   readout.status('Ornith 1.5')
    #   # => Status(model: "Ornith 1.5", context: "7.4k of 64.0k tokens", fill: 0.116,
    #   #           detail: "msg #2  Δ+1.6k  ↑1.0k  ↓0.6k")
    #
    # The detail is `TokenLog`'s line without its `ctx=`: Δ the context's growth since the
    # last reply, ↑ the prompt tokens this reply processed afresh, ↓ the tokens it wrote.
    #
    # Thread-safe.
    class ContextReadout
      # @param cap [Integer, nil] the context window, until a `ContextCap` says otherwise
      def initialize(cap: nil)
        @lock = Mutex.new
        @log = Pikuri::Agent::Listener::TokenLog.new
        @cap = cap
      end

      # @param event [Object] any agent or conversation event; the rest are ignored
      # @return [Boolean] whether the readout changed
      def on_event(event)
        @lock.synchronize do
          case event
          when Pikuri::Agent::Event::Tokens, Pikuri::Agent::Event::HistoryLoaded,
               Pikuri::Agent::Event::HistoryCompacted
            @log.on_event(event)
          # A new agent is a fresh count: a cleared conversation starts from zero.
          when Pikuri::Conversations::Event::Booting then @log = Pikuri::Agent::Listener::TokenLog.new
          when Pikuri::Conversations::Event::ContextCap then @cap = event.cap
          else next false
          end
          true
        end
      end

      # @param cap [Integer, nil] the window of a model picked before the agent boots
      # @return [void]
      def cap=(cap)
        @lock.synchronize { @cap = cap }
      end

      # @param model [String] the connection's name
      # @return [Puri::Protocol::Status]
      def status(model)
        @lock.synchronize do
          measured = !@log.status_line.empty?
          used = @log.context_window_size
          Protocol::Status.new(model:, context: context(measured, used),
                               fill: (used.fdiv(@cap).clamp(0.0, 1.0) if measured && @cap.to_i.positive?),
                               detail: @log.status_line.sub(/:?\s*ctx=\S+/, ''))
        end
      end

      private

      # @param measured [Boolean]
      # @param used [Integer] tokens
      # @return [String]
      def context(measured, used)
        if measured && @cap then "#{k(used)} of #{k(@cap)} tokens"
        elsif measured then "#{k(used)} tokens"
        elsif @cap then "#{k(@cap)} token window"
        else ''
        end
      end

      # As `TokenLog` writes a count: 1024-scaled.
      #
      # @param tokens [Integer]
      # @return [String] `12_453` → `"12.2k"`
      def k(tokens) = format('%.1fk', tokens / 1024.0)
    end
  end
end
