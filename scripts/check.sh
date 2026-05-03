#!/usr/bin/env bash
# Quick health check: tunneld → sidecar → device. Exit non-zero on any failure.

set -uo pipefail

ok()    { printf "  \033[32mok\033[0m  %s\n" "$1"; }
fail()  { printf "  \033[31mfail\033[0m %s\n" "$1"; }
info()  { printf "→ %s\n" "$1"; }

rc=0

info "tunneld (127.0.0.1:49151)"
TUNNELD_JSON="$(curl -sf --max-time 2 http://127.0.0.1:49151 || true)"
if [ -z "$TUNNELD_JSON" ]; then
  fail "tunneld not responding — run scripts/tunneld.sh"
  rc=1
else
  if [ "$TUNNELD_JSON" = "{}" ]; then
    fail "tunneld up but no device — plug iPhone in via USB, accept pairing prompt"
    rc=1
  else
    UDID="$(printf '%s' "$TUNNELD_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(next(iter(d), ""))')"
    ok "tunneld sees $UDID"
  fi
fi

info "sidecar (127.0.0.1:5555)"
if curl -sf --max-time 2 http://127.0.0.1:5555/health >/dev/null; then
  ok "sidecar /health"
else
  fail "sidecar not responding — run scripts/sidecar.sh"
  rc=1
fi

info "sidecar /device (DDI mount happens here, may take 10–60s first time)"
DEV_JSON="$(curl -s --max-time 90 http://127.0.0.1:5555/device || true)"
if printf '%s' "$DEV_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); assert "udid" in d' 2>/dev/null; then
  ok "device: $(printf '%s' "$DEV_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["name"], d["ios_version"])')"
else
  fail "device endpoint: $DEV_JSON"
  rc=1
fi

exit $rc
