# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_THEME="powerlevel10k/powerlevel10k"

# ═══════════════════════════════════════════════════════════════════════════
# ~/.zshrc - ABACUS CLI CONTROL CENTER
# ═══════════════════════════════════════════════════════════════════════════

# 1. LOAD BASE ENGINE
[ -f "$HOME/.acfs/zsh/acfs.zshrc" ] && source "$HOME/.acfs/zsh/acfs.zshrc"

# 2. PATHS & ENVIRONMENT
export PATH="$HOME/.local/bin:$PATH"
if command -v go &>/dev/null; then
    _gobin="$(go env GOPATH)/bin"
    [[ ":$PATH:" != *":${_gobin}:"* ]] && export PATH="$PATH:${_gobin}"
    unset _gobin
fi

# 3. TOOL INITIALIZATION
command -v atuin &>/dev/null && eval "$(atuin init zsh)"
[ -s "/home/ubuntu/.bun/_bun" ] && source "/home/ubuntu/.bun/_bun"
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# ═══════════════════════════════════════════════════════════════════════════
# 4. NTM (NAMED TMUX MANAGER) INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════

if command -v ntm &>/dev/null; then
    # Official shell integration (aliases, completions)
    eval "$(ntm shell zsh)"

    # Set up F6 tmux palette popup keybinding
    ntm bind &>/dev/null

    # ─────────────────────────────────────────────────────────────────────
    # SHARED HELPERS
    # ─────────────────────────────────────────────────────────────────────

    # Pane identity metadata: model-id -> "display name|accent color|type".
    # Accents are Catppuccin Mocha (matches ~/.tmux.conf). This is the SEED
    # of the unified team table (bead 764.2.2) — extend here, never at call
    # sites.
    typeset -gA _NTM_PANE_META=(
        CLAUDE_V4_6_SONNET_LOW_THINKING "Claude Sonnet 4.6|#fab387|cc"
        OPENAI_GPT5_3_CODEX           "GPT-5.3 Codex|#a6e3a1|cod"
        GEMINI_3_1_PRO                "Gemini 3.1 Pro|#89b4fa|gmi"
        ZAI_GLM_5                     "ZAI GLM 5|#f9e2af|zai"
        QWEN3_CODER_32B               "Qwen3 Coder 32B|#94e2d5|qwen"
        GROK_CODE_FAST                "Grok Code Fast|#cba6f7|grok"
    )

    # Abstract paths
    export AGENT_MAIL_ENV_PATH="${AGENT_MAIL_ENV_PATH:-$HOME/mcp_agent_mail/.env}"

    # Derive a tmux-safe session name from an optional argument (default:
    # basename of CWD). tmux silently rewrites '.' and ':' to '_' in session
    # names at creation, after which every `-t "<raw name>:1"` target fails
    # with "can't find session" — so sanitize here, up front, the same way.
    _ntm_target() {
        local name="${1:-${PWD:t}}"
        print -r -- "${name//[.:]/_}"
    }

    # Resolve current NTM session name (prefers $NTM_SESSION, falls back to
    # the sanitized folder name so it matches what the launchers create).
    _ntm_session() {
        if [[ -n "${NTM_SESSION:-}" ]]; then
            print -r -- "$NTM_SESSION"
        else
            _ntm_target
        fi
    }

    # Create a detached session with stable window names.
    _ntm_new_session() {  # <session> <first_window_name>
        tmux new-session -d -s "$1" -n "$2"
        tmux set-option -t "$1" automatic-rename off
        tmux set-option -t "$1" allow-rename off
    }

    # Focus window 1, then attach — or switch client when already in tmux.
    _ntm_attach() {  # <session>
        tmux select-window -t "${1}:1" 2>/dev/null
        if [[ -n "$TMUX" ]]; then
            tmux switch-client -t "$1"
        else
            tmux attach-session -t "$1"
        fi
    }

    # Load Agent Mail bearer token from env or .env file
    _ntm_mail_token() {
        local token="${AGENT_MAIL_TOKEN:-}"
        if [[ -z "$token" && -f "$AGENT_MAIL_ENV_PATH" ]]; then
            local line
            # Anchor the key at line start so commented lines or partial keys
            # can't leak in; -f2- keeps values that contain '='.
            line=$(grep -E '^HTTP_BEARER_TOKEN=' "$AGENT_MAIL_ENV_PATH" 2>/dev/null)
            [[ -n "$line" ]] && token=$(echo "$line" | cut -d= -f2- | tr -d '"' | tr -d "'")
        fi
        echo "$token"
    }

    # Launch one Abacus agent in a named tmux window with YOLO MODE enabled.
    # Always uses --model flag and --dangerously-skip-permissions for full headless operation.
    #
    # Usage: _ntm_spawn_agent <session> <win_idx> <win_name> <agent_name> <model> <project_path> <mail_url>
    #
    # The pane bootstrap is written to ~/.cache/ntm/spawn-<session>-<idx>.zsh
    # and `source`d in the pane, so only the script path crosses
    # `tmux send-keys` — a project path containing spaces or quotes can no
    # longer corrupt the typed commands — and the exports persist in the
    # pane after the agent exits. The mail token is derived inside the pane,
    # so the secret never crosses send-keys.
    #
    # If a window already exists at <win_idx> it is renamed and reused rather
    # than creating a duplicate — required for single-agent launchers whose
    # tmux new-session already occupies index 1.
    _ntm_spawn_agent() {
        local session="$1" idx="$2" win_name="$3" agent_name="$4" model="$5"
        local project_path="$6" agent_mail_url="$7"

        if tmux list-windows -t "$session" -F "#{window_index}" 2>/dev/null \
                | grep -qx "$idx"; then
            tmux rename-window -t "${session}:${idx}" "$win_name"
        else
            tmux new-window -t "${session}:${idx}" -n "$win_name"
        fi

        local script_dir="$HOME/.cache/ntm"
        local script="${script_dir}/spawn-${session}-${idx}.zsh"
        local setup_msg="🤖 Setting up ${agent_name} (${model})..."
        local ready_msg="✅ Ready! Launching Abacus with ${model} in YOLO MODE..."
        mkdir -p "$script_dir"
        {
            print -r -- "clear"
            print -r -- "echo ${(q)setup_msg}"
            print -r -- "cd ${(q)project_path}"
            print -r -- "export AGENT_NAME=${(q)agent_name}"
            print -r -- "export AGENT_PROGRAM='abacusai'"
            print -r -- "export AGENT_MODEL=${(q)model}"
            print -r -- "export AGENT_PROJECT=${(q)project_path}"
            print -r -- "export AGENT_MAIL_URL=${(q)agent_mail_url}"
            print -r -- "export AGENT_MAIL_PROJECT=${(q)project_path}"
            cat <<'PANE_EOF'
if [[ -z "${AGENT_MAIL_TOKEN:-}" && -f "${AGENT_MAIL_ENV_PATH:-$HOME/mcp_agent_mail/.env}" ]]; then
    export AGENT_MAIL_TOKEN="$(grep -E '^HTTP_BEARER_TOKEN=' "${AGENT_MAIL_ENV_PATH:-$HOME/mcp_agent_mail/.env}" | head -n1 | cut -d= -f2- | tr -d "\"'")"
fi
export DISPLAY="${DISPLAY:-:0}"
export ABACUS_HEADLESS=1
PANE_EOF
            print -r -- "echo ${(q)ready_msg}"
            print -r -- "if abacusai --model ${(q)model} --dangerously-skip-permissions; then"
            print -r -- "    echo '✅ Agent finished successfully.'"
            print -r -- "else"
            print -r -- '    echo "⚠️ Agent exited with error code $?!"'
            print -r -- "fi"
        } >| "$script"

        sleep 0.5
        tmux send-keys -t "${session}:${idx}" "source ${(q)script}" C-m

        # Record pane identity for _ntm_beautify_panes (survives ntm adopt,
        # which would otherwise overwrite titles with {s}__{type}_{n}).
        tmux set-option -p -t "${session}:${idx}.1" @agent_persona "$agent_name" 2>/dev/null
        tmux set-option -p -t "${session}:${idx}.1" @agent_model "$model" 2>/dev/null
    }

    # Premium pane headings: per-pane border format with accent color, active
    # indicator, and "Persona · Display Model" title. Reads the identity vars
    # recorded by _ntm_spawn_agent. Call AFTER `ntm adopt` (adopt re-titles).
    _ntm_beautify_panes() {  # <session>
        local session="$1"
        local win wname persona model meta display accent type fmt

        while read -r win wname; do
            persona=$(tmux show-options -pqv -t "${session}:${win}.1" @agent_persona 2>/dev/null)
            model=$(tmux show-options -pqv -t "${session}:${win}.1" @agent_model 2>/dev/null)

            if [[ -n "$persona" ]]; then
                meta="${_NTM_PANE_META[$model]:-}"
                display="${${meta%%|*}:-$model}"
                accent="${${${meta#*|}%%|*}:-#b4befe}"
                fmt=" #{?pane_active,#[fg=${accent}]◆,#[fg=#585b70]◇} #[fg=${accent},bold]${persona}#[fg=#9399b2] · ${display} "
                tmux select-pane -t "${session}:${win}.1" -T "${persona} · ${display}" 2>/dev/null
                tmux set-option -p -t "${session}:${win}.1" pane-border-format "$fmt" 2>/dev/null
                tmux set-option -p -t "${session}:${win}.1" pane-border-style "fg=#45475a" 2>/dev/null
                tmux set-option -p -t "${session}:${win}.1" pane-active-border-style "fg=${accent}" 2>/dev/null
            elif [[ "$wname" == *__overview ]]; then
                fmt=" #{?pane_active,#[fg=#b4befe]◈,#[fg=#585b70]◇} #[fg=#b4befe,bold]Mission Control#[fg=#9399b2] · ${session} "
                tmux select-pane -t "${session}:${win}.1" -T "Mission Control · ${session}" 2>/dev/null
                tmux set-option -p -t "${session}:${win}.1" pane-border-format "$fmt" 2>/dev/null
                tmux set-option -p -t "${session}:${win}.1" pane-active-border-style "fg=#b4befe" 2>/dev/null
            fi
        done < <(tmux list-windows -t "$session" -F "#{window_index} #{window_name}" 2>/dev/null)
    }

    # Render the overview banner into window 1 of a session.
    # Usage: _ntm_show_banner <session> <project_path> <ansi_color> <title> <subtitle> <"win:model:agent"> ...
    #
    # FIX: project_path is now an explicit parameter (was silently re-read from
    # $(pwd), which creates CWD coupling and can diverge from the path actually
    # passed to the agent panes).
    _ntm_show_banner() {
        local session="$1" project_path="$2" color="$3" title="$4" subtitle="$5"
        shift 5
        local W=62
        local border
        border=$(printf '%0.s═' $(seq 1 $W))
        local rule
        rule=$(printf '%0.s─' $(seq 1 $((W-4))))
        local banner
        banner=$(mktemp /tmp/ntm-banner-XXXXX)
        {
            printf '\n'
            printf "\033[${color}m╔%s╗\033[0m\n" "$border"
            printf "\033[${color}m║\033[1;97m%-*s\033[${color}m║\033[0m\n" $W ''
            printf "\033[${color}m║\033[1;97m%-*s\033[${color}m║\033[0m\n" $W "  ${title}"
            printf "\033[${color}m║\033[${color}m  %-*s\033[${color}m║\033[0m\n" $((W-2)) "  ${subtitle}"
            printf "\033[${color}m║%-*s║\033[0m\n" $W ''
            printf "\033[${color}m║  \033[33mSession :\033[1;97m %-*s\033[${color}m║\033[0m\n" $((W-12)) "$session"
            printf "\033[${color}m║  \033[33mProject :\033[1;97m %-*s\033[${color}m║\033[0m\n" $((W-12)) "$project_path"
            printf "\033[${color}m║%-*s║\033[0m\n" $W ''
            printf "\033[${color}m╠%s╣\033[0m\n" "$border"
            printf "\033[${color}m║  \033[33m%-5s %-28s %-*s\033[${color}m║\033[0m\n" 'Win' 'Model' $((W-37)) 'Agent'
            printf "\033[${color}m║  %s  ║\033[0m\n" "$rule"
            for entry in "$@"; do
                local win="${entry%%:*}"; local rest="${entry#*:}"
                local model="${rest%%:*}"; local agent="${rest##*:}"
                printf "\033[${color}m║  \033[97m%-5s %-28s %-*s\033[${color}m║\033[0m\n" \
                    "$win" "$model" $((W-37)) "$agent"
            done
            printf "\033[${color}m║%-*s║\033[0m\n" $W ''
            printf "\033[${color}m║  \033[33m%-*s\033[${color}m║\033[0m\n" $((W-2)) 'Navigate: Ctrl+B, then window number'
            printf "\033[${color}m║%-*s║\033[0m\n" $W ''
            printf "\033[${color}m╚%s╝\033[0m\n" "$border"
            printf '\n'
        } > "$banner"
        tmux send-keys -t "${session}:1" \
            "clear && cat '${banner}' && rm -f '${banner}'" C-m
    }

    # ─────────────────────────────────────────────────────────────────────
    # A-TEAM LAUNCHER  (Claude Sonnet 4.6 · GPT-5.3 Codex · Gemini 3.1 Pro)
    # NTM windows: {s}__overview  {s}__cc_1  {s}__cod_1  {s}__gmi_1
    # Usage: ntm-team [session-name]   (default: basename of CWD)
    #
    # Re-running while the session is live now just re-attaches — the old
    # version re-rendered the banner and stacked a SECOND copy of every
    # agent into the same panes.
    # ─────────────────────────────────────────────────────────────────────
    ntm-team() {
        local session_name="$(_ntm_target "$1")"
        local project_path="$PWD"
        local agent_mail_url="${AGENT_MAIL_URL:-http://127.0.0.1:8765/mcp/}"
        echo "🚀 Launching A-Team for session: ${session_name}"
        echo "📂 Project : ${project_path}"
        echo "📧 Mail    : ${agent_mail_url}"

        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "Session ${session_name} already exists. Attaching..."
            _ntm_attach "$session_name"
            return
        fi

        _ntm_new_session "$session_name" "${session_name}__overview"

        _ntm_show_banner "$session_name" "$project_path" "36" \
            "  MULTI-AGENT DEVELOPMENT TEAM (A-TEAM)" \
            "  ══════════════════════════════════════════════" \
            "2:Claude Sonnet 4.6" \
            "3:GPT-5.3 Codex" \
            "4:Gemini 3.1"

        sleep 1

        _ntm_spawn_agent "$session_name" 2 "${session_name}__cc_1"  \
            "BlueCastle"    "CLAUDE_V4_6_SONNET_LOW_THINKING" "$project_path" "$agent_mail_url"
        _ntm_spawn_agent "$session_name" 3 "${session_name}__cod_1" \
            "GreenMountain" "OPENAI_GPT5_3_CODEX"             "$project_path" "$agent_mail_url"
        _ntm_spawn_agent "$session_name" 4 "${session_name}__gmi_1" \
            "RedLake"       "GEMINI_3_1_PRO"                  "$project_path" "$agent_mail_url"

        # Register agent types so ntm-cc/ntm-cod/ntm-gmi resolve panes.
        # Pane addressing is W.1 (tmux pane-base-index=1); W.0 fails.
        # Never use --by-window (its --dry-run is not honored upstream).
        ntm adopt "$session_name" --cc=2.1 --cod=3.1 --gmi=4.1 &>/dev/null \
            || echo "⚠️ ntm adopt failed for ${session_name} — typed sends (ntm-cc/cod/gmi) will not resolve" >&2
        _ntm_beautify_panes "$session_name"

        _ntm_attach "$session_name"
    }

    # ─────────────────────────────────────────────────────────────────────
    # B-TEAM LAUNCHER  (ZAI GLM 5 · Qwen3 Coder · Grok Code Fast)
    # NTM windows: {s}__overview  {s}__zai_1  {s}__qwen_1  {s}__grok_1
    # Usage: ntm-bteam [session-name]
    # ─────────────────────────────────────────────────────────────────────
    ntm-bteam() {
        local session_name="$(_ntm_target "$1")"
        local project_path="$PWD"
        local agent_mail_url="${AGENT_MAIL_URL:-http://127.0.0.1:8765/mcp/}"
        echo "🚀 Launching B-Team for session: ${session_name}"
        echo "📂 Project : ${project_path}"
        echo "📧 Mail    : ${agent_mail_url}"

        if tmux has-session -t "$session_name" 2>/dev/null; then
            echo "Session ${session_name} already exists. Attaching..."
            _ntm_attach "$session_name"
            return
        fi

        _ntm_new_session "$session_name" "${session_name}__overview"

        _ntm_show_banner "$session_name" "$project_path" "35" \
            "  DEVELOPMENT TEAM - B SQUAD" \
            "  ═════════════════════════════════════════════" \
            "2:ZAI GLM 5" \
            "3:Qwen3 Coder" \
            "4:Grok Code Fast"

        sleep 1

        _ntm_spawn_agent "$session_name" 2 "${session_name}__zai_1"  \
            "ZaiAgent"  "ZAI_GLM_5"       "$project_path" "$agent_mail_url"
        _ntm_spawn_agent "$session_name" 3 "${session_name}__qwen_1" \
            "QwenAgent" "QWEN3_CODER_32B" "$project_path" "$agent_mail_url"
        _ntm_spawn_agent "$session_name" 4 "${session_name}__grok_1" \
            "GrokAgent" "GROK_CODE_FAST"  "$project_path" "$agent_mail_url"

        # Only grok has a native ntm type; zai/qwen stay pane-addressed
        # (ntm-to wrapper, bead 764.2.3).
        ntm adopt "$session_name" --grok=4.1 &>/dev/null \
            || echo "⚠️ ntm adopt failed for ${session_name} — typed sends will not resolve" >&2
        _ntm_beautify_panes "$session_name"

        _ntm_attach "$session_name"
    }

    # ─────────────────────────────────────────────────────────────────────
    # SINGLE-AGENT LAUNCHERS
    # Usage: ntm-{model} [session-name]
    #
    # _ntm_single holds the shared flow: create the session (the idx=1
    # window already created by new-session is reused by _ntm_spawn_agent),
    # spawn one agent, attach. Re-running while the session is live just
    # re-attaches instead of launching a second agent over the first.
    #
    # The mail token is no longer threaded through these launchers — the
    # pane derives it locally (see _ntm_spawn_agent). This also fixes
    # ntm-gemini previously referencing an unset $agent_mail_token.
    # ─────────────────────────────────────────────────────────────────────
    _ntm_single() {  # <session> <win_name> <agent_name> <model> <title>
        local session="$1" win="$2" agent="$3" model="$4" title="$5"
        local agent_mail_url="${AGENT_MAIL_URL:-http://127.0.0.1:8765/mcp/}"
        echo "🚀 Launching ${title}: ${session}"

        if tmux has-session -t "$session" 2>/dev/null; then
            echo "Session ${session} already exists. Attaching..."
            _ntm_attach "$session"
            return
        fi

        _ntm_new_session "$session" "$win"
        _ntm_spawn_agent "$session" 1 "$win" "$agent" "$model" "$PWD" "$agent_mail_url"

        # Register the single pane's agent type (window 1, pane 1) so typed
        # sends resolve. Type flag derived from the model id — mirrors the
        # routing below; no native type exists for qwen/zai (skip adopt).
        local adopt_type=""
        case "$model" in
            CLAUDE*|*SONNET*|*OPUS*|*HAIKU*) adopt_type="--cc=1.1" ;;
            OPENAI*|GPT*|*CODEX*)            adopt_type="--cod=1.1" ;;
            GEMINI*)                         adopt_type="--gmi=1.1" ;;
            GROK*)                           adopt_type="--grok=1.1" ;;
        esac
        if [[ -n "$adopt_type" ]]; then
            ntm adopt "$session" "${=adopt_type}" &>/dev/null \
                || echo "⚠️ ntm adopt failed for ${session} — typed sends will not resolve" >&2
        fi
        _ntm_beautify_panes "$session"

        _ntm_attach "$session"
    }

    # Claude Sonnet 4.6
    ntm-claude() {
        local s="$(_ntm_target "$1")"
        _ntm_single "$s" "${s}__claude" "Claude" "CLAUDE_V4_6_SONNET_LOW_THINKING" "Claude Sonnet 4.6"
    }

    # GPT-5.3 Codex
    ntm-gpt() {
        local s="$(_ntm_target "$1")"
        _ntm_single "$s" "${s}__gpt" "GPT" "OPENAI_GPT5_3_CODEX" "GPT-5.3 Codex"
    }

    # Gemini 3.1 Pro
    ntm-gemini() {
        local s="$(_ntm_target "$1")"
        _ntm_single "$s" "${s}__gemini" "Gemini" "GEMINI_3_1_PRO" "Gemini 3.1 Pro"
    }

    # Qwen3 Coder
    ntm-qwen() {
        local s="$(_ntm_target "$1")"
        _ntm_single "$s" "${s}__qwen" "Qwen" "QWEN3_CODER_32B" "Qwen3 Coder"
    }

    # ─────────────────────────────────────────────────────────────────────
    # NTM CONVENIENCE WRAPPERS
    # ─────────────────────────────────────────────────────────────────────

    # ntm exits 0 even on "no matching panes" / "session not found" (verified
    # on this build), so wrappers must detect failures themselves.
    _ntm_send_guard() {  # <session> <ntm-output-file> <context-desc>
        if ! tmux has-session -t "$1" 2>/dev/null; then
            echo "✖ ntm send: session '$1' not found (tmux ls to list)" >&2
            return 1
        fi
        if grep -qiE "no matching panes|^Error:" "$2" 2>/dev/null; then
            echo "✖ ntm send failed ($3): $(grep -iE 'no matching panes|^Error:' "$2" | head -1)" >&2
            return 1
        fi
    }

    # Broadcast to all agents in current session
    function ntm-all {
        local s="$(_ntm_session)" out
        out=$(mktemp /tmp/ntm-send-XXXXXX)
        ntm send "$s" "$@" 2>&1 | tee "$out"
        _ntm_send_guard "$s" "$out" "ntm-all"
        local rc=$?
        rm -f "$out"
        return $rc
    }

    # Targeted sends by agent type
    function ntm-cc  {
        local s="$(_ntm_session)" out
        out=$(mktemp /tmp/ntm-send-XXXXXX)
        ntm send "$s" --cc  "$@" 2>&1 | tee "$out"
        _ntm_send_guard "$s" "$out" "ntm-cc (no Claude-type panes? session adopted?)"
        local rc=$?
        rm -f "$out"
        return $rc
    }
    function ntm-cod {
        local s="$(_ntm_session)" out
        out=$(mktemp /tmp/ntm-send-XXXXXX)
        ntm send "$s" --cod "$@" 2>&1 | tee "$out"
        _ntm_send_guard "$s" "$out" "ntm-cod (no Codex-type panes? session adopted?)"
        local rc=$?
        rm -f "$out"
        return $rc
    }
    function ntm-gmi {
        local s="$(_ntm_session)" out
        out=$(mktemp /tmp/ntm-send-XXXXXX)
        ntm send "$s" --gmi "$@" 2>&1 | tee "$out"
        _ntm_send_guard "$s" "$out" "ntm-gmi (no Gemini-type panes? session adopted?)"
        local rc=$?
        rm -f "$out"
        return $rc
    }

    # Interrupt / dashboard / palette / activity monitor
    function ntm-stop    { ntm interrupt "$(_ntm_session)"; }
    function ntm-dash    { ntm dashboard "$(_ntm_session)"; }
    function ntm-palette { ntm palette   "$(_ntm_session)"; }
    function ntm-watch   { ntm activity  "$(_ntm_session)" --watch; }

    # Save all pane outputs to ~/logs/{session}/
    function ntm-save {
        local s outdir
        s="$(_ntm_session)"
        outdir="$HOME/logs/${s}"
        mkdir -p "$outdir"
        ntm save "$s" -o "$outdir"
        echo "✅ Outputs saved to ${outdir}"
    }

    # Copy Claude pane outputs to clipboard
    function ntm-copy-cc { ntm copy "$(_ntm_session)" --cc; }

    # Kill a whole session (default: current). Pass a name to kill another
    # session — killing your current session from inside ends this shell too.
    function ntm-kill { tmux kill-session -t "${1:-$(_ntm_session)}"; }

    # Show rich pane status (fixed jq interpolation from original)
    function ntm-status {
        local s
        s="$(_ntm_session)"
        ntm status "$s" 2>/dev/null || {
            ntm --robot-status --json 2>/dev/null \
            | jq -r '.sessions[]?.agents[]? | "\(.pane): \(.agent_type) - active:\(.active)"' \
            || echo "No NTM agents running for session '${s}'"
        }
    }

    alias ntm-terse='ntm --robot-terse'

    # NOTE: removed ntm-start / ntm-end / ntm-init aliases — the referenced
    # ~/scripts/ntm-daily-start.sh, ntm-daily-end.sh and ntm-init-project.sh
    # scripts do not exist anywhere on this machine (verified 2026-07-27).

    # ─────────────────────────────────────────────────────────────────────
    # AGENT MAIL CLI HELPER
    # Usage: agent_mail_send <to_agent> <subject> <body>
    # ─────────────────────────────────────────────────────────────────────
    agent_mail_send() {
        local to_agent="$1" subject="$2" body="$3"
        local project="${AGENT_MAIL_PROJECT:-$(pwd)}"
        local from_agent="${AGENT_MAIL_AGENT:-$AGENT_NAME}"
        local mail_url="${AGENT_MAIL_URL:-http://127.0.0.1:8765/mcp/}"
        local mail_token
        mail_token="$(_ntm_mail_token)"

        if [[ -z "$to_agent" || -z "$subject" || -z "$body" ]]; then
            echo "Usage: agent_mail_send <to_agent> <subject> <body>"
            echo "Example: agent_mail_send BlueCastle 'API Design' 'Please review the REST endpoints'"
            return 1
        fi

        # FIX: build JSON via jq --arg so that quotes, backslashes, newlines and
        # other special characters in any argument cannot break or inject the
        # JSON payload (previously raw shell interpolation was used, which would
        # produce malformed JSON for any subject/body containing " or \).
        local payload
        payload=$(jq -n \
            --arg pk   "$project"    \
            --arg from "$from_agent" \
            --arg to   "$to_agent"   \
            --arg subj "$subject"    \
            --arg body "$body"       \
            '{
              "jsonrpc": "2.0",
              "id": 3,
              "method": "tools/call",
              "params": {
                "name": "send_message",
                "arguments": {
                  "project_key": $pk,
                  "sender_name": $from,
                  "to":          [$to],
                  "subject":     $subj,
                  "body_md":     $body,
                  "importance":  "normal"
                }
              }
            }')

        # FIX: zsh never word-splits an unquoted expansion, so the previous
        # ${mail_token:+-H "..."} form reached curl as ONE argument
        # ("-H Authorization: Bearer tok") and only worked by accident of
        # curl's bundled-flag parsing. Build the header as an array instead:
        # "${auth_header[@]}" keeps "-H" and its value as separate arguments
        # and expands to zero arguments when the token is empty.
        local -a auth_header=()
        [[ -n "$mail_token" ]] && auth_header=(-H "Authorization: Bearer $mail_token")

        curl -s -X POST "$mail_url" \
            -H "Content-Type: application/json" \
            "${auth_header[@]}" \
            -d "$payload" \
        | jq -r '.result.deliveries[] | "✅ Delivered to \(.recipient)"'
    }

