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
  # $1 target  $2 key  $3 fail-on  [$4 fail-on-security, default off]
  #   [$5 sarif-file path, default unset]
  # -> sets GATE_RC, OUT (output file), SUM
  OUT=$(mktemp); SUM=$(mktemp)
  GITHUB_OUTPUT="$OUT" GITHUB_STEP_SUMMARY="$SUM" GITHUB_EVENT_NAME="push" \
  THRONE_TARGET="$1" THRONE_KEY="$2" THRONE_API="$API" THRONE_FAIL_ON="$3" \
  THRONE_FAIL_ON_SECURITY="${4:-off}" THRONE_SARIF="${5:-}" \
  THRONE_TIMEOUT="60" THRONE_COMMENT="false" THRONE_POLL_INTERVAL="1" \
    bash "$GATE" >/tmp/gate.log 2>&1
  GATE_RC=$?
}
# Last match wins, mirroring how GitHub resolves a repeated output name (the
# gate seeds defaults first, then overwrites them with real values).
getout() { grep "^$1=" "$OUT" | tail -1 | cut -d= -f2-; }

echo "== scenario 1: fit npm, fail-on=not_fit -> pass =="
run_gate "@scope/cool-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (gate passes)"
check "$(getout verdict)" "fit" "verdict output"
check "$(getout scan-id)" "scan-fit-npm" "scan-id output (matches action.yml's name)"
check "$(getout record-url)" "https://usethrone.dev/server/scope-cool-mcp" "clean slug url"
check "$(getout security-verdict)" "review" "security verdict output"
if grep -q "FIT TO SHIP" "$SUM"; then echo "  ok: summary has headline"; pass=$((pass+1)); else echo "  FAIL: summary headline"; fail=$((fail+1)); fi
if grep -q "| cursor | \`WARN\` |" "$SUM"; then echo "  ok: per-client table"; pass=$((pass+1)); else echo "  FAIL: per-client table"; fail=$((fail+1)); fi

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
if grep -q "rejected the API key" /tmp/gate.log; then echo "  ok: clear 401 message"; pass=$((pass+1)); else echo "  FAIL: 401 message"; fail=$((fail+1)); fi
check "$(getout verdict)" "unknown" "verdict output seeded on early failure"
check "$(getout security-verdict)" "not_run" "security-verdict seeded on early failure"

echo "== scenario 6: missing jq -> clear preflight error, no submit =="
# Run the gate with a PATH that exposes curl but not jq, so the dependency
# guard fires before any network call. Pre-create everything that needs the
# real PATH first (mktemp, curl, bash) — trimming PATH below would otherwise
# hide those too; the absolute bash path keeps the interpreter reachable.
BINDIR=$(mktemp -d); OUT=$(mktemp); SUM=$(mktemp)
BASH_BIN=$(command -v bash)
ln -s "$(command -v curl)" "${BINDIR}/curl"
PATH="$BINDIR" GITHUB_OUTPUT="$OUT" GITHUB_STEP_SUMMARY="$SUM" GITHUB_EVENT_NAME="push" \
  THRONE_TARGET="@scope/cool-mcp" THRONE_KEY="good" THRONE_API="$API" THRONE_FAIL_ON="not_fit" \
  THRONE_TIMEOUT="60" THRONE_COMMENT="false" \
    "$BASH_BIN" "$GATE" >/tmp/gate.log 2>&1
check "$?" "1" "exit 1 (missing jq)"
if grep -q "'jq' is not installed" /tmp/gate.log; then echo "  ok: clear missing-jq message"; pass=$((pass+1)); else echo "  FAIL: missing-jq message"; fail=$((fail+1)); fi
if grep -q "scan-id" "$OUT"; then echo "  FAIL: submitted despite missing jq"; fail=$((fail+1)); else echo "  ok: no submit before dependency check"; pass=$((pass+1)); fi
rm -rf "$BINDIR"

