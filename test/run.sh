#!/usr/bin/env bash
# Offline test of throne-gate.sh against the stub API. Asserts exit codes,
# outputs, slug derivation, and fail-on behaviour. Requires jq on PATH.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
GATE="${HERE}/../throne-gate.sh"
PORT=8799
API="http://127.0.0.1:${PORT}"
PY=$(command -v python3 || command -v python)

"$PY" "${HERE}/stub_api.py" "${PORT}" &
STUB=$!
trap 'kill $STUB 2>/dev/null' EXIT
sleep 1

pass=0; fail=0
check() { if [ "$1" = "$2" ]; then echo "  ok: $3"; pass=$((pass+1)); else echo "  FAIL: $3 (want '$2' got '$1')"; fail=$((fail+1)); fi; }

run_gate() {
  # $1 target  $2 key  $3 fail-on -> sets GATE_RC, OUT (output file), SUM
  OUT=$(mktemp); SUM=$(mktemp)
  GITHUB_OUTPUT="$OUT" GITHUB_STEP_SUMMARY="$SUM" GITHUB_EVENT_NAME="push" \
  THRONE_TARGET="$1" THRONE_KEY="$2" THRONE_API="$API" THRONE_FAIL_ON="$3" \
  THRONE_TIMEOUT="60" THRONE_COMMENT="false" \
    bash "$GATE" >/tmp/gate.log 2>&1
  GATE_RC=$?
}
getout() { grep "^$1=" "$OUT" | head -1 | cut -d= -f2-; }

echo "== scenario 1: fit npm, fail-on=not_fit -> pass =="
run_gate "@scope/cool-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (gate passes)"
check "$(getout verdict)" "fit" "verdict output"
check "$(getout record-url)" "https://usethrone.dev/server/scope-cool-mcp" "clean slug url"
check "$(getout security-verdict)" "review" "security verdict output"
grep -q "FIT TO SHIP" "$SUM" && echo "  ok: summary has headline" && pass=$((pass+1)) || { echo "  FAIL: summary headline"; fail=$((fail+1)); }
grep -q "| cursor | \`WARN\` |" "$SUM" && echo "  ok: per-client table" && pass=$((pass+1)) || { echo "  FAIL: per-client table"; fail=$((fail+1)); }

echo "== scenario 2: not_fit, fail-on=not_fit -> fail =="
run_gate "broken-mcp" "good" "not_fit"
check "$GATE_RC" "1" "exit 1 (gate blocks)"
check "$(getout verdict)" "not_fit" "verdict output"

echo "== scenario 3: inconclusive needs_credentials, github target, fail-on=not_fit -> pass =="
run_gate "https://github.com/Owner/Repo-Name" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (inconclusive not blocked)"
check "$(getout verdict)" "inconclusive" "verdict output"
check "$(getout reason)" "needs_credentials" "reason output"
check "$(getout record-url)" "https://usethrone.dev/server/owner-repo-name" "github slug url"

echo "== scenario 4: inconclusive blocks under strict fail-on =="
run_gate "https://github.com/Owner/Repo-Name" "good" "not_fit,inconclusive"
check "$GATE_RC" "1" "exit 1 (strict blocks inconclusive)"

echo "== scenario 5: bad key -> fast fail, no poll =="
run_gate "@scope/cool-mcp" "bad" "not_fit"
check "$GATE_RC" "1" "exit 1 (401)"
grep -q "rejected the API key" /tmp/gate.log && echo "  ok: clear 401 message" && pass=$((pass+1)) || { echo "  FAIL: 401 message"; fail=$((fail+1)); }

echo ""
echo "RESULT: ${pass} passed, ${fail} failed"
[ "$fail" = "0" ]
