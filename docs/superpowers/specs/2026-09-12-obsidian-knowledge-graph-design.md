# Obsidian Knowledge Graph + MCP Server — Design

- Status: draft
- Owner: Ednezer
- Date: 2026-09-12

## Motivation

Ednezer wants a "living" knowledge base built from his Obsidian vault
(`segundo-cerebro`) that:

1. Can be queried semantically and structurally by Claude (via MCP).
2. Keeps a diary of progress on the `sincro` project (this repo),
   written back into the vault as work happens.
3. Keeps a personal diary of other day-to-day activities, also written
   back into the vault.

This requires ingesting the vault's ~158 notes into a graph database
(embeddings for semantic search, wikilinks as graph edges), keeping
that ingestion current as notes change, and exposing both query and
write capability to Claude through a local MCP server.

## Decisions already confirmed with the user

- Graph database: **Memgraph** (not Neo4j — the original request named
  both; user picked Memgraph).
- Embeddings: **local, via Ollama** (privacy — vault contains personal
  diary content). Ollama is not currently installed on this machine;
  installing it is part of this project's setup, not a blocker to the
  design.
- MCP server scope: **read + write** (semantic search / graph queries,
  plus writing new diary entries back into the vault).
- Re-ingestion after the initial bootstrap: **automatic file watcher**.
- Code location: a **new, separate project directory**
  (`~/Desenvolvimento/projetos/obsidian-graph/`), not inside this repo.
- Existing `sync-obsidian-script.sh` / `INSTRUCOES-SYNC-OBSIDIAN.md`
  automation (repo docs → `sincro-sync/` folder): **unchanged**,
  unrelated to this project.
- Project-diary entries: appended to the existing
  `02_work/projetos/sincro/07 - Status Atual & Backlog em Andamento.md`.
- Personal-diary entries: written to `08_daily/` (currently empty —
  no pre-existing convention to match, so this design defines a
  minimal one consistent with `_conventions.md`).

## Architecture

```
Obsidian vault (segundo-cerebro)
        │
        │ read/write .md files
        ▼
┌───────────────────┐        ┌─────────────┐
│  watcher.py        │──────▶│  ingest.py   │──────▶ Memgraph (Bolt :7687)
│  (watchdog, daemon) │       │ (parse, embed, │
└───────────────────┘        │  link, upsert) │
                              └──────┬───────┘
                                     │ Cypher
                                     ▼
                        ┌────────────────────────┐
                        │  mcp_server.py           │◀── Claude (MCP client)
                        │  read tools + write tools│
                        └───────────┬──────────────┘
                                    │ write tools also call ingest.py
                                    │ directly (no watcher round-trip)
                                    ▼
                          Obsidian vault (diary files)

Ollama (localhost:11434, nomic-embed-text) — called by ingest.py
```

All new code lives in a standalone project,
`~/Desenvolvimento/projetos/obsidian-graph/`, structured as:

```
obsidian-graph/
├── docker-compose.yml       # memgraph (+ optional memgraph-lab)
├── ingest.py                # shared: parse note, embed, upsert to graph
├── bootstrap.py             # one-time full-vault ingestion (uses ingest.py)
├── watcher.py                # watchdog daemon, calls ingest.py per file event
├── mcp_server.py              # MCP server: read + write tools
├── launchd/
│   └── com.ednezer.obsidian-watcher.plist
├── requirements.txt
└── tests/
    ├── test_wikilinks.py
    └── test_frontmatter.py
```

## Components

### 1. `docker-compose.yml`

