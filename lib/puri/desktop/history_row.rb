# frozen_string_literal: true

require 'date'
require 'time'

module Puri
  module Desktop
    # One {Protocol::ConversationSummary} in the history: the title, when it started, and a `●`
    # while its turn runs.
    class HistoryRow < Gtk::ListBoxRow
      # @return [Puri::Protocol::ConversationSummary]
      attr_reader :summary

      # @param summary [Puri::Protocol::ConversationSummary]
      def initialize(summary)
        super()
        @title = Gtk::Label.new
        @title.xalign = 0
        @title.ellipsize = :end
        @title.hexpand = true
        @when = Gtk::Label.new
        @when.xalign = 0
        @when.add_css_class('dim-label')
        @when.add_css_class('caption')
        @running = Gtk::Label.new('●')
        @running.add_css_class('puri-running')
        @running.tooltip_text = 'Still working'
        top = Gtk::Box.new(:horizontal, 6)
        top.append(@title)
        top.append(@running)
        box = Gtk::Box.new(:vertical, 2)
        box.add_css_class('puri-history-row')
        box.append(top)
        box.append(@when)
        self.child = box
        self.summary = summary
      end

      # @param summary [Puri::Protocol::ConversationSummary]
      # @return [void]
      def summary=(summary)
        @summary = summary
        @title.text = summary.title
        @when.text = HistoryRow.timestamp(Time.iso8601(summary.started_at))
        @running.visible = summary.running
      end

      # @param query [String] lowercase; empty matches everything
      # @return [Boolean]
      def matches?(query) = query.empty? || @summary.title.downcase.include?(query)

      # @param time [Time]
      # @param now [Time]
      # @return [String] "14:05" today, "Yesterday", "Mon" this week, "Nov 2" this year, else "Nov 2, 2025"
      def self.timestamp(time, now = Time.now)
        days = (now.to_date - time.to_date).to_i
        if days.zero? then time.strftime('%H:%M')
        elsif days == 1 then 'Yesterday'
        elsif days < 7 then time.strftime('%A')
        elsif time.year == now.year then time.strftime('%b %-d')
        else time.strftime('%b %-d, %Y')
        end
      end
    end
  end
end
