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

# Optional services — register only if reachable. MCP streamable-http endpoints
# return some HTTP status (often 406) to a plain GET, so any response means alive.
probe() {
    curl -sS -o /dev/null -m 2 "$1" >/dev/null 2>&1
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

# Auto-resume the prior conversation for this cwd if one exists.
# Claude stores conversations in ~/.claude/projects/<cwd-with-slashes-as-dashes>/
SESSION_DIR="$HOME/.claude/projects/$(pwd | tr / -)"
if [ -d "$SESSION_DIR" ] && compgen -G "$SESSION_DIR/*.jsonl" >/dev/null; then
    exec claude --dangerously-skip-permissions --continue "$@"
else
    exec claude --dangerously-skip-permissions "$@"
fi
