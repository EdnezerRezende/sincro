# Obsidian Knowledge Graph + MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a standalone project that ingests the `segundo-cerebro` Obsidian vault into a Memgraph graph (with local Ollama embeddings), keeps it current via a file watcher, and exposes read + write access to Claude through a local MCP server.

**Architecture:** A shared `ingest.py` module (parse → embed → upsert) is called by `bootstrap.py` (one-time full walk), `watcher.py` (watchdog daemon, incremental), and `mcp_server.py`'s write tools (in-process, no watcher round-trip). Memgraph stores `Note`/`Tag` nodes and `LINKS_TO`/`TAGGED` edges; embeddings live as a node property and are ranked in Python (brute-force cosine — vault is ~158 notes, no need for a vector index).

**Tech Stack:** Python 3.11+, `neo4j` driver (Bolt, Memgraph-compatible), `python-frontmatter`, `requests` (Ollama HTTP API), `watchdog`, `mcp` (FastMCP), `numpy`, `pytest`. Memgraph via Docker Compose. Ollama installed via Homebrew, model `nomic-embed-text`.

**Spec:** `docs/superpowers/specs/2026-09-12-obsidian-knowledge-graph-design.md`

## Global Constraints

- New code lives entirely in `~/Desenvolvimento/projetos/obsidian-graph/` — a **new, separate project directory**, not inside the `sincro` repo.
- Memgraph Bolt port: **7687**. Memgraph Lab (optional web UI): **3001** (not 3000 — collides with sincro's `backend`).
- Embeddings are **local only**, via Ollama (`http://localhost:11434`, model `nomic-embed-text`) — vault contains personal diary content, nothing leaves the machine.
- Whole-note embeddings only — no chunking (YAGNI per spec).
- No generic "create arbitrary note" MCP tool — only `append_project_diary` and `append_personal_diary`.
- `sync-obsidian-script.sh`, `INSTRUCOES-SYNC-OBSIDIAN.md`, and `obsidian_auto_sync.py` are **unchanged** — unrelated to this project.
- Ingestion must be idempotent (`MERGE`, never `CREATE`) — re-running `bootstrap.py` must not duplicate nodes/relationships.
- Every write tool, after writing to the vault, must (1) call `ingest.py` in-process on the modified file, and (2) append matching entries to both tiers of the vault's log per `_conventions.md` (macroarea log + `resumo_geral`).
- Vault root for this machine: `/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro`.
- Timezone for all vault timestamps: `-03:00`.

---

## Task 1: Project scaffolding + Memgraph via Docker Compose

**Files:**
- Create: `~/Desenvolvimento/projetos/obsidian-graph/docker-compose.yml`
- Create: `~/Desenvolvimento/projetos/obsidian-graph/requirements.txt`
- Create: `~/Desenvolvimento/projetos/obsidian-graph/.gitignore`
- Create: `~/Desenvolvimento/projetos/obsidian-graph/README.md`

**Interfaces:**
- Produces: a running Memgraph instance reachable at `bolt://localhost:7687`, used by every later task via `neo4j.GraphDatabase.driver`.

- [ ] **Step 1: Create the project directory and git repo**

```bash
mkdir -p ~/Desenvolvimento/projetos/obsidian-graph
cd ~/Desenvolvimento/projetos/obsidian-graph
git init
```

- [ ] **Step 2: Write `docker-compose.yml`**

```yaml
services:
  memgraph:
    image: memgraph/memgraph-platform
    restart: unless-stopped
    ports:
      - "7687:7687"
      - "3001:3000"
    volumes:
      - obsidian_graph_memgraph_data:/var/lib/memgraph

volumes:
  obsidian_graph_memgraph_data:
```

- [ ] **Step 3: Write `requirements.txt`**

```text
neo4j>=5.19,<6
python-frontmatter>=1.1,<2
requests>=2.31,<3
watchdog>=4.0,<5
mcp>=1.0,<2
numpy>=1.26,<2
pytest>=8.0,<9
```

- [ ] **Step 4: Write `.gitignore`**

```text
.venv/
__pycache__/
*.pyc
.pytest_cache/
```

- [ ] **Step 5: Create and activate a virtualenv, install dependencies**

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

- [ ] **Step 6: Start Memgraph and verify it's reachable**

```bash
docker compose up -d
python3 -c "
from neo4j import GraphDatabase
d = GraphDatabase.driver('bolt://localhost:7687', auth=None)
d.verify_connectivity()
print('memgraph OK')
d.close()
"
```

Expected: prints `memgraph OK`.

- [ ] **Step 7: Write minimal `README.md`**

```markdown
# obsidian-graph

Ingests the `segundo-cerebro` Obsidian vault into Memgraph (embeddings via
local Ollama) and exposes it to Claude through an MCP server.

## Setup

    brew install ollama
    ollama pull nomic-embed-text
    python3 -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    docker compose up -d
    python3 bootstrap.py "/path/to/segundo-cerebro/Segundo-cerebro"

## Components

- `ingest.py` — shared parse/embed/upsert module
- `bootstrap.py` — one-time full-vault ingestion (idempotent, re-runnable)
- `watcher.py` — watchdog daemon, keeps the graph current
- `mcp_server.py` — MCP server (read + write tools)
```

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: scaffold obsidian-graph project with Memgraph compose"
```

---

## Task 2: `ingest.py` — parsing (frontmatter, wikilinks, tags)

**Files:**
- Create: `~/Desenvolvimento/projetos/obsidian-graph/ingest.py`
- Test: `~/Desenvolvimento/projetos/obsidian-graph/tests/test_wikilinks.py`
- Test: `~/Desenvolvimento/projetos/obsidian-graph/tests/test_frontmatter.py`

**Interfaces:**
- Produces: `parse_note(vault_root: Path, note_path: Path) -> ParsedNote`, dataclass `ParsedNote(path, title, type, domain, status, updated_at, body, links, tags)`. Used by Task 3's `ingest_file`.

- [ ] **Step 1: Write the failing tests**

`tests/test_wikilinks.py`:

```python
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from ingest import parse_note


def _write(tmp_path, name, content):
    p = tmp_path / name
    p.write_text(content, encoding="utf-8")
    return p


def test_simple_wikilink(tmp_path):
    note_path = _write(tmp_path, "a.md", "See [[Other Note]] for details.")
    note = parse_note(tmp_path, note_path)
    assert note.links == ["Other Note"]


def test_aliased_wikilink(tmp_path):
    note_path = _write(tmp_path, "a.md", "See [[Other Note|here]] for details.")
    note = parse_note(tmp_path, note_path)
    assert note.links == ["Other Note"]


def test_heading_wikilink(tmp_path):
    note_path = _write(tmp_path, "a.md", "See [[Other Note#Section]] for details.")
    note = parse_note(tmp_path, note_path)
    assert note.links == ["Other Note"]


def test_no_links(tmp_path):
    note_path = _write(tmp_path, "a.md", "Nothing to see here.")
    note = parse_note(tmp_path, note_path)
    assert note.links == []


def test_duplicate_links_deduplicated(tmp_path):
    note_path = _write(tmp_path, "a.md", "[[X]] and again [[X]].")
    note = parse_note(tmp_path, note_path)
    assert note.links == ["X"]
```

`tests/test_frontmatter.py`:

```python
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from ingest import parse_note


def _write(tmp_path, name, content):
    p = tmp_path / name
    p.write_text(content, encoding="utf-8")
    return p


def test_well_formed_frontmatter(tmp_path):
    content = """---
title: "My Note"
type: concept
domain: engenharia
status: active
updated_at: 2026-09-12
tags:
  - a
  - b
---
Body text with #inline-tag.
"""
    note_path = _write(tmp_path, "note.md", content)
    note = parse_note(tmp_path, note_path)
    assert note.title == "My Note"
    assert note.type == "concept"
    assert note.domain == "engenharia"
    assert note.status == "active"
    assert set(note.tags) == {"a", "b", "inline-tag"}


def test_missing_frontmatter(tmp_path):
    note_path = _write(tmp_path, "plain.md", "Just a body, no frontmatter.")
    note = parse_note(tmp_path, note_path)
    assert note.title == "plain"
    assert note.type is None
    assert note.tags == []


def test_malformed_yaml_does_not_crash(tmp_path):
    content = """---
title: [unclosed
---
Body.
"""
    note_path = _write(tmp_path, "bad.md", content)
    note = parse_note(tmp_path, note_path)
    assert note.title == "bad"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Desenvolvimento/projetos/obsidian-graph
pytest tests/test_wikilinks.py tests/test_frontmatter.py -v
```

Expected: FAIL / ERROR — `ingest.py` (and `parse_note`) don't exist yet.

- [ ] **Step 3: Write `ingest.py` (parsing portion)**

```python
"""Shared ingestion: parse a vault note, embed it, and upsert into Memgraph."""
from __future__ import annotations

import logging
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

import frontmatter

logger = logging.getLogger("ingest")

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://localhost:11434")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
MEMGRAPH_URI = os.environ.get("MEMGRAPH_URI", "bolt://localhost:7687")

WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)")
INLINE_TAG_RE = re.compile(r"(?<!\S)#([A-Za-z0-9_/-]+)")


