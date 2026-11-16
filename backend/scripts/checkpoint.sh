#!/usr/bin/env bash
# Usage (from backend/):  ./scripts/checkpoint.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PORT="${PORT:-8765}"
LOG="$(mktemp)"
SERVER_LOG="$(mktemp)"
SERVER_PID=""
PASSED=0
FAILED=0

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
  rm -f "$LOG" "$SERVER_LOG"
}
trap cleanup EXIT

check() {
  local name="$1"; shift
  if "$@" >"$LOG" 2>&1; then
    echo "✅ $name"
    sed 's/^/   /' "$LOG" | tail -n 3
    PASSED=$((PASSED + 1))
  else
    echo "❌ $name"
    sed 's/^/   │ /' "$LOG" | tail -n 25
    FAILED=$((FAILED + 1))
  fi
}

environment_in_sync() {
  uv sync --locked
}

unit_tests_pass() {
  .venv/bin/python -m pytest -q
}

spain_is_trusted() {
  .venv/bin/python - <<'PY'
import sys
from app.config import load_settings

settings = load_settings()
trust = settings.trust
print(f"{len(trust)} CSCA certificates from {len(trust.countries)} countries; {len(settings.crls)} CRLs")
print("Master list signatures:", "verified" if settings.master_lists_verified else "NOT verified")
sys.exit(0 if "ES" in trust.countries else 1)
PY
}

server_answers_health() {
  .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:$PORT/health" 2>/dev/null; then echo; return 0; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then cat "$SERVER_LOG"; return 1; fi
    sleep 0.25
  done
  cat "$SERVER_LOG"
  return 1
}

echo "Checkpoints"
echo "---------------------"
check "Python environment matches uv.lock" environment_in_sync
check "Unit tests pass"                    unit_tests_pass
check "Spain (ES) is in the trust store"   spain_is_trusted
check "Server starts and /health answers"  server_answers_health
echo "---------------------"
echo "$PASSED passed, $FAILED failed"
exit $((FAILED > 0))