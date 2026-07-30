# AGENTS_master.md

---

## Purpose & Scope

This document defines the operating instructions for autonomous coding agents and humans collaborating with them in the harbor_heist repository.

Project-local instructions in this file take precedence over shared skill-library defaults when there is a conflict.

---

## Project Overview

**Project Name:** harbor_heist

**Description:** Harbor Heist is a server-authoritative multiplayer fishing/aquarium tycoon game with PvP raids, fully implemented with 17 server services, persistence, analytics, anti-exploit
  hardening, and mobile UI, currently in closed V1 test phase with recent critical bug fixes (analytics API, quest hooks, stun exploit) and ready for launch pending final
  balance/decision finalization.

---

## Absolute Safety Rules

### No Deletions Without Explicit Permission

You may **NOT delete any file or directory** unless the user explicitly gives the exact deletion command **in the current session**.

This includes files you just created, temporary/test/generated files,
scripts, and directories that merely appear safe to remove.

If you think something should be removed, stop and ask. You must receive clear written approval before any deletion command is proposed or executed.

Forbidden without explicit approval: `git reset --hard`, `git clean -fd`,
`rm -rf`, and ANY command that can delete or overwrite code or data, or
perform a destructive git operation.

If unsure, ask first. Prefer safe inspection and preservation commands such as:

```bash
git status
git diff
git stash
```

---

## Required Session Startup Workflow

### 1. Register and Check Coordination State

Agent Mail is the multi-agent coordination server (messaging + advisory file
reservations). Use the project-local Python CLI `agent_mail_cli.py` (in the
repo root) for all Agent Mail operations. It is cross-platform, returns JSON,
and handles project-key resolution for you. Do NOT use the legacy
`am_*` shell helpers — they are deprecated for this project.

**Key facts (read before your first command):**

| Fact | Value |
| --- | --- |
| Server URL | `http://127.0.0.1:8765/mcp/` (override: `AGENT_MAIL_URL`) |
| Canonical project key | `home-ubuntu-developer-roblox` (CLI default; override: `AGENT_MAIL_PROJECT`) |
|| Your agent name | ASSIGNED BY THE SERVER at registration — it may differ from the hint you requested. Always use the returned name. |
|| Your token | The `registration_token` returned ONCE at registration. Required for `inbox`, `send`, `reserve`, `release`. It cannot be recovered — persist it (Step 1). |

#### Step 0 — Verify the server is up

```bash
python3 agent_mail_cli.py health
```

Expected: `"status": "healthy"`. If you get `Connection refused`, start the
server (it requires a SQLite DATABASE_URL — the global PostgreSQL one will
crash it on startup):

```bash
cd ~/mcp_agent_mail && DATABASE_URL="sqlite+aiosqlite:///$HOME/.mcp_agent_mail/storage.sqlite3" \
  nohup uv run python -m mcp_agent_mail.cli serve-http > /tmp/agent_mail_server.log 2>&1 &
cd - && sleep 8 && python3 agent_mail_cli.py health
```

Never run `mcp-agent-mail` or `agent-mail` directly as CLI tools — they are
launchers only and will just print a usage banner.

#### Step 1 — Resume or register your identity

FIRST check for saved credentials — the repo-root `.agent_mail_env` persists
an identity across sessions:

```bash
cat .agent_mail_env
```

- If it names an agent that is still ACTIVE (non-retired in the `agents`
  list), source and verify it:
  ```bash
  source .agent_mail_env
  python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" 10 false true
  ```
  A JSON inbox = identity resumed, skip registration. An auth error = stale
  creds; re-register below. The file may also hold a DIFFERENT, retired
  agent's creds — never assume it is yours.
- Otherwise register fresh (`session-start` = register + list agents + inbox
  check in one shot):

```bash
python3 agent_mail_cli.py session-start "YourNameHint" "abacusai"
```

The JSON response contains your ASSIGNED `agent_name` and your
`registration_token`. Persist both IMMEDIATELY by overwriting
`.agent_mail_env` with these three lines, then `source .agent_mail_env` at
the start of later commands (each bash call is a fresh shell):

```bash
export AGENT_MAIL_PROJECT='home-ubuntu-developer-roblox'
export AGENT_NAME='<assigned-name>'
export REGISTRATION_TOKEN='<token>'
```

**Name-taken recovery (common):** re-using a hint whose identity already
exists fails with `register_agent for an existing identity requires
registration_token`. You cannot reclaim that identity without its token —
do NOT loop. Register with a fresh unique hint (e.g. `RainyLynx-Jul24`),
save the new creds, and move on. The old identity's inbox is unreachable
and its file reservations expire by TTL.