@dataclass
class ParsedNote:
    path: str
    title: str
    type: str | None
    domain: str | None
    status: str | None
    updated_at: str | None
    body: str
    links: list[str] = field(default_factory=list)
    tags: list[str] = field(default_factory=list)


def parse_note(vault_root: Path, note_path: Path) -> ParsedNote:
    rel_path = str(note_path.relative_to(vault_root))
    try:
        post = frontmatter.load(note_path)
        meta = post.metadata or {}
        body = post.content
    except Exception as exc:
        logger.warning("malformed frontmatter in %s: %s", rel_path, exc)
        meta = {}
        body = note_path.read_text(encoding="utf-8", errors="replace")

    title = meta.get("title") or note_path.stem
    links = list(dict.fromkeys(m.strip() for m in WIKILINK_RE.findall(body)))

    frontmatter_tags = meta.get("tags") or []
    if isinstance(frontmatter_tags, str):
        frontmatter_tags = [frontmatter_tags]
    inline_tags = INLINE_TAG_RE.findall(body)
    tags = sorted(set(frontmatter_tags) | set(inline_tags))

    updated_at = meta.get("updated_at")
    return ParsedNote(
        path=rel_path,
        title=str(title),
        type=meta.get("type"),
        domain=meta.get("domain"),
        status=meta.get("status"),
        updated_at=str(updated_at) if updated_at else None,
        body=body,
        links=links,
        tags=tags,
    )
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
pytest tests/test_wikilinks.py tests/test_frontmatter.py -v
```

Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add ingest.py tests/test_wikilinks.py tests/test_frontmatter.py
git commit -m "feat(ingest): parse frontmatter, wikilinks, and tags from vault notes"
```

