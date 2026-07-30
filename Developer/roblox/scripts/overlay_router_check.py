#!/usr/bin/env python3
"""Static overlay-input-router contract guard (harborheist-m5fb / EPIC 42.3).

Mechanizes the exact class of bug that silently broke the game in
harborheist-3xlw: the three timed minigame overlays (cast / bite / raid)
register input handlers in `overlayInputHandlers.<name>`, and a SINGLE
UserInputService.InputBegan router at the bottom of init.client.lua
dispatches to the active one. When commit 6f1a0c8 appended the toast-history
block to the file end it overwrote that router — every handler stayed
registered but was never invoked, so the minigames could not receive clicks.
The failure shipped silently for days because no test exercised client input.

WHY STRING/COMMENT MASKING MATTERS (and why a naive grep is WRONG here):
when the router code was deleted, its detailed explanatory COMMENT block
("...the ONE UserInputService.InputBegan router...") survived. Any check
that greps raw text for the dispatch pattern would have matched the comment
and reported the wiring as intact — the exact false sense of security that
let 3xlw slip through. This script masks comments and string literals first
and only inspects real code.

WHAT IT CHECKS (all in src/client/init.client.lua)
  1. REGISTRATIONS: every `overlayInputHandlers.<name> = function(...)`
     (or `= <identifier>`) is collected.
  2. ACTIVATIONS: every `requestOverlay("<name>")` / `releaseOverlay("<name>")`
     string name is collected (overlays that actually open/close).
  3. ROUTER: a real (non-comment) dispatch exists — a reference to
     `overlayInputHandlers` (optionally indexed by `activeOverlay`) inside a
     `UserInputService.InputBegan:Connect(...)` body.
  4. FOR EVERY registered name that is also activated: FAIL if the router
     is absent (handler registered but never dispatched = dead minigame).

Exit code: 0 = contract holds, 1 = violation found, 2 = environment error.
"""
from __future__ import annotations

import os
import re
import sys


# ---------------------------------------------------------------------------
# Lexical mask: mark which source characters are "normal" code vs inside a
# string literal or comment. Copied from remote_arity_check.py (TASK 21.2) —
# identical Lua/Luau lexing rules (line/long comments, quoted + long strings).
# ---------------------------------------------------------------------------
def compute_normal_mask(text: str) -> list[bool]:
    n = len(text)
    normal = [True] * n
    i = 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        # Long comment --[[...]] / --[=[ ... ]=] or line comment
        if c == "-" and nxt == "-":
            j = i + 2
            while j < n and text[j] in " \t":
                j += 1
            if j < n and text[j] == "[":
                k = j + 1
                eq = 0
                while k < n and text[k] == "=":
                    eq += 1
                    k += 1
                if k < n and text[k] == "[":
                    close = "]" + ("=" * eq) + "]"
                    end = text.find(close, k + 1)
                    end = (end + len(close)) if end != -1 else n
                    for p in range(i, end):
                        normal[p] = False
                    i = end
                    continue
            # line comment to end of line
            j = text.find("\n", i)
            j = j if j != -1 else n
            for p in range(i, j):
                normal[p] = False
            i = j
            continue
        # Quoted string
        if c in ('"', "'"):
            quote = c
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == quote:
                    j += 1
                    break
                j += 1
            for p in range(i, min(j, n)):
                normal[p] = False
            i = j
            continue
        # Long string [[...]] / [=[ ... ]=]
        if c == "[":
            k = i + 1
            eq = 0
            while k < n and text[k] == "=":
                eq += 1
                k += 1
            if k < n and text[k] == "[":
                close = "]" + ("=" * eq) + "]"
                end = text.find(close, k + 1)
                end = (end + len(close)) if end != -1 else n
                for p in range(i, end):
                    normal[p] = False
                i = end
                continue
        i += 1
    return normal


def code_only(text: str, normal: list[bool]) -> str:
    """Return text with comment/string chars blanked to spaces (same length)."""
    chars = list(text)
    for p, ok in enumerate(normal):
        if not ok:
            chars[p] = " " if text[p] != "\n" else "\n"
    return "".join(chars)


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(root, "src", "client", "init.client.lua")
    if not os.path.isfile(path):
        print(f"ENV ERROR: {path} not found", file=sys.stderr)
        return 2

    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    normal = compute_normal_mask(text)
    code = code_only(text, normal)

    # 1. Registered overlay input handlers (real code only).
    registered = set(
        re.findall(r"overlayInputHandlers\.([A-Za-z_][A-Za-z0-9_]*)\s*=", code)
    )

    # 2. Activated overlays: requestOverlay("x") / releaseOverlay("x").
    #    String args are masked in `code`, so re-scan raw text but only for
    #    these literal call sites (their arg string is what we need).
    activated = set(
        re.findall(r"(?:requestOverlay|releaseOverlay)\(\s*[\"']([A-Za-z_]+)[\"']", text)
    )

    # 3. Router: a real InputBegan connection whose body references
    #    overlayInputHandlers (the dispatch). Scan each Connect block in code.
    router_found = False
    for m in re.finditer(
        r"UserInputService\.InputBegan:Connect\s*\(", code
    ):
        # Take a generous window after the connect start and look for the
        # dispatch reference within it (the router body is short).
        window = code[m.start(): m.start() + 400]
        if "overlayInputHandlers" in window:
            router_found = True
            break

    print("=== Overlay input-router contract check (harborheist-m5fb) ===")
    print(f"Registered handlers : {sorted(registered) or '(none)'}")
    print(f"Activated overlays  : {sorted(activated) or '(none)'}")
    print(f"Router dispatch     : {'FOUND' if router_found else 'MISSING'}")

    # Every handler that an overlay actually opens for MUST be dispatchable.
    needs_router = registered & activated
    if registered and not router_found:
        print(
            f"\nFAIL: overlay input handlers registered {sorted(registered)} "
            "but NO UserInputService.InputBegan router dispatches to them — "
            "minigames cannot receive input (harborheist-3xlw class).",
            file=sys.stderr,
        )
        return 1
    # A handler that is registered but never activated is suspicious but not
    # fatal (may be opened indirectly); warn only.
    unactivated = registered - activated
    if unactivated:
        print(f"\nWARN: handlers registered but never requestOverlay()-ed: {sorted(unactivated)}")

    print("\nOK: overlay input-router contract holds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