#### Step 2 — Discover active agents and check your inbox

```bash
python3 agent_mail_cli.py agents          # list agents; ignore entries with a non-null "retired_at"
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" 10 false true
```

#### Step 3 — Introduce yourself

Send a short intro to each ACTIVE (non-retired) agent by name:

```bash
python3 agent_mail_cli.py send "$AGENT_NAME" "OtherAgent1,OtherAgent2" \
  "Introduction: $AGENT_NAME joining" "Who you are, what you plan to work on."
```

#### Known gotchas
1. **No broadcast.** `send ... "All" ...` is rejected. List explicit recipient names.
2. **Contact approval.** The first message to a never-contacted agent fails with `Contact approval required` — but the failed send AUTO-CREATES pending contact requests, so no extra step is needed: wait ~15s and retry once; the retry succeeds. Do not loop.
3. **Token required.** `inbox`/`send`/`reserve`/`release` need the `registration_token` (as an arg or exported). Keep it in `.agent_mail_env` (Step 1).
4. **Project key.** The canonical key for this repo is `home-ubuntu-developer-roblox` (the CLI default). `home-ubuntu-developer-roblox-games` does NOT exist — if you see it referenced anywhere, it's stale. Only use another key (e.g. `home-ubuntu-developer-renewal-radar`) when you are deliberately coordinating in that project's repo.
5. **Assigned name.** Use the server-assigned name, not your hint. Re-registering an existing name without its token fails — pick a fresh unique hint (Step 1).
6. **No list-reservations command.** The CLI cannot show current reservations; conflicts surface only in the `conflicts` array of a `reserve` response. Reserve before editing and read that array.

#### Full command reference

```bash
python3 agent_mail_cli.py health
python3 agent_mail_cli.py session-start "NameHint" "abacusai" [project_key]
python3 agent_mail_cli.py agents [project_key]
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" [limit] [urgent_only] [include_bodies]
python3 agent_mail_cli.py send "$AGENT_NAME" "Recipient1,Recipient2" "Subject" "Body" ["$REGISTRATION_TOKEN"]
python3 agent_mail_cli.py reserve "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/**,tests/**" 3600 true --reason "br-123"
python3 agent_mail_cli.py release "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/**,tests/**"
```

Reservation notes: TTL is in seconds (minimum 60; default 3600). Reserve the
narrowest paths that cover your edit (e.g. `src/server/FishingService.lua`,
not `src/**`).

### 2. Gather Context and Priorities

```bash
~/cm-context-prompt.sh "your task description"
bv --robot-triage | jq '.recommendations[0:3]'
```

### 3. Use the Shared Skills Library for Non-Trivial Tasks

Agents have access to a shared skills library at `/home/ubuntu/SKILLS`:

- Extracted skills: `/home/ubuntu/SKILLS/extracted/<skill-name>/`
- Registry metadata: `/home/ubuntu/SKILLS/registry/`
- Shared routing policy: `/home/ubuntu/SKILLS/AGENTS.md`

Before starting any non-trivial task: classify it into one primary category,
consult `/home/ubuntu/SKILLS/registry/skills-index.json` (optionally
`skills-by-trigger.json` / `skills-by-category.json`), select one primary
skill plus up to two supporting ones, and read the primary skill's
`SKILL.md` (supporting files only when directly relevant). Minimize context:
never scan the full tree; prefer lightweight skills.

Common skill preferences:

| Task Type | Preferred Skill |
| --- | --- |
| Debugging | `investigate` |
| Code review | `review` |
| Quality verification | `qa` |
| Risky work | `guard`, `careful` |
| Migrations, deploys, destructive operations | `guard`, `careful` |
| Planning-heavy work | `autoplan` |

#### Native skill precedence
Hermes runtime native skills (`skill_view`) take precedence over shared repo skills. If a skill exists in both, use the native one. Fall back to shared `SKILL.md` only if no native equivalent exists. Shared library (snapshot 2026-04-27) may lag.
Follow routing in `/home/ubuntu/SKILLS/AGENTS.md`. Read root `SKILLS.md` if present.

---

## Project Stack and Key Tools

### Languages and Runtimes

- Luau (Roblox) for all game code; Python via `uv` for tooling and scripts.

### Build, Test, and Verification (Luau / Roblox)