---

## Task 3: `ingest.py` — embedding + Memgraph upsert/delete

**Files:**
- Modify: `~/Desenvolvimento/projetos/obsidian-graph/ingest.py`

**Interfaces:**
- Consumes: `ParsedNote`, `MEMGRAPH_URI`, `OLLAMA_URL`, `EMBED_MODEL` from Task 2.
- Produces: `embed_text(text: str) -> list[float] | None`, `get_driver() -> Driver`, `upsert_note(driver, note: ParsedNote, embedding: list[float] | None) -> None`, `delete_note(driver, rel_path: str) -> None`, `ingest_file(vault_root: Path, note_path: Path, driver: Driver | None = None) -> None`. `ingest_file` and `delete_note` are used by `bootstrap.py`, `watcher.py`, and `mcp_server.py`'s write tools.

- [ ] **Step 1: Append to `ingest.py`**

```python
import requests
from neo4j import Driver, GraphDatabase


def embed_text(text: str) -> list[float] | None:
    try:
        resp = requests.post(
            f"{OLLAMA_URL}/api/embeddings",
            json={"model": EMBED_MODEL, "prompt": text},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["embedding"]
    except requests.RequestException as exc:
        logger.warning("Ollama unreachable, skipping embedding: %s", exc)
        return None


def get_driver() -> Driver:
    return GraphDatabase.driver(MEMGRAPH_URI, auth=None)


def upsert_note(driver: Driver, note: ParsedNote, embedding: list[float] | None) -> None:
    with driver.session() as session:
        session.run(
            """
            MERGE (n:Note {path: $path})
            SET n.title = $title, n.type = $type, n.domain = $domain,
                n.status = $status, n.updated_at = $updated_at,
                n.embedding = $embedding, n.exists = true
            """,
            path=note.path, title=note.title, type=note.type, domain=note.domain,
            status=note.status, updated_at=note.updated_at, embedding=embedding,
        )
        for target in note.links:
            session.run(
                """
                MATCH (n:Note {path: $path})
                OPTIONAL MATCH (existing:Note)
                  WHERE existing.exists = true
                    AND (existing.title = $target OR existing.path ENDS WITH $target_md)
                FOREACH (_ IN CASE WHEN existing IS NOT NULL THEN [1] ELSE [] END |
                  MERGE (n)-[:LINKS_TO]->(existing)
                )
                FOREACH (_ IN CASE WHEN existing IS NULL THEN [1] ELSE [] END |
                  MERGE (ghost:Note {title: $target})
                  ON CREATE SET ghost.exists = false
                  MERGE (n)-[:LINKS_TO]->(ghost)
                )
                """,
                path=note.path, target=target, target_md=f"{target}.md",
            )
        for tag in note.tags:
            session.run(
                """
                MATCH (n:Note {path: $path})
                MERGE (t:Tag {name: $tag})
                MERGE (n)-[:TAGGED]->(t)
                """,
                path=note.path, tag=tag,
            )


def delete_note(driver: Driver, rel_path: str) -> None:
    with driver.session() as session:
        session.run("MATCH (n:Note {path: $path}) DETACH DELETE n", path=rel_path)


def ingest_file(vault_root: Path, note_path: Path, driver: Driver | None = None) -> None:
    owns_driver = driver is None
    driver = driver or get_driver()
    try:
        note = parse_note(vault_root, note_path)
        embedding = embed_text(f"{note.title}\n{note.body}")
        upsert_note(driver, note, embedding)
    finally:
        if owns_driver:
            driver.close()
```

