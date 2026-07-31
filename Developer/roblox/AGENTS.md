# AGENTS.md

## Purpose & Scope

Operating instructions for autonomous coding agents and humans in the harbor_heist repository. Project-local instructions take precedence over shared skill-library defaults.

## Project Overview

**harbor_heist** — Server-authoritative multiplayer fishing/aquarium tycoon game with PvP raids. 17 server services, persistence, analytics, anti-exploit hardening, mobile UI. Closed V1 test phase; ready for launch pending final balance/decision finalization.

## Absolute Safety Rules

**No Deletions Without Explicit Permission.** You may NOT delete any file or directory unless the user explicitly gives the exact deletion command in the current session. This includes files you created, temp/test/generated files, and directories that appear safe. If you think something should be removed, stop and ask.

Forbidden without explicit approval: `git reset --hard`, `git clean -fd`, `rm -rf`, and ANY command that can delete/overwrite code or data, or perform a destructive git operation. If unsure, ask first. Prefer `git status`, `git diff`, `git stash`.

## Required Session Startup Workflow

### 1. Register and Check Coordination State

Agent Mail is the multi-agent coordination server (messaging + advisory file reservations). Use the project-local CLI `agent_mail_cli.py` (repo root) for all operations. It returns JSON and handles project-key resolution. Do NOT use the legacy `am_*` shell helpers.

**Key facts:**

| Fact | Value |
| --- | --- |
| Server URL | `http://127.0.0.1:8765/mcp/` (override: `AGENT_MAIL_URL`) |
| Project key | `home-ubuntu-developer-roblox` (CLI default; override: `AGENT_MAIL_PROJECT`) |
| Agent name | ASSIGNED BY THE SERVER — may differ from your hint. Always use the returned name. |
| Token | `registration_token` returned ONCE at registration. Required for `inbox`/`send`/`reserve`/`release`. Cannot be recovered — persist it. |

#### Step 0 — Verify server is up

```bash
python3 agent_mail_cli.py health
```

Expected: `"status": "healthy"`. If `Connection refused`, start the server (needs SQLite, NOT the global PostgreSQL which crashes it):

```bash
cd ~/mcp_agent_mail && DATABASE_URL="sqlite+aiosqlite:///$HOME/.mcp_agent_mail/storage.sqlite3" \
  nohup uv run python -m mcp_agent_mail.cli serve-http > /tmp/agent_mail_server.log 2>&1 &
cd - && sleep 8 && python3 agent_mail_cli.py health
```

Never run `mcp-agent-mail` or `agent-mail` directly — they are launchers that only print a usage banner.

#### Step 1 — Resume or register identity

Check saved credentials first (`.agent_mail_env` persists identity across sessions):

```bash
cat .agent_mail_env
```

If it names an ACTIVE (non-retired) agent, source and verify it:
```bash
source .agent_mail_env
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" 10 false true
```
A JSON inbox = identity resumed. An auth error = stale creds; re-register below. Never assume the file is yours — it may hold a retired agent's creds.

Otherwise register fresh (register + list agents + inbox check in one shot):

```bash
python3 agent_mail_cli.py session-start "YourNameHint" "abacusai"
```

Persist the assigned `agent_name` and `registration_token` IMMEDIATELY by overwriting `.agent_mail_env`:
```bash
export AGENT_MAIL_PROJECT='home-ubuntu-developer-roblox'
export AGENT_NAME='<assigned-name>'
export REGISTRATION_TOKEN='<token>'
```

**Name-taken recovery:** re-using an existing hint fails with "requires registration_token". Pick a fresh unique hint (e.g. `RainyLynx-Jul24`), save new creds, move on. The old identity's inbox is unreachable; its file reservations expire by TTL.

#### Step 2 — Discover active agents and check inbox

```bash
python3 agent_mail_cli.py agents          # ignore entries with non-null "retired_at"
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" 10 false true
```

#### Step 3 — Introduce yourself

Send a short intro to each ACTIVE agent by name:
```bash
python3 agent_mail_cli.py send "$AGENT_NAME" "OtherAgent1,OtherAgent2" \
  "Introduction: $AGENT_NAME joining" "Who you are, what you plan to work on."
```

#### Known gotchas

1. **No broadcast.** Explicit recipient names only — `send ... "All"` is rejected.
2. **Contact approval.** First message to a never-contacted agent fails with "Contact approval required" but auto-creates the request. Wait ~15s and retry once.
3. **Token required.** Keep `registration_token` in `.agent_mail_env`.
4. **Project key.** Canonical key is `home-ubuntu-developer-roblox`. `home-ubuntu-developer-roblox-games` does NOT exist.
5. **Assigned name.** Use the server-assigned name, not your hint.
6. **No list-reservations command.** Conflicts surface in the `conflicts` array of a `reserve` response. Reserve before editing and read that array.