fi  # end: command -v ntm

# ═══════════════════════════════════════════════════════════════════════════
# 5. SESSION UTILITIES
# ═══════════════════════════════════════════════════════════════════════════

# The "Nuke" command — kills EVERY abacusai agent you own (not just strays;
# any agents running in tmux die with their server below) and, when possible,
# respawns a clean login shell.
#
# Behavior depends on where it runs:
#   - INSIDE tmux: `tmux kill-server` terminates this pane's shell, so
#     nothing after it can execute — there is NO respawn (the old comment
#     claiming `exec zsh -l` "works correctly inside tmux" was wrong; that
#     line was unreachable).
#   - OUTSIDE tmux: the shell respawns clean via `exec zsh -l`, which
#     re-sources this file.
nuke-session() {
    pkill -u "$USER" -f "abacusai" 2>/dev/null
    tmux kill-server 2>/dev/null
    [[ -z "$TMUX" ]] && exec zsh -l
}

# Fix grep (system has ripgrep aliased which breaks -E flag)
alias grep='command grep'

# ═══════════════════════════════════════════════════════════════════════════
# 6. APP SPECIFIC
# ═══════════════════════════════════════════════════════════════════════════
alias am='cd "/home/ubuntu/mcp_agent_mail" && scripts/run_server_with_token.sh'

