#!/usr/bin/env bash
# setup.sh — build the claude-sandbox-core container image. Idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"

if docker image inspect claude-sandbox-core >/dev/null 2>&1; then
    echo "Image claude-sandbox-core already built — skipping."
    exit 0
fi

echo "Building claude-sandbox-core image..."
docker build -t claude-sandbox-core "$ROOT/core"
