#!/usr/bin/env bash
# clean.sh [<domain>] — full teardown.
#
# With <domain>: also runs each MCP repo's clean.sh (containers + images).
# Always: removes the claude-sandbox-core image.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

DOMAIN="${1:-}"

if [ -n "$DOMAIN" ]; then
    CONF="$ROOT/domains/$DOMAIN.conf"
    if [ ! -f "$CONF" ]; then
        echo "Error: $CONF not found."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$CONF"

    for repo in "${MCP_REPOS[@]}" "${OPTIONAL_REPOS[@]:-}"; do
        [ -z "$repo" ] && continue
        [ -x "$repo/clean.sh" ] || continue
        echo "==> Cleaning $(basename "$repo")..."
        "$repo/clean.sh" || true
    done
fi

echo "==> Removing claude-sandbox-core image..."
docker image rm claude-sandbox-core 2>/dev/null && echo "  removed" || echo "  not present"

echo "Done."
