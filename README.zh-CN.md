# Throne MCP Gate

[English](README.md) · **简体中文** · [Русский](README.ru.md) · [हिन्दी](README.hi.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md)

[![GitHub Marketplace 上的 Throne MCP Gate](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throne：粘贴一个 MCP 服务器，得到判定" width="840"></a>
</p>

> 本文档为翻译版本，英文 [README](README.md) 为权威来源。

**不要再发布会在真实客户端里崩溃的 MCP 服务器。** 这个 Action 会在一次性的 microVM 中运行你的服务器，按照从真实 Claude Code 与 Cursor 流量校准出的客户端行为重放九个协议步骤，扫描源码中的安全问题，并在判定结果回退时让构建失败。

每一次运行都会链接到一份公开的证据记录。没有经过实际执行验证的结论，我们绝不声称。

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## 为什么

每个 MCP 目录都只是自我申报的条目，没有人真正运行过这些服务器。Throne 会运行：每次扫描都启动一个全新的 Firecracker microVM，从 npm、PyPI 或 GitHub 安装，通过 stdio 启动，运行结束后销毁。最终得到一个可以用来卡合并的判定结果，而且任何人都能查阅背后的证据。

## 快速开始

为每个 Pull Request 设卡，并把判定结果作为评论回帖：

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # 允许该 Action 发布判定评论

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # 或 "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

如果不需要 PR 评论，可删除 `permissions` 块，或设置 `comment-on-pr: false`。

## 输入

| 参数 | 必填 | 默认值 | 含义 |
|---|---|---|---|
| `target` | 是 | | npm 包（`@scope/name` 或 `name`）、`uvx <pypi-name>`，或 `https://github.com/owner/repo` |
| `api-key` | 是 | | 你的 Throne API 密钥。请存放在仓库 secrets 中 |
| `fail-on` | 否 | `not_fit` | 触发构建失败的判定，逗号分隔。加入 `inconclusive` 即为严格模式 |
| `fail-on-security` | 否 | `off` | 让安全扫描也参与卡合并：`review` 遇到任何发现即卡住，`high` 仅在高危发现时卡住，`off` 从不卡住 |
| `comment-on-pr` | 否 | `true` | 在 PR 上发布固定的判定评论（需要 `pull-requests: write`） |
| `github-token` | 否 | `${{ github.token }}` | 用于发布 PR 评论的令牌 |
| `api-base` | 否 | `https://api.usethrone.dev` | 仅在自托管或测试时才需要覆盖 |
| `timeout-seconds` | 否 | `600` | 等待扫描的最长秒数 |

## 输出

| 输出 | 含义 |
|---|---|
| `verdict` | `fit`、`not_fit`、`inconclusive` 或 `unknown` |
| `reason` | 当 inconclusive 时：`needs_credentials`、`needs_arguments`、`needs_environment`、`unsupported_layout`、`install_timeout`、`no_handshake` 或 `launch_error` |
| `security-verdict` | `clean`、`review` 或 `not_run` |
| `security-findings` | 安全发现的总数（干净或未运行时为 `0`） |
| `security-high` | 高危安全发现的数量 |
| `scan-id` | 支撑该判定的扫描 ID |
| `record-url` | 公开证据记录的链接 |
| `summary` | 一行判定摘要 |

即使门禁失败，输出也保持有定义：当扫描出错、超时或被拒绝时，在 `if: always()` 下读取输出的步骤会看到 `verdict: unknown` 和 `security-verdict: not_run`，而不是空字符串。

## 判定结果的含义

- **fit** — 在两个客户端画像上都完全兼容协议。可以放心发布。
- **not_fit** — 真实的协议失败。这是默认情况下唯一会卡住合并的判定。
- **inconclusive** — 服务器运行了，但无法被完整评估。`reason` 会说明原因。最常见的是 `needs_credentials`：服务器安装并正常启动，然后因缺少 API 密钥而退出。这通常没有问题，因此除非你把它加入 `fail-on`，否则 `inconclusive` **不会**卡住合并。

安全发现属于另一条独立的判定轴。`review` 的安全判定是给人审阅的材料，它不会改变兼容性判定，也不会单独卡住合并。

## 严格模式

如果你也希望在服务器无法被评估时卡住合并：

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## 可审计性

这是一个 composite action，整个门禁就是一份可读的 shell 脚本 [`throne-gate.sh`](./throne-gate.sh)：没有编译后的二进制文件，没有打包的 JavaScript，没有任何传递依赖。对于一个放进发布流程的工具，你应该能读懂它运行的每一行。这里你可以。

## 获取密钥

Throne 正在招募一小批创始设计合作伙伴。请发送邮件至 **hello@usethrone.dev** 申请密钥，或在 [usethrone.dev/pricing](https://usethrone.dev/pricing) 提交申请。[usethrone.dev](https://usethrone.dev) 上的免费扫描无需密钥。

## 佩戴王冠

如果你的服务器判定为 `fit`，它的证据记录会提供一个实时的 README 徽章，徽章会根据最新一次扫描自动刷新。如果某次发布破坏了判定结果，徽章会自动如实显示。

## 许可证

MIT。详见 [LICENSE](./LICENSE)。