- [ ] **Step 2: Manual verification against real Memgraph + Ollama**

```bash
brew list ollama || brew install ollama
ollama list | grep -q nomic-embed-text || ollama pull nomic-embed-text
brew services start ollama 2>/dev/null || ollama serve &

cd ~/Desenvolvimento/projetos/obsidian-graph
mkdir -p /tmp/fixture-vault
cat > /tmp/fixture-vault/a.md <<'EOF'
---
title: "A"
tags: [demo]
---
Links to [[B]].
EOF
cat > /tmp/fixture-vault/b.md <<'EOF'
---
title: "B"
---
No links.
EOF

python3 -c "
from pathlib import Path
from ingest import get_driver, ingest_file
d = get_driver()
ingest_file(Path('/tmp/fixture-vault'), Path('/tmp/fixture-vault/a.md'), driver=d)
ingest_file(Path('/tmp/fixture-vault'), Path('/tmp/fixture-vault/b.md'), driver=d)
with d.session() as s:
    rows = list(s.run('MATCH (n:Note)-[:LINKS_TO]->(m:Note) RETURN n.path, m.path'))
    print(rows)
d.close()
"
```

Expected: prints a row showing `a.md -> b.md` (resolved, not a ghost node, since `b.md` exists and its title `B` matches).

- [ ] **Step 3: Commit**

```bash
git add ingest.py
git commit -m "feat(ingest): embed via Ollama and upsert notes/links/tags into Memgraph"
```

---

## Task 4: `bootstrap.py` — full-vault ingestion + idempotency test

**Files:**
- Create: `~/Desenvolvimento/projetos/obsidian-graph/bootstrap.py`
- Test: `~/Desenvolvimento/projetos/obsidian-graph/tests/test_bootstrap_idempotency.py`

**Interfaces:**
- Consumes: `ingest_file`, `get_driver` from Task 3.
- Produces: `iter_notes(vault_root: Path) -> Iterator[Path]`, `run(vault_root: Path) -> int`. `run` is used directly by the idempotency test; the CLI entry point is used standalone.

- [ ] **Step 1: Write `bootstrap.py`**

```python
"""One-time (and re-runnable, idempotent) full-vault ingestion."""
import argparse
import logging
from pathlib import Path

from ingest import get_driver, ingest_file

logger = logging.getLogger("bootstrap")

IGNORE_DIR_NAMES = {"node_modules", ".git", ".obsidian", ".trash"}


def iter_notes(vault_root: Path):
    for path in vault_root.rglob("*.md"):
        if path.name.startswith("."):
            continue
        rel_parts = path.relative_to(vault_root).parts[:-1]
        if any(part in IGNORE_DIR_NAMES or part.startswith(".") for part in rel_parts):
            continue
        yield path


def run(vault_root: Path) -> int:
    driver = get_driver()
    count = 0
    try:
        for note_path in iter_notes(vault_root):
            ingest_file(vault_root, note_path, driver=driver)
            count += 1
            logger.info("ingested %s", note_path.relative_to(vault_root))
    finally:
        driver.close()
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description="Bootstrap Memgraph from an Obsidian vault")
    parser.add_argument("vault_root", type=Path)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    total = run(args.vault_root)
    print(f"Ingested {total} notes")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Write the idempotency integration test**

```python
"""Integration test: run bootstrap twice against a real vault, expect zero drift.

Requires Memgraph running (docker compose up -d) and VAULT_PATH set:

    VAULT_PATH="/path/to/segundo-cerebro/Segundo-cerebro" pytest tests/test_bootstrap_idempotency.py
"""
import os
from pathlib import Path

import pytest

import bootstrap
from ingest import get_driver

VAULT_PATH = os.environ.get("VAULT_PATH")

