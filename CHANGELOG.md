# Changelog

## Unreleased

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