- Source layout: `src/server/`, `src/client/`, `src/shared/`, mapped by `default.project.json` (Rojo).
- Rebuild the place file after script edits: `rojo build -o HarborHeist.rbxlx` (or `rojo serve` + the Studio plugin for live sync).
- Pure-Luau specs (headless, Linux-safe): `scripts/run_tests.sh --pure` — runs `pure_specs/` under lune with an integrated coverage gate. All-pass is required before committing.
- TestEZ specs in `specs/` need Roblox Studio. On the Linux box Studio is unavailable — record them as NOT-verified-on-Linux rather than claiming a run. On a Windows PC with Studio they DO run: see the "Running on Windows (Studio present)" section in `docs/TESTING.md` for the Git-Bash/CRLF gotchas.
- Static checks: `luau-analyze` / `selene` — compare error counts before vs after your edit; never add NEW errors (a known set pre-exists on the client).
- UBS has no Lua scanner, so it is N/A for `.lua`-only changes; the pure-spec suite + coverage gate is the quality bar here.

### Git Repo Layout — read before staging

- The git repo ROOT is `/home/ubuntu`; this project lives at `Developer/roblox/`. From the project dir, `git status` shows `../../` home-directory noise — that is expected.
- NEVER `git add -A`, `git add .`, or `git commit -a` from the repo root: you would sweep in unrelated home files and other agents' uncommitted WIP. Stage explicit paths only (`git add Developer/roblox/src/...`).
- Landing work inside a shared file that contains ANOTHER agent's uncommitted changes? Use partial staging (`git apply --cached` with only your hunks) and leave their hunks unstaged — see the 20d962a / hvfh.4.3 mail thread for why.

### Core Tools

| Tool | Purpose |
| --- | --- |
| `br` | Beads issue tracking |
| `bv` | Graph-aware planning and triage for Beads |
| `ubs` | Ultimate Bug Scanner quality gate |
| Agent Mail (`agent_mail_cli.py`) | Multi-agent reservations and messaging |
| CASS (`cass`) | Session search and memory |
| `ast-grep` | Structural code search and safe rewrites |
| `rg` | Fast textual search |
| `mcp__morph-mcp__warp_grep` | Exploratory AI-powered code search |

---

## Multi-Agent Coordination

### Canonical Identifiers

Use Beads issue IDs as the canonical cross-tool identifier.

| Concept | Value |
| --- | --- |
| Beads issue ID | `br-123` |
| Mail `thread_id` | `br-###` |
| Mail subject prefix | `[br-###] ...` |
| File reservation reason | `br-###` |
| Commit messages | Include `br-###` when working from a bead |

### Claim, Reserve, and Announce Work

For multi-agent work, claim the task, reserve files before editing, and
announce your intent. All examples assume `AGENT_NAME` and
`REGISTRATION_TOKEN` are exported (see Session Startup) and are run from the
repo root.

```bash
TASK_ID="br-123"
br update $TASK_ID --status in_progress
python3 agent_mail_cli.py reserve "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/server/FishingService.lua" 3600 true --reason "$TASK_ID"
python3 agent_mail_cli.py send "$AGENT_NAME" "ActiveAgent1,ActiveAgent2" "[br-123] Start: Fix widget" "Starting work on br-123. Editing src/server/FishingService.lua."
```

During work:

```bash
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN"
```

If you discover follow-up work:

```bash
br create "New subtask discovered" --deps discovered-from:$TASK_ID
```

When done:

```bash
python3 agent_mail_cli.py release "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/server/FishingService.lua"
br close $TASK_ID --reason "Completed: [what you did]"
python3 agent_mail_cli.py send "$AGENT_NAME" "ActiveAgent1,ActiveAgent2" "[br-123] Completed" "Task complete. Changed files: [list]."
```

Coordination rules:

- Always reserve shared files before editing; keep patterns as narrow as possible.
- Release reservations promptly when finished.
- Use the `[br-###]` subject prefix so messages thread with their bead.
- Set acknowledgement requirements when handoff is required.
- Periodically check Agent Mail during longer sessions.

---

## Beads (`br`) Issue Tracking

`br` manages issues in `.beads/` and is the single source of truth for task status, dependencies, and priorities.

### Quick Reference

```bash
br onboard
br ready
br ready --json
br list --status=open
br show <id>
br create --title="..." --type=task --priority=2
br update <id> --status=in_progress
br close <id> --reason "Completed"
br sync --flush-only
```

### Conventions

