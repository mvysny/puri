# Competitors — what a Puri user weighs it against, and where each stands

The products a Puri user compares it with, and how each one stacks up against the three promises
in `AGENTS.md`: *Private first*, *Easy, the Apple way* and *Yours, local first*. Like `research.md`,
this file is about *them*, with one provenance marker per claim. **[docs]** means the vendor's own
page. **[unverified]** means the press, a listing or memory. Nothing here was installed or run.
Siri's behaviour lives in `research.md` (`R_siri_popup`, `R_siri_app`, `R_siri_spotlight`), and
this file only places Siri among the others. A product gets a section when a user would weigh it
against Puri, and loses it when nobody would. Checked 2026-11-25. Cite a product by its heading.

---

## Where Puri stands

- **No other Linux product found combines a popup, the user's mail and calendar, and a local
  model by default.** Newelle comes closest: GNOME, local models, a mini window and documents.
  It reads no mail, though, and it gives the model a shell and a page reader.
- **Every product here that reads private data and documents its tools has a way out.** It fetches
  pages, runs a shell, or both, with an approval or a sandbox in front: Newelle, Moose's Web tool,
  Lumo, Perplexity, OpenClaw and Goose. None leaves fetch out altogether the way *Search, never
  fetch* does.
- **Ubuntu's launcher is the closest threat.** It uses the same promise words, on the default
  desktop of Puri's own distro, with a first version due in January. Canonical hasn't said
  anything yet about the points that set Puri apart: mail, tools, fetch, confirmations, history.
- **Hosted assistants reached Linux in 2026:** Claude in June, ChatGPT in August, Lumo in
  November. A Linux user no longer needs Puri to get an AI window. Puri's case is the local model
  and the broken trifecta.
- **Siri sets the bar for *Easy, the Apple way*:** a pill that grows into a conversation, with
  every conversation kept in one app. No Linux product matches it. Newelle's mini window is the
  nearest.

## At a glance

**Fetch / shell** means a tool that an injected instruction could use to send data out. **Acts
unasked** means it changes something without the user's click. A dash means no; a question mark
means not stated or not found.

| | Linux | Popup | Mail & calendar | Local by default | Fetch / shell | Acts unasked | Open source |
|---|---|---|---|---|---|---|---|
| Puri | GNOME | yes | Thunderbird | yes | — | — | yes |
| Siri, macOS 27 | — | yes | Mail, Calendar | small requests | ? | creates events | — |
| Ubuntu's launcher | Ubuntu | ? | ? | yes, AI opt-in | ? | ? | ? |
| Newelle | Flatpak | mini window | — | user's pick | both | commands, unconfirmed? | yes |
| Alpaca | Flatpak | — | — | Ollama | pasted URL, scripts | ? | yes |
| Moose | Flatpak | — | — | managed Ollama | fetch, asks first | — | yes |
| deepin UOS AI | deepin | ? | ? | — | ? | ? | ? |
| OpenClaw | daemon | — | yes | — in practice | both | yes | yes |
| Goose | AppImage, snap | — | ? | user's pick | shell | ? | yes |
| Khoj | self-hosted | — | — | user's pick | web | automations | yes |
| ChatGPT desktop | preview | ? | ? | — | ? | ? | — |
| Claude desktop | beta | ? | ? | — | ? | ? | — |
| Lumo desktop | yes | ? | Proton Mail | ? | both | per connector | ? |
| Copilot on Windows | — | wake word | ? | — | ? | sensitive steps ask | — |
| Gemini desktop | — | yes | ? | — | ? | ? | — |
| Perplexity Computer | — | yes | Mail, Notes | opt-in, 36 GB | via the cloud, asks | ? | — |
| Raycast AI | — | yes | — | Pro: Ollama | ? | ? | — |

## The reference

### Siri on macOS 27

It isn't a competitor, since it runs only on Apple hardware, but it is the bar for *Easy*.

- Cmd-Space opens a pill that grows into a card, and every popup conversation also lands in the
  Siri app's history: `R_siri_popup`, `R_siri_app`.
