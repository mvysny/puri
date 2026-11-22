# Weather: a `weather` tool on Open-Meteo

From `siri-parity.md`: "What's the weather like in San Francisco?" [docs]. Today Puri can only
web-search it. Brainstormed 2026-11-22.

**Decided (owner, 2026-11-22):** Open-Meteo first; MET Norway is as solid, and may come later.
A `[weather]` table in `config.toml` turns the tool on, and only works together with `[maps]`.
The tool lives here, like the place tools (`D_places`), and moves to pikuri-workshop once it
has matured. The tool's shape is as below. The answer is text only, with no card under it.

## Open-Meteo, as read and tried

Docs at open-meteo.com/en/docs, terms and pricing pages; one request tried on 2026-11-22.

- **One GET:** `https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&current=…&daily=…&hourly=…&timezone=auto`,
  plus either `forecast_days` (0–16, default 7) or `start_date`/`end_date` (`yyyy-mm-dd`).
  `past_days` goes back 0–92 days. Units are set with `temperature_unit` (`celsius`,
  `fahrenheit`), `wind_speed_unit` (`kmh`, `ms`, `mph`, `kn`) and `precipitation_unit` (`mm`,
  `inch`). `timezone=auto` means the place's own time zone: its days, its sunrise.
- **The answer is in columns:** one array per variable, aligned to `daily.time` or
  `hourly.time`, with a `*_units` object beside each block. Tried, trimmed:

  ```json
  { "latitude": 52.512604, "longitude": 13.419517, "timezone": "Europe/Berlin", "utc_offset_seconds": 3600,
    "current": { "time": "2026-11-22T15:15", "interval": 900, "temperature_2m": 4.8, "weather_code": 3,
                 "wind_speed_10m": 11.5, "apparent_temperature": 1.1 },
    "daily": { "time": ["2026-11-22", "2026-11-23", "2026-11-24"], "weather_code": [80, 80, 77],
               "temperature_2m_max": [5.6, 3.9, 2.5], "temperature_2m_min": [2.1, -0.1, 0.2],
               "precipitation_sum": [2.1, 0.0, 0.4], "precipitation_probability_max": [88, 23, 18],
               "wind_speed_10m_max": [17.2, 18.1, 14.1], "sunrise": ["2026-11-22T07:39", …] },
    "daily_units": { "temperature_2m_max": "°C", "precipitation_sum": "mm", … } }
  ```

  The coordinates that come back are the grid cell's, not the ones asked for. `current` is
  15-minute data. Every hourly variable can also be asked for as `current`.
- **Errors** are HTTP 400 with `{"error": true, "reason": "…"}`, and the reason reads well. Tried:
  `forecast_days=20` gives "Forecast days is invalid. Allowed range 0 to 16. Given 20."; a
  `start_date` of 2026-12-20 gives "Parameter 'start_date' is out of allowed range from 2026-08-21
  to 2026-12-07". The forecast therefore reaches today + 15. `Places::Http#reason` reads only
  `message` and `error`, so it would drop this reason: it needs `reason` too.
- **`weather_code`** follows WMO's table, 28 codes from 0 "Clear sky" to 99 "Thunderstorm with
  heavy hail". Codes 96 and 99 come only from models that forecast hail (ICON, UKMO).
- **Terms:**
  - No key, and no User-Agent or contact is asked for, unlike OSM's services and MET Norway.
  - The free tier is non-commercial: no subscriptions or ads. Puri fits.
  - Limits: under 10,000 calls a day, 5,000 an hour, 600 a minute.
  - The data is CC BY 4.0, so Open-Meteo is credited wherever it is shown.
  - The server is AGPLv3 (github.com/open-meteo/open-meteo), so it can be self-hosted.
- **Also there, not used in v1:**
  - Geocoding at `geocoding-api.open-meteo.com/v1/search`: GeoNames, so towns and postcodes
    only.
  - Air quality at `air-quality-api.open-meteo.com/v1/air-quality`: CAMS data, pollen in Europe
    only, 7 days.
  - The Historical Weather API: ERA5 reanalysis, back to 1940.

## The tool

```
weather(place:, from: nil, to: nil)
```

- **`place`** takes what `route`'s ends take: a number from `place_search`, an address, or
  coordinates. It is resolved through `Places::Ends.resolve`, so the place gets a number, and the
  result names what it matched, "Weather for [7] Lisboa (city), Portugal"; a wrong match shows,
  as it does for a route. For "here" or "at home", the model passes the home address from
  `Notes/PURI.md`, as `places.txt` already says.