echo "== scenario 7: fit pypi via 'uvx', slug from normalized name =="
run_gate "uvx some-pypi-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (gate passes)"
check "$(getout verdict)" "fit" "verdict output"
check "$(getout record-url)" "https://usethrone.dev/server/some-pypi-mcp" "pypi slug url"
check "$(getout security-verdict)" "clean" "clean security verdict"
if grep -q "no findings" "$SUM"; then echo "  ok: clean security line"; pass=$((pass+1)); else echo "  FAIL: clean security line"; fail=$((fail+1)); fi

echo "== scenario 8: scan status failed -> die with clear message =="
run_gate "flaky-mcp" "good" "not_fit"
check "$GATE_RC" "1" "exit 1 (scan failed)"
if grep -q "sandbox exploded" /tmp/gate.log; then echo "  ok: surfaces failure detail"; pass=$((pass+1)); else echo "  FAIL: failure detail"; fail=$((fail+1)); fi

echo "== scenario 9: unknown verdict, no clients -> passes, no client table =="
run_gate "weird-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (unknown not in fail-on)"
check "$(getout verdict)" "unknown" "verdict output"
if grep -q "| Client | Result |" "$SUM"; then echo "  FAIL: client table for empty clients"; fail=$((fail+1)); else echo "  ok: no client table when no clients"; pass=$((pass+1)); fi

echo "== scenario 10: non-numeric timeout -> fast fail, no submit =="
OUT=$(mktemp); SUM=$(mktemp)
GITHUB_OUTPUT="$OUT" GITHUB_STEP_SUMMARY="$SUM" GITHUB_EVENT_NAME="push" \
THRONE_TARGET="@scope/cool-mcp" THRONE_KEY="good" THRONE_API="$API" THRONE_FAIL_ON="not_fit" \
THRONE_TIMEOUT="10m" THRONE_COMMENT="false" \
  bash "$GATE" >/tmp/gate.log 2>&1
check "$?" "1" "exit 1 (bad timeout)"
if grep -q "timeout-seconds must be a whole number" /tmp/gate.log; then echo "  ok: clear timeout error"; pass=$((pass+1)); else echo "  FAIL: timeout error message"; fail=$((fail+1)); fi
if grep -q "scan-id" "$OUT"; then echo "  FAIL: submitted despite bad timeout"; fail=$((fail+1)); else echo "  ok: no submit before validation"; pass=$((pass+1)); fi

echo "== scenario 11: typo in fail-on -> warns and does not silently block =="
run_gate "broken-mcp" "good" "notfit"
check "$GATE_RC" "0" "exit 0 (typo'd token never matches)"
if grep -q "is not a known verdict" /tmp/gate.log; then echo "  ok: warns on unknown fail-on token"; pass=$((pass+1)); else echo "  FAIL: unknown fail-on warning"; fail=$((fail+1)); fi

echo "== scenario 12: scan vanishes after submit -> fast fail on 404s, not timeout =="
START=$(date +%s)
run_gate "vanished-mcp" "good" "not_fit"
ELAPSED=$(( $(date +%s) - START ))
check "$GATE_RC" "1" "exit 1 (vanished scan)"
if grep -q "no longer knows scan" /tmp/gate.log; then echo "  ok: clear vanished-scan message"; pass=$((pass+1)); else echo "  FAIL: vanished-scan message"; fail=$((fail+1)); fi
if [ "$ELAPSED" -lt 30 ]; then echo "  ok: failed fast (${ELAPSED}s), did not wait out the timeout"; pass=$((pass+1)); else echo "  FAIL: took ${ELAPSED}s (waited out the timeout?)"; fail=$((fail+1)); fi

echo "== scenario 13: transient 500s while polling -> rides them out, then passes =="
run_gate "wobbly-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (gate passes after transient 500s)"
check "$(getout verdict)" "fit" "verdict output survives poll hiccups"

echo "== scenario 14: fail-on-security defaults off -> review never blocks a fit =="
run_gate "@scope/cool-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (security off by default)"
check "$(getout security-findings)" "1" "security-findings count output"
check "$(getout security-high)" "0" "security-high count output"
if grep -q "not blocking" /tmp/gate.log; then echo "  ok: review surfaced as non-blocking"; pass=$((pass+1)); else echo "  FAIL: review annotation"; fail=$((fail+1)); fi