# ═══════════════════════════════════════════════════════════════════════════
# 7. HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════════════
abacus-doctor() {
    echo "════════════════════════════════════"
    echo "  Abacus CLI + NTM Health Check"
    echo "════════════════════════════════════"
    if ! command -v abacusai &>/dev/null; then echo "✖ Abacus CLI missing"; return 1; fi
    echo "✔ Abacus CLI installed"

    if abacusai -p "test" &>/dev/null; then
        echo "✔ Abacus CLI authenticated"
    else
        echo "✖ Abacus CLI not authenticated"
        return 1
    fi

    if command -v ntm &>/dev/null; then
        echo "✔ NTM installed ($(ntm --version 2>/dev/null || echo 'version unknown'))"
        ntm deps 2>/dev/null | grep -q "tmux" && echo "✔ tmux available" || echo "⚠ tmux not found"
    else
        echo "⚠ NTM not installed — run: brew install dicklesworthstone/tap/ntm"
    fi

    curl -fsS http://127.0.0.1:8765/health &>/dev/null \
        && echo "✔ Agent Mail running" \
        || echo "⚠ Agent Mail down (run 'am')"
}

# ═══════════════════════════════════════════════════════════════════════════
# 8. MISC
# ═══════════════════════════════════════════════════════════════════════════
alias htui='docker exec -it helix node /app/node_modules/.pnpm/@mariozechner+pi-coding-agent@0.52.12_ws@8.19.0_zod@4.3.6/node_modules/@mariozechner/pi-coding-agent/dist/cli.js tui'
alias gohelix="docker exec -it helix bash -c \"cd /home/node/.openclaw/workspace/vps_files && exec bash\""

