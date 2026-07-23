#!/usr/bin/env python3
"""Static arity-contract guard for Roblox RemoteEvents (TASK 21.2).

Mechanizes the exact class of bug fixed in TASK 21.1: a client
`OnClientEvent:Connect(function(...))` handler that declares FEWER parameters
than the server sends via `FireClient` / `FireAllClients`. Luau binds FireClient
arguments positionally with zero arity checking, so a too-short handler silently
binds each param to the wrong argument and only blows up at runtime when a
mistyped value hits a typed operation (e.g. `number > string`) — far too late.

WHAT IT CHECKS
  1. Every server-side `<remote>:FireClient(player, ...)` and
     `<remote>:FireAllClients(...)` call is parsed; the payload argument count
     is computed (FireClient: total args - 1 for the player; FireAllClients:
     total args, no player). The MAX payload across all fire sites per remote
     is the contract the client must be able to receive.
  2. Every client-side `<remote>.OnClientEvent:Connect(...)` handler is parsed
     and its declared parameter count is computed. Inline `function(...)` and
     function-reference handlers (e.g. `:Connect(showNotification)`) are both
     resolved.
  3. For each remote that the server fires AND the client handles, the check
     FAILS if the client handler declares fewer params than the server's max
     payload (more params is safe — they bind nil).

Directionality falls out naturally: client->server remotes (FireServer /
OnServerEvent) and RemoteFunctions (InvokeClient / OnClientInvoke) are never
matched by the FireClient/OnClientEvent patterns, so they are out of scope.

Exit code: 0 = contract holds, 1 = at least one arity mismatch.
"""
from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass


@dataclass
class FireSite:
    remote: str
    path: str
    line: int
    kind: str  # "FireClient" or "FireAllClients"
    payload: int  # arg count the client receives


@dataclass
class HandlerSite:
    remote: str
    path: str
    line: int
    params: int


# ---------------------------------------------------------------------------
# Lexical mask: mark which source characters are "normal" code vs inside a
# string literal or comment. Used both to discard false regex matches and to
# ignore parens/commas that live inside strings/comments when depth-counting.
# ---------------------------------------------------------------------------
def compute_normal_mask(text: str) -> list[bool]:
    n = len(text)
    normal = [True] * n
    i = 0
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        # Long comment [[...]] / [=[ ... ]=] (may follow --) or long string
        if c == "-" and nxt == "-":
            # Line vs long comment?
            j = i + 2
            # skip whitespace
            while j < n and text[j] in " \t":
                j += 1
            if j < n and text[j] == "[":
                # count = signs
                k = j + 1
                eq = 0
                while k < n and text[k] == "=":
                    eq += 1
                    k += 1
                if k < n and text[k] == "[":
                    close = "]" + "=" * eq + "]"
                    end = text.find(close, k + 1)
                    if end == -1:
                        end = n
                    else:
                        end += len(close)
                    for x in range(i, end):
                        if x < n and text[x] != "\n":
                            normal[x] = False
                    i = end
                    continue
            # line comment
            j = i + 2
            while j < n and text[j] != "\n":
                normal[j] = False
                j += 1
            normal[i] = False
            normal[i + 1] = False
            i = j
            continue
        if c == "[" and nxt == "[" or (c == "[" and nxt == "="):
            # long string [[...]] or [=[ ... ]=]
            eq = 0
            k = i + 1
            while k < n and text[k] == "=":
                eq += 1
                k += 1
            if k < n and text[k] == "[":
                close = "]" + "=" * eq + "]"
                end = text.find(close, k + 1)
                if end == -1:
                    end = n
                else:
                    end += len(close)
                for x in range(i, end):
                    if x < n and text[x] != "\n":
                        normal[x] = False
                i = end
                continue
        if c == '"' or c == "'":
            quote = c
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == quote:
                    j += 1
                    break
                if text[j] == "\n":
                    break
                j += 1
            for x in range(i, j):
                normal[x] = False
            i = j
            continue
        i += 1
    return normal


def line_of(text: str, idx: int) -> int:
    return text.count("\n", 0, idx) + 1


# ---------------------------------------------------------------------------
# Depth-aware argument / parameter counting from an opening paren, ignoring
# brackets/braces/parens and commas that live inside strings or comments.
# ---------------------------------------------------------------------------
def count_call_args(text: str, mask: list[bool], open_idx: int) -> int:
    depth = 0
    argcount = 0
    seen_content = False
    i = open_idx
    n = len(text)
    while i < n:
        if not mask[i]:
            i += 1
            continue
        c = text[i]
        if c in "([{":
            depth += 1
            if depth > 1:
                seen_content = True
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                if seen_content:
                    argcount += 1
                return argcount
        elif c == "," and depth == 1:
            argcount += 1
            seen_content = False
        elif not c.isspace():
            seen_content = True
        i += 1
    return argcount  # unterminated; treat what we have as the count


FIRE_RE = re.compile(r"\.([A-Za-z_]\w*)\s*:\s*Fire(Client|AllClients)\s*\(")
HANDLER_RE = re.compile(r"([A-Za-z_]\w*)\s*\.\s*OnClientEvent\s*:\s*Connect\s*\(")


