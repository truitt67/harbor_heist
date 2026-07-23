#!/usr/bin/env python3
"""
Agent Mail CLI - A Python-based command-line interface for Agent Mail.

This is a drop-in replacement for the bash agent-mail-helpers.sh that works
cross-platform and provides better error handling, JSON output, and agent-friendly
commands.

Usage:
    python agent_mail_cli.py register <name_hint> <model> [project_path]
    python agent_mail_cli.py agents [project_path]
    python agent_mail_cli.py inbox <agent_name> <token> [limit] [urgent_only] [include_bodies]
    python agent_mail_cli.py send <from_agent> <to_csv> <subject> <body>
    python agent_mail_cli.py reserve <agent_name> <token> <paths_csv> [ttl] [exclusive]
    python agent_mail_cli.py release <agent_name> <token> <paths_csv>
    python agent_mail_cli.py health
    python agent_mail_cli.py session-start <name_hint> <model> [project_path]

Environment Variables:
    AGENT_MAIL_URL      - MCP server URL (default: http://127.0.0.1:8765/mcp/)
    AGENT_MAIL_PROJECT  - Default project key (default: home-ubuntu-developer-roblox)
    PROJECT_KEY         - Accepted as a fallback when AGENT_MAIL_PROJECT is unset
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

AGENT_MAIL_URL = os.getenv("AGENT_MAIL_URL", "http://127.0.0.1:8765/mcp/")
PROJECT_KEY = (
    os.getenv("AGENT_MAIL_PROJECT")
    or os.getenv("PROJECT_KEY")
    or "home-ubuntu-developer-roblox"
)
# Ensure we never accidentally use a filesystem path as the project key.
if PROJECT_KEY.startswith("/home/") or PROJECT_KEY.startswith("/"):
    PROJECT_KEY = "home-ubuntu-developer-roblox"
# When agents register, the server may return a different project_key.
# We track the authoritative key per-agent to avoid mismatch errors.
_REGISTERED_PROJECT_KEY: str | None = None


def _set_project_key(key: str) -> None:
    """Persist the authoritative project key for this process."""
    global _REGISTERED_PROJECT_KEY
    _REGISTERED_PROJECT_KEY = key


def _active_project() -> str:
    """Return the project key to use for API calls."""
    return _REGISTERED_PROJECT_KEY or PROJECT_KEY


def _slug(path: str) -> str:
    """Normalize a path into a project slug."""
    return "".join(c if c.isalnum() else "-" for c in path.lower().strip("/"))


def _rpc(method: str, params: dict) -> dict:
    """Make a JSON-RPC 2.0 call to the Agent Mail MCP server."""
    payload = json.dumps(
        {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
    ).encode("utf-8")

    req = urllib.request.Request(
        AGENT_MAIL_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"Error: HTTP {e.code} - {e.read().decode()}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(
            f"Error: Cannot reach Agent Mail server at {AGENT_MAIL_URL} - {e.reason}",
            file=sys.stderr,
        )
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


def _tool(name: str, arguments: dict) -> dict:
    """Call an Agent Mail tool via JSON-RPC tools/call."""
    resp = _rpc("tools/call", {"name": name, "arguments": arguments})
    if resp.get("error"):
        msg = resp["error"].get("message", "Tool error")
        print(f"Error: {msg}", file=sys.stderr)
        sys.exit(1)
    result = resp.get("result", {})
    if result.get("isError"):
        text = result.get("content", [{}])[0].get("text", "Unknown tool error")
        print(f"Error: {text}", file=sys.stderr)
        sys.exit(1)
    return result


def _extract_text(result: dict) -> str:
    """Extract text content from a tool result."""
    content = result.get("content", [{}])
    if not content:
        return ""
    return content[0].get("text", "")


def cmd_register(args):
    """Register a new agent with Agent Mail."""
    project = args.project or PROJECT_KEY

    result = _tool(
        "register_agent",
        {
            "name": args.name_hint,
            "program": "abacusai",
            "model": args.model,
            "project_key": project,
        },
    )
    text = _extract_text(result)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        data = {
            "name": args.name_hint,
            "registration_token": "",
            "project_key": project,
        }

    name = data.get("name", args.name_hint)
    token = data.get("registration_token", "")
    # The server may canonicalise the project key; prefer its version.
    authoritative_project = data.get("project_key", project)
    _set_project_key(authoritative_project)

    if not token:
        print("Error: Registration failed - no token returned", file=sys.stderr)
        sys.exit(1)

    output = {
        "agent_name": name,
        "registration_token": token,
        "project_key": authoritative_project,
        "model": args.model,
        "export_commands": [
            f"export AGENT_NAME='{name}'",
            f"export REGISTRATION_TOKEN='{token}'",
            f"export AGENT_MAIL_PROJECT='{authoritative_project}'",
        ],
    }
    print(json.dumps(output, indent=2))


def cmd_agents(args):
    """List all agents in the project."""
    project = args.project or PROJECT_KEY
    slug = _slug(project)
    resp = _rpc("resources/read", {"uri": f"resource://project/{slug}"})
    result = resp.get("result", {})
    contents = result.get("contents", [{}])[0].get("text", "{}")
    try:
        data = json.loads(contents)
    except json.JSONDecodeError:
        data = {}
    print(json.dumps(data.get("agents", []), indent=2))


def cmd_inbox(args):
    """Fetch an agent's inbox."""
    result = _tool(
        "fetch_inbox",
        {
            "project_key": _active_project(),
            "agent_name": args.agent_name,
            "registration_token": args.token,
            "limit": int(args.limit),
            "urgent_only": args.urgent_only.lower() == "true",
            "include_bodies": args.include_bodies.lower() == "true",
        },
    )
    text = _extract_text(result)
    try:
        messages = json.loads(text)
    except json.JSONDecodeError:
        messages = []
    print(json.dumps(messages, indent=2))


