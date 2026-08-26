# AGENTS.md

## Purpose & Scope

Operating instructions for autonomous coding agents and humans working in the **harbor_heist** repository. This file reflects the CURRENT checkout: a standalone clone whose root **is** `/data/projects/harbor_heist` (the game lives in `Developer/roblox/`). It supersedes all instructions written for the original `/home/ubuntu` shared-host layout; where an old path or server is referenced anywhere else, treat this file as authoritative.

## Project Overview

**harbor_heist** — Server-authoritative multiplayer fishing/aquarium tycoon with PvP raids. 17 server services, persistence, analytics, anti-exploit hardening, mobile UI. Closed V1 test phase; launch-pending final balance/decision finalization.

**Current program (2026-08-26):** a nine-slice full-app audit produced EPIC 47 — *Pre-Launch Remediation* (epic bead `harborheist-v0ud`) — spanning data integrity, PvP fairness, economic truth, premium interaction quality, motion polish, docs truthing, and a verification funnel. 57 beads with evidence-grounded bodies, dependency graph, estimates, and three ⚑DECISION gates awaiting the user:

| Gate | Bead | Question |
| --- | --- | --- |
| DeepWater rebalance approach | `harborheist-8h9r` | rod-gate+cut vs intermediate zone vs cut-only |
| Dead canonical motion modules | `harborheist-v0ud.31` | adopt PanelAnimation vs delete + repoint DESIGN_SYSTEM |
| Destructive hygiene deletions | `harborheist-v0ud.41` items 3–4 | dead bead-seeding scripts, DESIGN_SYSTEM.docx |

Provenance digests (per-slice verdicts and finding→bead mapping) are posted as comments on the epic bead. Read them before re-auditing anything.

## Absolute Safety Rules

**No Deletions Without Explicit Permission.** You may NOT delete any file or directory unless the user explicitly gives the exact deletion command in the current session. This includes files you created, temp/test/generated files, and directories that appear safe. If you think something should be removed, stop and ask.

Forbidden without explicit approval: `git reset --hard`, `git clean -fd`, `rm -rf`, and ANY command that can delete/overwrite code or data, or perform a destructive git operation. If unsure, ask first. Prefer `git status`, `git diff`, `git stash`.

## Environment & Toolchain (this machine)

| Tool | Status | Notes |
| --- | --- | --- |
| `br`, `bv`, `ubs` | ✅ `~/.local/bin` | Beads tracking, graph triage, bug scanner |
| `lune` 0.10.5 | ✅ `~/.local/bin` | Runs the pure suite headless |
| `rojo` 7.7.0 | ✅ `~/.local/bin` | Place builds |
| `selene` 0.31.0 | ✅ `~/.local/bin` | Luau lint gate |
| `rg`, `ast-grep` | ✅ | Textual / structural search |
| `python3`, `uv`, `git`, `gh` | ✅ | Scripting + tooling |
| `cass` | ✅ | Session memory search |
| Roblox Studio | ❌ never | Datamodel + E2E suites are NOT-runnable here |
| `run-in-roblox` | ❌ | Requires Studio; install only on Windows hosts |
| `luau-analyze` | ❌ not installed | `selene` is the lint gate here |
| Agent Mail server | ❌ absent | See Appendix A — coordination degraded to solo |
| `~/cm-context-prompt.sh`, `/home/ubuntu/SKILLS` | ❌ old-host artifacts | Ignore any reference elsewhere |

Ensure `export PATH="$HOME/.local/bin:$PATH"` before running builds/tests. Tools were installed as direct release binaries (lune/rojo/selene from GitHub releases); rokit is NOT set up on this machine.

## Required Session Startup Workflow

1. `cd /data/projects/harbor_heist/Developer/roblox`
2. **Pick work from the tracker, not from memory:** `br ready` (unblocked, priority-ordered) or `bv --robot-next` (graph-aware recommendation). Respect decision gates — do not start beads downstream of `harborheist-8h9r` / `harborheist-v0ud.31` until they close.
3. **Claim:** `br update <id> --status in_progress`.
4. **Read the whole bead.** Bodies are self-contained: GOAL / EVIDENCE (file:line) / WHY IT MATTERS / APPROACH / CONSIDERATIONS (including rejected alternatives) / SOURCE slice, plus structured acceptance criteria. If a claim seems wrong, verify against source before editing either.
5. Do the work under the quality gates below; close out per Session Completion.

