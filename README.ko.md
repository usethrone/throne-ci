# Throne MCP Gate

[English](README.md) · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · [हिन्दी](README.hi.md) · [日本語](README.ja.md) · **한국어** · [Deutsch](README.de.md)

[![GitHub Marketplace의 Throne MCP Gate](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throne: MCP 서버를 붙여넣고 판정을 받으세요" width="840"></a>
</p>

**실제 클라이언트에서 깨지는 MCP 서버를 출시하지 마세요.** 이 액션은 일회용 microVM 안에서 서버를 실행하고, 기록된 Claude Code 및 Cursor 트래픽으로 보정한 클라이언트 동작에 대해 9개의 프로토콜 단계를 재생하며, 소스의 보안 문제를 스캔하고, 판정이 후퇴하면 빌드를 실패시킵니다.

모든 실행은 공개 증거 기록으로 연결됩니다. 그것을 증명한 실행 없이는 아무것도 주장하지 않습니다.

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## 왜 필요한가

모든 MCP 디렉터리는 자기 신고된 항목을 나열할 뿐, 아무도 서버를 실행하지 않습니다. Throne은 실행합니다. 스캔마다 새로운 Firecracker microVM을 만들고, npm·PyPI·GitHub에서 설치하여 stdio로 실행한 뒤 끝나면 폐기합니다. 그 결과는 머지를 막을 수 있는 판정이며, 누구나 읽을 수 있는 증거로 뒷받침됩니다.

## 빠른 시작

모든 풀 리퀘스트를 게이트하고 판정을 코멘트로 게시합니다.

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # 액션이 판정 코멘트를 게시할 수 있게 함

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # 또는 "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

PR 코멘트를 원하지 않으면 `permissions` 블록을 제거하거나 `comment-on-pr: false`로 설정하세요.

## 입력

| 입력 | 필수 | 기본값 | 의미 |
|---|---|---|---|
| `target` | 예 | | npm 패키지(`@scope/name` 또는 `name`), `uvx <pypi-name>`, 또는 `https://github.com/owner/repo` |
| `api-key` | 예 | | Throne API 키. 저장소 시크릿에 보관하세요 |
| `fail-on` | 아니오 | `not_fit` | 머지를 막는 판정의 쉼표 구분 목록. 엄격 모드에는 `inconclusive` 추가 |
| `fail-on-security` | 아니오 | `off` | 보안 스캔도 함께 막게 함: `review`는 발견 사항이 하나라도 있으면 막고, `high`는 심각도 높은 것에서만, `off`는 절대 막지 않음 |
| `comment-on-pr` | 아니오 | `true` | PR에 판정 코멘트 고정(`pull-requests: write` 필요) |
| `github-token` | 아니오 | `${{ github.token }}` | PR 코멘트에 사용하는 토큰 |
| `api-base` | 아니오 | `https://api.usethrone.dev` | 셀프 호스팅이나 테스트에서만 재정의 |
| `timeout-seconds` | 아니오 | `600` | 이 시간이 지나면 스캔 대기를 포기 |

## 출력

| 출력 | 의미 | 
|---|---|
| `verdict` | `fit`, `not_fit`, `inconclusive`, 또는 `unknown` |
| `reason` | inconclusive일 때: `needs_credentials`, `needs_arguments`, `needs_environment`, `unsupported_layout`, `install_timeout`, `no_handshake`, 또는 `launch_error` |
| `security-verdict` | `clean`, `review`, 또는 `not_run` |
| `security-findings` | 보안 발견 사항 총 개수(깨끗하거나 실행되지 않았을 때 `0`) |
| `security-high` | 심각도 높은 보안 발견 사항의 개수 |
| `scan-id` | 이 판정을 뒷받침하는 스캔 |
| `record-url` | 공개 증거 기록 |
| `summary` | 판정 한 줄 요약 |

게이트가 실패해도 출력은 정의된 상태로 유지됩니다. 스캔이 오류로 끝나거나, 시간 초과되거나, 거부된 경우에도 `if: always()`로 출력을 읽는 스텝은 빈 문자열 대신 `verdict: unknown`, `security-verdict: not_run`, `security-findings: 0`을 받습니다.

```yaml
      - uses: usethrone/throne-ci@v1
        id: throne
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
      - run: echo "Verdict was ${{ steps.throne.outputs.verdict }} — ${{ steps.throne.outputs.record-url }}"
```

## 판정의 의미

- **fit** — 두 클라이언트 프로파일 모두에서 완전한 프로토콜 호환성. 출시해도 안전합니다.
- **not_fit** — 실제 프로토콜 실패. 기본적으로 머지를 막는 유일한 판정입니다.
- **inconclusive** — 서버는 실행되었지만 완전히 평가할 수 없었습니다. `reason`이 이유를 설명합니다. 가장 흔한 것은 `needs_credentials`로, 서버가 깔끔하게 설치·실행된 후 API 키를 요구하며 종료합니다. 보통 이는 정상이므로, `fail-on`에 추가하지 않는 한 `inconclusive`는 **막지 않습니다**.

보안 발견 사항은 별도의 축입니다. `review` 보안 판정은 사람이 읽어야 할 자료이며, 호환성 판정을 바꾸지 않고 그 자체로 머지를 막지도 않습니다.

## 엄격 모드

서버를 평가할 수 없을 때도 막으려면:

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## 감사 가능성

이것은 컴포지트 액션입니다. 게이트 전체가 읽기 쉬운 하나의 셸 스크립트 [`throne-gate.sh`](./throne-gate.sh)입니다. 컴파일된 바이너리도, 번들된 JavaScript도, 전이 의존성도 없습니다. 릴리스 경로에 넣는 도구라면 실행되는 모든 줄을 읽을 수 있어야 합니다. 읽을 수 있습니다.

## 키 받기

Throne는 소수의 파운딩 디자인 파트너를 모집하고 있습니다. **hello@usethrone.dev** 로 키를 요청하거나 [usethrone.dev/pricing](https://usethrone.dev/pricing) 에서 신청하세요. [usethrone.dev](https://usethrone.dev) 의 무료 스캔에는 키가 필요하지 않습니다.

## 왕관을 쓰세요

서버가 `fit`이면, 그 증거 기록에서 최신 스캔으로 다시 렌더링되는 라이브 README 배지를 받을 수 있습니다. 릴리스가 판정을 깨뜨리면 배지가 스스로 그것을 알립니다.

## 라이선스

MIT. [LICENSE](./LICENSE)를 참조하세요.
