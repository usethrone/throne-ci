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
THRONE_FAIL_ON_SECURITY="${THRONE_FAIL_ON_SECURITY:-off}"
THRONE_TIMEOUT="${THRONE_TIMEOUT:-600}"
THRONE_COMMENT="${THRONE_COMMENT:-true}"
# Optional path to write a SARIF report of the security findings. Empty (the
# default) means do not write one. When set, callers upload it with
# github/codeql-action/upload-sarif to surface findings in the Security tab.
THRONE_SARIF="${THRONE_SARIF:-}"

# timeout-seconds feeds bash arithmetic below; a non-numeric value (e.g. "10m")
# would blow up mid-run with a cryptic arithmetic error. Guard it up front.
case "$THRONE_TIMEOUT" in
  ''|*[!0-9]*) die "timeout-seconds must be a whole number of seconds, got '${THRONE_TIMEOUT}'." ;;
esac
[ "$THRONE_TIMEOUT" -gt 0 ] || die "timeout-seconds must be greater than 0, got '${THRONE_TIMEOUT}'."

# Accept the usual truthy spellings for the boolean inputs so "True"/"YES" do
# not silently disable the PR comment.
THRONE_COMMENT=$(printf '%s' "$THRONE_COMMENT" | tr '[:upper:]' '[:lower:]')
case "$THRONE_COMMENT" in
  true|yes|1|on) THRONE_COMMENT="true" ;;
  *) THRONE_COMMENT="false" ;;
esac

# A typo in fail-on (e.g. "notfit") would parse fine and then never match any
# verdict, silently disabling the gate. Warn on any token we do not recognise
# so a misconfigured gate is loud, not silently green.
_KNOWN_VERDICTS="fit not_fit inconclusive unknown"
IFS=',' read -ra _FAIL_TOKENS <<< "$THRONE_FAIL_ON"
for _tok in "${_FAIL_TOKENS[@]}"; do
  _tok=$(printf '%s' "$_tok" | tr -d '[:space:]')
  [ -z "$_tok" ] && continue
  case " ${_KNOWN_VERDICTS} " in
    *" ${_tok} "*) ;;
    *) warn "fail-on contains '${_tok}', which is not a known verdict (${_KNOWN_VERDICTS// /, }). It will never match, so the gate may never block. Check for a typo." ;;
  esac
done

# Security is a second, opt-in gate. `off` (default) keeps the historical
# behaviour: findings are review material and never block. `review` blocks on
# any finding; `high` blocks only on a high-severity one. Normalise the input to
# one of off/review/high. Mirror the fail-on ethos: a typo warns loudly and
# leaves the gate open rather than silently blocking (or silently disabling a
# gate the user asked for) — a wrong value is never treated as a stricter one.
SEC_GATE=$(printf '%s' "$THRONE_FAIL_ON_SECURITY" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
case "$SEC_GATE" in
  ''|off|none|never|no|false|0) SEC_GATE="off" ;;
  review|any|all|findings) SEC_GATE="review" ;;
  high|high-only|highs) SEC_GATE="high" ;;
  *)
    warn "fail-on-security='${THRONE_FAIL_ON_SECURITY}' is not recognised. Use 'off', 'review', or 'high'. Treating it as 'off' (security will not block)."
    SEC_GATE="off"
    ;;
esac

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

# Downstream steps often read these outputs under `if: always()`. Seed every
# output with a defined default now so a failure path (bad key, scan failure,
# timeout) never leaves them as empty strings; real values written later win,
# because GitHub takes the last value for a repeated output name.
{
  echo "verdict=unknown"
  echo "reason="
  echo "security-verdict=not_run"
  echo "security-findings=0"
  echo "security-high=0"
  echo "scan-id="
  echo "record-url=$(record_url '' '')"
  echo "summary="
  echo "sarif-file="
} >> "$GITHUB_OUTPUT"

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
  # Do not sleep after the final attempt — we are about to give up anyway.
  if [ "$attempt" -lt 3 ]; then
    echo "submit attempt ${attempt} failed (HTTP ${code}); retrying..."
    sleep $(( attempt * 3 ))
  else
    echo "submit attempt ${attempt} failed (HTTP ${code})."
  fi