echo "== scenario 15: fail-on-security=review blocks a compatible server with findings =="
run_gate "@scope/cool-mcp" "good" "not_fit" "review"
check "$GATE_RC" "1" "exit 1 (review gate blocks despite fit verdict)"
check "$(getout verdict)" "fit" "verdict still fit (compat axis unchanged)"
check "$(getout security-verdict)" "review" "security-verdict output"
if grep -q "fail-on-security=review" /tmp/gate.log; then echo "  ok: names the security gate in the block message"; pass=$((pass+1)); else echo "  FAIL: block message"; fail=$((fail+1)); fi

echo "== scenario 16: fail-on-security=high does NOT block when findings are only medium =="
run_gate "@scope/cool-mcp" "good" "not_fit" "high"
check "$GATE_RC" "0" "exit 0 (no high-severity finding)"

echo "== scenario 17: fail-on-security=high blocks on a high-severity finding =="
run_gate "sketchy-mcp" "good" "not_fit" "high"
check "$GATE_RC" "1" "exit 1 (high-severity finding blocks)"
check "$(getout verdict)" "fit" "verdict still fit"
check "$(getout security-high)" "1" "security-high count output"
if grep -q "high-severity security finding" /tmp/gate.log; then echo "  ok: names the high finding"; pass=$((pass+1)); else echo "  FAIL: high block message"; fail=$((fail+1)); fi
if grep -q "1 high, 1 medium, 1 low" "$SUM"; then echo "  ok: severity breakdown in summary"; pass=$((pass+1)); else echo "  FAIL: severity breakdown"; fail=$((fail+1)); fi

echo "== scenario 18: fail-on-security=review passes a clean scan (nothing to block) =="
run_gate "uvx some-pypi-mcp" "good" "not_fit" "review"
check "$GATE_RC" "0" "exit 0 (clean scan, review gate has nothing to act on)"

echo "== scenario 19: both axes block -> failure names compatibility AND security =="
run_gate "broken-mcp" "good" "not_fit" "high"
check "$GATE_RC" "1" "exit 1 (compat + security)"
if grep -q "is in fail-on" /tmp/gate.log && grep -q "high-severity security finding" /tmp/gate.log; then
  echo "  ok: block message names both reasons"; pass=$((pass+1))
else echo "  FAIL: combined block message"; fail=$((fail+1)); fi

echo "== scenario 20: unrecognised fail-on-security -> warns, treats as off (does not block) =="
run_gate "sketchy-mcp" "good" "not_fit" "hihg"
check "$GATE_RC" "0" "exit 0 (typo'd security gate does not silently block)"
if grep -q "is not recognised" /tmp/gate.log; then echo "  ok: warns on unknown fail-on-security value"; pass=$((pass+1)); else echo "  FAIL: unknown value warning"; fail=$((fail+1)); fi

echo "== scenario 21: findings detail table lists each finding in the summary =="
run_gate "sketchy-mcp" "good" "not_fit"
check "$GATE_RC" "0" "exit 0 (security off by default)"
if grep -q "| Severity | Finding |" "$SUM"; then echo "  ok: findings table header"; pass=$((pass+1)); else echo "  FAIL: findings table header"; fail=$((fail+1)); fi
if grep -q "Spawns a shell with unsanitised input" "$SUM"; then echo "  ok: high finding title shown"; pass=$((pass+1)); else echo "  FAIL: high finding title"; fail=$((fail+1)); fi
# The finding with no title field falls back to a generic label, never blank.
if grep -q "| \`LOW\` | Security finding |" "$SUM"; then echo "  ok: title fallback for finding without one"; pass=$((pass+1)); else echo "  FAIL: title fallback"; fail=$((fail+1)); fi
# HIGH must render before LOW: the table is ordered by severity, not input order.
if awk '/`HIGH`/{h=NR} /`LOW`/{l=NR} END{exit !(h&&l&&h<l)}' "$SUM"; then echo "  ok: rows ordered high-severity first"; pass=$((pass+1)); else echo "  FAIL: severity ordering"; fail=$((fail+1)); fi

