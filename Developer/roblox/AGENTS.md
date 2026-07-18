# AGENTS_master.md

---

## Purpose & Scope

This document defines the operating instructions for autonomous coding agents and humans collaborating with them in the harbor_heist repository.

Project-local instructions in this file take precedence over shared skill-library defaults when there is a conflict.

---

## Project Overview

**Project Name:** harbor_heist

**Description:** harbot_heist

**Primary audience:** Autonomous coding agents and humans coordinating with those agents.

---

## Absolute Safety Rules

### No Deletions Without Explicit Permission

You may **NOT delete any file or directory** unless the user explicitly gives the exact deletion command **in the current session**.

This includes:

- Files you just created
- Temporary files
- Test files
- Scripts
- Generated files
- Directories that appear safe to remove

If you think something should be removed, stop and ask. You must receive clear written approval before any deletion command is proposed or executed.

Forbidden without explicit approval:

```bash
git reset --hard
git clean -fd
rm -rf
```

Also forbidden without explicit approval:

- Any command that can delete code or data
- Any command that can overwrite important code or data
- Any destructive git operation

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
| Canonical project key | `home-ubuntu-developer-roblox-games` (CLI default; override: `AGENT_MAIL_PROJECT`) |
| Your agent name | ASSIGNED BY THE SERVER at registration (e.g. `PinkDog`) — it may differ from the name you requested. Always use the returned name. |
| Your token | The `registration_token` returned at registration. Required for `inbox`, `send`, `reserve`, and `release`. Save it for the whole session. |

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

#### Step 1 — Register

```bash
python3 agent_mail_cli.py register "YourNameHint" "abacusai"
```

The JSON response contains your ASSIGNED `agent_name` and your
`registration_token`. Export both immediately (each bash call is a fresh
session, so re-export or inline them in later commands):

```bash
export AGENT_NAME='<assigned-name-from-response>'
export REGISTRATION_TOKEN='<token-from-response>'
```

Alternatively, `session-start` performs register + list agents + inbox check
in one shot:

```bash
python3 agent_mail_cli.py session-start "YourNameHint" "abacusai"
```

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

#### Known gotchas (each of these WILL bite you otherwise)

1. **No broadcast.** `send ... "All" ...` is rejected by the server. Always
   list explicit recipient agent names (comma-separated).
2. **Contact approval.** Your FIRST message to an agent may fail with
   `Contact approval required`; the server auto-creates a pending contact
   request. Wait ~15 seconds and retry the same `send` once — auto-approval
   usually clears it. If it still fails, proceed with your work and retry
   later; do not loop.
3. **Token required to send.** `send` needs your registration token: pass it
   as the optional 5th positional argument, or have `REGISTRATION_TOKEN`
   exported in the same shell invocation.
4. **Project key errors.** If a command fails with `Project ... not found`,
   the server will suggest valid keys. Use
   `home-ubuntu-developer-renewal-radar` — never a filesystem path.
5. **Assigned name.** All subsequent commands must use the server-assigned
   agent name, not your requested name hint.

#### Full command reference

```bash
python3 agent_mail_cli.py health
python3 agent_mail_cli.py register "NameHint" "abacusai" [project_key]
python3 agent_mail_cli.py session-start "NameHint" "abacusai" [project_key]
python3 agent_mail_cli.py agents [project_key]
python3 agent_mail_cli.py inbox "$AGENT_NAME" "$REGISTRATION_TOKEN" [limit] [urgent_only] [include_bodies]
python3 agent_mail_cli.py send "$AGENT_NAME" "Recipient1,Recipient2" "Subject" "Body" ["$REGISTRATION_TOKEN"]
python3 agent_mail_cli.py reserve "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/**,tests/**" 3600 true --reason "br-123"
python3 agent_mail_cli.py release "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/**,tests/**"
```

Reservation notes: TTL is in seconds (minimum 60; default 3600). Reserve the
narrowest paths that cover your edit (e.g. `src/api/routes/alerts.py`, not
`src/**`). Reservations on code paths are advisory — check the `conflicts`
array in the response and coordinate via mail if it is non-empty.

### 2. Gather Context and Priorities

```bash
~/cm-context-prompt.sh "your task description"
bv --robot-triage | jq '.recommendations[0:3]'
br ready --json
```

### 3. Use the Shared Skills Library for Non-Trivial Tasks

Agents have access to a shared skills library at `/home/ubuntu/SKILLS`:

- Extracted skills: `/home/ubuntu/SKILLS/extracted/<skill-name>/`
- Registry metadata: `/home/ubuntu/SKILLS/registry/`
- Shared routing policy: `/home/ubuntu/SKILLS/AGENTS.md`

Before starting any non-trivial task:

1. Classify the task into one primary category.
2. Consult `/home/ubuntu/SKILLS/registry/skills-index.json`.
3. Optionally consult `skills-by-trigger.json` / `skills-by-category.json`.
4. Select one primary skill and up to two supporting skills.
5. Read the selected primary skill’s `SKILL.md`.
6. Read supporting skill files only when directly relevant.
7. Execute using the chosen skill set.

Skill loading discipline: minimize context — read the primary skill's `SKILL.md`, avoid scanning the full tree, prefer lightweight skills.

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