def cmd_send(args):
    """Send a message to other agents."""
    recipients = [name.strip() for name in args.to_csv.split(",") if name.strip()]
    sender_token = args.sender_token or os.getenv("REGISTRATION_TOKEN", "")
    result = _tool(
        "send_message",
        {
            "project_key": _active_project(),
            "sender_name": args.from_agent,
            "sender_token": sender_token,
            "to": recipients,
            "subject": args.subject,
            "body_md": args.body,
            "thread_id": None,
            "importance": "normal",
        },
    )
    text = _extract_text(result)
    print(json.dumps({"status": "sent", "detail": text}, indent=2))


def cmd_reserve(args):
    """Reserve files for editing."""
    result = _tool(
        "file_reservation_paths",
        {
            "project_key": _active_project(),
            "agent_name": args.agent_name,
            "registration_token": args.token,
            "paths": [p.strip() for p in args.paths.split(",") if p.strip()],
            "ttl_seconds": int(args.ttl),
            "exclusive": args.exclusive.lower() == "true",
            "reason": args.reason or "",
        },
    )
    text = _extract_text(result)
    print(json.dumps({"status": "reserved", "detail": text}, indent=2))


def cmd_release(args):
    """Release file reservations."""
    result = _tool(
        "release_file_reservations",
        {
            "project_key": _active_project(),
            "agent_name": args.agent_name,
            "registration_token": args.token,
            "paths": [p.strip() for p in args.paths.split(",") if p.strip()],
        },
    )
    text = _extract_text(result)
    print(json.dumps({"status": "released", "detail": text}, indent=2))


def cmd_health(args):
    """Check Agent Mail server health."""
    try:
        _rpc("resources/list", {})
        print(
            json.dumps(
                {
                    "status": "healthy",
                    "server_url": AGENT_MAIL_URL,
                    "project_key": PROJECT_KEY,
                },
                indent=2,
            )
        )
    except SystemExit:
        print(
            json.dumps(
                {
                    "status": "unhealthy",
                    "server_url": AGENT_MAIL_URL,
                    "error": "Server unreachable",
                },
                indent=2,
            )
        )
        sys.exit(1)


