#!/usr/bin/env bash
# Throne CI gate. Submits the target to Throne, waits for the sandboxed scan
# to finish, renders the verdict into the job summary (and optionally a PR
# comment), then fails the job when the verdict is in `fail-on`.
#
# Inputs arrive as THRONE_* environment variables (set by action.yml). Only
# curl and jq are required, both preinstalled on GitHub-hosted runners.
set -euo pipefail

# ----------------------------------------------------------------- helpers ---

die() { echo "::error::$*"; exit 1; }
note() { echo "::notice::$*"; }
warn() { echo "::warning::$*"; }

# curl and jq are preinstalled on GitHub-hosted runners, but this action also
# supports self-hosted runners (see api-base). Fail clearly if either is absent
# rather than crashing mid-scan with a cryptic "command not found".
for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || die "'${dep}' is not installed on this runner. Throne needs both curl and jq; they are preinstalled on GitHub-hosted runners, so install ${dep} on your self-hosted runner."
done

# Friendly guards for the two required inputs (the most common setup mistake
# is a missing or misnamed api-key secret).
[ -n "${THRONE_TARGET:-}" ] || die "no target. Set the 'target' input: an npm package, 'uvx <pypi-name>', or a github.com/owner/repo URL."
[ -n "${THRONE_KEY:-}" ] || die "api-key is empty. Add your Throne key as a repo secret named THRONE_API_KEY and pass it as 'api-key'. Keys: hello@usethrone.dev"

# Keep the key out of logs no matter what echoes it later.
echo "::add-mask::${THRONE_KEY}"
THRONE_API="${THRONE_API:-https://api.usethrone.dev}"
THRONE_API="${THRONE_API%/}" # tolerate a trailing slash
THRONE_FAIL_ON="${THRONE_FAIL_ON:-not_fit}"
THRONE_TIMEOUT="${THRONE_TIMEOUT:-600}"
THRONE_COMMENT="${THRONE_COMMENT:-true}"