# OpenClaw Completion
[ -f "/home/ubuntu/.openclaw/completions/openclaw.zsh" ] && source "/home/ubuntu/.openclaw/completions/openclaw.zsh"

unalias br 2>/dev/null  # br installer - remove conflicting alias

# ═══════════════════════════════════════════════════════════════════════════
# 9. PATH ADDITIONS
# ═══════════════════════════════════════════════════════════════════════════
# Note: ~/.local/bin is already added in section 2; the guard below is
# retained for safety (e.g. if section 2 is conditionally skipped) but
# will be a no-op in normal operation.
if [[ ":$PATH:" != *":/home/ubuntu/.local/bin:"* ]]; then
  export PATH="/home/ubuntu/.local/bin:$PATH"
fi
if [[ ":$PATH:" != *":/home/ubuntu/.cargo/bin:"* ]]; then
  export PATH="/home/ubuntu/.cargo/bin:$PATH"
fi

# Prefer bun's global bin over npm-global for CLI tools
   [[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:${PATH//:\/home\/ubuntu\/.npm-global\/bin/}:/home/ubuntu/.npm-global/bin"

# NOTE: `bd` must stay resolved to the beads binary (~/go/bin/bd) used by
# the project issue-tracking workflow. Do NOT alias it to `br` (MCP Agent
# Mail's tracker) — call `br` directly when you need that tool.

# ═══════════════════════════════════════════════════════════════════════════
# 10. SENSITIVE KEYS  →  move these to ~/.zshrc.local !
# ⚠ WARNING: API keys in version-controlled dotfiles are a security risk.
# Move the exports below into ~/.zshrc.local (git-ignored) instead:
#
# export ABACUS_API_KEY=...
# export GEMINI_API_KEY=...
# ═══════════════════════════════════════════════════════════════════════════

# D-Bus & keyring (headless mode support)
# FIX: the previous version ran `dbus-launch` in EVERY shell where the
# address was unset, and the new address was never shared — so each shell
# spawned another dbus-daemon that lived forever. Now: prefer the systemd
# user bus, else reuse a cached dbus-launch address while its daemon is
# still alive, and only launch a new daemon as a last resort.
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    _dbus_cache="$HOME/.cache/dbus-session-bus"
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    elif [ -f "$_dbus_cache" ] && [ -f "$_dbus_cache.pid" ] \
            && kill -0 "$(cat "$_dbus_cache.pid")" 2>/dev/null; then
        export DBUS_SESSION_BUS_ADDRESS="$(cat "$_dbus_cache")"
    else
        eval "$(dbus-launch --sh-syntax)"
        mkdir -p "$HOME/.cache"
        printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$_dbus_cache"
        printf '%s\n' "$DBUS_SESSION_BUS_PID" > "$_dbus_cache.pid"
    fi
    unset _dbus_cache
fi
if ! pgrep -u "$USER" gnome-keyring-d > /dev/null; then
    echo -n "" | gnome-keyring-daemon --unlock > /dev/null 2>&1
fi

# ═══════════════════════════════════════════════════════════════════════════
# 11. LOCAL OVERRIDES  (last — wins over everything above)
# Put secrets, machine-specific tweaks, and API key exports here:
#   ~/.zshrc.local
# ═══════════════════════════════════════════════════════════════════════════
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# NOTE: MCP Agent Mail's installer used to inject two blocks here:
#   1. a duplicate ~/.cargo/bin PATH addition (already handled, with a
#      duplicate guard, in section 9 above), and
#   2. `alias bd='br'` — which shadowed the real beads binary at
#      ~/go/bin/bd and rerouted the project's `bd` issue-tracking workflow
#      to a different tool (Agent Mail's `br` tracker, a separate SQLite
#      store with a different command set).
# Both removed. Invoke Agent Mail's tracker as `br` directly. If the
# installer re-adds these blocks on update, delete them again.

alias acfs-force-update='./scripts/lib/security.sh --update-checksums > checksums.yaml && acfs update --stack'

alias acfs-sync='cd ~/.acfs/scripts/lib && ./security.sh --update-checksums > checksums.yaml && cp checksums.yaml ../checksums.yaml && cp checksums.yaml ~/.acfs/checksums.yaml'