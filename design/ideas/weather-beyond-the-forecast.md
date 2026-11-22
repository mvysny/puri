# Weather beyond the forecast

What the `weather` tool (`D_weather`) leaves out, from its brainstorm on 2026-11-22. None of it
is decided.

- **Typical weather past the forecast.** Today the tool refuses a date past its last day. The
  Historical Weather API (`archive-api.open-meteo.com`, ERA5 reanalysis, back to 1940) could
  answer the same dates over the last ten years instead, as one request across ten years or ten
  requests of one week each: "usually 12–17 °C, rain on 4 days in 10".
- **Air quality and pollen**, "is the pollen bad today?": Open-Meteo's air-quality API, at
  `air-quality-api.open-meteo.com/v1/air-quality`. Its data is CAMS', 7 days ahead, and the
  pollen covers Europe only.
- **Severe-weather alerts:** Open-Meteo has none. MET Norway's MetAlerts covers the Nordics.
- **MET Norway as a second provider,** `[weather] provider = "met-no"`. Its terms want an
  identifying User-Agent with a version, and Puri has no version yet: the same snag as
  Transitous (`routes-by-bike-foot-and-bus.md`).