pytestmark = pytest.mark.skipif(
    not VAULT_PATH, reason="set VAULT_PATH to run the bootstrap idempotency integration test"
)


def _counts(driver):
    with driver.session() as session:
        notes = session.run("MATCH (n:Note) RETURN count(n) AS c").single()["c"]
        tags = session.run("MATCH (t:Tag) RETURN count(t) AS c").single()["c"]
        rels = session.run("MATCH ()-[r]->() RETURN count(r) AS c").single()["c"]
    return notes, tags, rels


def test_bootstrap_is_idempotent():
    vault_root = Path(VAULT_PATH)
    bootstrap.run(vault_root)
    driver = get_driver()
    try:
        before = _counts(driver)
        bootstrap.run(vault_root)
        after = _counts(driver)
    finally:
        driver.close()
    assert before == after
```

- [ ] **Step 3: Run the full bootstrap against the real vault, then the idempotency test**

```bash
cd ~/Desenvolvimento/projetos/obsidian-graph
python3 bootstrap.py "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro"
VAULT_PATH="/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro" pytest tests/test_bootstrap_idempotency.py -v
```

Expected: first command prints `Ingested <N> notes` (N ≈ 158); the pytest run PASSes.

- [ ] **Step 4: Commit**

```bash
git add bootstrap.py tests/test_bootstrap_idempotency.py
git commit -m "feat(bootstrap): full-vault walk with idempotency integration test"
```

---

## Task 5: `watcher.py` — incremental re-ingestion daemon + launchd plist

**Files:**
- Create: `~/Desenvolvimento/projetos/obsidian-graph/watcher.py`
- Create: `~/Desenvolvimento/projetos/obsidian-graph/launchd/com.ednezer.obsidian-watcher.plist`

**Interfaces:**
- Consumes: `ingest_file`, `delete_note`, `get_driver` from Task 3.
- Produces: a long-lived process; no importable interface consumed by later tasks (mcp_server calls `ingest_file` directly, not through the watcher).

- [ ] **Step 1: Write `watcher.py`**

```python
"""Long-lived watchdog daemon: re-ingests notes on change, removes deleted ones."""
import logging
import sys
import time
from pathlib import Path
from threading import Timer

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

from ingest import delete_note, get_driver, ingest_file

logger = logging.getLogger("watcher")
DEBOUNCE_SECONDS = 2.0


class NoteEventHandler(FileSystemEventHandler):
    def __init__(self, vault_root: Path):
        self.vault_root = vault_root
        self.driver = get_driver()
        self._pending: dict[str, Timer] = {}

    def _debounced(self, key: str, action) -> None:
        existing = self._pending.get(key)
        if existing:
            existing.cancel()
        timer = Timer(DEBOUNCE_SECONDS, action)
        self._pending[key] = timer
        timer.start()

    def on_created(self, event):
        self._handle_change(event)

    def on_modified(self, event):
        self._handle_change(event)

    def on_deleted(self, event):
        if event.is_directory or not event.src_path.endswith(".md"):
            return
        path = Path(event.src_path)
        rel_path = str(path.relative_to(self.vault_root))
        self._debounced(str(path), lambda: self._delete(rel_path))

    def _handle_change(self, event):
        if event.is_directory or not event.src_path.endswith(".md"):
            return
        path = Path(event.src_path)
        self._debounced(str(path), lambda: self._ingest(path))

    def _ingest(self, path: Path) -> None:
        try:
            ingest_file(self.vault_root, path, driver=self.driver)
            logger.info("re-ingested %s", path.relative_to(self.vault_root))
        except Exception:
            logger.exception("failed to ingest %s", path)

    def _delete(self, rel_path: str) -> None:
        try:
            delete_note(self.driver, rel_path)
            logger.info("deleted %s", rel_path)
        except Exception:
            logger.exception("failed to delete %s", rel_path)


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    if len(sys.argv) != 2:
        print("usage: watcher.py <vault_root>")
        sys.exit(1)
    vault_root = Path(sys.argv[1]).resolve()
    handler = NoteEventHandler(vault_root)
    observer = Observer()
    observer.schedule(handler, str(vault_root), recursive=True)
    observer.start()
    logger.info("watching %s", vault_root)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Manual verification**

```bash
cd ~/Desenvolvimento/projetos/obsidian-graph
python3 watcher.py "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro" &
WATCHER_PID=$!
sleep 1
echo "teste watcher $(date)" >> "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro/08_daily/_watcher_test.md"
sleep 4
python3 -c "
from ingest import get_driver
d = get_driver()
with d.session() as s:
    row = s.run(\"MATCH (n:Note {path: '08_daily/_watcher_test.md'}) RETURN n.title\").single()
    print(row)
d.close()
"
rm "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro/08_daily/_watcher_test.md"
sleep 4
kill $WATCHER_PID
```