done
[ -n "$scan_id" ] || die "Could not submit the scan after 3 attempts (last HTTP ${code:-000}). Likely transient; re-run the job."

# The key must match action.yml's `scan-id` output exactly; GitHub does not
# fuzzy-match `scan_id` to `scan-id`.
echo "scan-id=${scan_id}" >> "$GITHUB_OUTPUT"
note "Throne scan ${scan_id} queued for ${THRONE_TARGET}"

# -------------------------------------------------------------------- poll ---

# Internal knob (not an action input): the offline test suite shrinks this so
# the scenarios do not each sit through 8-second sleeps.
poll_interval="${THRONE_POLL_INTERVAL:-8}"
case "$poll_interval" in ''|*[!0-9]*|0) poll_interval=8 ;; esac

deadline=$(( $(date +%s) + THRONE_TIMEOUT ))
status="running"
scan="{}"
last_progress=""
missing=0
echo "::group::Throne scan ${THRONE_TARGET}"
while [ "$(date +%s)" -lt "$deadline" ]; do
  sleep "$poll_interval"
  resp=$(curl -sS -m 30 -w $'\n%{http_code}' "${THRONE_API}/api/scans/${scan_id}" \
    -H "Authorization: Bearer ${THRONE_KEY}" 2>/dev/null) || resp=$'\n000'
  code=$(printf '%s' "$resp" | tail -n1)
  body=$(printf '%s' "$resp" | sed '$d')
  # A 404 means the API no longer knows the scan we just submitted. One could
  # be a routing blip; three in a row means it is gone, and polling until the
  # timeout would just burn ten minutes to report the same thing.
  if [ "$code" = "404" ]; then
    missing=$((missing + 1))
    if [ "$missing" -ge 3 ]; then
      echo "::endgroup::"
      die "Throne no longer knows scan ${scan_id} (three 404s in a row). Likely transient; re-run the job."
    fi
    continue
  fi
  missing=0
  # Anything else non-2xx (5xx, 000 network error) or a non-JSON body is
  # transient: keep the last good state and try again next tick.
  case "$code" in 2*) ;; *) continue ;; esac
  printf '%s' "$body" | jq -e . >/dev/null 2>&1 || continue
  scan="$body"
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
# Per-severity counts for the breakdown and the high-severity gate. Severity is
# upper-cased defensively; a severity_count helper keeps the four calls uniform.
severity_count() { printf '%s' "$scan" | jq -r --arg s "$1" '[(.security.findings // [])[] | select((.severity // "" | ascii_upcase) == $s)] | length'; }
sec_high=$(severity_count HIGH)
sec_med=$(severity_count MEDIUM)
sec_low=$(severity_count LOW)
# Anything with an unrecognised or missing severity lands in `other`, so the
# buckets always sum to the total.
sec_other=$(( sec_total - sec_high - sec_med - sec_low ))
type=$(printf '%s' "$scan" | jq -r '.target.type // empty')
norm=$(printf '%s' "$scan" | jq -r '.target.normalized // empty')
record=$(record_url "$type" "$norm")
face=$(verdict_face "$verdict" "$reason")

# Human-readable severity breakdown, e.g. "1 high, 2 medium". Only non-empty
# buckets appear, so a lone medium finding does not read as "0 high, 1 medium".
sev_bits=""
add_bit() { [ "$1" -gt 0 ] && sev_bits="${sev_bits:+${sev_bits}, }${1} ${2}"; return 0; }
add_bit "$sec_high" high
add_bit "$sec_med" medium
add_bit "$sec_low" low
add_bit "$sec_other" other

# Resolve the security gate now so the report, the annotations, and the exit
# decision all agree. `review` blocks on any finding; `high` on a high one.
sec_blocks=0
sec_block_msg=""
case "$SEC_GATE" in
  review)
    if [ "$sec_verdict" = "review" ]; then
      sec_blocks=1
      sec_block_msg="security scan returned 'review'${sev_bits:+ (${sev_bits})} and fail-on-security=review"
    fi ;;
  high)
    if [ "$sec_high" -gt 0 ]; then
      sec_blocks=1
      sec_block_msg="${sec_high} high-severity security finding(s) and fail-on-security=high"
    fi ;;