Agents in the Hermes runtime have a native skills system (`skill_view` /
`skills_list`) that uses different names than this shared repo — e.g.
shared `investigate` ↔ native `systematic-debugging`; shared `qa` ↔ native
`code-quality-security-audit`. The two systems do not overlap by name.

When a task matches a skill in **both** systems, prefer the native Hermes
skill (wired into the runtime, always current). Fall back to the shared-repo
`SKILL.md` only when no native equivalent exists. Never load both versions
of the same skill — pick one. The shared library is a snapshot (index
generated 2026-04-27) and may lag; native skills are the source of truth.

Unless this file explicitly overrides a rule, follow the shared routing policy in:

```text
/home/ubuntu/SKILLS/AGENTS.md
```

If `SKILLS.md` exists in the project root, read it too.

---

## Project Stack and Key Tools

### Languages and Runtimes

- Bun for JavaScript and TypeScript
- Python via `uv`
- Rust, if needed

### Frontend Build Toolchain

The frontend dashboard at `src/frontend/` uses **Create React App (react-scripts@5)**.

**Working directory for all frontend commands:** `src/frontend/`

**Install:**
```bash
cd src/frontend && npm install
```

**Run tests (CI-safe, non-interactive):**
```bash
cd src/frontend && npm test
```

**Run tests (interactive watch mode):**
```bash
cd src/frontend && npm run test:watch
```

**Run tests with coverage (CI pipeline):**
```bash
cd src/frontend && npm run test:ci
```

**Build production bundle:**
```bash
cd src/frontend && npm run build
```

**Start dev server:**
```bash
cd src/frontend && npm start
```

**Bun compatibility note:** The runtime environment is Bun, which has a compatibility issue with jest-runtime's Module property assignment. A postinstall script (`scripts/patch-jest-runtime.js`) and explicit test-script preamble automatically apply the needed patch. Tests will not run without it.

**Test discovery:** CRA discovers tests via `src/**/*.{test,spec}.{js,jsx,ts,tsx}` and `src/**/__tests__/**/*.{js,jsx,ts,tsx}`. The `types/data-contracts.test.js` test is duplicated at `src/data-contracts.test.js` for CRA discovery. Both must be kept in sync.

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
python3 agent_mail_cli.py reserve "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/api/routes/alerts.py,tests/test_alerts.py" 3600 true --reason "$TASK_ID"
python3 agent_mail_cli.py send "$AGENT_NAME" "ActiveAgent1,ActiveAgent2" "[br-123] Start: Fix widget" "Starting work on br-123. Editing src/api/routes/alerts.py and tests/test_alerts.py."
```

(Recipients must be explicit active agent names from
`python3 agent_mail_cli.py agents` — the server rejects `"All"`.)

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
python3 agent_mail_cli.py release "$AGENT_NAME" "$REGISTRATION_TOKEN" "src/api/routes/alerts.py,tests/test_alerts.py"
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
- After `br sync --flush-only`, manually stage and commit `.beads/` changes.

```bash
br sync --flush-only
git add .beads/
git commit -m "[br-123] sync beads"
```

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
- Useful output fields include `recommendations`, `quick_ref`, `quick_wins`, `blockers_to_clear`, and `commands`.

Example:

```bash
bv --robot-triage | jq '.recommendations[0]'
```

Robot JSON may include `data_hash`, `status`, `as_of`, and `as_of_commit`.

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
ubs --help
ubs sessions --entries 1
ubs .
```

Scope UBS to changed files whenever possible. Use full-project scans sparingly.

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

Anti-patterns:

- Ignoring UBS findings.
- Running a full project scan for small edits.
- Fixing symptoms instead of root causes.

---

## Code Search and Rewrites

Use the right tool for the question.

| Task | Tool |
| --- | --- |
| Fast textual search | `rg` |
| Exact symbol or string lookup | `rg` |
| Structural matching or safe rewrites | `ast-grep` |
| Exploratory architecture questions | `mcp__morph-mcp__warp_grep` |

Examples:

```bash
ast-grep run -l Rust -p '$EXPR.unwrap()'
rg -n 'println!' -t rust
rg -l -t rust 'unwrap\(' | xargs ast-grep run -l Rust -p '$X.unwrap()' --json
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

1. File `br` issues for remaining work.
2. Run quality gates if code changed:
   - Tests
   - Linters
   - Builds
   - UBS on changed files
3. Update issue status:
   - Close finished issues.
   - Update in-progress items.
4. Release file reservations.
5. Sync Beads metadata.
6. Commit all intended changes.
7. Push to remote when responsible for landing the work.
8. Verify the working tree and remote state.
9. Hand off clear context for the next session.

Recommended command flow:

```bash
git status
git add <files>
br sync --flush-only
git add .beads/
git commit -m "[br-123] ..."
git pull --rebase
git push
git status
```

Critical rules:

- Do not say “ready to push when you are” if you are responsible for landing the work.
- If push fails, resolve the issue and retry unless blocked by user instructions or permissions.
- Local-only completed work is considered stranded.
- Clear stashes and prune remote branches only when safe and explicitly appropriate.

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