Expected: the query prints a row (the test note was ingested within the debounce window).

- [ ] **Step 3: Write the launchd plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ednezer.obsidian-watcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Users/ed/Desenvolvimento/projetos/obsidian-graph/.venv/bin/python3</string>
        <string>/Users/ed/Desenvolvimento/projetos/obsidian-graph/watcher.py</string>
        <string>/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/ed/Desenvolvimento/projetos/obsidian-graph</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/obsidian-watcher.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/obsidian-watcher.err</string>
</dict>
</plist>
```

Note the plist points at the venv's own `python3` (not `/usr/bin/env python3`) so `watchdog`/`neo4j`/`requests` are importable when launchd runs it outside any shell profile.

- [ ] **Step 4: Add install instructions to `README.md`**

```markdown
## Auto-start the watcher on login

    cp launchd/com.ednezer.obsidian-watcher.plist ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.ednezer.obsidian-watcher.plist
```

- [ ] **Step 5: Commit**

```bash
git add watcher.py launchd/com.ednezer.obsidian-watcher.plist README.md
git commit -m "feat(watcher): watchdog daemon with debounce + launchd install"
```

---

## Task 6: `mcp_server.py` — read tools

**Files:**
- Create: `~/Desenvolvimento/projetos/obsidian-graph/mcp_server.py`

**Interfaces:**
- Consumes: `embed_text`, `get_driver` from Task 3; reads `VAULT_ROOT` env var.
- Produces: MCP tools `semantic_search`, `get_note`, `get_neighbors`, `find_by_tag`, plus the `mcp` `FastMCP` instance and helpers `_cosine`, `VAULT_ROOT`, `TZ` consumed by Task 7's write tools.

- [ ] **Step 1: Write `mcp_server.py` (read tools)**

```python
"""MCP server exposing read/write tools over the Obsidian vault graph."""
import logging
import os
from datetime import timedelta, timezone
from pathlib import Path

import numpy as np
from mcp.server.fastmcp import FastMCP

from ingest import embed_text, get_driver

logger = logging.getLogger("mcp_server")

VAULT_ROOT = Path(os.environ["VAULT_ROOT"])
TZ = timezone(timedelta(hours=-3))

mcp = FastMCP("obsidian-graph")


def _cosine(a: list[float], b: list[float]) -> float:
    va, vb = np.array(a), np.array(b)
    denom = np.linalg.norm(va) * np.linalg.norm(vb)
    return float(np.dot(va, vb) / denom) if denom else 0.0


@mcp.tool()
def semantic_search(query: str, top_k: int = 10) -> list[dict]:
    """Busca semantica nas notas do vault usando embeddings locais (Ollama)."""
    query_embedding = embed_text(query)
    if query_embedding is None:
        return []
    driver = get_driver()
    try:
        with driver.session() as session:
            rows = session.run(
                "MATCH (n:Note {exists: true}) WHERE n.embedding IS NOT NULL "
                "RETURN n.path AS path, n.title AS title, n.embedding AS embedding"
            )
            scored = [
                {
                    "path": row["path"],
                    "title": row["title"],
                    "score": _cosine(query_embedding, row["embedding"]),
                }
                for row in rows
            ]
    finally:
        driver.close()
    scored.sort(key=lambda r: r["score"], reverse=True)
    top = scored[:top_k]
    for item in top:
        full_path = VAULT_ROOT / item["path"]
        text = full_path.read_text(encoding="utf-8", errors="replace")
        item["snippet"] = text[:280]
    return top


@mcp.tool()
def get_note(path: str) -> dict:
    """Retorna metadados e corpo de uma nota pelo caminho relativo ao vault."""
    full_path = VAULT_ROOT / path
    if not full_path.exists():
        return {"error": f"note not found: {path}"}
    driver = get_driver()
    try:
        with driver.session() as session:
            row = session.run("MATCH (n:Note {path: $path}) RETURN n AS n", path=path).single()
    finally:
        driver.close()
    metadata = dict(row["n"]) if row else {}
    metadata.pop("embedding", None)
    metadata["body"] = full_path.read_text(encoding="utf-8", errors="replace")
    return metadata


