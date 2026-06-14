# Throne MCP Gate

**English** Â· [ç®€ä½“ä¸­æ–‡](README.zh-CN.md) Â· [Ð ÑƒÑÑÐºÐ¸Ð¹](README.ru.md) Â· [à¤¹à¤¿à¤¨à¥à¤¦à¥€](README.hi.md)

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

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # or "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

Drop the `permissions` block if you do not want PR comments, or set `comment-on-pr: false`.

## Inputs

| input | required | default | meaning |
|---|---|---|---|
| `target` | yes | | npm package (`@scope/name` or `name`), `uvx <pypi-name>`, or `https://github.com/owner/repo` |
| `api-key` | yes | | your Throne API key. Keep it in repo secrets |
| `fail-on` | no | `not_fit` | comma-separated verdicts that block the merge. Add `inconclusive` for strict mode |
| `comment-on-pr` | no | `true` | post a sticky verdict comment on the PR (needs `pull-requests: write`) |
| `github-token` | no | `${{ github.token }}` | token used for the PR comment |
| `api-base` | no | `https://api.usethrone.dev` | override only for self-hosted or testing |
| `timeout-seconds` | no | `600` | give up waiting for the scan after this long |

## Outputs

| output | meaning |
|---|---|
| `verdict` | `fit`, `not_fit`, `inconclusive`, or `unknown` |
| `reason` | when inconclusive: `needs_credentials`, `needs_arguments`, `needs_environment`, `unsupported_layout`, `install_timeout`, `no_handshake`, or `launch_error` |
| `security-verdict` | `clean`, `review`, or `not_run` |
| `scan-id` | the scan backing this verdict |
| `record-url` | public evidence record |
| `summary` | one-line verdict summary |

```yaml
      - uses: usethrone/throne-ci@v1
        id: throne
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
      - run: echo "Verdict was ${{ steps.throne.outputs.verdict }} â€” ${{ steps.throne.outputs.record-url }}"
```

## What the verdict means

- **fit** â€” full protocol compatibility on both client profiles. Safe to ship.
- **not_fit** â€” a real protocol failure. This is the only verdict that blocks by default.
- **inconclusive** â€” the server ran but could not be fully assessed. The `reason` says why. The most common is `needs_credentials`: the server installs and launches cleanly, then exits asking for an API key. That is usually fine, so `inconclusive` does **not** block unless you add it to `fail-on`.

Security findings are a separate axis. A `review` security verdict is material for a human to read; it never changes the compatibility verdict and never blocks a merge on its own.

## Strict mode

To also block when the server could not be assessed:

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## Auditability

This is a composite action. The entire gate is one readable shell script, [`throne-gate.sh`](./throne-gate.sh): no compiled binary, no bundled JavaScript, no transitive dependencies. For a tool you put in your release path, you should be able to read every line it runs. You can.

## Getting a key

Founding-customer keys are `$29/mo` with a 12-month price lock. Email **hello@usethrone.dev** or see [usethrone.dev/pricing](https://usethrone.dev/pricing).

## Wear the crown

If your server is `fit`, its evidence record offers a live README badge that re-renders from the latest scan. If a release ever breaks the verdict, the badge says so on its own.

## License

MIT. See [LICENSE](./LICENSE).
