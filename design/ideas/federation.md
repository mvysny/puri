# Federation, in v2: several agents in one popup, the human routing between them

Goal: v1 is **one agent**, less capable than Siri, holding the whole tool set of
`trifecta-and-tools.md`. Once it works, brainstorm whether it should split into a *federation*
(pikuri's `design/ideas/assistant.md`): separate agents with separate contexts, memories and
toolsets, addressed by name, and the human as the only router between them. Nothing here is for v1.

## Why it's worth a v2 look

pikuri's argument: no agent holds all three trifecta legs, because nothing carries text from one
to another but the human. The v1 agent holds all three (mail is untrusted, notes are private,
search is egress) and stays safe only because its egress is vouched. A federation could buy
back what v1 gives up:

- **A web agent that can fetch.** `@web` holds `fetch` and `web_scrape` and nothing private; the
  user carries its answer to the main agent. That's the "v2 researcher" of
  `trifecta-and-tools.md`, without the taint machinery.
- **An untrusted-free notes agent.** `@notes` reads and writes notes but never mail or the web, so
  stored injection has no way in except through the user's own words. Then its writes could go
  unconfirmed.
- **pikuri-tui-computer is already a member**, as a separate binary (`@os`).

## Why it may not survive

pikuri's own note says the existential risk is over-securing into uselessness. Siri's appeal is one
box that does everything; "ask `@mail`, then copy to `@notes`" is the opposite. What v1 practice
should measure: how often does a request need two legs the federation would split? "Summarize
today's mail into a note" is exactly such a request.

## How it might look in this UI

- An `@name` prefix in the entry, completed from a popup list; the transcript marks which agent
  answered.
- One conversation per agent, or one conversation with several agents taking turns? Taking turns
  in one transcript makes the human-router invisible: the model of agent B sees agent A's reply in
  its own context, which *is* the propagation the federation exists to prevent. So probably
  separate contexts, shown side by side or as tabs.
- A "send to `@notes`" button on a reply: the human routing, made cheap. The human still sees and
  edits what gets carried.

## Open questions

- `Q_split_signal`: what v1 metric says "split now"? Count requests refused or gated because of a
  leg the agent shouldn't have?
- `Q_shared_context`: one transcript or one per agent (see above)?
- `Q_members`: which members first — `@web` alone (the cheapest win) or the full split?