Multi-agent registration/reservation protocol is in **Appendix A** — currently UNAVAILABLE on this host; skip unless the health check passes.

## Build, Test, and Verification (Luau / Roblox)

- Source layout: `src/server/`, `src/client/`, `src/shared/`, mapped by `default.project.json` (Rojo). Rebuild after script edits:
  ```bash
  rojo build -o HarborHeist.rbxlx
  ```
- **Pure-Luau suite is the mandatory gate** (runs headless, includes function-call coverage threshold AND source-contract specs that assert against module SOURCE TEXT — even comment-only edits can fail tests):
  ```bash
  scripts/run_tests.sh --pure        # 1239 tests + coverage gate; all-pass required
  ```
- Static checks: `selene .` — compare error/warning counts before vs after; NEVER add new errors (a small known warning set pre-exists, e.g. deliberate `_G.HARBORHEIST_TEST` bridge usage). `luau-analyze` is unavailable here.
- TestEZ datamodel suite (`scripts/run_tests.sh --datamodel`, 410 tests last verified) and the scenario-E2E harness (`scripts/run_e2e_scenarios.sh`) require Studio + run-in-roblox: record results as NOT-verified-on-Linux. See `docs/TESTING.md`; on Windows see its Git-Bash/CRLF notes.
- The legacy monolithic E2E runner (`runner.server.lua`, `e2e.project.json`, `run_e2e.sh`) was retired (`harborheist-1kns`); the scenario architecture (`tests/e2e/bootstrap.server.lua` + `tests/e2e/scenarios/*.lua`) is the only E2E path.
- UBS has no Lua scanner — N/A for `.lua`-only changes; still run it on shell/python/markdown you touch.

## Git Repo Layout & Commit Protocol

- The git repo ROOT is the clone root `/data/projects/harbor_heist`; the game project lives at `Developer/roblox/`. There is no home-directory noise in `git status` on this checkout — the old warnings about sweeping unrelated home files no longer apply, BUT explicit-path staging remains mandatory:
  - NEVER `git add -A`, `git add .`, or `git commit -a`. Stage the exact files you touched.
  - Landing work in a shared file with another stream's uncommitted changes? Use partial staging (`git apply --cached`) and leave their hunks unstaged.
- Commit messages carry bead IDs: `[harborheist-xxxx] what changed`. After tracker mutations: `br sync --flush-only && git add .beads/issues.jsonl` (export is passive; `.beads/beads.db*` sidecars are local-only and slated for gitignore in `v0ud.41`).
- **Push reality (as of 2026-08-26):** GitHub credentials are NOT configured on this host (`gh auth login` pending). Commits queue locally on `main` (`322a823`, `702cdac`, `588bab6`, `02a9ab9`, …). Until auth lands: finish everything else in Session Completion, leave a clean committed tree, and report push as blocked — NEVER claim pushed when it isn't, and never fabricate remotes.

## Beads Issue Tracking

`br` manages issues in `.beads/` and is the single source of truth for task status, dependencies, priorities, and estimates. `bd` exists as an alternative interface; prefer `br`.

```bash
br ready                        # unblocked work, priority-ordered
br ready --json                 # JSON for scripting
br show <id>                    # full self-contained brief + acceptance criteria
br create --title="..." --type=bug --priority=2 --parent=<id> --estimate=3
br dep add <issue> <depends-on>            # blocks edge (default)
br dep add <child> <parent> -t parent-child
br update <id> --status in_progress | --description ... | --estimate N
br comments add <id> -m "..."   # provenance, decisions, review notes
br close <id> --reason "Completed: ..."
br sync --flush-only            # export to issues.jsonl (then git add manually)
```

Conventions:

