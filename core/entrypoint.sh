#!/usr/bin/env bash
# entrypoint.sh — register MCP services from domain.conf, then launch Claude.
#
# Reads /etc/claude-sandbox/domain.conf (mounted in by bin/start.sh).
# Conf format: bash file declaring SERVICES and OPTIONAL_SERVICES arrays as
# "name|url" pairs. Required services are registered unconditionally;
# optional services are registered only if a probe succeeds.
set -euo pipefail

CONF=/etc/claude-sandbox-domain.conf
if [ ! -f "$CONF" ]; then
    echo "entrypoint: $CONF not found — start.sh should mount it." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONF"

# Idempotent: deregister every service that any domain might register.
# bin/start.sh aggregates this from all domains/*.conf so switching domains
# scrubs registrations left behind by previous sessions (the claude config
# at ~/.claude.json is host-mounted, so it persists across container runs).
for name in ${ALL_KNOWN_SERVICES:-}; do
    claude mcp remove "$name" 2>/dev/null || true
done

# Required services — register unconditionally. Host network means localhost
# ports inside the container reach the host's loopback.
for entry in "${SERVICES[@]}"; do
    name="${entry%%|*}"
    url="${entry##*|}"
    claude mcp add "$name" --transport http "$url"
done

# Optional services — register only if reachable. A plain GET is no good as a
# probe: SDK v2 servers answer it with an SSE stream that stays open, so curl
# hits its timeout and reports dead. Probe with a real stateless tools/list
# POST (MCP 2026-07-28) instead — it gets an immediate JSON reply from a
# migrated server, and an immediate 4xx from a legacy one; either means alive.
probe() {
    curl -sS -o /dev/null -m 2 -X POST "$1" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -H 'MCP-Protocol-Version: 2026-07-28' \
        -H 'Mcp-Method: tools/list' \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"sandbox-probe","version":"0"},"io.modelcontextprotocol/clientCapabilities":{}}}}' \
        >/dev/null 2>&1
}

for entry in "${OPTIONAL_SERVICES[@]:-}"; do
    [ -z "$entry" ] && continue
    name="${entry%%|*}"
    url="${entry##*|}"
    if probe "$url"; then
        claude mcp add "$name" --transport http "$url"
        echo "Registered optional service: $name"
    fi
done

# If the domain mounts a SANDBOX.md under /workspace/docs/, surface it as
# /workspace/CLAUDE.md so Claude's CLAUDE.md auto-load (which walks cwd
# ancestors) picks it up. The cwd is /workspace/<project>/, so /workspace/
# is the first ancestor checked. Without this symlink, the doc lives in a
# sibling dir and never auto-loads.
#
# /workspace must be writable for the symlink. The image's Dockerfile
# chmods it 1777 for that reason — but on older images it's still 755 and
# the symlink will fail. Treat the failure as non-fatal: the session is
# still useful without auto-load, sandbox-Claude can be told to read the
# doc explicitly.
if [ -f /workspace/docs/SANDBOX.md ] && [ ! -e /workspace/CLAUDE.md ]; then
    if ! ln -sf /workspace/docs/SANDBOX.md /workspace/CLAUDE.md 2>/dev/null; then
        echo "entrypoint: could not symlink /workspace/CLAUDE.md (rebuild" \
             "the claude-sandbox-core image to fix); SANDBOX.md will not" \
             "auto-load. Read it via: cat /workspace/docs/SANDBOX.md" >&2
    fi
fi

# Auto-resume the prior conversation for this cwd if one exists.
# Claude stores conversations in ~/.claude/projects/<cwd-with-slashes-as-dashes>/
SESSION_DIR="$HOME/.claude/projects/$(pwd | tr / -)"
if [ -d "$SESSION_DIR" ] && compgen -G "$SESSION_DIR/*.jsonl" >/dev/null; then
    exec claude --dangerously-skip-permissions --continue "$@"
else
    exec claude --dangerously-skip-permissions "$@"
fi
