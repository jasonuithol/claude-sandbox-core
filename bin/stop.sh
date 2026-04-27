#!/usr/bin/env bash
# stop.sh <domain> [--kill] — stop MCP services for a domain.
#
# Forwards extra args to each repo's stop.sh (e.g. --kill for SIGKILL).
# Containers are left in place; use clean.sh to remove them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
    echo "Usage: stop.sh <domain> [--kill]"
    exit 1
fi
shift

CONF="$ROOT/domains/$DOMAIN.conf"
if [ ! -f "$CONF" ]; then
    echo "Error: $CONF not found."
    exit 1
fi

# shellcheck disable=SC1090
source "$CONF"

for repo in "${MCP_REPOS[@]}" "${OPTIONAL_REPOS[@]:-}"; do
    [ -z "$repo" ] && continue
    [ -x "$repo/stop.sh" ] || continue
    echo "==> Stopping $(basename "$repo")..."
    "$repo/stop.sh" "$@" || true
done
