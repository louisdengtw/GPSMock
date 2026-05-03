#!/usr/bin/env bash
# Terminal A — long-lived tunneld. Needs sudo (RemoteXPC tunnel creation).
# Uses the sidecar venv's pymobiledevice3 so versions match the sidecar.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PMD3="$REPO_ROOT/sidecar/.venv/bin/pymobiledevice3"

if [ ! -x "$PMD3" ]; then
  echo "error: $PMD3 not found. Run 'make sidecar-install' first." >&2
  exit 1
fi

# Sanity: warn if ~/.pymobiledevice3 is root-owned (causes mounter_failed in sidecar).
CACHE="$HOME/.pymobiledevice3"
if [ -d "$CACHE" ] && [ "$(stat -f %u "$CACHE")" != "$(id -u)" ]; then
  echo "warning: $CACHE is not owned by you. Fix with:" >&2
  echo "  sudo chown -R \"\$(whoami):staff\" $CACHE" >&2
fi

echo "→ starting tunneld (will prompt for sudo). Leave this terminal open."
echo "  iPhone may pop a 'Trust / Allow' dialog — tap Allow on the phone."
exec sudo "$PMD3" remote tunneld
