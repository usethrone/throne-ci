# Changelog

## Unreleased

- Add `sarif-file`: write a SARIF 2.1.0 report of the security findings for upload to GitHub code scanning (`github/codeql-action/upload-sarif`). Severity maps to the code-scanning level (`high`→error, `medium`→warning, `low`→note) and to the numeric `security-severity` the Security tab sorts on; rules are de-duplicated by id and every result carries a location (a real file/line when the scan reports one, otherwise the target) so none is dropped. The report is written on any completed scan — including a clean one, so resolved alerts auto-close — but never on an early failure, so a broken run cannot resolve alerts by uploading an empty result set. Exposed as the `sarif-file` output (empty when none was written).
- Surface the security findings themselves, not just their counts: the job summary and PR comment now include a severity-ordered table of each finding (title + severity), and finding titles fall back through a few field names before a generic label.
- Add `fail-on-security`: opt in to failing the build on the security scan. `review` blocks on any finding, `high` blocks only on a high-severity one, `off` (default) keeps the historical review-only behaviour. The compatibility verdict and the security scan are independent axes, so both can block and the failure names every reason. An unrecognised value warns and is treated as `off` rather than silently blocking.
- Surface security findings even when they do not block: the job summary and PR comment now break findings down by severity (e.g. "3 finding(s) (1 high, 2 medium)"), and a review result is emitted as a warning annotation so it is visible in the Checks UI.
- Add `security-findings` and `security-high` outputs (finding counts), seeded to `0` alongside the other always-defined outputs.
- Seed every output with a defined default (`verdict=unknown`, `security-verdict=not_run`, empty `reason`/`scan-id`/`summary`, a search-URL `record-url`) before submitting, so steps reading outputs under `if: always()` see those values instead of empty strings when the scan fails, times out, or is rejected.
- Fix the `scan-id` output: the script wrote `scan_id=` while `action.yml` reads `scan-id`, so the output was always empty.
- Authenticate poll requests with the API key, matching the submit request.
- Harden the poll loop: ignore transient non-2xx responses and malformed bodies instead of clobbering the last good state, and fail fast with a clear message when the scan 404s three times in a row rather than spinning until the timeout.
- Preflight-check `curl` and `jq` before running, with a clear message for self-hosted runners.
- Validate `timeout-seconds` is a positive whole number and fail fast on garbage (e.g. `10m`) instead of a cryptic arithmetic error mid-run.
- Warn when `fail-on` contains a token that is not a known verdict (e.g. a `notfit` typo) so a misconfigured gate is loud, not silently green.
- Accept the usual truthy spellings (`true`/`yes`/`1`/`on`, any case) for `comment-on-pr`.
- Skip the back-off sleep after the final submit attempt.
- Docs: add a `concurrency` block to the quickstart and note the `gh` requirement for PR comments.

## v1.0.0

First public release.

- Composite action: submit a target, wait for the sandboxed scan, gate the build on the verdict.
- Inputs: `target`, `api-key`, `fail-on` (default `not_fit`), `comment-on-pr`, `github-token`, `api-base`, `timeout-seconds`.
- Outputs: `verdict`, `reason`, `security-verdict`, `scan-id`, `record-url`, `summary`.
- Job summary with a per-client result table and a link to the public evidence record.
- Optional sticky pull-request comment (best-effort; never fails the gate).
- Clear handling of bad keys (401), rate limits (429), and rejected targets.
- Record links use the clean `/server/<slug>` URL, matching the website.
