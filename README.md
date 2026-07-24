# Throne MCP Gate

**English** · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · [हिन्दी](README.hi.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md)

[![Throne MCP Gate on the GitHub Marketplace](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throne: paste an MCP server, get the verdict" width="840"></a>
</p>

**Stop shipping MCP servers that break on real clients.** This action executes your server in a disposable microVM, replays nine protocol steps against client behaviour calibrated from recorded Claude Code and Cursor traffic, scans the source for security issues, and fails the build when the verdict regresses.

Every run links to a public evidence record. Nothing is asserted without the execution that proved it.

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## Why

Every MCP directory lists self-reported entries. Nobody runs the servers. Throne does: a fresh Firecracker microVM per scan, installed from npm, PyPI, or GitHub, launched over stdio, and torn down afterward. The result is a verdict you can gate a merge on, backed by evidence anyone can read.

## Quickstart

Gate every pull request, and post the verdict back as a comment:

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # lets the action post the verdict comment

# One in-flight scan per branch: a new push cancels the previous run so two
# jobs never race to post the sticky comment.
concurrency:
  group: throne-${{ github.ref }}
  cancel-in-progress: true

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # or "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

Drop the `permissions` block if you do not want PR comments, or set `comment-on-pr: false`. The PR comment uses the `gh` CLI, which is preinstalled on GitHub-hosted runners; on a self-hosted runner without it, the comment is skipped and the verdict still lands in the job summary.

## Inputs

| input | required | default | meaning |
|---|---|---|---|
| `target` | yes | | npm package (`@scope/name` or `name`), `uvx <pypi-name>`, or `https://github.com/owner/repo` |
| `api-key` | yes | | your Throne API key. Keep it in repo secrets |
| `fail-on` | no | `not_fit` | comma-separated verdicts that block the merge. Add `inconclusive` for strict mode |
| `fail-on-security` | no | `off` | let the security scan also block: `review` blocks on any finding, `high` only on a high-severity one, `off` never blocks |
| `comment-on-pr` | no | `true` | post a sticky verdict comment on the PR (needs `pull-requests: write`) |
| `github-token` | no | `${{ github.token }}` | token used for the PR comment |
| `api-base` | no | `https://api.usethrone.dev` | override only for self-hosted or testing |
| `timeout-seconds` | no | `600` | give up waiting for the scan after this long |
| `sarif-file` | no | | path to write a SARIF report of the security findings, for upload to GitHub code scanning |

## Outputs

| output | meaning |
|---|---|
| `verdict` | `fit`, `not_fit`, `inconclusive`, or `unknown` |
| `reason` | when inconclusive: `needs_credentials`, `needs_arguments`, `needs_environment`, `unsupported_layout`, `install_timeout`, `no_handshake`, or `launch_error` |
| `security-verdict` | `clean`, `review`, or `not_run` |
| `security-findings` | total number of security findings (`0` when clean or not run) |
| `security-high` | number of high-severity security findings |
| `scan-id` | the scan backing this verdict |
| `record-url` | public evidence record |
| `summary` | one-line verdict summary |
| `sarif-file` | path to the written SARIF report, or empty when none was written |

Outputs stay defined even when the gate fails: if the scan errors, times out, or is rejected, a step reading them under `if: always()` sees `verdict: unknown`, `security-verdict: not_run`, and `security-findings: 0` rather than empty strings.

```yaml
      - uses: usethrone/throne-ci@v1
        id: throne
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
      - run: echo "Verdict was ${{ steps.throne.outputs.verdict }} — ${{ steps.throne.outputs.record-url }}"
```

## What the verdict means

- **fit** — full protocol compatibility on both client profiles. Safe to ship.
- **not_fit** — a real protocol failure. This is the only verdict that blocks by default.
- **inconclusive** — the server ran but could not be fully assessed. The `reason` says why. The most common is `needs_credentials`: the server installs and launches cleanly, then exits asking for an API key. That is usually fine, so `inconclusive` does **not** block unless you add it to `fail-on`.

Security findings are a separate axis. A `review` security verdict is material for a human to read; by default it never changes the compatibility verdict and does not block a merge. When there is something to review, the action always surfaces it as a warning annotation and lists the findings by severity in the job summary — you opt into blocking with `fail-on-security` (below).

## Strict mode

To also block when the server could not be assessed:

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## Gating on security

The compatibility verdict and the security scan are independent axes. By default (`fail-on-security: off`) security is review-only: findings show up in the job summary and as a warning, but they never fail the build. Opt in when you want CI to block on them:

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on-security: "high"   # block only on a high-severity finding
```

- **`off`** (default) — security never blocks. Findings are surfaced but advisory.
- **`review`** — block on *any* security finding (the strict choice).
- **`high`** — block only when there is at least one high-severity finding.

The two axes are additive: a `not_fit` verdict still blocks regardless of `fail-on-security`, and when both axes block the failure names both reasons. The security counts are also exposed as the `security-findings` and `security-high` outputs, so a downstream step can, say, alert on high-severity findings without re-parsing the summary.

The job summary and the PR comment also list each finding by severity, so the counts come with the detail a reviewer can act on — not just "3 findings" but what those three are.

## Code scanning (SARIF)

Set `sarif-file` and the action writes a [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) report of the security findings. Upload it with [`github/codeql-action/upload-sarif`](https://github.com/github/codeql-action) to see findings in the repository's **Security → Code scanning** tab, tracked over time and (where the scan reports a file) annotated inline on the diff:

```yaml
permissions:
  contents: read
  security-events: write   # lets upload-sarif publish the findings

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        id: throne
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          sarif-file: throne.sarif
      - uses: github/codeql-action/upload-sarif@v3
        if: always() && steps.throne.outputs.sarif-file != ''
        with:
          sarif_file: ${{ steps.throne.outputs.sarif-file }}
          category: throne
```

Severity maps to the code-scanning level: `high` → error, `medium` → warning, `low` → note. The report is written on any completed scan — including a clean one with zero findings, so a release that fixes an issue uploads an empty run and code scanning closes the resolved alert. It is deliberately **not** written when the scan fails, times out, or is rejected: guard the upload with `steps.throne.outputs.sarif-file != ''` (as above) so a broken run never resolves your alerts by uploading nothing.

## Auditability

This is a composite action. The entire gate is one readable shell script, [`throne-gate.sh`](./throne-gate.sh): no compiled binary, no bundled JavaScript, no transitive dependencies. For a tool you put in your release path, you should be able to read every line it runs. You can.

## Getting a key

Throne is onboarding a small group of founding design partners. Request a key at **hello@usethrone.dev** or apply at [usethrone.dev/pricing](https://usethrone.dev/pricing). The free scan at [usethrone.dev](https://usethrone.dev) needs no key.

## Wear the crown

If your server is `fit`, its evidence record offers a live README badge that re-renders from the latest scan. If a release ever breaks the verdict, the badge says so on its own.

## License

MIT. See [LICENSE](./LICENSE).