Single `memgraph` service (image `memgraph/memgraph-platform` or plain
`memgraph/memgraph`), Bolt protocol exposed on **7687** (Memgraph's
default — no collision with sincro's ports 3000/5433/8080). Optional
`memgraph-lab` web UI on **3001** (avoids sincro's `backend` on 3000).
Named volume for persistence, so re-running `docker compose up` never
re-triggers a full re-ingestion.

### 2. `ingest.py` — shared ingestion module

Given a note's absolute path:

1. Read file, split YAML frontmatter from body (`python-frontmatter`
   or a small manual parser).
2. Extract `[[wikilinks]]` from the body via regex (`\[\[([^\]|#]+)`,
   handling the `[[Target|Alias]]` and `[[Target#Heading]]` forms by
   taking `Target`).
3. Extract `#tags` — both frontmatter `tags:` list and inline
   `#hashtag` occurrences in the body.
4. Call Ollama's embeddings endpoint (`nomic-embed-text`) with the
   **whole note** (frontmatter fields relevant to meaning + body) —
   one vector per note, no chunking.
5. Upsert into Memgraph via idempotent Cypher:
   ```cypher
   MERGE (n:Note {path: $path})
   SET n.title = $title, n.type = $type, n.domain = $domain,
       n.status = $status, n.updated_at = $updated_at,
       n.embedding = $embedding, n.exists = true
   ```
6. For each extracted wikilink target, resolve to a vault path if a
   matching note exists; otherwise `MERGE` a **ghost node**
   (`Note {title: $target, exists: false}` — no `path`). Create
   `MERGE (n)-[:LINKS_TO]->(target)`.
7. For each tag, `MERGE (t:Tag {name: $tag})` and
   `MERGE (n)-[:TAGGED]->(t)`.
8. On note deletion: `MATCH (n:Note {path: $path}) DETACH DELETE n`
   (ghost nodes for links pointing at the deleted note are left as-is
   — they'll just point at nothing until/unless recreated).

Idempotent by design — safe to call repeatedly for the same file.

### 3. `bootstrap.py`

Walks the vault root, calls `ingest.py` for every `.md` file (skipping
the same ignore patterns as the existing `obsidian_auto_sync.py`:
dotfiles, `node_modules`, etc., plus this project's own output if it
ever lived inside the vault, which it won't). Prints a summary count
at the end. This is also the integration test — see Testing below.

### 4. `watcher.py`

`watchdog` `Observer` on the vault root. On `created`/`modified`
events for `.md` files: debounce (e.g. 2s window per path, since
editors often fire multiple events per save) then call `ingest.py`.
On `deleted`: call the delete path in `ingest.py`. Runs as a long-lived
process; ships with a `launchd` plist (same pattern as
`INSTRUCOES-SYNC-OBSIDIAN.md` already uses) so the user can install it
to auto-start on login, independent of this conversation/session.

### 5. `mcp_server.py`

**Read tools:**
- `semantic_search(query: str, top_k: int = 10)` — embed the query via
  Ollama, fetch all `(:Note {exists: true})` embeddings from Memgraph,
  rank by cosine similarity in Python, return top-k `{path, title,
  score, snippet}`.
- `get_note(path: str)` — return a note's metadata + body.
- `get_neighbors(path: str, depth: int = 1)` — `LINKS_TO`/`TAGGED`
  neighborhood via Cypher variable-length path.
- `find_by_tag(tag: str)` — notes with a given tag.

**Write tools:**
- `append_project_diary(entry: str, project: str = "sincro")` —
  appends a dated entry under a `## 📔 Diário de Atualizações` section
  (created if missing) in
  `02_work/projetos/<project>/07 - Status Atual & Backlog em Andamento.md`.
  Entry format:
  ```markdown
  ### 2026-09-12
  <entry text>
  ```
- `append_personal_diary(entry: str, date: str | None = None)` —
  creates/appends `08_daily/YYYY-MM-DD.md` (defaulting to today).
  New-file frontmatter:
  ```yaml
  ---
  title: "YYYY-MM-DD"
  type: daily
  created_at: YYYY-MM-DDTHH:mm:ss-03:00
  owner: Ednezer
  tags:
    - daily
  ---
  ```
  followed by a bulleted or timestamped entry list.

Both write tools, after writing to the vault:
1. Call `ingest.py` directly on the modified file (graph stays current
   without waiting for the watcher).
2. Append a matching entry to the vault's two-tier log per
   `_conventions.md` (`03_agente/07_logs/02_work/YYYY-MM.md` using the
   macroarea template, action `atualizacao`, plus a condensed line in
   `03_agente/07_logs/resumo_geral/YYYY-MM.md`).

No generic "create arbitrary note" tool — only these two diary
writers, matching what was actually requested.

## Data flow summary

- **Obsidian edit → graph**: watcher detects change → `ingest.py` →
  Memgraph updated.
- **Claude query → answer**: MCP read tool → Cypher / brute-force
  cosine → result.
- **Claude "log this" → vault + graph**: MCP write tool → file written
  to vault → `ingest.py` called in-process → vault log updated.

## Error handling

- Ollama unreachable during ingestion: log a warning, upsert the note
  without an embedding (metadata/links still update), leave
  `embedding: null`. A note with no embedding is simply excluded from
  `semantic_search` ranking until the next successful ingestion.
- Malformed/missing frontmatter: parse best-effort (missing fields
  become `null`), log a warning, never crash the watcher loop or
  bootstrap run.
- Memgraph unreachable: ingestion calls raise and are logged; the
  watcher keeps running and will naturally retry on the next file
  event (or `bootstrap.py` can be re-run once Memgraph is back).

## Testing

- **Integration**: run `bootstrap.py` against the real vault, then run
  it again — assert the second run creates zero additional `Note` or
  `Tag` nodes and zero additional relationships (idempotency check via
  a Cypher count query before/after).
- **Unit**: `test_wikilinks.py` (parsing `[[Target]]`,
  `[[Target|Alias]]`, `[[Target#Heading]]`, plus notes with no links);
  `test_frontmatter.py` (well-formed frontmatter, missing frontmatter,
  malformed YAML).

## Out of scope (YAGNI)

- Section/chunk-level embeddings — whole-note only, revisit if notes
  grow long.
- Memgraph's native vector index (MAGE) — brute-force cosine is fast
  enough at ~158 notes.
- A generic "create/edit arbitrary note" MCP tool.
- Any change to `sync-obsidian-script.sh`, `INSTRUCOES-SYNC-OBSIDIAN.md`,
  or `obsidian_auto_sync.py`.

## Open setup step

Ollama is not installed on this machine. The implementation plan must
include installing it (`brew install ollama`) and pulling
`nomic-embed-text` as a setup step before `bootstrap.py` can run.