@mcp.tool()
def get_neighbors(path: str, depth: int = 1) -> dict:
    """Retorna a vizinhanca LINKS_TO/TAGGED de uma nota ate `depth` saltos."""
    depth = max(1, min(int(depth), 5))
    driver = get_driver()
    try:
        with driver.session() as session:
            rows = session.run(
                f"""
                MATCH (n:Note {{path: $path}})-[r:LINKS_TO|TAGGED*1..{depth}]-(neighbor)
                RETURN DISTINCT neighbor.path AS path, neighbor.title AS title,
                       labels(neighbor) AS labels
                """,
                path=path,
            )
            neighbors = [dict(row) for row in rows]
    finally:
        driver.close()
    return {"path": path, "neighbors": neighbors}


@mcp.tool()
def find_by_tag(tag: str) -> list[dict]:
    """Lista notas marcadas com uma tag especifica."""
    driver = get_driver()
    try:
        with driver.session() as session:
            rows = session.run(
                "MATCH (n:Note {exists: true})-[:TAGGED]->(:Tag {name: $tag}) "
                "RETURN n.path AS path, n.title AS title",
                tag=tag,
            )
            return [dict(row) for row in rows]
    finally:
        driver.close()
```

- [ ] **Step 2: Manual verification (after Task 4's bootstrap has run against the real vault)**

```bash
cd ~/Desenvolvimento/projetos/obsidian-graph
VAULT_ROOT="/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro" python3 -c "
from mcp_server import semantic_search, find_by_tag
print(semantic_search('convenções de nomenclatura da wiki', top_k=3))
print(find_by_tag('governanca'))
"
```

Expected: `semantic_search` returns a ranked list whose top hit is `_conventions.md`; `find_by_tag` includes it too.

- [ ] **Step 3: Commit**

```bash
git add mcp_server.py
git commit -m "feat(mcp): read tools — semantic_search, get_note, get_neighbors, find_by_tag"
```

---

## Task 7: `mcp_server.py` — write tools (diary + two-tier logging)

**Files:**
- Modify: `~/Desenvolvimento/projetos/obsidian-graph/mcp_server.py`

**Interfaces:**
- Consumes: `mcp`, `VAULT_ROOT`, `TZ` from Task 6; `ingest_file` from Task 3.
- Produces: MCP tools `append_project_diary(entry: str, project: str = "sincro") -> dict`, `append_personal_diary(entry: str, date: str | None = None) -> dict`; `main()` entry point that runs the server.

- [ ] **Step 1: Append to `mcp_server.py`**

```python
from datetime import datetime

from ingest import ingest_file

LOG_DIR = VAULT_ROOT / "03_agente" / "07_logs"


def _now() -> datetime:
    return datetime.now(TZ)


def _append_macroarea_log(macroarea: str, acao: str, origem: str, destino: str,
                           subpasta: str, arquivo: str, criterio: str,
                           impacto: str, observacao: str) -> None:
    log_path = LOG_DIR / macroarea / f"{_now():%Y-%m}.md"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    entry = (
        f"\n## {_now():%Y-%m-%dT%H:%M:%S}-03:00\n"
        f"Ação: {acao}\n"
        f"Origem: `{origem}`\n"
        f"Destino: `{destino}`\n"
        f"Subpasta: {subpasta}\n"
        f"Arquivo: {arquivo}\n"
        f"Responsável: Ednezer\n"
        f"Critério: {criterio}\n"
        f"Impacto: {impacto}\n"
        f"Observação: {observacao}\n"
    )
    with log_path.open("a", encoding="utf-8") as f:
        f.write(entry)


def _append_resumo_geral(macroarea: str, acao: str, item: str, resultado: str) -> None:
    log_path = LOG_DIR / "resumo_geral" / f"{_now():%Y-%m}.md"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    entry = (
        f"\n## {_now():%Y-%m-%dT%H:%M:%S}-03:00\n"
        f"Área: {macroarea}\n"
        f"Ação: {acao}\n"
        f"Item: `{item}`\n"
        f"Resultado: {resultado}\n"
    )
    with log_path.open("a", encoding="utf-8") as f:
        f.write(entry)


