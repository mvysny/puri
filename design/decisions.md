# Decisions

Why this project is the way it is and not otherwise — FAQ-shaped: each entry is a question and
its current answer. Rewrite the answer when it changes; delete the entry when nobody asks any
more. An entry is earned by what it would cost to reverse — half the code base — or by research
the next person would otherwise redo (cited as its `R_`). Not an entry: windows → panels
"because that's the trend", this red over that red, `get_foo` over `is_foo?`, the testing library,
the CI host, a version bump — a comment at the site of the choice, or nothing; nothing about
`design/` itself. Cite by slug, `D_<slug>`, never by position; `grep '^## D_' design/decisions.md`
is the index. The first entry is the ruler: every later one trims to its length — which is how
long this file gets, so keep it short. When you have written an entry, re-read it against the one
above, open the doc comments it touches and cut what they already say, then cut the fat.

---

## D_one_process — Why one Ruby process holding both Core and the GTK4 UI, rather than a backend daemon and a UI client?

Something is resident anyway: the agents, the saved conversations, the notes index and the
reminder timers (the model itself runs in llama-server). And no Ruby UI starts fast enough on the
hotkey — ~1.2 s (`R_gtk4_binding_cost`) — so the UI stays resident too, hidden rather than
closed, and a second process would save only a hidden window's memory. The costs we carry: a
crash in GTK or its binding takes a running turn and the reminder timers down with it; pikuri's
threads reach GTK only through the main loop; trying a UI change restarts pikuri too. So it is
drawn as two: Core and Desktop share no constants, and every value crosses as JSON, so a split
over D-Bus swaps only the connection. Splitting is optional, not a milestone: when those costs
bite, when a second client appears, or when Desktop leaves Ruby (`D_ruby_gtk4`). Why not
separate gems to hold the line: `gtk4` comes from apt, on the default load path whatever a
gemspec says, so gems enforce nothing; a grep spec and a GTK-free load spec do. Packwerk would
do the grep statically, but apt doesn't ship it.

## D_ruby_gtk4 — Why Ruby + GTK4 for the UI, with Vala as the fallback, rather than Python, the JVM or Flutter?