esac

# Per-client overall: any fail -> FAIL, any warn -> WARN, has steps -> PASS,
# no steps -> CALIBRATING (an emulation profile not yet released).
clients_tsv=$(printf '%s' "$scan" | jq -r '
  .clients[]? | .name + "\t" + (
    if (.steps | length) == 0 then "calibrating"
    elif any(.steps[]; .status == "fail") then "fail"
    elif any(.steps[]; .status == "warn") then "warn"
    else "pass" end)')

# Per-finding "SEVERITY<TAB>title" rows for the detail table in the report, so a
# reviewer sees what the findings are, not just how many. Rows are ordered
# highest-severity first (an unrecognised severity sorts last but is never
# dropped). The title falls back through a few field names the API may use, then
# to a generic label. Tabs and newlines are flattened and pipes escaped so a
# title can never break the TSV split or the markdown table it feeds.
findings_tsv=$(printf '%s' "$scan" | jq -r '
  def rank($x): ($x // "" | tostring | ascii_upcase) as $u
    | if $u == "HIGH" then 0 elif $u == "MEDIUM" then 1
      elif $u == "LOW" then 2 else 3 end;
  (.security.findings // [])
  | sort_by(rank(.severity))[]
  | ((.severity // "unknown") | ascii_upcase) + "\t"
  + ((.title // .message // .name // .description // "Security finding") | tostring
     | gsub("[\t\n\r]"; " ") | gsub("[|]"; "\\|") | .[0:200])')

# Persist the rest of the outputs.
{
  echo "verdict=${verdict}"
  echo "reason=${reason}"
  echo "security-verdict=${sec_verdict}"
  echo "security-findings=${sec_total}"
  echo "security-high=${sec_high}"
  echo "record-url=${record}"
  printf 'summary<<THRONE_EOF\n%s\nTHRONE_EOF\n' "$summary"
} >> "$GITHUB_OUTPUT"

# ------------------------------------------------------------------ sarif ---
# When sarif-file is set, write a SARIF 2.1.0 report of the security findings so
# it can be uploaded with github/codeql-action/upload-sarif and shown in the
# Security tab (and inline on the PR). We emit it whenever the scan completed —
# even with zero findings — because code scanning treats an empty run as "these
# alerts are resolved" and closes stale ones. It is intentionally NOT written on
# an early failure (bad key, timeout): the seeded empty `sarif-file` output tells
# callers to skip the upload rather than wrongly resolving every prior finding.
if [ -n "$THRONE_SARIF" ]; then
  # Severity drives both the SARIF `level` (how GitHub badges the alert) and the
  # `security-severity` property (the numeric score the Security tab sorts on).
  # Every finding also carries a location: a real file/line when the scan
  # reported one, otherwise the target itself, so no result is dropped for
  # lacking a location. Rules are de-duplicated by id and scored by their
  # highest-severity finding.
  sarif_loc="${norm:-$THRONE_TARGET}"
  mkdir -p "$(dirname "$THRONE_SARIF")"
  printf '%s' "$scan" | jq \
    --arg ver "${GITHUB_ACTION_REF:-v1}" \
    --arg loc "$sarif_loc" \
    --arg record "$record" '
    def sev($x): ($x // "unknown" | tostring | ascii_upcase);
    def level($x): sev($x) as $u
      | if $u == "HIGH" then "error" elif $u == "MEDIUM" then "warning"
        elif $u == "LOW" then "note" else "warning" end;
    def score($x): sev($x) as $u
      | if $u == "HIGH" then "8.0" elif $u == "MEDIUM" then "5.0"
        elif $u == "LOW" then "2.0" else "0.0" end;
    def rank($x): sev($x) as $u
      | if $u == "HIGH" then 3 elif $u == "MEDIUM" then 2
        elif $u == "LOW" then 1 else 0 end;
    def ruleid: (.id // .rule // .check // .category // .type // "throne-security") | tostring;
    def title: (.title // .message // .name // .description // "Security finding") | tostring;
    (.security.findings // []) as $f
    | {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        version: "2.1.0",
        runs: [{
          tool: { driver: {
            name: "Throne",
            informationUri: "https://usethrone.dev",
            version: $ver,
            rules: ([$f[] | {id: ruleid, sev: (.severity // ""), t: title}]
              | group_by(.id)
              | map((max_by(rank(.sev))) as $top | {
                  id: $top.id,
                  name: $top.id,
                  shortDescription: { text: $top.t },
                  properties: { "security-severity": score($top.sev) }
                }))
          }},
          results: [$f[] | {
            ruleId: ruleid,
            level: level(.severity),
            message: { text: (title + " [" + sev(.severity) + "]") },
            locations: [{ physicalLocation: (
              { artifactLocation: { uri: ((.file // .path // $loc) | tostring) } }
              + (if (.line // .start_line // .startLine)
                 then { region: { startLine: (((.line // .start_line // .startLine) | tonumber?) // 1) } }
                 else {} end)
            )}],
            properties: { severity: sev(.severity), record: $record }
          }]
        }]
      }' > "$THRONE_SARIF"
  echo "sarif-file=${THRONE_SARIF}" >> "$GITHUB_OUTPUT"
  note "Wrote SARIF report (${sec_total} finding(s)) to ${THRONE_SARIF}. Upload it with github/codeql-action/upload-sarif to see findings in the Security tab."
fi

# ----------------------------------------------------------- report (md) ---

sec_line="SECURITY: $(printf '%s' "$sec_verdict" | tr '[:lower:]' '[:upper:]')"
if [ "$sec_verdict" = "review" ]; then
  sec_line="${sec_line} · ${sec_total} finding(s)"
  [ -n "$sev_bits" ] && sec_line="${sec_line} (${sev_bits})"
  if [ "$sec_blocks" = "1" ]; then
    sec_line="${sec_line} · blocks the merge (fail-on-security=${SEC_GATE})"
  else
    sec_line="${sec_line} · review material, not a verdict"
  fi
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
  # List what the findings actually are, highest severity first, so the count in
  # sec_line is backed by detail a reviewer can act on. Only shown when there is
  # at least one finding.
  if [ -n "$findings_tsv" ]; then
    echo "| Severity | Finding |"
    echo "|---|---|"
    while IFS=$'\t' read -r fsev ftitle; do
      [ -z "$fsev" ] && continue
      echo "| \`${fsev}\` | ${ftitle} |"
    done <<< "$findings_tsv"
    echo ""
  fi
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

# Two independent axes can block: the compatibility verdict (fail-on) and the
# security scan (fail-on-security). Collect every reason so the failure names
# all of them at once instead of hiding the second behind the first.
block_reasons=()

compat_blocked=0
IFS=',' read -ra FAILS <<< "$THRONE_FAIL_ON"
for b in "${FAILS[@]}"; do
  b=$(printf '%s' "$b" | tr -d '[:space:]')
  [ -z "$b" ] && continue
  if [ "$verdict" = "$b" ]; then compat_blocked=1; fi
done
[ "$compat_blocked" = "1" ] && block_reasons+=("verdict '${verdict}' is in fail-on (${THRONE_FAIL_ON})")
[ "$sec_blocks" = "1" ] && block_reasons+=("${sec_block_msg}")

if [ "${#block_reasons[@]}" -gt 0 ]; then
  why=""
  for r in "${block_reasons[@]}"; do why="${why:+${why}; }${r}"; done
  die "Blocking: ${why}. Evidence: ${record}"
fi

# Not blocking. Surface a review-only security result so it is visible in the
# Checks UI (not just buried in the summary), and point at the opt-in gate.
if [ "$sec_verdict" = "review" ]; then
  warn "Security scan flagged ${sec_total} finding(s)${sev_bits:+ (${sev_bits})} to review — material, not blocking. Set fail-on-security to 'review' or 'high' to gate on it. Evidence: ${record}"
fi

if [ "$verdict" = "inconclusive" ]; then
  warn "Verdict 'inconclusive'${reason:+ (${reason})} is not in fail-on, so the gate passes. Evidence: ${record}"
else
  note "Throne gate passed: ${verdict}. Evidence: ${record}"
fi