def collect_server_fires(server_dir: str) -> list[FireSite]:
    sites: list[FireSite] = []
    for root, _dirs, files in os.walk(server_dir):
        for fname in files:
            if not fname.endswith(".lua"):
                continue
            path = os.path.join(root, fname)
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            mask = compute_normal_mask(text)
            for m in FIRE_RE.finditer(text):
                if not mask[m.start()]:
                    continue
                remote = m.group(1)
                kind = "Fire" + m.group(2)
                paren = m.end() - 1  # index of '('
                total = count_call_args(text, mask, paren)
                payload = total - 1 if kind == "FireClient" else total
                payload = max(payload, 0)
                sites.append(FireSite(remote, path, line_of(text, m.start()), kind, payload))
    return sites


def resolve_ref_params(text: str, mask: list[bool], name: str) -> int | None:
    patterns = [
        rf"local\s+function\s+{re.escape(name)}\s*\(",
        rf"function\s+{re.escape(name)}\s*\(",
        rf"\b{re.escape(name)}\s*=\s*function\s*\(",
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if m and mask[m.start()]:
            paren = m.end() - 1
            return count_call_args(text, mask, paren)
    return None


def collect_client_handlers(client_dir: str) -> list[HandlerSite]:
    sites: list[HandlerSite] = []
    for root, _dirs, files in os.walk(client_dir):
        for fname in files:
            if not fname.endswith(".lua"):
                continue
            path = os.path.join(root, fname)
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            mask = compute_normal_mask(text)
            for m in HANDLER_RE.finditer(text):
                if not mask[m.start()]:
                    continue
                remote = m.group(1)
                paren = m.end() - 1  # index of '(' for Connect(
                # Determine handler shape: inline function(...) or reference.
                j = paren + 1
                while j < len(text) and text[j].isspace():
                    j += 1
                # inline function?
                if text[j:j + 8] == "function":
                    # find the '(' after the function keyword (skip optional name)
                    k = j + 8
                    while k < len(text) and text[k] != "(":
                        k += 1
                    params = count_call_args(text, mask, k)
                else:
                    # bare identifier reference
                    mm = re.match(r"([A-Za-z_]\w*)\b", text[j:])
                    if not mm:
                        sites.append(HandlerSite(remote, path, line_of(text, m.start()), -1))
                        continue
                    params = resolve_ref_params(text, mask, mm.group(1))
                    if params is None:
                        params = -1
                sites.append(HandlerSite(remote, path, line_of(text, m.start()), params))
    return sites


def rel(path: str, root: str) -> str:
    return os.path.relpath(path, root)


def main() -> int:
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    server_dir = os.path.join(root, "src", "server")
    client_dir = os.path.join(root, "src", "client")
    if not os.path.isdir(server_dir) or not os.path.isdir(client_dir):
        print("ERROR: src/server or src/client not found under project root " + root, file=sys.stderr)
        return 2

    fires = collect_server_fires(server_dir)
    handlers = collect_client_handlers(client_dir)

    # max payload sent per remote
    max_payload: dict[str, int] = {}
    for f in fires:
        max_payload[f.remote] = max(max_payload.get(f.remote, 0), f.payload)

    handler_params: dict[str, list[HandlerSite]] = {}
    for h in handlers:
        handler_params.setdefault(h.remote, []).append(h)

    print(f"server fire sites: {len(fires)}  client handlers: {len(handlers)}")
    print()

    checked = sorted(set(max_payload) & set(handler_params))
    fails = []
    print(f"{'remote':<22} {'server max payload':>18} {'client params':>14}  result")
    print("-" * 70)
    for remote in checked:
        sp = max_payload[remote]
        hp = max(h.params for h in handler_params[remote])
        status = "OK" if hp >= sp else "FAIL"
        print(f"{remote:<22} {sp:>18} {hp:>14}  {status}")
        if hp < sp:
            fails.append((remote, sp, hp, handler_params[remote]))

    # informational: client handlers with no server fire (could be dead, or
    # purely client->server wiring we don't model) -- not a failure.
    orphans_c = sorted(set(handler_params) - set(max_payload))
    orphans_s = sorted(set(max_payload) - set(handler_params))
    if orphans_c:
        print()
        print("client handlers with no matching server FireClient/FireAllClients (info):")
        for r in orphans_c:
            print(f"  {r}")
    if orphans_s:
        print()
        print("server fires with no matching client OnClientEvent handler (info):")
        for r in orphans_s:
            print(f"  {r}")

    print()
    if fails:
        print("FAIL — client handler arity below server payload contract:")
        for remote, sp, hp, hsites in fails:
            loc = ", ".join(f"{rel(h.path, root)}:{h.line}" for h in hsites)
            print(f"  {remote}: client handler(s) declare {hp} param(s) but server sends up to {sp} payload arg(s) -> {loc}")
        return 1
    print(f"OK — {len(checked)} remote(s) checked, arity contract holds.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
