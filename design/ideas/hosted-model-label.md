# A hosted model, labelled in the window

Goal: make *Yours, local first*'s "Puri says plainly that their conversations then leave" something
the user sees, not only a comment in the config. Raised 2026-11-25, not decided.

Apple's precedent: before Siri hands a request to ChatGPT it asks, and the answer is labelled as
ChatGPT's. Puri could mark a conversation whose model isn't the user's own, in the window, every
time it answers.

The catch: Puri can't tell a hosted provider from the user's home server by its URL; a tailnet
name, a LAN address and a cloud API all look alike. So the config would have to say it, say a
`hosted = true` on the `[[server]]`, and the label rests on the user saying so honestly.

## Open questions

- `Q_hosted_flag`: a flag the user sets, or a list of known providers' hosts that Puri recognises
  itself, or both?
- `Q_hosted_ask`: label only, or also ask before the first question goes out, as Apple does?
