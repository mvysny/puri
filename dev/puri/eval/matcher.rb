# frozen_string_literal: true

require 'date'

module Puri
  module Eval
    # Whether a text holds an expected fact, in any of the forms a model writes it. An item is a
    # plain string (case and spacing ignored), a tagged one from {Task::Context}, or an Array of
    # alternatives, any of which will do:
    #
    #   Matcher.match?('Due on 28 Nov: EUR 1 284,50', '@num:1284.5')        # => true
    #   Matcher.match?('Due on 28 Nov: EUR 1 284,50', '@date:2026-11-28')   # => true
    #   Matcher.match?('at 5 pm', '@time:17:00')                            # => true
    #   Matcher.match?('FI2112345600000785', '@iban:FI21 1234 5600 0007 85') # => true
    #   Matcher.match?('one month', ['1 month', 'one month'])                # => true
    module Matcher
      module_function

      # @param text [String]
      # @param item [String, Array<String>]
      # @return [Boolean]
      def match?(text, item)
        return item.any? { match?(text, _1) } if item.is_a?(Array)

        tag, value = item.to_s.split(':', 2) if item.to_s.start_with?('@')
        case tag
        when '@num' then numbers(text).any? { (_1 - Float(value)).abs < 0.005 }
        when '@date' then date_pattern(Date.iso8601(value)).match?(text)
        when '@time' then time_pattern(value).match?(text)
        when '@iban' then squeeze(text).include?(squeeze(value))
        when '@digits' then text.gsub(/\D/, '').include?(value.gsub(/\D/, ''))
        else plain(text).include?(plain(item))
        end
      end

      # Every number in the text, its thousands grouping and decimal comma read: "1 284,50",
      # "1,284.50" and "1284.5" are all 1284.5; "4.000" and "4,000" are 4000, "1,2" is 1.2.
      #
      # @param text [String]
      # @return [Array<Float>]
      def numbers(text)
        text.scan(/\d(?:[\d   .,']*\d)?/).flat_map do |token|
          [*read_number(token.delete("   '")), *token.split(/[   ]/).flat_map { read_number(_1) }]
        end.uniq
      end

      # @param token [String] digits, with "." and "," in them
      # @return [Array<Float>] its readings: both, for one separator before exactly three digits
      #   ("4,000" or "192.675"), which a thousands separator and a decimal one write alike
      def read_number(token)
        last = token.rindex(/[.,]/)
        return [Float(token)] unless last

        int = token[0...last].delete('.,')
        frac = token[(last + 1)..]
        decimal = Float("#{int}.#{frac}")
        return [decimal] unless frac.size == 3

        thousands = Float("#{int}#{frac}")
        token.count(token[last]) > 1 ? [thousands] : [thousands, decimal]
      rescue ArgumentError
        []
      end

      # @param date [Date]
      # @return [Regexp] "28 November", "Nov 28th", "28.11.", "2026-11-28", "28/11" and the like
      def date_pattern(date)
        day = date.day
        month = Date::MONTHNAMES[date.month]
        name = "(?:#{month}|#{month[0, 3]}\\.?)"
        ordinal = "#{day}(?:st|nd|rd|th)?"
        Regexp.new([
          "(?<!\\d)#{ordinal}\\.?(?:\\s+of)?\\s+#{name}",
          "#{name}\\s+#{ordinal}(?!\\d)",
          date.iso8601,
          "(?<!\\d)0?#{day}\\.\\s?0?#{date.month}\\.",
          "(?<![\\d/])0?#{day}/0?#{date.month}(?![\\d])",
          "(?<![\\d/])0?#{date.month}/0?#{day}(?![\\d])"
        ].join('|'), Regexp::IGNORECASE)
      end

      # @param hhmm [String] "17:00"
      # @return [Regexp] "17:00", "17.00", "5 pm", "5:00 PM", "at 17", "17h"
      def time_pattern(hhmm)
        hour, minute = hhmm.split(':').map(&:to_i)
        twelve = ((hour - 1) % 12) + 1
        suffix = hour < 12 ? 'a\.?m\.?(?!\w)' : 'p\.?m\.?(?!\w)'
        mm = format('%02d', minute)
        forms = ["(?<!\\d)0?#{hour}[:.]#{mm}(?!\\d)", "(?<!\\d)#{twelve}(?:[:.]#{mm})?\\s?#{suffix}"]
        forms += ["\\bat #{hour}(?![\\d:.])", "(?<!\\d)#{hour}h(?!\\w)", "\\b#{twelve} o'clock"] if minute.zero?
        Regexp.new(forms.join('|'), Regexp::IGNORECASE)
      end

      # Every duration the text states, in minutes: "1 h 55 min", "1 hour and 55 minutes",
      # "about 2 hours", "115 minutes", "1:55 h".
      #
      # @param text [String]
      # @return [Array<Float>]
      def durations(text)
        hours = /(\d+(?:[.,]\d+)?)\s*(?:h|hrs?|hours?)\b(?:\s*(?:and\s*)?(\d+)\s*(?:m|min|mins|minutes?)\b)?/i
        found = text.scan(hours)
                    .map { |h, m| (Float(h.tr(',', '.')) * 60) + m.to_i }
        found += text.scan(/(?<![\d:.])(\d+)\s*(?:min|mins|minutes)\b/i).map { Float(_1[0]) }
        found + text.scan(/(?<!\d)(\d{1,2}):(\d{2})\s*h\b/i).map { |h, m| (h.to_i * 60) + m.to_i }
      end

      # @param text [String]
      # @return [String] downcased, spacing and dashes normalized
      def plain(text) = text.to_s.downcase.tr('  –—’', "  --'").squeeze(' ')

      # @param text [String]
      # @return [String] uppercased, with no spacing at all
      def squeeze(text) = text.to_s.upcase.gsub(/[\s  ]/, '')
    end
  end
end
