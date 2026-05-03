#!/usr/bin/env bash
# Terminal B — FastAPI sidecar on 127.0.0.1:5555.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$REPO_ROOT/sidecar/.venv/bin/python"

if [ ! -x "$PY" ]; then
  echo "error: $PY not found. Run 'make sidecar-install' first." >&2
  exit 1
fi

# Override on the command line: `GPSMOCK_LOG_LEVEL=INFO ./scripts/sidecar.sh`
export GPSMOCK_LOG_LEVEL="${GPSMOCK_LOG_LEVEL:-DEBUG}"

exec "$PY" -m gpsmock_sidecar