Ruby lives in Core's process and shares pikuri's code (`D_one_process`). Its measured start and
memory (`R_gtk4_binding_cost`) count only against an on-demand launch, which a resident process
never does; every other option adds a second language and IPC from day one to buy back exactly
those two. GTK4 gives any binding the headless Broadway + Playwright loop. Why not Python: the
leanest binding measured, but a tier-2 language for the owner and still a binding. Why not
Flutter: a GTK3 shell from a snap, no Broadway, and its strength, animation, aimed at a window
whose size Mutter controls. Why not Swing or Compose: XWayland, blurry under fractional scaling,
and tests on Xvfb. The fallback is the binding, not the numbers: `ruby-gtk4` is far less used
than PyGObject, so if it segfaults or misbehaves (widgets losing their Ruby object, signals
misfiring, a main loop starving pikuri's threads) and the cause is the binding, Desktop alone is
rewritten in Vala as its own process, Protocol over D-Bus, Core still Ruby: `valac` is in apt,
GTK4, libadwaita and GDBus are first-class, it starts like C, and no binding layer is left to go
wrong. That is why Desktop only draws — widgets and `BackendClient`, view state only, one plain
widget class per file, Markdown rendered in Core — so a rewrite has nothing to migrate.

## D_confirmation_answers — Why does a confirmation take four answers, told apart by gesture, rather than buttons alone?

The answer's type carries the meaning, the gesture picks the type, and the model never guesses
it from text. Update is `Approved`. Cancel is `Rejected`, with no reason: the model carries on
and stops by itself, saying so, as Siri does; a retry would only ask again, since the
confirmation is the safety, not the stop, and the other half of a two-part request can still
happen. Typed text and Enter is `Redirected`: the model follows the words and proposes again,
which asks again, the way Siri's row stays non-modal (`R_siri_popup`). Escape cancels the turn,
as it does everywhere. Desktop never decides which: the buttons call `answer`, and typed text
goes through `ask`, which Core takes as the redirect while a confirmation waits. Why Enter on an
empty entry does nothing and the buttons never take focus: a stray Enter must never press a red
button. The three results and their prompt wording are pikuri's `Confirmer` (pikuri#12), not
ours. The question names everything that matters, which calendar, which note, because Siri's
unconfirmed create picked the wrong calendar.

## D_port_pikuri_web — Why host conversations through pikuri-conversations rather than our own store, or pikuri?

Puri is pikuri-web ported onto a backend that doesn't care what its frontend is, and both hosts
need the same hosting around pikuri's `Agent`: a turn per thread, mid-turn messages, cancel,
one folder per conversation, a titler, a throttle per server. Two copies drifted, so it lives
once, in the workshop's `pikuri-conversations`; pikuri itself stays the synchronous loop, since
none of it matters to one conversation alone. The folder format is the one both already wrote:
pikuri's `history.json` beside a `meta.json` envelope, where Puri adds `last_question` and
`asked_at`. Displaying a turn stays ours: blocks, Markdown, wording.

## D_own_prompts — Why write our own system prompts rather than use pikuri's as they are?

What an agent needs to be told differs per app and per model (a dense 4B and Ornith 1.5 are
different beasts), so pikuri's system prompts are examples, and Puri writes its own. The line is
the code: a prompt whose wording pikuri's code depends on stays pikuri's and is never reworded
here. That covers a tool's description, the Confirmer's answers, a cancelled call's repair text
and memory extraction. A model that needs one worded otherwise is a gap to fix upstream. pikuri's
fragments also carry instructions an agent does worse without, like `agent-loop.txt`'s tool-loop
hygiene, so our system prompt keeps every fragment our extensions bring. It drops or rewords one
only for a reason seen on the model in question.

## D_app_id — Why `io.github.mvysny.Puri` as the app id?

It names the D-Bus service, the desktop entry, the `.service` file and the command the shortcut
runs, so it is hard to change once installed. Reverse-DNS on the GitHub repo: Flathub accepts
`io.github.<user>.*`, verified through `mvysny.github.io`, and no longer accepts new
`com.github.*` ids. Why not Codeberg's `page.codeberg.*`: its Terms of Use §2.7, a July 2026
member vote, bar mostly-AI-written projects, and it goes down often.

## D_whole_reply — Why does Core re-send the whole `Reply` per delta, rather than only what changed?

Because the bytes are not the cost. A 10 KB reply crosses `Protocol.round_trip` in 0.05 ms,
0.1% of a core at 15 fps, and Desktop skips a part whose content is unchanged. What costs is
laying out the prose that changed (`R_label_layout_cost`), and a Protocol that sent finished
parts once wouldn't shrink it: merged prose made the open part the whole prose run so far. So
`ReplyStream` keeps the open block apart from the finished prose until the reply ends. Per
delta, one paragraph is laid out again, and a selection spans the tail once the reply is done.


## D_own_config — Why Puri's own required `config.toml`, rather than pikuri's shared one?

pikuri-tui and pikuri-web share `~/.config/pikuri/config.toml`, so each must accept every table
the other writes, and a key one shell adds must never stop the other starting. Puri wants none
of that: its own `~/.config/puri/config.toml` holds only what Puri reads, and a key it doesn't
know is an error. The loader is pikuri-web's, copied (`D_port_pikuri_web`). The file is required
and nothing has a default, the titler included: a built-in model tag would be a second, invisible
place a connection comes from, so a missing file fails at once and quotes the example to paste.

## D_titler_model — Why title on the main model with thinking off, after the first answer, rather than on a small model or beside it?

One model stays loaded, and the small instruct models pikuri-web tried failed the job: they
titled in the wrong language, or obeyed the opener instead of naming it. Thinking off makes the
main model cheap enough (`R_llama_server_titles`), so `[titler]` is a second connection to the
same server that differs only in `params`. The Titler's caps and `</think>` strip stay, since a
server can accept that parameter and ignore it. The title is asked once the first turn has ended:
beside it, on a one-slot server, the title wins the permit and the answer waits about a second
for it. The cost is a "New conversation" row until the answer is in. Why no slot is pinned:
pinning the turn lost its cached prefix.