- Priority P0 critical … P4 backlog. Types: `task`, `bug`, `feature`, `epic`, `question`, `docs`. Estimates are coarse hours.
- Program structure: EPIC 47 streams are encoded in title prefixes and labels — `47.A*` DATA, `47.B*` RAID, `47.C*` CLIENT, `47.D*` FISH, `47.E*` MOTION, `47.F*` ECON, `47.G*` DOCS, plus `V1` verification funnel. Labels mirror streams (`audit-data`, `audit-raid`, …) with `decision-needed` marking gates.
- Finding-head beads (e.g. `6b4d`, `hdl8`, `1t0k`) are problem statements; their children decompose execution. Close heads only when every child closes.
- Use JSON flags when parsing: `br list --json | jq`. Never parse human output in scripts.
- After `br sync --flush-only`, manually `git add .beads/issues.jsonl && git commit -m "[bead-id] sync beads"`.
- Do NOT use TodoWrite-style external trackers for project work — beads are canonical. `br remember` stores persistent knowledge.

## Code Search and Rewrites

| Task | Tool |
| --- | --- |
| Fast textual search / exact symbol lookup | `rg` |
| Structural matching or safe rewrites | `ast-grep` |
| Deep exploratory questions | reason over the code yourself; no AI-search MCP is wired on this host |

```bash
rg -n 'FireClient' src/server
ast-grep run -l lua -p '$REMOTE:FireServer($$$)' src/client
```

## UBS Quality Gate

Run `ubs` on changed non-Lua files before commit (exit 0 = safe). Severity ladder and workflow unchanged from prior guidance; scope scans to changed files (`ubs <files>`), never full-project for small edits. No Lua scanner — skip for `.lua`-only diffs.

## Code Change Quality Requirements

1. Understand the root cause before editing.
2. Minimal, focused changes; style consistent with surrounding code.
3. Targeted tests first when available.
4. Full applicable quality suite before finalizing: `--pure` green + coverage gate + selene delta + `rojo build` for touched mappings. Source-contract specs mean DOC-COMMENT edits can break tests — always run the suite.
5. UBS on changed non-Lua files.
6. Prefer a review pass (fresh-eyes style, like slices documented on EPIC 47) before merging substantial changes.

Unless explicitly instructed otherwise, always run the full test suite before finalizing code changes.

## Practical End-to-End Workflow

Pick bead from `br ready` → read fully → claim → implement → gates (`--pure`, coverage, selene delta, `rojo build`) → release/close bead with completion reason → `br sync --flush-only` → stage explicit paths → commit `[bead-id]` → attempt push (see blocked-push reality above) → hand off context.

## Session Completion

When ending a work session, complete ALL steps below. With credentials configured, work is NOT complete until `git push` succeeds; while push is credential-blocked on this host, the bar is: **clean committed tree, tracker synced, blocker explicitly reported** — never silently skipped.

1. File `br` issues for remaining work; close finished issues; update in-progress items.
2. Run quality gates if code changed: `--pure` + coverage, selene delta, `rojo build`, UBS on non-Lua diffs.
3. Sync Beads: `br sync --flush-only && git add .beads/issues.jsonl`.
4. Commit intended changes (explicit paths, bead ID in message).
5. Attempt `git pull --rebase && git push`. On auth failure: report the queued commits and stop — do not retry-loop, do not claim success.
6. Verify `git status` shows a clean tree.
7. Hand off clear context for the next session.

---

## Appendix A — Multi-Agent Coordination (Agent Mail): UNAVAILABLE ON THIS HOST

The original workflow required registering with a local Agent Mail server (`http://127.0.0.1:8765/mcp/`, project key `home-ubuntu-developer-roblox`, credentials persisted in `.agent_mail_env`). That server's source is ABSENT on this machine (only stale launcher binaries remain under `~/mcp_agent_mail`), and the project key referenced the old host layout. Registration therefore cannot succeed; sessions operate solo by default.

If the server is ever rehosted:

```bash
python3 agent_mail_cli.py health          # if unhealthy, do NOT improvise a start command; ask
python3 agent_mail_cli.py session-start "YourNameHint" "abacusai"
# persist returned name+token to .agent_mail_env (gitignored), then:
#   reserve narrowest paths before editing shared files (TTL seconds, default 3600)
#   announce claims with subject prefix [br-###]; release reservations on completion
```

Historic gotchas that will apply again after a rehost: no broadcast sends (explicit recipients only), first-contact approval delay (~15s retry), tokens shown once, assigned names differ from hints, reservation conflicts surface in the `reserve` response `conflicts` array.