#### Full command reference

```bash
python3 agent_mail_cli.py health
python3 agent_mail_cli.py session-start "NameHint" "abacusai" [project_key]
python3 agent_mail_cli.py agents [project_key]
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" [limit] [urgent_only] [include_bodies]
python3 agent_mail_cli.py send "$AGENT_NAME" "Recipient1,Recipient2" "Subject" "Body" ["$REGISTRATION_TOKEN"]
python3 agent_mail_cli.py reserve "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/Foo.lua" 3600 true --reason "br-123"
python3 agent_mail_cli.py release "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/Foo.lua"
```

Reservation TTL is in seconds (min 60, default 3600). Reserve the narrowest paths covering your edit.

### 2. Gather Context and Priorities

```bash
~/cm-context-prompt.sh "your task description"
bv --robot-triage | jq '.recommendations[0:3]'
```

### 3. Use the Shared Skills Library for Non-Trivial Tasks

Shared skills at `/home/ubuntu/SKILLS`. Before non-trivial tasks: classify into a category, consult `/home/ubuntu/SKILLS/registry/skills-index.json`, select a primary skill, read its `SKILL.md`. Minimize context — never scan the full tree.

| Task Type | Preferred Skill |
| --- | --- |
| Debugging | `investigate` |
| Code review | `review` |
| Quality verification | `qa` |
| Risky/destructive work | `guard`, `careful` |
| Planning-heavy work | `autoplan` |

Hermes runtime native skills (`skill_view`) take precedence over shared skills. Follow routing in `/home/ubuntu/SKILLS/AGENTS.md`.

## Project Stack and Key Tools

### Languages and Runtimes

Luau (Roblox) for all game code; Python via `uv` for tooling and scripts.

### Build, Test, and Verification (Luau / Roblox)

- Source layout: `src/server/`, `src/client/`, `src/shared/`, mapped by `default.project.json` (Rojo).
- Rebuild after script edits: `rojo build -o HarborHeist.rbxlx`.
- Pure-Luau specs (headless, Linux-safe): `scripts/run_tests.sh --pure` — runs `pure_specs/` under lune with an integrated coverage gate. All-pass required before committing.
- TestEZ specs in `specs/` need Roblox Studio (unavailable on Linux — record as NOT-verified-on-Linux). On Windows with Studio, see `docs/TESTING.md` for Git-Bash/CRLF gotchas.
- Static checks: `luau-analyze` / `selene` — compare error counts before vs after; never add NEW errors (a known set pre-exists on the client).
- UBS has no Lua scanner (N/A for `.lua`-only changes). The pure-spec suite + coverage gate is the quality bar.

### Git Repo Layout — read before staging

- The git repo ROOT is `/home/ubuntu`; this project lives at `Developer/roblox/`. `git status` shows `../../` home-directory noise — that is expected.
- NEVER `git add -A`, `git add .`, or `git commit -a` from the repo root — you would sweep in unrelated home files and other agents' WIP. Stage explicit paths only.
- Landing work in a shared file with ANOTHER agent's uncommitted changes? Use partial staging (`git apply --cached` with only your hunks) and leave their hunks unstaged.

### Core Tools

| Tool | Purpose |
| --- | --- |
| `br` | Beads issue tracking |
| `bv` | Graph-aware planning and triage for Beads |
| `ubs` | Ultimate Bug Scanner quality gate |
| `agent_mail_cli.py` | Multi-agent reservations and messaging |
| `cass` | Session search and memory |
| `ast-grep` | Structural code search and safe rewrites |
| `rg` | Fast textual search |
| `mcp__morph-mcp__warp_grep` | Exploratory AI-powered code search |

## Multi-Agent Coordination

### Canonical Identifiers

Use Beads issue IDs as the cross-tool identifier. Mail subject prefix: `[br-###]`. File reservation reason: `br-###`. Commit messages: include `br-###` when working from a bead.

### Claim, Reserve, and Announce Work

Assumes `AGENT_NAME` and `REGISTRATION_TOKEN` are exported (see Session Startup). Run from the repo root.

```bash
TASK_ID="br-123"
br update $TASK_ID --status in_progress
python3 agent_mail_cli.py reserve "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/server/FishingService.lua" 3600 true --reason "$TASK_ID"
python3 agent_mail_cli.py send "$AGENT_NAME" "ActiveAgent1,ActiveAgent2" "[br-123] Start: Fix widget" "Starting work on br-123."
```

During work: `python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN"`

Follow-up work: `br create "New subtask" --deps discovered-from:$TASK_ID`