@mcp.tool()
def append_project_diary(entry: str, project: str = "sincro") -> dict:
    """Anexa uma entrada datada ao diário de progresso do projeto no vault."""
    rel_path = Path("02_work") / "projetos" / project / "07 - Status Atual & Backlog em Andamento.md"
    full_path = VAULT_ROOT / rel_path
    if not full_path.exists():
        return {"error": f"diary file not found: {rel_path}"}

    text = full_path.read_text(encoding="utf-8")
    section_header = "## 📔 Diário de Atualizações"
    date_header = f"### {_now():%Y-%m-%d}"
    block = f"{date_header}\n{entry}\n"

    if section_header not in text:
        text = text.rstrip() + f"\n\n{section_header}\n\n{block}"
    else:
        head, _, tail = text.partition(section_header)
        text = f"{head}{section_header}{tail.rstrip()}\n\n{block}"

    full_path.write_text(text, encoding="utf-8")
    ingest_file(VAULT_ROOT, full_path)
    _append_macroarea_log(
        macroarea="02_work", acao="atualizacao", origem="mcp_server.append_project_diary",
        destino=str(rel_path), subpasta=f"projetos/{project}",
        arquivo=full_path.name, criterio="entrada de diário de progresso via MCP",
        impacto="baixo", observacao=entry[:120],
    )
    _append_resumo_geral(
        macroarea="02_work", acao="atualizacao", item=str(rel_path),
        resultado=f"diário do projeto {project} atualizado via MCP",
    )
    return {"path": str(rel_path), "written": True}


@mcp.tool()
def append_personal_diary(entry: str, date: str | None = None) -> dict:
    """Cria ou anexa uma entrada ao diário pessoal do dia em 08_daily/."""
    day = date or f"{_now():%Y-%m-%d}"
    rel_path = Path("08_daily") / f"{day}.md"
    full_path = VAULT_ROOT / rel_path
    full_path.parent.mkdir(parents=True, exist_ok=True)

    if not full_path.exists():
        frontmatter_block = (
            "---\n"
            f'title: "{day}"\n'
            "type: daily\n"
            f"created_at: {day}T{_now():%H:%M:%S}-03:00\n"
            "owner: Ednezer\n"
            "tags:\n"
            "  - daily\n"
            "---\n\n"
        )
        full_path.write_text(frontmatter_block, encoding="utf-8")

    with full_path.open("a", encoding="utf-8") as f:
        f.write(f"- {_now():%H:%M} {entry}\n")

    ingest_file(VAULT_ROOT, full_path)
    _append_macroarea_log(
        macroarea="08_daily", acao="atualizacao", origem="mcp_server.append_personal_diary",
        destino=str(rel_path), subpasta="", arquivo=full_path.name,
        criterio="entrada de diário pessoal via MCP", impacto="baixo",
        observacao=entry[:120],
    )
    _append_resumo_geral(
        macroarea="08_daily", acao="atualizacao", item=str(rel_path),
        resultado="diário pessoal atualizado via MCP",
    )
    return {"path": str(rel_path), "written": True}


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Manual verification**

```bash
cd ~/Desenvolvimento/projetos/obsidian-graph
VAULT_ROOT="/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro" python3 -c "
from mcp_server import append_personal_diary
print(append_personal_diary('teste de escrita via MCP — pode apagar esta linha'))
"
tail -n 5 "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro/08_daily/$(date +%Y-%m-%d).md"
tail -n 8 "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro/03_agente/07_logs/08_daily/$(date +%Y-%m).md"
tail -n 5 "/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro/03_agente/07_logs/resumo_geral/$(date +%Y-%m).md"
```

Expected: the daily note has the test entry; both log tiers have a matching entry. **Manually remove the test line from all three files afterward** — this step writes into the real vault.

- [ ] **Step 3: Commit**

```bash
git add mcp_server.py
git commit -m "feat(mcp): write tools — append_project_diary, append_personal_diary, two-tier logging"
```

---

## Task 8: Register the MCP server with Claude Code

**Files:**
- Modify: user's Claude Code MCP config (`~/.claude.json` or via `claude mcp add`, whichever this installation uses).

**Interfaces:**
- Consumes: `mcp_server.py`'s `main()` entry point from Task 7.
- Produces: nothing consumed by other tasks — this is the final wiring step.

- [ ] **Step 1: Register the server**

```bash
claude mcp add obsidian-graph \
  --env VAULT_ROOT="/Users/ed/Library/CloudStorage/OneDrive-Pessoal/Documentos/obsidian/segundo-cerebro/Segundo-cerebro" \
  -- /Users/ed/Desenvolvimento/projetos/obsidian-graph/.venv/bin/python3 \
     /Users/ed/Desenvolvimento/projetos/obsidian-graph/mcp_server.py
```

- [ ] **Step 2: Verify registration**

```bash
claude mcp list
```

Expected: `obsidian-graph` appears in the list, reachable.

- [ ] **Step 3: Restart Claude Code and manually invoke `semantic_search` once**

Confirm the tool shows up and returns results for a real query about the vault.

No commit — this step changes local Claude Code configuration, not the project repo.