- Priority scale: P0 critical, P1 high, P2 medium, P3 low, P4 backlog.
- Types: `task`, `bug`, `feature`, `epic`, `question`, `docs`.
- Add dependencies with `br dep add <issue> <depends-on>`.
- `br` is non-invasive and does not execute git commands automatically.
- After `br sync --flush-only`, manually stage and commit `.beads/` changes (`git add .beads/ && git commit -m "[br-123] sync beads"`).

### Automation Rules

Always use JSON or robot flags when parsing `br` output programmatically.

```bash
br list --json | jq '.[0]'
br ready --json
br schema all --format json
```

Do not parse human-oriented output in scripts.

---

## BV Triage Engine

Use `bv` to choose and plan work from the Beads graph.

### Entry Points

```bash
bv --robot-triage
bv --robot-next
bv --robot-plan --label backend
bv --robot-insights --as-of HEAD~30
bv --recipe actionable --robot-plan
```

Rules:

- Use `--robot-*` modes for automation.
- Do not use interactive TUI output in automated sessions.
- Useful output fields: `recommendations`, `quick_wins`, `blockers_to_clear`, `commands`.

---

## UBS Quality Gate

UBS stands for Ultimate Bug Scanner. It is required for catching likely bugs early.

### Installation

```bash
curl -sSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh | bash
```

### Golden Rule

Run `ubs` on changed files before every commit.

- Exit code `0` means safe to commit.
- Exit code `>0` means fix issues and re-run.

### Recommended Commands

```bash
ubs file.ts file2.py
ubs $(git diff --name-only --cached)
ubs --only=js,python src/
ubs --ci --fail-on-warning .
```

### Fix Workflow

1. Read the finding category, description, and suggested fix.
2. Go to `file:line:col`.
3. Verify whether the finding is a real issue.
4. Fix the root cause, not just the symptom.
5. Re-run `ubs <file>` until exit code is `0`.
6. Commit.

### Severity Guidance

- Critical: always fix null safety, XSS, injection, async misuse, memory/resource leaks.
- Important: fix production-impacting type narrowing issues, division-by-zero, unwrap panics, and unclosed resources.
- Contextual: use judgment for TODOs, FIXMEs, debug prints, and console logs.

Anti-patterns: ignoring UBS findings; full-project scans for small edits; fixing symptoms instead of root causes.

---

## Code Search and Rewrites

Use the right tool for the question.

| Task | Tool |
| --- | --- |
| Fast textual search | `rg` |
| Exact symbol or string lookup | `rg` |
| Structural matching or safe rewrites | `ast-grep` |
| Exploratory architecture questions | `mcp__morph-mcp__warp_grep` |

Examples (Luau):

```bash
rg -n 'FireClient' src/server
ast-grep run -l lua -p '$REMOTE:FireServer($$$)' src/client
```

Do not use `warp_grep` for exact symbol lookup. Do not use plain text search for deep architecture understanding when exploratory AI search is available.

---

## Code Change Quality Requirements

When changing code:

1. Understand the root cause before editing.
2. Make minimal, focused changes.
3. Keep style consistent with surrounding code.
4. Run targeted tests first when available.
5. Run the full applicable quality suite before finalizing code changes.
6. Run UBS on changed files before committing.
7. Prefer `review` or `qa` skills before merging substantial changes.

Unless the user explicitly instructs otherwise, always run the full test suite before finalizing code changes.

---

## Session Completion: Landing the Plane

When ending a work session, complete all applicable steps below. Work is not complete until changes are committed and pushed when a commit/push workflow is in scope.

### Mandatory Checklist

1. File `br` issues for remaining work; close finished issues; update in-progress items.
2. Run quality gates if code changed: tests, linters, builds, UBS on changed files.
3. Release file reservations.
4. Sync Beads metadata and commit it: `br sync --flush-only && git add .beads/`.
5. Commit all intended changes (bead ID in the message), then `git pull --rebase && git push`.
6. Verify `git status` shows a clean tree, up to date with origin.
7. Hand off clear context for the next session.

Critical rules: never say "ready to push when you are" if you are responsible
for landing the work — push it yourself; if push fails, resolve and retry;
local-only completed work is stranded; clear stashes and prune remote
branches only when safe and explicitly appropriate.

---

## Practical End-to-End Workflow

Register → gather context (CASS/BV/`br ready`) → claim bead → reserve files → announce → load skill → implement → check mail → run quality gates → release reservations → close beads → sync/commit/push → hand off. See each section above for exact commands.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md for details and anti-patterns.

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