- **`from`, `to`** are dates, `yyyy-mm-dd`, in the place's own calendar:
  - **Both omitted:** today and the 6 days after it. The model reads the lines it needs, so
    "tomorrow", "the next three days" and "this weekend" pass no date at all. Every line names
    its weekday, so the model looks "Saturday" up instead of adding days to today. A small model
    slips on that arithmetic across a month's end.
  - **`from` alone:** that one day.
  - **Both:** that range, such as a trip's dates copied from the calendar.
- **The view depends on the range:**
  - One day gives its summary line, then that day in 3-hour steps, with sunrise and sunset. That
    answers "will it rain this afternoon?".
  - Several days give one line a day.
  - When the range includes today, a "Now" line from `current` comes first.
- **The latest date is in the description (owner):** "the forecast reaches 2026-12-07". It is a
  date rather than "15 days ahead", so the model has nothing to add up.
  - It is the machine's today + 15, worked out when the agent is built, like the system prompt's
    "Today is".
  - It then stays fixed for the agent's life, so llama-server's cache of the prompt holds. An
    agent still alive after midnight sees a date that is a day stale, just as its "Today is" is.
    The tool checks against the real date anyway.
  - A range that ends later is cut at the forecast's last day, and the result says so. A range
    that starts later is an error naming that day.
- **Past days:** up to 92 work, so "what was it like yesterday?" is answered too. The answer
  comes from the weather model's own analysis, not from a weather station.
- **One request per place:** the tool always asks for the full 16 days, plus `past_days` when
  `from` is before today, and cuts the range out itself. It never sends `start_date`/`end_date`.
  - The API then never refuses a date.
  - The forecast's last day is whatever the answer holds, in the place's own time zone. For a
    place far east or west of the machine, that is a day later or earlier than the description's
    date.
  - Asking about the same place again within the cache's life sends no new request.

### "The weather on my trip to xyz"

The question goes through the calendar and needs no new tool. The calendar's search (or the mail)
finds the trip's dates and place, then the model calls
`weather(place: "Lisbon", from: "2026-12-03", to: "2026-12-06")`. This is one more line for the
multi-step test list in `siri-parity.md`.

- The tool knows nothing about trips. The prompt says it in one line: for a trip or an event, find
  its dates and place first, and when there are none, ask the user.
- A trip to two places means two calls.
- Try it on the owner's model before building anything more for it.

### What it returns

Like every pikuri tool, it returns a `Pikuri::Tool::Result` whose `content` is a String that the
model reads and puts in its own words, and a short `summary` for the tool line. An example; the
numbers are made up:

```
Weather for [7] Lisboa (city), Portugal, in its own time (Europe/Lisbon, UTC+00:00).

Now, 15:15: overcast, 14 °C, feels like 12 °C, wind 12 km/h.
Sun 22 Nov: slight rain showers, 11–16 °C, 2.1 mm of rain (88 % chance), wind up to 17 km/h.
Mon 23 Nov: partly cloudy, 10–17 °C, no rain (10 % chance), wind up to 15 km/h.
…
```

- **Words, not codes:** each WMO code becomes Open-Meteo's own wording, lower-cased. A model shown
  "80" guesses what it means.
- **Rounding:** whole degrees, as Siri and GNOME Weather show them, and rain to 0.1 mm.
- **The tool line:** `describe_call` gives "Lisboa, 3–6 Dec", and the summary "4 days, 10–17 °C",
  or for one day "Slight rain showers, 11–16 °C".
- **Units are GNOME's (owner):** the `temperature-unit` and `speed-unit` keys of
  `org.gnome.GWeather4`. The schema is installed here, and both keys are `default`. `default`
  follows the locale's `LC_MEASUREMENT`, which is metric here [unverified that libgweather reads
  it so]. Puri then shows the same numbers as the shell's clock and GNOME Weather. Open-Meteo
  has no Beaufort, so Puri converts to it itself.

### Credit

The two texts disagree on whether a private window needs a credit (read 2026-11-22):

- **CC BY 4.0's legal code requires it only when sharing.** Its attribution conditions apply "If
  You Share the Licensed Material", and to share means "to provide material to the public".
  Showing the owner their own forecast on their own desktop isn't sharing.
