# frozen_string_literal: true

require 'date'

module Puri
  module Core
    module Weather
      # `weather`: the weather at a place, now and over the days asked, from Open-Meteo.
      #
      #   tool = ForecastTool.new(open_meteo:, osm:, notebook:, units: Units.gnome, today: Date.today)
      #   tool.run('place' => 'Jumbo Vantaa').content
      #   # => Weather for [1] Jumbo (mall), Vantaanportinkatu 3, 01510 Vantaa, in its local time (Europe/Helsinki).
      #   #
      #   #    Now, 16:45: partly cloudy, 0 °C, feels like -5 °C, wind 17 km/h.
      #   #    Sun 22 Nov: light drizzle, 0 to 1 °C, precipitation 0.7 mm, 61 % chance, wind up to 18 km/h.
      #   #    Mon 23 Nov: …
      #
      # No dates: today and the {DAYS} after it, a line a day, so "tomorrow" and "this weekend" are
      # lines to read, not dates to work out. `from` alone: that one day every {STEP} hours, with
      # its sunrise and sunset. Both: the range, a trip's say. `to` alone: today until then, or
      # that one day when it's past. Days are the place's own, and a range past the forecast's
      # last day is cut there, and says so.
      #
      # The place resolves as `route`'s ends do, so it gets a number, and the result names what it
      # matched (`D_places`).
      #
      # Sharing: P_one_agent, through its {Places::Notebook}, which is one conversation's.
      class ForecastTool < Pikuri::Tool
        # @return [Integer] days after today that no dates show
        DAYS = 6

        # @return [Integer] hours between the lines of one day
        STEP = 3

        # @return [String] with the forecast's last date to fill in
        DESCRIPTION = <<~DESC
          The weather at a place, from Open-Meteo: now, then a line a day, or one day every three hours.

          Usage:
          - `place` is a number from place_search's results ("3"), an address or a town ("Lisbon"), or coordinates ("60.2931, 25.0307"). For "here" or "at home", pass the user's home address.
          - Leave out `from` and `to` for today and the next 6 days. Each line names its weekday, so for "tomorrow" or "this weekend" read its line rather than passing dates.
          - Pass `from` alone for one day every three hours, as for "will it rain this afternoon?". Pass `from` and `to` for a range, such as a trip's dates from the calendar. Dates are YYYY-MM-DD.
          - The forecast reaches %<last>s; later days can't be forecast yet. Past days work too, up to 92 days back.
          - The result names the place it found, like "[3] Lisboa (city), Portugal": when that isn't the place the user meant, say so. Pass the number to route or place_search.
        DESC

        # A date the model wrote that isn't one; the message is for the model.
        class BadDate < StandardError; end

        # @param open_meteo [Puri::Core::Weather::OpenMeteo]
        # @param osm [Puri::Core::Places::Osm] what finds the place
        # @param notebook [Puri::Core::Places::Notebook] the conversation's, which numbers the place
        # @param units [Puri::Core::Weather::Units]
        # @param today [Date] the machine's, for the description's last date
        def initialize(open_meteo:, osm:, notebook:, units:, today:)
          @open_meteo = open_meteo
          @osm = osm
          @notebook = notebook
          @units = units
          super(
            name: 'weather', description: format(DESCRIPTION, last: (today + OpenMeteo::AHEAD).iso8601),
            parameters: Pikuri::Tool::Parameters.build do |p|
              p.required_string :place, 'Where: a number from place_search ("3"), an address or a town, or ' \
                                        'coordinates "60.2931, 25.0307".'
              p.optional_string :from, 'The first day, YYYY-MM-DD. Leave out for today.'
              p.optional_string :to, 'The last day, YYYY-MM-DD. Leave out for the one day `from` names.'
            end,
            execute: ->(place:, context:, from: nil, to: nil) { weather(place, from, to, context.cancellable) },
            # The place leaves the machine unreviewed, to hosts the tool fixes; its name comes back
            # as whatever anyone mapped.
            trifecta_legs: Pikuri::Tool::TrifectaLegs.new(private: false, untrusted: :hard,
                                                          egress_payload_review: :unreviewed,
                                                          egress_destination: :tool_vouched),
            wants_context: true
          )
        end

        # @param arguments [Hash] the model's
        # @return [String] "Lisbon, 3–6 Dec"
        def describe_call(arguments)
          args = arguments.transform_keys(&:to_s)
          span = span(args['from'], args['to'])
          Pikuri::Tool.one_line([args['place'], span].compact.join(', '))
        end

        private

        # @param text [String] the model's place
        # @param from_text [String, nil]
        # @param to_text [String, nil]
        # @param cancellable [Pikuri::Agent::Control::Cancellable]
        # @return [Pikuri::Tool::Result]
        def weather(text, from_text, to_text, cancellable)
          from = date(from_text, 'from')
          to = date(to_text, 'to')
          return Pikuri::Tool::Result.error('to is before from') if from && to && to < from

          number, place = Places::Ends.resolve(text, osm: @osm, notebook: @notebook, cancellable:)
          forecast = @open_meteo.forecast(lat: place.lat, lon: place.lon, units: @units,
                                          past_days: past_days(from || to), cancellable:)
          answer("Weather for [#{number}] #{place.label}, in its local time (#{forecast.timezone}).", forecast,
                 from, to)
        rescue BadDate => e
          Pikuri::Tool::Result.error(e.message)
        rescue Places::Ends::Unresolved => e
          Pikuri::Tool::Result.error("place: #{e.message}")
        rescue Http::Error => e
          Pikuri::Tool::Result.error(e.message)
        end

        # @param text [String, nil]
        # @param name [String] the parameter's
        # @return [Date, nil]
        # @raise [BadDate]
        def date(text, name)
          text = text.to_s.strip
          Date.iso8601(text) unless text.empty?
        rescue Date::Error
          raise BadDate, "#{name}: #{text.inspect} is no date; write it as YYYY-MM-DD"
        end

        # @param earliest [Date, nil] the earliest day asked
        # @return [Integer] days back to ask for, a day to spare where the place's today is ahead
        #   of the machine's
        def past_days(earliest)
          earliest ? ((Date.today - earliest).to_i + 1).clamp(0, OpenMeteo::PAST_DAYS) : 0
        end

        # @param head [String]
        # @param forecast [Puri::Core::Weather::Forecast]
        # @param from [Date, nil]
        # @param to [Date, nil]
        # @return [Pikuri::Tool::Result]
        def answer(head, forecast, from, to)
          first = from || [forecast.today, to].compact.min
          last = to || from || (forecast.today + DAYS)
          known = forecast.days.first.date..forecast.days.last.date
          if first > known.end
            return Pikuri::Tool::Result.error("#{day_name(first)} is past the forecast, which reaches " \
                                              "#{day_name(known.end)}: ask again nearer the time")
          end
          if last < known.begin
            return Pikuri::Tool::Result.error("#{day_name(last)} is too long ago: past days reach back to " \
                                              "#{day_name(known.begin)}")
          end

          notes = []
          notes << "The forecast reaches only #{day_name(known.end)}; later days can't be forecast yet." if
            last > known.end
          notes << "Past days reach back only to #{day_name(known.begin)}." if first < known.begin
          range = [first, known.begin].max..[last, known.end].min
          lines = forecast.today.between?(range.begin, range.end) ? [now_line(forecast.now)] : []
          days = forecast.days.select { range.cover?(_1.date) }
          lines += if days.size == 1 && range.begin == range.end
                     one_day(forecast, days.first)
                   else
                     days.map do
                       day_line(_1)
                     end
                   end
          content = [head, lines.join("\n"), *(notes.join(' ') unless notes.empty?)].join("\n\n")
          Pikuri::Tool::Result.new(content:, summary: summary(days))
        end

        # @param forecast [Puri::Core::Weather::Forecast]
        # @param day [Puri::Core::Weather::Forecast::Day]
        # @return [Array<String>] the day's line, its hours every {STEP} from now on, its sun
        def one_day(forecast, day)
          hours = forecast.hours_of(day.date).select { (_1.clock[0, 2].to_i % STEP).zero? }
          hours = hours.select { _1.time >= forecast.now.time[0, 13] } if day.date == forecast.today
          sun = [("sunrise #{day.sunrise}" if day.sunrise), ("sunset #{day.sunset}" if day.sunset)].compact
          [day_line(day), *hours.map { hour_line(_1) }, *("#{sun.join(', ').sub(/\A./, &:upcase)}." unless sun.empty?)]
        end

        # @param now [Puri::Core::Weather::Forecast::Now]
        # @return [String] "Now, 16:45: partly cloudy, 0 °C, feels like -5 °C, wind 17 km/h."
        def now_line(now)
          feels = "feels like #{degrees(now.feels_like)}" if now.feels_like
          "Now, #{now.clock}: #{parts(now.condition, degrees(now.temperature), feels, wind('wind', now.wind))}."
        end

        # @param day [Puri::Core::Weather::Forecast::Day]
        # @return [String] "Sun 22 Nov: light drizzle, 0 to 1 °C, precipitation 0.7 mm, 61 % chance, …"
        def day_line(day)
          "#{day_name(day.date)}: " \
            "#{parts(day.condition, spread(day), *precipitation(day.precipitation, day.chance),
                     wind('wind up to', day.wind))}."
        end

        # @param hour [Puri::Core::Weather::Forecast::Hour]
        # @return [String] "15:00: overcast, 5 °C, precipitation 0.2 mm, 40 % chance, wind 12 km/h."
        def hour_line(hour)
          "#{hour.clock}: #{parts(hour.condition, degrees(hour.temperature),
                                  *precipitation(hour.precipitation, hour.chance), wind('wind', hour.wind))}."
        end

        # @param days [Array<Puri::Core::Weather::Forecast::Day>]
        # @return [String] "Light drizzle, 0 to 1 °C" for one day, "7 days, -11 to 2 °C" for more
        def summary(days)
          return 'No forecast' if days.empty?
          return parts(days.first.condition, spread(days.first)).sub(/\A./, &:upcase) if days.size == 1

          lows = days.filter_map(&:low)
          highs = days.filter_map(&:high)
          range = "#{lows.min.round} to #{degrees(highs.max)}" unless lows.empty? || highs.empty?
          parts(Pikuri::Tool.pluralize(days.size, 'day'), range)
        end

        # @param words [Array<String, nil>]
        # @return [String] the given ones, comma-separated
        def parts(*words) = words.compact.join(', ')

        # @param day [Puri::Core::Weather::Forecast::Day]
        # @return [String, nil] "0 to 1 °C"
        def spread(day)
          return degrees(day.high || day.low) unless day.low && day.high

          "#{day.low.round} to #{degrees(day.high)}"
        end

        # @param value [Float, nil]
        # @return [String, nil] "-5 °C"
        def degrees(value) = value && "#{value.round} #{@units.temperature_label}"

        # @param amount [Float, nil]
        # @param chance [Integer, nil]
        # @return [Array<String>] "precipitation 0.7 mm", "61 % chance", either missing
        def precipitation(amount, chance)
          rounded = amount&.round(@units.precipitation == :inch ? 2 : 1)
          shown = rounded&.zero? ? '0' : rounded.to_s
          [("precipitation #{shown} #{@units.precipitation_label}" if amount), ("#{chance} % chance" if chance)].compact
        end

        # @param words [String] "wind" or "wind up to"
        # @param speed [Integer, nil]
        # @return [String, nil] "wind up to 18 km/h"
        def wind(words, speed) = speed && "#{words} #{speed} #{@units.wind_label}"

        # @param date [Date]
        # @return [String] "Sun 22 Nov"
        def day_name(date) = date.strftime('%a %-d %b')

        # @param from [String, nil]
        # @param to [String, nil]
        # @return [String, nil] "3–6 Dec", "30 Nov – 2 Dec", "3 Dec", "until 6 Dec"; a date that
        #   doesn't parse as the model wrote it
        def span(from, to)
          first = short(from)
          last = short(to)
          return last && "until #{last}" unless first
          return first if last.nil? || last == first

          same_month = first.split.last == last.split.last
          same_month ? "#{first.split.first}–#{last}" : "#{first} – #{last}"
        end

        # @param text [String, nil]
        # @return [String, nil] "3 Dec"
        def short(text)
          return nil if text.to_s.strip.empty?

          Date.iso8601(text.strip).strftime('%-d %b')
        rescue Date::Error
          text.strip
        end
      end
    end
  end
end
