# Throne MCP Gate

[English](README.md) · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · [हिन्दी](README.hi.md) · **日本語** · [한국어](README.ko.md) · [Deutsch](README.de.md)

[![GitHub Marketplace の Throne MCP Gate](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throne: MCP サーバーを貼り付けて、判定を受け取る" width="840"></a>
</p>

**実際のクライアントで壊れる MCP サーバーを出荷するのはやめましょう。** このアクションは、使い捨ての microVM 内でサーバーを実行し、記録された Claude Code と Cursor のトラフィックから較正したクライアント挙動に対して 9 つのプロトコルステップを再生し、ソースのセキュリティ問題をスキャンし、判定が後退したときにビルドを失敗させます。

すべての実行は公開された証拠記録にリンクします。それを証明した実行なしに主張されるものは何もありません。

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## なぜ必要か

どの MCP ディレクトリも、自己申告された項目を並べているだけで、誰もサーバーを実行していません。Throne は実行します。スキャンごとに新しい Firecracker microVM を用意し、npm・PyPI・GitHub からインストールし、stdio 越しに起動して、終わったら破棄します。その結果は、マージをブロックできる判定であり、誰でも読める証拠に裏付けられています。

## クイックスタート

すべてのプルリクエストをゲートし、判定をコメントとして投稿します。

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # アクションが判定コメントを投稿できるようにする

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # または "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

PR コメントが不要な場合は `permissions` ブロックを削除するか、`comment-on-pr: false` を設定してください。

## 入力

| 入力 | 必須 | デフォルト | 意味 |
|---|---|---|---|
| `target` | はい | | npm パッケージ（`@scope/name` または `name`）、`uvx <pypi-name>`、または `https://github.com/owner/repo` |
| `api-key` | はい | | あなたの Throne API キー。リポジトリのシークレットに保管してください |
| `fail-on` | いいえ | `not_fit` | マージをブロックする判定のカンマ区切り。厳格モードには `inconclusive` を追加 |
| `fail-on-security` | いいえ | `off` | セキュリティスキャンにもブロックさせる：`review` はすべての所見でブロック、`high` は高深刻度の所見のみでブロック、`off` は決してブロックしない |
| `comment-on-pr` | いいえ | `true` | PR に判定コメントを固定表示（`pull-requests: write` が必要） |
| `github-token` | いいえ | `${{ github.token }}` | PR コメントに使うトークン |
| `api-base` | いいえ | `https://api.usethrone.dev` | セルフホストやテスト時のみ上書き |
| `timeout-seconds` | いいえ | `600` | この秒数を超えたらスキャン待機を諦める |

## 出力

| 出力 | 意味 |
|---|---|
| `verdict` | `fit`、`not_fit`、`inconclusive`、または `unknown` |
| `reason` | inconclusive のとき：`needs_credentials`、`needs_arguments`、`needs_environment`、`unsupported_layout`、`install_timeout`、`no_handshake`、または `launch_error` |
| `security-verdict` | `clean`、`review`、または `not_run` |
| `security-findings` | セキュリティ所見の総数（クリーンまたは未実行のときは `0`） |
| `security-high` | 高深刻度のセキュリティ所見の数 |
| `scan-id` | この判定を裏付けるスキャン |
| `record-url` | 公開された証拠記録 |
| `summary` | 判定の 1 行要約 |

ゲートが失敗しても出力は定義されたままです。スキャンがエラーになった場合、タイムアウトした場合、または拒否された場合でも、`if: always()` で出力を読むステップは、空文字列ではなく `verdict: unknown`、`security-verdict: not_run`、`security-findings: 0` を受け取ります。

```yaml
      - uses: usethrone/throne-ci@v1
        id: throne
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
      - run: echo "Verdict was ${{ steps.throne.outputs.verdict }} — ${{ steps.throne.outputs.record-url }}"
```

## 判定の意味

- **fit** — 両方のクライアントプロファイルで完全なプロトコル互換性。出荷して安全です。
- **not_fit** — 実際のプロトコル失敗。デフォルトでブロックする唯一の判定です。
- **inconclusive** — サーバーは実行されたものの、完全には評価できませんでした。`reason` が理由を示します。最も多いのは `needs_credentials` で、サーバーはきれいにインストール・起動した後、API キーを求めて終了します。通常はこれで問題ないため、`fail-on` に追加しない限り `inconclusive` は**ブロックしません**。

セキュリティの所見は別の軸です。`review` のセキュリティ判定は人間が読むべき材料であり、デフォルトでは互換性判定を変えることはなく、マージをブロックすることもありません。レビューすべきものがあるときは、アクションは常にそれを警告アノテーションとして提示し、ジョブサマリーに所見を深刻度別に列挙します。ブロックさせたい場合は `fail-on-security`（下記）でオプトインします。

## 厳格モード

サーバーを評価できなかった場合にもブロックするには：

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## セキュリティでのゲート

互換性判定とセキュリティスキャンは独立した軸です。デフォルト（`fail-on-security: off`）ではセキュリティはレビュー専用で、所見はジョブサマリーと警告に表示されますが、ビルドを失敗させることは決してありません。CI にそれらでブロックさせたい場合はオプトインしてください：

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on-security: "high"   # 高深刻度の所見のときのみブロック
```

- **`off`**（デフォルト）— セキュリティは決してブロックしません。所見は提示されますが助言的です。
- **`review`** — *すべての* セキュリティ所見でブロックします（厳格な選択肢）。
- **`high`** — 高深刻度の所見が少なくとも 1 つあるときのみブロックします。

2 つの軸は加算的です。`not_fit` 判定は `fail-on-security` に関係なく依然としてブロックし、両方の軸がブロックするときは失敗が両方の理由を挙げます。セキュリティのカウントは `security-findings` と `security-high` の出力としても公開されるため、下流のステップはサマリーを再解析することなく、たとえば高深刻度の所見でアラートを出すことができます。

## 監査可能性

これはコンポジットアクションです。ゲート全体が 1 つの読みやすいシェルスクリプト [`throne-gate.sh`](./throne-gate.sh) です。コンパイル済みバイナリも、バンドルされた JavaScript も、推移的依存関係もありません。リリース経路に組み込むツールなら、実行されるすべての行を読めるべきです。読めます。

## キーの取得

Throne は少数のファウンディングデザインパートナーを募集しています。**hello@usethrone.dev** までキーをリクエストするか、[usethrone.dev/pricing](https://usethrone.dev/pricing) からお申し込みください。[usethrone.dev](https://usethrone.dev) の無料スキャンにキーは不要です。

## 王冠を身につける

あなたのサーバーが `fit` なら、その証拠記録から、最新スキャンを反映して再描画されるライブ README バッジを取得できます。リリースで判定が壊れれば、バッジが自動的にそれを示します。

## ライセンス

MIT。[LICENSE](./LICENSE) を参照してください。