echo "== scenario 22: sarif-file writes a valid SARIF report of the findings =="
SARIF=$(mktemp)
run_gate "sketchy-mcp" "good" "not_fit" "off" "$SARIF"
check "$GATE_RC" "0" "exit 0"
check "$(getout sarif-file)" "$SARIF" "sarif-file output points at the written report"
if jq -e . "$SARIF" >/dev/null 2>&1; then echo "  ok: SARIF is valid JSON"; pass=$((pass+1)); else echo "  FAIL: SARIF not valid JSON"; fail=$((fail+1)); fi
check "$(jq -r '.version' "$SARIF")" "2.1.0" "SARIF version"
check "$(jq -r '.runs[0].tool.driver.name' "$SARIF")" "Throne" "SARIF tool name"
check "$(jq -r '.runs[0].results | length' "$SARIF")" "3" "one SARIF result per finding"
# HIGH -> error, and the numeric security-severity GitHub sorts on is set.
check "$(jq -r '[.runs[0].results[] | select(.level=="error")] | length' "$SARIF")" "1" "high finding maps to level error"
check "$(jq -r '.runs[0].tool.driver.rules[] | select(.id=="shell-exec") | .properties["security-severity"]' "$SARIF")" "8.0" "high rule scored 8.0"
# A finding with no id field still yields a valid, non-empty ruleId.
if [ -n "$(jq -r '.runs[0].results[1].ruleId' "$SARIF")" ]; then echo "  ok: ruleId fallback for finding without an id"; pass=$((pass+1)); else echo "  FAIL: empty ruleId"; fail=$((fail+1)); fi
# Every result carries a location so GitHub never drops one; a real file when
# the scan reported one, otherwise the target.
check "$(jq -r '[.runs[0].results[] | select((.locations | length) > 0)] | length' "$SARIF")" "3" "every result has a location"
check "$(jq -r '.runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri' "$SARIF")" "src/tools/run.ts" "real file location preserved"
check "$(jq -r '.runs[0].results[0].locations[0].physicalLocation.region.startLine' "$SARIF")" "88" "line number preserved"
rm -f "$SARIF"

echo "== scenario 23: sarif-file on a clean scan writes an empty run (resolves stale alerts) =="
SARIF=$(mktemp)
run_gate "uvx some-pypi-mcp" "good" "not_fit" "off" "$SARIF"
check "$GATE_RC" "0" "exit 0"
check "$(getout sarif-file)" "$SARIF" "sarif-file output set even with no findings"
check "$(jq -r '.runs[0].results | length' "$SARIF")" "0" "empty results for a clean scan"
check "$(jq -r '.version' "$SARIF")" "2.1.0" "still a valid SARIF skeleton"
rm -f "$SARIF"

echo "== scenario 24: no sarif-file -> no file written, output stays empty =="
run_gate "@scope/cool-mcp" "good" "not_fit"
check "$(getout sarif-file)" "" "sarif-file output empty when not requested"

echo "== scenario 25: early failure -> no SARIF written, so a broken scan never resolves alerts =="
SARIF="$(mktemp -u)"   # a path that does not exist yet
run_gate "@scope/cool-mcp" "bad" "not_fit" "off" "$SARIF"
check "$GATE_RC" "1" "exit 1 (bad key)"
check "$(getout sarif-file)" "" "sarif-file output empty on early failure"
if [ ! -e "$SARIF" ]; then echo "  ok: no SARIF file written on early failure"; pass=$((pass+1)); else echo "  FAIL: wrote SARIF despite early failure"; fail=$((fail+1)); rm -f "$SARIF"; fi

echo ""
echo "RESULT: ${pass} passed, ${fail} failed"
[ "$fail" = "0" ]
