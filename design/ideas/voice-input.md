# Voice input: a mic in the prompt, transcribed by the user's own server

Siri takes voice only on a key or a click, never by itself (`R_siri_popup`). It has two ways in,
and Puri gets them differently:

- **The dictation key** (Siri's F5) types into whatever field has focus. On GNOME that is an
  IBus speech engine typing into `PromptEntry` like any input method — Myna on Ubuntu,
  `ibus-speech-to-text` on Fedora. No code here; a README paragraph.
- **The mic in the field** (Siri's pill and card) is Puri's own: no system tool has an API an
  app could start it with. This file is about that one.

## What exists (checked 2026-11-21)

- **Myna**, Canonical's dictation tool: announced June 2026, a technology preview since 12 Oct
  2026 ([blog](https://ubuntu.com/blog/myna-speech-to-text-technology-preview-available),
  [Discourse](https://discourse.ubuntu.com/t/introducing-myna-speech-to-text-for-ubuntu-desktop/84251)).
  - From `ppa:canonical-desktop-team/myna` (`myna-config`); the orchestrator and each model are
    snaps. Ubuntu 24.04, 26.04, 26.10, amd64, GNOME on Wayland only. Not in 26.10's archive; only
    its Shell indicator extension made the default install
    ([OMG! Ubuntu, Aug](https://omgubuntu.co.uk/2026/08/testing-ubuntu-ai-voice-dictation)).
  - Delivers the text "back to the text field of an app using IBus"; not a Shell extension. A
    Wayland-native input method is planned (same article).
  - A toggle: press the shortcut, speak, press again; it transcribes after the stop, not while you
    speak. Whether to show partial text live is open on their Discourse.
  - Parakeet, Whisper or FunASR, local; GPU only on NVIDIA so far. No D-Bus API documented.
- **GNOME upstream**: a [Discourse proposal](https://discourse.gnome.org/t/proposal-desktop-wide-offline-speech-to-text-dictation-support/35858)
  (June 2026) for a desktop dictation service with a D-Bus API and pluggable engines; no
  maintainer decision.
- **Fedora** packages [`ibus-speech-to-text`](https://github.com/PhilippeRo/IBus-Speech-To-Text)
  (Vosk; Whisper through pywhispercpp
  [proposed for F44](https://fedoraproject.org/wiki/Changes/ibus-speech-to-text_pywhispercpp)).
  Ubuntu's archive has no IBus speech engine.
- **whisper.cpp 1.8.3** is in 26.04's universe (`whisper.cpp`, `libwhisper1`), ggml's Vulkan
  backend beside it (`libggml0-backend-vulkan`). It ships `whisper-server`, `whisper-stream`,
  `whisper-cli`, `whisper-vad-speech-segments`, and a 53 s, 16 kHz mono sample
  `/usr/share/sounds/debian/samples/en-Wikipedia-Ignore_All_Rules.wav`. **No models**: the ggml
  weights (`ggml-base.en.bin`, `ggml-small.en.bin`, `ggml-large-v3-turbo.bin`, …) come from
  Hugging Face.
- **`whisper-server`**'s defaults: `--port 8080` (llama-server's too), `-l en` (not `auto`),
  `-t 4`. `--inference-path` replaces `/inference` (which then answers 404). An `.en` model
  ignores `-l` ("model is not multilingual, ignoring language").
- **`pw-record`** (`pipewire-bin`) records the mic; PipeWire is every current GNOME distro's.

## Measured (2026-11-21, whisper.cpp 1.8.3, `small.en`, CPU, 4 threads, Ryzen 7 PRO 4750U)

Server: `whisper-server -m ggml-small.en.bin --port 8081 --inference-path /v1/audio/transcriptions`.

- **OpenAI's shape works.** Multipart `file` + `model=whisper-1` answers `{"text": …}`; `model`
  is ignored, a `Bearer` key is ignored, JSON is the default without `response_format`.
- **A clip costs 7–8 s however short**, silence included: the encoder always runs a 30 s
  window. 2 s → 7.3 s, 5 s → 7.9 s, 10 s → 14.4 s, the whole 53 s → 17.5–20 s.
- **The text** starts with a space and has a newline per segment: `" Wikipedia, ignore all
  rules.\n From EN\n"`.
- **Silence, faint noise and a 0.3 s clip** answer `" [BLANK_AUDIO]\n"`. With
  `suppress_nst=true` the same clips answer `" you"` and `" Thank you."` — Whisper's known
  inventions.
- **Errors come as HTTP 200** with `{"error": "failed to read audio data"}` or
  `{"error": "no 'file' field in the request"}`.
- **48 kHz stereo WAV** is resampled and transcribed the same.
- **Knobs that hurt:** `temperature_inc=0` sent a clip cut mid-sentence into a repetition loop
  (21 s, the same two lines seven times); `no_timestamps=true` was no faster and lost the
  punctuation.
- **RubyLLM 2.2.2** (pikuri-core's) has `RubyLLM.transcribe` / `RubyLLM::Context#transcribe`;
  its OpenAI protocol posts multipart `model`, `file` (and `language` when given) to
  `<api_base>/audio/transcriptions` and reads `text`. Against this server with
  `openai_api_base = "http://127.0.0.1:8081/v1"`, `provider: :openai, assume_model_exists:
  true`: a path and a `StringIO` of WAV bytes both transcribe (8.0 s), silence answers
  `" [BLANK_AUDIO]\n"`, and a non-audio file answers `text: nil` without raising — the
  HTTP-200 error passes RubyLLM's status check, and its message is lost.

## The proposal

**The user owns the server, Puri owns the button.** The user installs whisper.cpp (or any
OpenAI-style transcription server), picks the model and the language, runs it, and measures
whether the GPU has room; the README shows how. Puri records and posts. A bigger model changes
nothing on Puri's side, the same request and the same answer, only slower and more accurate.

```toml
[dictation]
url = "http://127.0.0.1:8081"
# api_key = "…"          # a hosted server only
# model   = "whisper-1"  # whisper-server ignores it; a hosted server needs its own
```

No table, no mic icon — like `[maps]`. Its own `url`, not a `[[server]]` id (owner,
2026-11-21): `Config::Server` is a chat server, its `max_concurrent_requests` falling back to
llama-server's `total_slots`, and `PikuriCore.from_config` walks `config.servers` as chat servers
for throttle limits; a whisper-server is none of that, and nothing else would point at it. Like
`[maps]` and `[search]`, the endpoint and key live in the feature's own table. `Config.keys?`
then counts `dictation.api_key` for its loose-permissions warning. The cost, a hosted OpenAI key
written twice for chat and dictation, falls only on someone who opted out of local first.

- **Core transcribes through RubyLLM directly**, not through pikuri: one call on a
  `RubyLLM::Context` of its own, as `Pikuri::VectorDb::Embedder` does for embeddings.

  ```ruby
  context = RubyLLM.context do |c|
    c.openai_api_base = "#{dictation.url}/v1"
    c.openai_api_key  = dictation.api_key || 'not-needed'
  end
  context.transcribe(wav_io, model:, provider: :openai, assume_model_exists: true).text
  ```

  - It bends *A desktop UI and nothing else*, since the transport is pikuri's, and is excusable
    (owner, 2026-11-21): a URL and a key, none of a chat's transport (context window, params,
    modalities, throttle), and nothing in pikuri for it to drift from. On graduation: a `D_`
    entry; `AGENTS.md`'s exception line names it beside the place tools; `ruby_llm` goes into
    the Gemfile, since Puri then requires it itself rather than only through pikuri-core. Should
    pikuri ever grow a transcriber, Puri moves to it.
  - `text: nil` means the server failed (whisper-server's HTTP-200 error) and raises; the text
    is squeezed to single spaces; an answer made only of bracketed tags (`[BLANK_AUDIO]`)
    inserts nothing.
- **Core** records with `pw-record` at 16 kHz mono while listening (six times smaller than
  48 kHz stereo), wraps the PCM in a WAV header in a `StringIO`, and transcribes that. OpenAI's
  shape, so a hosted server is the same code, an explicit opt-in.
  - A clip under ~0.5 s isn't sent: a stray click would cost 8 s of CPU.
  - Backend methods `dictation_start` / `dictation_stop`; a `Dictation` event (listening,
    transcribing, text, failed) through `BackendClient#deliver`, JSON like every other.
- **Desktop** draws: a mic as `PromptEntry`'s secondary icon (`audio-input-microphone-symbolic`)
  and a key in the window; press to start, press to stop; the state on the icon — transcribing
  shows, since it takes seconds; the text inserted at the cursor, waiting for Return. GNOME's top
  bar shows its own mic-in-use indicator.
- **One clip per press**, like Myna. Phrases appearing at each pause would cost the 8 s floor
  per phrase on this CPU; only for a setup fast enough to afford it.
- **The mic and the recording are Puri's**: input, not agent; neither pikuri-tui nor pikuri-web
  has a mic button.
- **The Dummy backend** emits canned `Dictation` events, so the GTK specs drive the mic on
  Broadway without a microphone.

## The README, roughly

- `sudo apt install whisper.cpp`; a model from
  [Hugging Face](https://huggingface.co/ggerganov/whisper.cpp); `whisper-server -m <model>
  --port 8081 --inference-path /v1/audio/transcriptions -l auto`, as a systemd user unit to keep
  it warm. `--port`, since 8080 is llama-server's; `-l`, since the default is English.
- An `.en` model hears English only: spoken Finnish comes back as English gibberish.
- Speed is the user's to tune: a smaller model, more threads (`-t`), or the GPU.
- The IBus paragraph: Myna or `ibus-speech-to-text` type into Puri like into any field.

## Open questions

- **Decided (owner, 2026-11-21):** F5 starts and F5 stops, in the window's `ShortcutController`
  beside F9; the mic icon does the same. Stopping transcribes into the entry; Return still sends.
- **Decided (owner, 2026-11-21), kept small:** in specs Core's recorder reads a WAV file (a real
  source, not a mock) and the transcription runs on a scripted Faraday adapter (the context's
  `faraday_adapter`, as pikuri's `Pikuri::Testing.fake_transport` does for chats), covering the
  three answers the proposal handles: text, `[BLANK_AUDIO]`, `text: nil`. One opt-in spec posts
  the sample WAV to a running whisper-server.
- `Q_dictation_ui`: the owner's sketch is a small popup, an animated bar and "Listening; press F5
  to …". Lean: "Listening… press F5 when done" — "stop listening" sounds like discarding,
  "transcribe" is jargon. A `Gtk::LevelBar` on the mic's volume while listening (a progress bar
  has nothing to progress toward; a flat level shows a dead mic at once), then "Transcribing…"
  with a pulsing bar. Escape cancels first and inserts nothing, like Escape on a streaming reply.
  The window already has this shape — `StatusBar` and `Activity(state: 'working', status:)`, a
  progress bar with Core's words under it — so reuse it with `listening` / `transcribing` states
  rather than a popover? Then: dictating while a turn runs, with one `Activity` per conversation?
- `Q_room_noise`: does a real room, keyboard and fan, still come back `[BLANK_AUDIO]`, or as an
  invented "Thank you."? Revisited at the first test on a real mic (owner, 2026-11-21).
