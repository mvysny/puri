# Whisper models: which one the README recommends, and what silence types

Dictation works end to end (owner's test, 2026-11-21): F5, `pw-record`, the server, the text at
the cursor. But a press with nothing said types **"Thank you."** into the prompt on the owner's
server. Accepted for now (owner, 2026-11-21); this file is for trying models and knobs until we
know what to recommend.

## Measured (2026-11-21)

- **`small.en`, whisper.cpp 1.8.3, local CPU** (`R_whisper_server`): silence and faint noise answer
  `" [BLANK_AUDIO]\n"`, which Puri inserts as nothing. 7–8 s per clip however short.
- **`ggml-large-v3-turbo-q8_0.bin`, the owner's server** (`mavi-fw`, over the tailnet):
  - 5 s of the Debian sample → "Wikipedia Ignore All Rules from EN" in 1.3 s; all 53 s, correctly
    punctuated, in 2.4 s.
  - 2 s of digital silence → `" Thank you.\n"`, whatever the request's `suppress_nst` (default,
    `false`, `true`): unlike `small.en`, this model doesn't seem to produce `[BLANK_AUDIO]` at all.
  - 1 s of a 440 Hz tone → `"."`.
  - Through Puri, a 3 s clip: second F5 → text in 1.25 s, `pw-record`'s stop included. A ~40 s
    clip took 7–10 s, presumably the upload over the tailnet.
- This machine's built-in analog input delivers digital silence (every level 0.0, nothing plugged
  in?), so no real voice or real room has gone through Puri yet.

## To try

- **Models**, the same clips through each: `base`, `small`, `medium`, `large-v3-turbo` (q5 and q8),
  `large-v3`; the `.en` twins where English is enough. What each answers for silence, a fan and a
  keyboard; accuracy; speed on CPU and on the owner's GPU box.
- **Server-side VAD**: whisper-server 1.8.3 has `--vad --vad-model <file>`, a Silero model that
  keeps only the speech before Whisper sees it, so silence and noise never reach it. Its weights,
  `ggml-silero-v5.1.2.bin`, are another Hugging Face download (repo from memory:
  `ggml-org/whisper-vad`; check).
- **Server thresholds**: `--no-speech-thold` (0.60), `--entropy-thold` (2.40),
  `--logprob-thold` (-1.00). Maybe `large-v3-turbo` with a stricter no-speech threshold is
  enough.
- **Puri's side**: a reply that is only punctuation (the tone's ".") inserts nothing, which is
  cheap and safe either way. A loudness gate on the levels Core already measures (no send unless
  some window passes, say, −45 dBFS): needs a mic-dependent threshold, and a fan passes it.
  Filtering "Thank you." by name: brittle, and sometimes it's what was said.

## Open questions

- `Q_recommended_model`: one model in the install guide (`small` for now), or `small` for a CPU
  and `large-v3-turbo` for a GPU?
- `Q_silence`: VAD on the server (the README says how), a gate in Puri, or both?
- `Q_languages`: which languages to test, and whether `.en` models deserve a mention at all, since
  they turn other languages into English gibberish.
- `Q_room_noise` (from the voice-input idea, `[unverified]` in `R_whisper_server`): a real mic in a
  real room, with keyboard and fan; needs a mic plugged in.
- `Q_clips`: a fixed clip set (the Debian sample, silence, the tone, a room recording, the owner
  speaking each language) run against each model. As an opt-in spec like `WHISPER_URL`'s, or a
  rake task: never a loose script.
