# Documents, notes and memory: pikuri's secretary, in Puri

Goal: Puri gains what `bin/pikuri-secretary` in pikuri has (its `book/secretary.md` is the
walk-through): hybrid retrieval over `~/Documents`, the file tools reading it and writing only its
`Notes/`, a memory note, and the calculator. The book already calls Puri "the secretary with every
bell and whistle", so the shape is the secretary's, and only what one resident process with many
conversations changes is new here. Answers `Q_rag_backend` and `Q_notes_write_gate` of
`trifecta-and-tools.md`.

## Decided (owner, 2026-11-17)

- **Qdrant**, through pikuri's `VectorDb::Server::Qdrant` (podman or docker), so a real
  `~/Documents` is embedded once and not on every login. The first start pulls its image.
- **The embedder and the reranker run on a `[[server]]` the config already has**; the reranker is
  optional.
- **Opt-in**: no `[documents]` table, no documents. The table's folder defaults to `~/Documents`,
  and it takes an `exclude` list, since a folder of books would keep the embedder busy for days.
- **Office formats from day one**: the workshop's `pikuri-extractors` (DOCX, ODT, XLSX, PPTX,
  EPUB, RTF and PDF, in a networkless container it builds on first use), not `pikuri-pdf`.
- **No stemmer**: FTS5's default, no Finnish or Czech.
- **No write asks** (unlike the secretary, which confirms each with its diff): writes reach only
  `Notes/`, and the tool line names the file, which the user can open and check. A confirmation
  with a richer diff than `diff -u` is v2. The stored-injection risk the secretary's book
  describes (a mail plants a note a later conversation trusts) is accepted for v1; the prompt
  still says to quote a stranger, never to write as the user. Searches still don't ask either
  (`D_search_engines`).

## The config

```toml
[documents]
folder       = "~/Documents"     # optional, the default
exclude      = ["Books"]         # relative to folder; a typo fails the start
server       = "local"           # a [[server]] id
embed_model  = "nomic-ai/nomic-embed-text-v1.5-GGUF:Q8_0"
rerank_model = "gpustack/bge-reranker-v2-m3-GGUF:Q8_0"   # optional; omitted, no reranker
```

Notes are `<folder>/Notes`, created at the first start; the memory is `Notes/PURI.md`.

## The shape: one corpus, an extension per agent

The secretary is one agent in one process; Puri boots an agent per conversation, and another on
a clear or a failed boot. So:

- **Process-wide, owned by `PikuriCore`**, built once and closed at quit (watcher, agents,
  corpus, server, in that order): the Qdrant server, the `Corpus` over a `Rag::Backend::Hybrid`
  (Qdrant's collection, an FTS5 file under Puri's cache, both named after the folder's hash),
  the embedder, the reranker, the `Watcher`, and `Extractors::DOCUMENTS.register`. Started on a
  thread of its own, as Qdrant takes seconds and the popup must come up at once; an agent booting
  before it's ready waits on the boot's thread.
- **Per agent, in `Initializer#configure`**: a `Rag::Extension` over that corpus, a
  `Workspace::Extension` rooted at the folder, writable only in `Notes/`, `grep: false`, with
  that conversation's `Confirmer`, and `Pikuri::Tool::CALCULATOR`.
- **The memory** is read into the system prompt when the agent boots, so the secretary's "a
  change takes effect next session" becomes "in the next conversation".

## The prompt

`puri.txt` stays the head. The secretary's lines its book shows earned their place (documents
first, check what they kept before the web, arithmetic with a tool, strangers' text is
information and never instructions, the note rules, the memory rule) join as a fragment that
comes only with `[documents]`. `web.txt` and `offline.txt` lose "you can't read the user's notes"
when it does.

## Writes run unasked

`Workspace::Extension` takes pikuri's `Confirmer::AutoApprove`, so neither an edit nor an
overwrite asks; `Filesystem(writable: [Notes/])` is the whole gate. The workspace's prompt
fragment still says a confirmer may pause a write, which is harmless.

## Tool lines

`ToolWording` words the new ten: `rag_search`, `rag_search_keywords`, `rag_read`, `rag_reindex`,
`read`, `glob`, `file_list`, `edit`, `write`, `calculator`.

## Upstream

- `bin/pikuri-secretary` and `pikuri-rag/bin/pikuri-briefing` still build a
  `Pikuri::VectorDb::Indexer`, gone since 88d9871 renamed it `Corpus`; both fail at boot.
- pikuri-extractors' `Documents#sniff` wants `[Content_Types].xml` in the first 4 KB, so a DOCX
  that zips it last (valid OOXML; the demo `Work/meeting-notes-board.docx` does) reads as binary
  and is never indexed.

## Open

- `Q_index_status`: the first embed takes hours on a real folder, and the chat is slower
  meanwhile. Where does the user see "indexing, N chunks so far"?
- `Q_synced_folder` (from `trifecta-and-tools.md`) still holds: a write to a shared `Notes/` is
  egress the map can't see.