# The clean, canonical record URL for a (type, normalized) target. Mirrors the
# website's slugFor so the CI link and the public page never disagree.
record_url() {
  local type="$1" norm="$2" slug base owner repo
  if [ "$type" = "github" ]; then
    base=$(printf '%s' "$norm" | sed -E 's#^https?://github\.com/##; s#/+$##; s#\.git$##')
    owner=${base%%/*}
    repo=${base#*/}
    repo=${repo%%/*}
    slug=$(printf '%s-%s' "$owner" "$repo")
  else
    slug=$(printf '%s' "$norm" | sed 's/^@//; s#/#-#g')
  fi
  slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//')
  if [ -n "$slug" ]; then
    printf 'https://usethrone.dev/server/%s' "$slug"
  else
    printf 'https://usethrone.dev/server?s=%s' "$(jq -rn --arg t "$THRONE_TARGET" '$t|@uri')"
  fi
}

# Face (emoji + headline) for a verdict, mirroring the registry's classes.
verdict_face() {
  case "$1" in
    fit) echo "✅ FIT TO SHIP" ;;
    not_fit) echo "⛔ NOT FIT TO SHIP" ;;
    inconclusive)
      case "$2" in
        needs_credentials) echo "🔑 RUNS · NEEDS YOUR API KEY" ;;
        needs_arguments) echo "🔑 RUNS · NEEDS LAUNCH ARGUMENTS" ;;
        needs_environment) echo "🔌 RUNS · NEEDS A LIVE BACKEND" ;;
        *) echo "❔ INCONCLUSIVE" ;;
      esac ;;
    *) echo "❔ ${1:-unknown}" ;;
  esac
}

# ------------------------------------------------------------------ submit ---

payload=$(jq -nc --arg t "$THRONE_TARGET" '{target:$t}')
scan_id=""
for attempt in 1 2 3; do
  resp=$(curl -sS -m 30 -w $'\n%{http_code}' -X POST "${THRONE_API}/api/scan" \
    -H "Authorization: Bearer ${THRONE_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null) || resp=$'\n000'
  code=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
  case "$code" in
    200|201)
      scan_id=$(printf '%s' "$body" | jq -r '.scan_id // empty')
      [ -n "$scan_id" ] && break
      ;;
    401) die "Throne rejected the API key (401). Store a valid key in repo secrets and pass it as api-key. Keys: hello@usethrone.dev" ;;
    429) die "Throne rate-limited this key (429): 30 scans per hour. Wait and re-run." ;;
    400|422) die "Throne rejected the target '${THRONE_TARGET}' (${code}): $(printf '%s' "$body" | jq -r '.error // .detail // empty')" ;;
  esac
  echo "submit attempt ${attempt} failed (HTTP ${code}); retrying..."
  sleep $(( attempt * 3 ))
done
[ -n "$scan_id" ] || die "Could not submit the scan after 3 attempts (last HTTP ${code:-000}). Likely transient; re-run the job."

echo "scan_id=${scan_id}" >> "$GITHUB_OUTPUT"
note "Throne scan ${scan_id} queued for ${THRONE_TARGET}"

# -------------------------------------------------------------------- poll ---

deadline=$(( $(date +%s) + THRONE_TIMEOUT ))
status="running"
scan="{}"
last_progress=""
echo "::group::Throne scan ${THRONE_TARGET}"
while [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 8
  scan=$(curl -sS -m 30 "${THRONE_API}/api/scans/${scan_id}" 2>/dev/null || echo '{}')
  status=$(printf '%s' "$scan" | jq -r '.status // "polling"')
  progress=$(printf '%s' "$scan" | jq -r '.progress // empty')
  if [ -n "$progress" ] && [ "$progress" != "$last_progress" ]; then
    echo "  ${progress}"
    last_progress="$progress"
  fi
  if [ "$status" = "complete" ] || [ "$status" = "failed" ]; then break; fi
done
echo "::endgroup::"

if [ "$status" = "failed" ]; then
  err=$(printf '%s' "$scan" | jq -r '.error // "no detail"')
  die "Throne scan failed on our side: ${err}. This is usually transient; re-run the job."
fi
if [ "$status" != "complete" ]; then
  die "Throne scan did not finish within ${THRONE_TIMEOUT}s (status: ${status}). Raise timeout-seconds or re-run."
fi

# ----------------------------------------------------------------- verdict ---

verdict=$(printf '%s' "$scan" | jq -r '.verdict.value // "unknown"')
reason=$(printf '%s' "$scan" | jq -r '.verdict.reason // empty')
summary=$(printf '%s' "$scan" | jq -r '.verdict.summary // ""')
sec_verdict=$(printf '%s' "$scan" | jq -r '.security.verdict // "not_run"')
sec_total=$(printf '%s' "$scan" | jq -r '(.security.findings // []) | length')
sec_high=$(printf '%s' "$scan" | jq -r '[(.security.findings // [])[] | select((.severity // "" | ascii_upcase) == "HIGH")] | length')
type=$(printf '%s' "$scan" | jq -r '.target.type // empty')
norm=$(printf '%s' "$scan" | jq -r '.target.normalized // empty')
record=$(record_url "$type" "$norm")
face=$(verdict_face "$verdict" "$reason")

# Per-client overall: any fail -> FAIL, any warn -> WARN, has steps -> PASS,
# no steps -> CALIBRATING (an emulation profile not yet released).
clients_tsv=$(printf '%s' "$scan" | jq -r '
  .clients[]? | .name + "\t" + (
    if (.steps | length) == 0 then "calibrating"
    elif any(.steps[]; .status == "fail") then "fail"
    elif any(.steps[]; .status == "warn") then "warn"
    else "pass" end)')

# Persist the rest of the outputs.
{
  echo "verdict=${verdict}"
  echo "reason=${reason}"
  echo "security-verdict=${sec_verdict}"
  echo "record-url=${record}"
  printf 'summary<<THRONE_EOF\n%s\nTHRONE_EOF\n' "$summary"
} >> "$GITHUB_OUTPUT"

# ----------------------------------------------------------- report (md) ---

sec_line="SECURITY: $(printf '%s' "$sec_verdict" | tr '[:lower:]' '[:upper:]')"
if [ "$sec_verdict" = "review" ]; then
  sec_line="${sec_line} · ${sec_total} finding(s)"
  [ "$sec_high" -gt 0 ] && sec_line="${sec_line}, ${sec_high} high"
  sec_line="${sec_line} · review material, not a verdict"
elif [ "$sec_verdict" = "clean" ]; then
  sec_line="${sec_line} · no findings"
fi

build_report() {
  echo "## ${face}"
  echo ""
  echo "\`${THRONE_TARGET}\`"
  echo ""
  if [ -n "$clients_tsv" ]; then
    echo "| Client | Result |"
    echo "|---|---|"
    while IFS=$'\t' read -r cname cres; do
      [ -z "$cname" ] && continue
      echo "| ${cname} | \`$(printf '%s' "$cres" | tr '[:lower:]' '[:upper:]')\` |"
    done <<< "$clients_tsv"
    echo ""
  fi
  echo "**${sec_line}**"
  echo ""
  echo "[Full evidence record](${record}) · scan \`${scan_id}\`"
  echo ""
  echo "<sub>Executed in a disposable microVM against Claude Code and Cursor client behaviour. Verified by [Throne](https://usethrone.dev).</sub>"
}

report=$(build_report)
printf '%s\n' "$report" >> "$GITHUB_STEP_SUMMARY"

echo "VERDICT: ${verdict}${reason:+ (${reason})}"
echo "evidence: ${record}"

# ------------------------------------------------------- sticky PR comment ---
# Best-effort: never fail the gate because a comment could not be posted.
if [ "$THRONE_COMMENT" = "true" ] && [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ] && [ -n "${THRONE_GH_TOKEN:-}" ]; then
  post_comment() {
    local marker="<!-- throne-gate -->"
    local pr repo body existing
    pr=$(jq -r '.pull_request.number // empty' "${GITHUB_EVENT_PATH}")
    repo="${GITHUB_REPOSITORY}"
    [ -z "$pr" ] && return 0
    body="${marker}"$'\n\n'"${report}"
    existing=$(GH_TOKEN="$THRONE_GH_TOKEN" gh api "repos/${repo}/issues/${pr}/comments" --paginate 2>/dev/null \
      | jq -r --arg m "$marker" '.[] | select(.body | contains($m)) | .id' | head -n1)
    if [ -n "$existing" ]; then
      GH_TOKEN="$THRONE_GH_TOKEN" gh api -X PATCH "repos/${repo}/issues/comments/${existing}" -f body="$body" >/dev/null
    else
      GH_TOKEN="$THRONE_GH_TOKEN" gh api -X POST "repos/${repo}/issues/${pr}/comments" -f body="$body" >/dev/null
    fi
  }
  if command -v gh >/dev/null 2>&1; then
    post_comment || warn "Could not post the PR comment (needs pull-requests: write permission). The verdict is in the job summary."
  fi
fi

# ------------------------------------------------------------------- gate ---

blocked=0
IFS=',' read -ra FAILS <<< "$THRONE_FAIL_ON"
for b in "${FAILS[@]}"; do
  b=$(printf '%s' "$b" | tr -d '[:space:]')
  [ -z "$b" ] && continue
  if [ "$verdict" = "$b" ]; then blocked=1; fi
done

if [ "$blocked" = "1" ]; then
  die "Verdict '${verdict}' is in fail-on (${THRONE_FAIL_ON}). Blocking. Evidence: ${record}"
fi

if [ "$verdict" = "inconclusive" ]; then
  warn "Verdict 'inconclusive'${reason:+ (${reason})} is not in fail-on, so the gate passes. Evidence: ${record}"
else
  note "Throne gate passed: ${verdict}. Evidence: ${record}"
fi