- **Open-Meteo's licence page asks for more:** "You must include a link next to any location
  Open-Meteo data are displayed", with `<a href="https://open-meteo.com/">Weather data by
  Open-Meteo.com</a>` as the example. Its terms bind the free API's users to "the CC-BY 4.0
  licence, as specified in the [licence conditions]", which is that page. Read to the letter,
  Puri's window is a place where the data is displayed.
- **The specs' fixtures need it either way:** fixtures recorded from Open-Meteo and committed to
  the public repo are shared under any reading. Unlike Nominatim's, Open-Meteo's answers carry no
  `licence` field, so the credit goes beside them.

**Decided (owner, 2026-11-22): the tool line carries the credit.** It reads "Weather from
Open-Meteo: Lisboa, 3–6 Dec". It sits next to the data, stays in the transcript, and needs no
card and nothing from the model.

- "Open-Meteo" is a link to open-meteo.com, because the licence page asks for a link.
  `ToolLine` text is plain today, while the map's `note` already carries Pango markup with links.
  So this is a small `Protocol` and Desktop change: a tool line gains an optional link, or
  markup.
- Puri also credits Open-Meteo once at setup, in the README and the config example, beside
  `[weather]`.

## Where the place goes, and what leaves

- **Photon resolves the place, not Open-Meteo's geocoding.** GeoNames knows towns and postcodes,
  but not "Kielotie 4, Vantaa", the kind of address the memory keeps. Going through `Ends` also
  gives `route` a number to reuse. The price is two hosts per call; repeats come from `Http`'s
  cache.
- **Coordinates go to Open-Meteo rounded to 0.01°**, about 1 km, which is finer than its 1–11 km
  grid anyway. The home's exact point never reaches Open-Meteo. Photon still gets the address,
  as it does from `place_search` today.
- **Trifecta legs** are the place tools': `private: false` (only places leave),
  `untrusted: :hard` (the place's label is whatever anyone mapped), egress unreviewed, to a
  destination the tool fixes.
- **A `prompts/weather.txt`**, beside `places.txt`, says:
  - the place leaves the machine for OpenStreetMap and Open-Meteo;
  - "here" means the home address from the memory;
  - a trip's dates come from the calendar first;
  - the model asks the user when it can't find them.

## Wiring

- **Config:** `[weather]`, which may be empty and still turns the tool on. An optional `url`,
  `https://api.open-meteo.com` by default, points at a self-hosted Open-Meteo instead, the way
  `[maps] tiles` is a setting. It also gets a line in `Config`'s example and in the README.
- **`[weather]` needs `[maps]` (owner):** `weather` is wired beside `place_search` and `route`,
  on the same `osm` and `Notebook`, so the agent-session wiring stays as it is. `[weather]`
  without `[maps]` fails the config's load with a `Config::Error` that names the missing table,
  rather than quietly leaving the tool out.
- **`Http` moves up to `Core::Http` (owner),** shared by `Places::Osm` and the Open-Meteo
  client, one per process as now. Three changes come with the move:
  - **An expiry:** today's cache is a 256-answer LRU with no expiry. That is fine for a place,
    and wrong for a forecast in a Puri that stays resident for days. `get_json` gains a
    `max_age:`: 15 minutes for a forecast, the `current` interval, and never for a place.
  - **Open-Meteo's error text:** `reason` reads `reason` as well as `message` and `error`.
  - **Its comment** names OSM's services alone today, and needs rewording.

  The one-request-a-second pacing per host is far below Open-Meteo's 600 a minute, and does no
  harm.
- **Files:** `lib/puri/core/http.rb`, plus `lib/puri/core/weather/` holding `open_meteo.rb` (the
  request, units, WMO words) and `weather_tool.rb`.
- **Specs:** a fake Open-Meteo served the way `spec/support/fake_osm.rb` serves OSM, with
  fixtures recorded from the real API. No mocks.
- **At graduation:**
  - a `D_weather` entry: why Open-Meteo, why the tool lives here, and why the credit is on the
    tool line, with the licence quotes;
  - AGENTS.md's line listing the exceptions to *a gap is a missing pikuri primitive* gains the
    weather tool;
  - the Weather row of the parity list moves to "At parity".

## Later, not v1

- **Typical weather past the forecast:** v1 refuses past its last date. Later, the Historical
  Weather API could answer the same dates over the last ten years, as one request across ten
  years or ten requests of one week each: "usually 12–17 °C, rain on 4 days in 10".

- **MET Norway** as a second provider, `[weather] provider = "met-no"`. Its terms want an
  identifying User-Agent. `Puri::USER_AGENT` names the repository, but Puri has no version yet,
  the same snag Transitous has (`routes-by-bike-foot-and-bus.md`).
- **Air quality and pollen**, "is the pollen bad today?": the air-quality API, Europe-only for
  pollen.
- **Severe-weather alerts:** Open-Meteo has none; MET Norway's MetAlerts covers the Nordics.
