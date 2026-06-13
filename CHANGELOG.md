# Changelog

## v1.0.0

First public release.

- Composite action: submit a target, wait for the sandboxed scan, gate the build on the verdict.
- Inputs: `target`, `api-key`, `fail-on` (default `not_fit`), `comment-on-pr`, `github-token`, `api-base`, `timeout-seconds`.
- Outputs: `verdict`, `reason`, `security-verdict`, `scan-id`, `record-url`, `summary`.
- Job summary with a per-client result table and a link to the public evidence record.
- Optional sticky pull-request comment (best-effort; never fails the gate).
- Clear handling of bad keys (401), rate limits (429), and rejected targets.
- Record links use the clean `/server/<slug>` URL, matching the website.
