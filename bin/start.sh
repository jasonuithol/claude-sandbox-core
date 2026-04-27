#!/usr/bin/env bash
# start.sh <domain> <project> — bring up MCP services and launch the sandbox.
#
# 1. Source domains/<domain>.conf
# 2. Verify each MCP_REPOS sibling repo is present, run its setup.sh, start.sh
# 3. podman run claude-sandbox-core with the conf, workspace, project, and any
#    EXTRA_MOUNTS / EXTRA_ENV from the conf
# 4. On Claude exit, stop each MCP repo so the next start.sh revives them
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

DOMAIN="${1:-}"
PROJECT="${2:-}"

if [ -z "$DOMAIN" ] || [ -z "$PROJECT" ]; then
    available="$(ls "$ROOT/domains" 2>/dev/null | sed -n 's/\.conf$//p' | tr '\n' ' ')"
    echo "Usage: start.sh <domain> <project>"
    echo "  domain : one of: ${available:-<no domain confs found>}"
    echo "  project: folder name under ~/Projects to mount at /workspace/<project>"
    exit 1
fi

CONF="$ROOT/domains/$DOMAIN.conf"
if [ ! -f "$CONF" ]; then
    echo "Error: $CONF not found."
    exit 1
fi

# shellcheck disable=SC1090
source "$CONF"

if [ ! -d "$HOME/Projects/$PROJECT" ]; then
    echo "Error: ~/Projects/$PROJECT does not exist."
    exit 1
fi

# Verify each required MCP repo is checked out
for repo in "${MCP_REPOS[@]}"; do
    if [ ! -d "$repo" ]; then
        echo "Error: required MCP repo not found at $repo"
        echo "  clone the corresponding mcp-* sibling and re-run."
        exit 1
    fi
    if [ ! -x "$repo/start.sh" ]; then
        echo "Error: $repo/start.sh missing or not executable."
        exit 1
    fi
done

# Optional repos — start any that happen to be cloned. If a host has
# mcp-dosre alongside mcp-pygame, we bring it up too (it's cross-domain,
# useful from inside the pygame sandbox for binary-analysis projects).
PRESENT_OPTIONAL_REPOS=()
for repo in "${OPTIONAL_REPOS[@]:-}"; do
    [ -z "$repo" ] && continue
    if [ -d "$repo" ] && [ -x "$repo/start.sh" ]; then
        PRESENT_OPTIONAL_REPOS+=("$repo")
    fi
done

# Build the sandbox image if needed (idempotent)
"$SCRIPT_DIR/setup.sh"

# Bring up each MCP repo. Each repo's start.sh runs its own setup.sh internally.
for repo in "${MCP_REPOS[@]}" "${PRESENT_OPTIONAL_REPOS[@]:-}"; do
    [ -z "$repo" ] && continue
    echo "==> Starting $(basename "$repo")..."
    "$repo/start.sh"
done

# Give host services a moment to bind their ports
sleep 2

# Per-domain host workspace dir. Created on the host so sibling MCP
# containers (e.g. valheim-build's /opt/workspace) can persist logs there
# across runs. NOT bind-mounted into the Claude container — doing so makes
# podman auto-create empty mountpoint stubs on the host for every nested
# bind (project, docs, EXTRA_MOUNTS), which accumulate over runs and are
# owned by the userns-mapped uid (unremovable without `podman unshare`).
WORKSPACE="${WORKSPACE:-$ROOT/workspaces/$DOMAIN}"
mkdir -p "$WORKSPACE"

MOUNT_ARGS=(
    -v "$HOME/.claude:/home/claude/.claude:Z"
    -v "$HOME/.claude.json:/home/claude/.claude.json:Z"
    -v "$HOME/Projects/$PROJECT:/workspace/$PROJECT:Z"
    -v "$CONF:/etc/claude-sandbox-domain.conf:ro,Z"
    -v "$ROOT/core/entrypoint.sh:/usr/local/bin/entrypoint.sh:ro,Z"
)

for m in "${EXTRA_MOUNTS[@]:-}"; do
    [ -z "$m" ] && continue
    MOUNT_ARGS+=(-v "$m")
done

ENV_ARGS=()
for e in "${EXTRA_ENV[@]:-}"; do
    [ -z "$e" ] && continue
    ENV_ARGS+=(-e "$e")
done

# Collect every service name across all domain confs. entrypoint.sh uses this
# to deregister stale registrations from a previous domain — switching from
# pygame to valheim should scrub pygame-build/knowledge/dos-re-* etc, not just
# the current domain's own list.
ALL_KNOWN_SERVICES=""
for c in "$ROOT"/domains/*.conf; do
    names="$(
        bash -c '
            # shellcheck disable=SC1090
            source "$1"
            for e in "${SERVICES[@]:-}" "${OPTIONAL_SERVICES[@]:-}"; do
                [ -z "$e" ] && continue
                printf "%s\n" "${e%%|*}"
            done
        ' _ "$c"
    )"
    ALL_KNOWN_SERVICES="$ALL_KNOWN_SERVICES $names"
done
ALL_KNOWN_SERVICES="$(echo "$ALL_KNOWN_SERVICES" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
ENV_ARGS+=(-e "ALL_KNOWN_SERVICES=$ALL_KNOWN_SERVICES")

echo "==> Launching Claude sandbox: domain=$DOMAIN project=$PROJECT"

# --userns=keep-id and :Z labels are required for rootless podman so Claude
# Code can run as a non-root user with --dangerously-skip-permissions.
podman run -it --rm \
    --userns=keep-id \
    --network=host \
    "${MOUNT_ARGS[@]}" \
    "${ENV_ARGS[@]}" \
    -w "/workspace/$PROJECT" \
    claude-sandbox-core \
    /usr/local/bin/entrypoint.sh

echo "==> Claude exited. Stopping MCP services for $DOMAIN..."
# stop (don't clean) — next start revives the same containers and preserves state
for repo in "${MCP_REPOS[@]}" "${PRESENT_OPTIONAL_REPOS[@]:-}"; do
    [ -z "$repo" ] && continue
    [ -x "$repo/stop.sh" ] || continue
    "$repo/stop.sh" 2>/dev/null || true
done