- It reaches the user's data through the Spotlight index: `R_siri_spotlight`.
- Its models are AFM 3, five of them, built "in collaboration with Google". Two run on the device:
  Core (3B) and Core Advanced, on "our most capable Apple silicon systems". Three run in Private
  Cloud Compute, and Cloud Pro runs on NVIDIA GPUs in Google Cloud.
  ([Apple](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models))
  **[docs]** Cloud Pro is Apple's own model "refined using outputs from Gemini frontier models",
  per Federighi ([Macworld](https://www.macworld.com/article/3162330/how-much-gemini-is-really-in-the-new-siri-ai.html));
  the often-quoted 1.2-trillion-parameter Gemini is a pre-WWDC Bloomberg report neither company
  confirmed. **[unverified]**
- It creates an event without asking, and sends a mail itself once the user types yes to
  "Ready to send?": `R_siri_popup`. Its guard against injection: `R_siri_guard`.
- It is closed source and runs on Apple hardware only. **[docs]**

## On the Linux desktop

### Ubuntu's launcher (Canonical)

- It is meant to replace the app grid as "a unified entry point" for apps and files, with AI only
  "when you explicitly ask for it". Input is by keyboard or speech.
  ([Discourse, 2026-11-24](https://discourse.ubuntu.com/t/beyond-a-launcher-a-new-way-to-interact-with-ubuntu/92365))
  **[docs]**
- It has four principles. Strictly optional: all AI is opt-in. Local-first: "rather than sending
  your queries to external cloud services by default". Privacy-first. Security-first: confinement
  and sandboxing, so that agentic parts "cannot compromise your host system". **[docs]**
- No model ships in the default install. The post names no model, runtime, tool list or
  confirmation flow, and doesn't say whether it reads mail or fetches pages. **[docs]**
- The `warty-prototype` snap (October 2026) is a scripted mockup, opened from an Ubuntu logo in the
  top panel. It simulates finding an image for the wallpaper, finding an ePub reader in the Snap
  Store, and building a calendar itinerary from clipboard history.
  ([OMG! Ubuntu](https://www.omgubuntu.co.uk/2026/10/ubuntu-ai-launcher-prototype))
  **[unverified]**
- Canonical will publish its architecture and a first version "in January", presumably 2027.
  **[docs]** Voice will probably use Myna, which is only OMG! Ubuntu's guess
  ([article](https://www.omgubuntu.co.uk/2026/11/ubuntu-ai-launcher-details)); Myna itself is in
  `R_dictation_tools`. **[unverified]**

### Newelle

- A GNOME assistant on Flathub (`io.github.qwersyk.Newelle`) and Nix. It runs local models through
  llama.cpp or Ollama, downloaded in the app, or a cloud provider.
  ([README](https://raw.githubusercontent.com/qwersyk/Newelle/master/README.md)) **[docs]**
- It has a "Mini Window Mode" (`newelle --mini`) on a hotkey the user binds, kept chats with
  folders and branches, and long-term memory. **[docs]**
- It chats with documents, has a built-in file manager with per-file permissions, and does a web
  search (no engine named). It reads a website when the prompt carries `#https://…`. **[docs]**
- It runs terminal commands the model suggests, with no confirmation described. It also has MCP
  servers, skills, background scheduled tasks, Telegram and an API to drive it, and voice in and
  out with a wake word. It reads no mail or calendar. **[docs]**
- Its own warning: "we can't guarantee the privacy of your chat data", and granting all files plus
  the session bus exposes "your data and terminal". **[docs]**
- 1.2 (January 2026) brought llama.cpp with Vulkan and the command tool, followed by MCP, 1.4 in
  May and 1.5 in August.
  ([Phoronix](https://phoronix.com/news/gnome-ai-newelle-1.2)) **[unverified]**

### Moose

- Rust, GTK4 and libadwaita, GPL-3.0+, on Flathub (`io.github.moooossee.Moose`), version 0.8.5. It
  installs and manages Ollama itself, or talks to Ollama Cloud, OpenRouter, Groq, OpenAI, Claude or
  Gemini. ([README](https://github.com/moooossee/moose)) **[docs]**
- Chats, drafts and a searchable document library (SQLite FTS5, PDFs through `pdftotext`) stay on
  the device. It writes PDF and office files. It has no popup and reads no mail. **[docs]**
- Its Web tool "asks for its own permission: search services receive your searches, websites
  receive requests for the pages you read". Local Only mode blocks remote models and the web
  tools. Remote chats ask before sharing a file. **[docs]**
- It first appeared in October 2026.
  ([Phoronix](https://www.phoronix.com/news/GNOME-Moose-Local-AI)) **[unverified]**

### Alpaca

- An Ollama client on Flathub (`com.jeffser.Alpaca`). Cloud models go through OpenAI-compatible
  APIs and the user's own keys.
  ([README](https://raw.githubusercontent.com/Jeffser/Alpaca/main/README.md)) **[docs]**
- It reads plain-text documents, images, YouTube transcripts and websites by pasted URL, and lists
  "Integrated Script Execution" and web search. It has no popup and reads no mail. **[docs]**
- Last commit 2026-05-26.
  ([linuxphoneapps](https://linuxphoneapps.org/apps/com.jeffser.alpaca/)) **[unverified]**

### deepin's UOS AI

- Built into the deepin desktop. A local model runs on llama.cpp once the user downloads one; the
  guide uses DeepSeek-R1 1.5B and recommends an i5-class CPU. Since 2.0 it switches between cloud
  and local models.
  ([deepin](https://www.deepin.org/en/uos-ai-integration-with-deepseek-r1)) **[docs]**
- It takes any OpenAI-compatible API, Ollama included.
  ([Habr](https://habr.com/en/articles/976754)) **[unverified]**
- UOS AI 2.8 added "three agents"; deepin 25.1 (April 2026) focused on UOS AI.
  ([deepin](https://www.deepin.org/en/uos-ai-2-8),
  [AlternativeTo](https://alternativeto.net/news/2026/4/deepin-25-1-launches-with-linux-6-18-uos-ai-upgrades-and-new-immutable-system-features))
  **[unverified]**

### GNOME Shell extensions

- LLM Popup: a top-bar popup to Ollama, llama.cpp, OpenAI-compatible APIs, Claude or Gemini, with
  keys in the keyring. Chat only, as described.
  ([review](https://extensions.gnome.org/review/77222)) **[docs]**
- Penguin AI Chatbot: a top-panel chat with cloud providers only.
  ([extensions.gnome.org](https://extensions.gnome.org/extension/7338/penguin-ai-chatbot))
  **[docs]**

### KDE Plasma

- Plasma has no assistant. "Make Plasma smart" is a proposed 2026 KDE goal, and KaDAi, a concept
  for an "AI-native" Plasma, was put up for Akademy 2026 with no prototype.
  ([KDE goal](https://invent.kde.org/teams/goals/goal-setting/2026/-/work_items/19),
  [WindowsForum](https://windowsforum.com/news/kde-plasma-kadai-is-a-proposal-not-an-ai-desktop.444963/))
  **[unverified]**
- An initiative, KDE for People, calls for banning generative AI from Plasma.
  ([Linux Magazine](https://www.linux-magazine.com/Online/News/KDE-for-People-Initiative-Calls-for-AI-Ban-in-Plasma))
  **[unverified]**

## Agents

### OpenClaw

- A daemon the user messages from WhatsApp or Telegram, with shell, browser and file access and
  third-party skills. It wants 64K+ context and a strong model, so in practice it runs on cloud
  models. ([MindStudio](https://www.mindstudio.ai/blog/what-is-openclaw-ai-agent))
  **[unverified]**
- It is known for its security record: leaked credentials, and an inbox it began deleting.
  ([Built In](https://builtin.com/articles/what-is-openclaw),
  [NYU Shanghai RITS](https://rits.shanghai.nyu.edu/ai/openclaw-the-open-source-ai-agent-you-can-run-locally-but-beware-the-risks/),
  [HackerNoon](https://hackernoon.com/openclaw-is-a-security-nightmare-here-are-the-alternatives-to-use-instead))
  **[unverified]**
- Its own docs say local models lack hosted providers' safety filters, so tool permissions and
  prompt-injection defences need care.
  ([docs](https://docs.openclaw.ai/gateway/local-models)) **[docs]**
- Ollama 0.17 sets it up in one click.
  ([dev.to](https://dev.to/darbogach/ollama-just-made-openclaw-one-click-heres-how-to-secure-it-2j2e))
  **[unverified]**

### Goose

- Apache 2.0, now under the Linux Foundation's Agentic AI Foundation: a desktop app (Electron), a
  CLI and an API on Linux, macOS and Windows, "for code, workflows, and everything in between".
  ([README](https://github.com/aaif-goose/goose)) **[docs]**
- On Linux it ships as an AppImage, or as a snap with classic confinement "to operate with full
  host access". ([snap](https://snapcraft.io/goose)) **[docs]**
- It has 70+ MCP extensions, and local models through Ollama with no key.
  ([docs](https://goose-docs.ai/)) **[docs]**

### Khoj

- AGPL-3.0, a "personal AI": it answers from files and the web, runs custom agents and scheduled
  automations, and works with any local or online model. It is self-hosted (Docker, Postgres,
  SearxNG) or runs at app.khoj.dev. ([README](https://github.com/khoj-ai/khoj)) **[docs]**
- It is reached from the web, a desktop app, Obsidian, Emacs or WhatsApp. It reads notes and
  documents, not mail.
  ([Obsidian plugin](https://community.obsidian.md/plugins/khoj)) **[unverified]**

## Hosted assistants with a Linux app

### ChatGPT desktop

- A Linux preview since August 2026: `.deb` and `.rpm` for x64 and ARM64, with ChatGPT, Work and
  Codex in one app, behind a sign-in. Computer Use is missing on Linux.
  ([OpenAI](https://learn.chatgpt.com/docs/linux/linux-app)) **[docs]**
- It is tested on Ubuntu 24.04 and 26.04, Debian 13, and Fedora 43 and 44.
  ([Phoronix](https://phoronix.com/news/ChatGPT-Desktop-Linux-Preview)) **[unverified]**

### Claude desktop

- A Linux beta since 2026-06-30 for Ubuntu 22.04+ and Debian 12+, from Anthropic's apt repository,
  with Chat, Cowork and Claude Code.
  ([Anthropic](https://code.claude.com/docs/en/desktop-linux)) **[docs]**
- Computer use, voice input and some hotkeys are missing from the beta.
  ([PC Watch](https://pc.watch.impress.co.jp/docs/news/2121519.html)) **[unverified]**

### Lumo desktop (Proton)

- Out 2026-11-17 for Windows, macOS and Linux, behind a Proton account. Proton says only the user
  can read the chat history, it keeps no server-side logs, and it hosts in Switzerland. Neither
  article names the model or where it runs.
  ([TechCrunch](https://techcrunch.com/2026/11/17/protons-lumo-a-privacy-focused-alternative-to-chatgpt-and-claude-arrives-on-desktop/),
  [PCWorld](https://www.pcworld.com/article/3289395/proton-launches-an-ai-assistant-for-computers-with-a-strong-focus-on-privacy.html))
  **[unverified]**
- Its connectors cover file-system access, shell execution, "browser content fetching", Proton
  Mail, Confluence, Dropbox, Jira, and local and remote MCP. For each connector the user picks
  automatic, needs approval, or blocked, and scheduled tasks get their own permissions.
  ([TechCrunch](https://techcrunch.com/2026/11/17/protons-lumo-a-privacy-focused-alternative-to-chatgpt-and-claude-arrives-on-desktop/))
  **[unverified]**

## Elsewhere only

### Copilot on Windows 11

- "Hey Copilot" is an opt-in wake word.
  ([Microsoft](https://blogs.windows.com/windowsexperience/2025/10/16/making-every-windows-11-pc-an-ai-pc/))
  **[docs]**
- Copilot Actions works on local files. It is off by default, shows every step, can be paused, and
  asks before sensitive ones; the preview keeps to Documents, Downloads, Desktop and Pictures.
  ([Windows Report](https://windowsreport.com/microsoft-previews-copilot-actions-for-local-files-in-windows-11/))
  **[unverified]**
- Since October 2026 it may change local files and runs some tasks on on-device models.
  Execution Containers, which give an agent file and network policies, have been generally
  available since 2026-10-07.
  ([Computerworld](https://www.computerworld.com/article/4073153/the-newest-windows-copilot-agent-can-send-emails-update-documents-on-its-own.html))
  **[unverified]**

### Gemini desktop

- A Mac app since April 2026 (macOS 15+, Apple silicon) and a Windows app since 2026-09-10.
  Option+Space or Alt+Space opens a mini chat over any app. There is no Linux app.
  ([Google](https://blog.google/innovation-and-ai/products/gemini-app/the-gemini-app-is-now-available-for-windows/),
  [Workspace](https://workspaceupdates.googleblog.com/2026/04/now-available-gemini-app-for-mac.html))
  **[docs]**
- Agent features need a paid plan.
  ([Engadget](https://engadget.com/2255197/a-native-gemini-app-is-finally-available-for-windows-pcs))
  **[unverified]**

### Perplexity's Personal Computer

- Part of the Mac app since May 2026, on a Pro or Max plan. It reads, writes and searches local
  files and operates Mail, Slack, Notes and Finder. Files it creates go to a sandbox, and its
  actions can be audited and reversed.
  ([TechCrunch](https://techcrunch.com/2026/05/07/perplexitys-personal-computer-is-now-available-everyone-on-mac))
  **[unverified]**
- Since October 2026, an on-device mode runs both the model (Qwen 3.6 or PPLX Pro) and the agent
  on the Mac, best with 36 GB of memory. Current information, browser use and connected apps still
  go to the cloud once the user approves.
  ([9to5Mac](https://9to5mac.com/2026/10/20/perplexitys-computer-can-now-run-entirely-on-your-mac-even-offline/))
  **[unverified]**

### Raycast AI

- A launcher for macOS and Windows, with no Linux client found.
  ([changelog](https://www.raycast.com/changelog/windows)) **[docs]**
- Local models through Ollama need Pro and are capped at 64K of context. They power Quick AI, AI
  Chat and AI Commands, but not the extensions' AI.
  ([manual](https://manual.raycast.com/ai/local-models)) **[docs]**

## Local chat apps

- **Jan:** `.deb`, AppImage and Flathub. It runs GGUF models, serves an OpenAI API on `:1337`,
  and is an MCP client. ([docs](https://www.jan.ai/docs/desktop/mcp)) **[docs]**
- **AnythingLLM, LM Studio, GPT4All:** desktop apps on Linux for local models. AnythingLLM's focus
  is chatting with documents.
  ([Vellum](https://www.vellum.ai/blog/best-local-ai-assistants)) **[unverified]**
- These are chat windows over a local model. None of them has a popup or reads mail.
  **[unverified]**

## In the apps Puri reads

### Thunderbird

- MZLA intends to offer AI by subscription through Thunderbird Pro, not in base Thunderbird. The
  "Thunderbird Assist" idea (thread summaries, rewording drafts) has no release date.
  ([Mozilla Connect](https://connect.mozilla.org/t5/ideas/thunderbird-assist-built-in-smart-assistant-for-faster-clearer/idi-p/91798))
  **[unverified]**

### Firefox's Smart Window

- An opt-in AI window (announced in 2025 as "AI Window"), on Mozilla's models or the user's own
  OpenAI-compatible endpoint, such as Ollama. It needs a Firefox Account, and has rolled out since
  Firefox 150 in the US and Canada.
  ([Mozilla](https://support.mozilla.org/kb/smart-window-byom)) **[docs]**

## Voice

### OpenVoiceOS

- An open-source, modular voice-assistant framework: a "privacy-first, transparent alternative"
  to proprietary voice assistants. ([NLnet](https://nlnet.nl/project/OpenVoiceOS/)) **[docs]**
- It hands questions it can't handle to an OpenAI-compatible model through plugins. It runs on
  Linux, a Raspberry Pi or Docker, not as a desktop app, and isn't offline by default.
  ([PromptQuorum](https://www.promptquorum.com/power-local-llm/openvoiceos-review))
  **[unverified]**