def cmd_session_start(args):
    """One-shot session startup: register + list agents + check inbox."""
    project = args.project or PROJECT_KEY

    # Register
    reg_result = _tool(
        "register_agent",
        {
            "name": args.name_hint,
            "program": "abacusai",
            "model": args.model,
            "project_key": project,
        },
    )
    reg_text = _extract_text(reg_result)
    try:
        reg_data = json.loads(reg_text)
    except json.JSONDecodeError:
        reg_data = {"name": args.name_hint, "registration_token": ""}

    name = reg_data.get("name", args.name_hint)
    token = reg_data.get("registration_token", "")

    if not token:
        print("Error: Registration failed", file=sys.stderr)
        sys.exit(1)

    # List agents
    slug = _slug(project)
    agents_resp = _rpc("resources/read", {"uri": f"resource://project/{slug}"})
    agents_contents = (
        agents_resp.get("result", {}).get("contents", [{}])[0].get("text", "{}")
    )
    try:
        agents_data = json.loads(agents_contents)
    except json.JSONDecodeError:
        agents_data = {}

    # Check inbox
    inbox_result = _tool(
        "fetch_inbox",
        {
            "project_key": _active_project(),
            "agent_name": name,
            "registration_token": token,
            "limit": 10,
            "urgent_only": False,
            "include_bodies": True,
        },
    )
    inbox_text = _extract_text(inbox_result)
    try:
        messages = json.loads(inbox_text)
    except json.JSONDecodeError:
        messages = []

    output = {
        "agent_name": name,
        "registration_token": token,
        "project_key": project,
        "model": args.model,
        "project_agents": agents_data.get("agents", []),
        "inbox_messages": messages,
        "export_commands": [
            f"export AGENT_NAME='{name}'",
            f"export REGISTRATION_TOKEN='{token}'",
            f"export AGENT_MAIL_PROJECT='{project}'",
        ],
        "next_steps": [
            "Claim a bead: br update <id> --status=in_progress",
            "Reserve files: python agent_mail_cli.py reserve ...",
            "Announce work: python agent_mail_cli.py send ...",
            "Check inbox: python agent_mail_cli.py inbox ...",
        ],
    }
    print(json.dumps(output, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="Agent Mail CLI - Python-based agent coordination tool"
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # register
    p_reg = subparsers.add_parser("register", help="Register a new agent")
    p_reg.add_argument("name_hint", help="Desired agent name")
    p_reg.add_argument("model", help="Model identifier (e.g., abacusai, qwen)")
    p_reg.add_argument("project", nargs="?", help="Project path or slug")
    p_reg.set_defaults(func=cmd_register)

    # agents
    p_agents = subparsers.add_parser("agents", help="List agents in project")
    p_agents.add_argument("project", nargs="?", help="Project path or slug")
    p_agents.set_defaults(func=cmd_agents)

    # inbox
    p_inbox = subparsers.add_parser("inbox", help="Fetch agent inbox")
    p_inbox.add_argument("agent_name", help="Agent name")
    p_inbox.add_argument("token", help="Registration token")
    p_inbox.add_argument("limit", nargs="?", default="10", help="Message limit")
    p_inbox.add_argument("urgent_only", nargs="?", default="false", help="Urgent only")
    p_inbox.add_argument(
        "include_bodies", nargs="?", default="true", help="Include bodies"
    )
    p_inbox.set_defaults(func=cmd_inbox)

    # send
    p_send = subparsers.add_parser("send", help="Send a message")
    p_send.add_argument("from_agent", help="Sender agent name")
    p_send.add_argument("to_csv", help="Recipients (comma-separated or 'All')")
    p_send.add_argument("subject", help="Message subject")
    p_send.add_argument("body", help="Message body")
    p_send.add_argument(
        "sender_token", nargs="?", default="", help="Sender registration token"
    )
    p_send.set_defaults(func=cmd_send)

    # reserve
    p_res = subparsers.add_parser("reserve", help="Reserve files")
    p_res.add_argument("agent_name", help="Agent name")
    p_res.add_argument("token", help="Registration token")
    p_res.add_argument("paths", help="Comma-separated file paths/globs")
    p_res.add_argument(
        "ttl", nargs="?", default="3600", help="Reservation TTL in seconds"
    )
    p_res.add_argument(
        "exclusive", nargs="?", default="true", help="Exclusive reservation"
    )
    p_res.add_argument("--reason", help="Reservation reason")
    p_res.set_defaults(func=cmd_reserve)

    # release
    p_rel = subparsers.add_parser("release", help="Release file reservations")
    p_rel.add_argument("agent_name", help="Agent name")
    p_rel.add_argument("token", help="Registration token")
    p_rel.add_argument("paths", help="Comma-separated file paths/globs")
    p_rel.set_defaults(func=cmd_release)

    # health
    p_health = subparsers.add_parser("health", help="Check server health")
    p_health.set_defaults(func=cmd_health)

    # session-start
    p_start = subparsers.add_parser("session-start", help="Full session startup")
    p_start.add_argument("name_hint", help="Desired agent name")
    p_start.add_argument("model", help="Model identifier")
    p_start.add_argument("project", nargs="?", help="Project path or slug")
    p_start.set_defaults(func=cmd_session_start)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()