When done:
```bash
python3 agent_mail_cli.py release "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/server/FishingService.lua"
br close $TASK_ID --reason "Completed: [what you did]"
python3 agent_mail_cli.py send "$AGENT_NAME" "ActiveAgent1,ActiveAgent2" "[br-123] Completed" "Task complete. Changed files: [list]."
```

Rules: reserve shared files before editing (narrowest paths); release promptly; use `[br-###]` subject prefix; check mail periodically during longer sessions.

## Beads Issue Tracking

`br` manages issues in `.beads/` and is the single source of truth for task status, dependencies, and priorities. The project also has `bd (beads)` — a separate Go binary with overlapping commands (e.g. `bd ready`, `bd show`, `bd update --claim`, `bd close`). Use `br` as the primary CLI; `bd` is an alternative interface.

### Quick Reference

```bash
br ready                        # Find available work
br ready --json                 # JSON for scripting
br show <id>                    # View issue details
br create --title="..." --type=task --priority=2
br update <id> --status in_progress
br close <id> --reason "Completed"
br sync --flush-only            # Export to issues.jsonl
```

### Conventions

- Priority: P0 critical, P1 high, P2 medium, P3 low, P4 backlog. Types: `task`, `bug`, `feature`, `epic`, `question`, `docs`.
- Add dependencies: `br dep add <issue> <depends-on>`.
- `br` is non-invasive — does not execute git commands. After `br sync --flush-only`, manually: `git add .beads/ && git commit -m "[br-123] sync beads"`.
- Use JSON/robot flags when parsing programmatically: `br list --json | jq '.[0]'`. Do not parse human output in scripts.
- Use `br` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists. Use `br remember` for persistent knowledge, not MEMORY.md files.
- Architecture: issues live in a local Dolt DB; sync uses `refs/dolt/data` on your remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/SYNC_CONCEPTS.md.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:7510c1e2 -->
## Session Completion

**When ending a work session**, complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. File `br` issues for remaining work; close finished issues; update in-progress items.
2. Run quality gates if code changed: tests, linters, builds, UBS on changed files.
3. Release file reservations.
4. Sync Beads: `br sync --flush-only && git add .beads/`.
5. Commit all intended changes (bead ID in message), then `git pull --rebase && git push`.
6. Verify `git status` shows a clean tree, up to date with origin.
7. Hand off clear context for the next session.

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds. NEVER stop before pushing.
- NEVER say "ready to push when you are" — YOU must push. If push fails, resolve and retry until it succeeds.
- Clear stashes and prune remote branches only when safe and appropriate.
<!-- END BEADS INTEGRATION -->

## BV Triage Engine

Use `bv` to choose and plan work from the Beads graph.

```bash
bv --robot-triage              # Full triage report
bv --robot-next                # Single top recommendation
bv --robot-plan --label backend
bv --robot-insights --as-of HEAD~30
```

Use `--robot-*` modes for automation (do not use interactive TUI output). Useful fields: `recommendations`, `quick_wins`, `blockers_to_clear`, `commands`.

## UBS Quality Gate

Run `ubs` on changed files before every commit. Exit code `0` = safe to commit; `>0` = fix and re-run.

```bash
ubs file.ts file2.py
ubs $(git diff --name-only --cached)
```

**Severity:** Critical (null safety, XSS, injection, async misuse, resource leaks) — always fix. Important (type narrowing, division-by-zero, unwrap panics, unclosed resources) — fix production-impacting issues. Contextual (TODOs, debug prints) — use judgment.

Note: UBS has no Lua scanner — N/A for `.lua`-only changes. Install: `curl -sSL https://raw.githubusercontent.com/Dicklesworthstone/ultimate_bug_scanner/master/install.sh | bash`

## Code Search and Rewrites

| Task | Tool |
| --- | --- |
| Fast textual search / exact symbol lookup | `rg` |
| Structural matching or safe rewrites | `ast-grep` |
| Exploratory architecture questions | `mcp__morph-mcp__warp_grep` |

Do not use `warp_grep` for exact symbol lookup. Do not use plain text search for deep architecture questions when AI search is available.

```bash
rg -n 'FireClient' src/server
ast-grep run -l lua -p '$REMOTE:FireServer($$$)' src/client
```

## Code Change Quality Requirements

1. Understand the root cause before editing.
2. Make minimal, focused changes. Keep style consistent with surrounding code.
3. Run targeted tests first when available.
4. Run the full applicable quality suite before finalizing code changes.
5. Run UBS on changed files before committing.
6. Prefer `review` or `qa` skills before merging substantial changes.

Unless explicitly instructed otherwise, always run the full test suite before finalizing code changes.

## Practical End-to-End Workflow

Register → gather context (CASS/BV/`br ready`) → claim bead → reserve files → announce → load skill → implement → check mail → run quality gates → release reservations → close beads → sync/commit/push → hand off. See each section above for exact commands.
