# Throne MCP Gate

[English](README.md) Â· **ç®€ä½“ä¸­æ–‡** Â· [Ð ÑƒÑÑÐºÐ¸Ð¹](README.ru.md) Â· [à¤¹à¤¿à¤¨à¥à¤¦à¥€](README.hi.md)

[![GitHub Marketplace ä¸Šçš„ Throne MCP Gate](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throneï¼šç²˜è´´ä¸€ä¸ª MCP æœåŠ¡å™¨ï¼Œå¾—åˆ°åˆ¤å®š" width="840"></a>
</p>

> æœ¬æ–‡æ¡£ä¸ºç¿»è¯‘ç‰ˆæœ¬ï¼Œè‹±æ–‡ [README](README.md) ä¸ºæƒå¨æ¥æºã€‚

**ä¸è¦å†å‘å¸ƒä¼šåœ¨çœŸå®žå®¢æˆ·ç«¯é‡Œå´©æºƒçš„ MCP æœåŠ¡å™¨ã€‚** è¿™ä¸ª Action ä¼šåœ¨ä¸€æ¬¡æ€§çš„ microVM ä¸­è¿è¡Œä½ çš„æœåŠ¡å™¨ï¼ŒæŒ‰ç…§ä»ŽçœŸå®ž Claude Code ä¸Ž Cursor æµé‡æ ¡å‡†å‡ºçš„å®¢æˆ·ç«¯è¡Œä¸ºé‡æ”¾ä¹ä¸ªåè®®æ­¥éª¤ï¼Œæ‰«ææºç ä¸­çš„å®‰å…¨é—®é¢˜ï¼Œå¹¶åœ¨åˆ¤å®šç»“æžœå›žé€€æ—¶è®©æž„å»ºå¤±è´¥ã€‚

æ¯ä¸€æ¬¡è¿è¡Œéƒ½ä¼šé“¾æŽ¥åˆ°ä¸€ä»½å…¬å¼€çš„è¯æ®è®°å½•ã€‚æ²¡æœ‰ç»è¿‡å®žé™…æ‰§è¡ŒéªŒè¯çš„ç»“è®ºï¼Œæˆ‘ä»¬ç»ä¸å£°ç§°ã€‚

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## ä¸ºä»€ä¹ˆ

æ¯ä¸ª MCP ç›®å½•éƒ½åªæ˜¯è‡ªæˆ‘ç”³æŠ¥çš„æ¡ç›®ï¼Œæ²¡æœ‰äººçœŸæ­£è¿è¡Œè¿‡è¿™äº›æœåŠ¡å™¨ã€‚Throne ä¼šè¿è¡Œï¼šæ¯æ¬¡æ‰«æéƒ½å¯åŠ¨ä¸€ä¸ªå…¨æ–°çš„ Firecracker microVMï¼Œä»Ž npmã€PyPI æˆ– GitHub å®‰è£…ï¼Œé€šè¿‡ stdio å¯åŠ¨ï¼Œè¿è¡Œç»“æŸåŽé”€æ¯ã€‚æœ€ç»ˆå¾—åˆ°ä¸€ä¸ªå¯ä»¥ç”¨æ¥å¡åˆå¹¶çš„åˆ¤å®šç»“æžœï¼Œè€Œä¸”ä»»ä½•äººéƒ½èƒ½æŸ¥é˜…èƒŒåŽçš„è¯æ®ã€‚

## å¿«é€Ÿå¼€å§‹

ä¸ºæ¯ä¸ª Pull Request è®¾å¡ï¼Œå¹¶æŠŠåˆ¤å®šç»“æžœä½œä¸ºè¯„è®ºå›žå¸–ï¼š

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # å…è®¸è¯¥ Action å‘å¸ƒåˆ¤å®šè¯„è®º

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # æˆ– "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

å¦‚æžœä¸éœ€è¦ PR è¯„è®ºï¼Œå¯åˆ é™¤ `permissions` å—ï¼Œæˆ–è®¾ç½® `comment-on-pr: false`ã€‚

## è¾“å…¥

| å‚æ•° | å¿…å¡« | é»˜è®¤å€¼ | å«ä¹‰ |
|---|---|---|---|
| `target` | æ˜¯ | | npm åŒ…ï¼ˆ`@scope/name` æˆ– `name`ï¼‰ã€`uvx <pypi-name>`ï¼Œæˆ– `https://github.com/owner/repo` |
| `api-key` | æ˜¯ | | ä½ çš„ Throne API å¯†é’¥ã€‚è¯·å­˜æ”¾åœ¨ä»“åº“ secrets ä¸­ |
| `fail-on` | å¦ | `not_fit` | è§¦å‘æž„å»ºå¤±è´¥çš„åˆ¤å®šï¼Œé€—å·åˆ†éš”ã€‚åŠ å…¥ `inconclusive` å³ä¸ºä¸¥æ ¼æ¨¡å¼ |
| `comment-on-pr` | å¦ | `true` | åœ¨ PR ä¸Šå‘å¸ƒå›ºå®šçš„åˆ¤å®šè¯„è®ºï¼ˆéœ€è¦ `pull-requests: write`ï¼‰ |
| `github-token` | å¦ | `${{ github.token }}` | ç”¨äºŽå‘å¸ƒ PR è¯„è®ºçš„ä»¤ç‰Œ |
| `api-base` | å¦ | `https://api.usethrone.dev` | ä»…åœ¨è‡ªæ‰˜ç®¡æˆ–æµ‹è¯•æ—¶æ‰éœ€è¦è¦†ç›– |
| `timeout-seconds` | å¦ | `600` | ç­‰å¾…æ‰«æçš„æœ€é•¿ç§’æ•° |

## è¾“å‡º

| è¾“å‡º | å«ä¹‰ |
|---|---|
| `verdict` | `fit`ã€`not_fit`ã€`inconclusive` æˆ– `unknown` |
| `reason` | å½“ inconclusive æ—¶ï¼š`needs_credentials`ã€`needs_arguments`ã€`needs_environment`ã€`unsupported_layout`ã€`install_timeout`ã€`no_handshake` æˆ– `launch_error` |
| `security-verdict` | `clean`ã€`review` æˆ– `not_run` |
| `scan-id` | æ”¯æ’‘è¯¥åˆ¤å®šçš„æ‰«æ ID |
| `record-url` | å…¬å¼€è¯æ®è®°å½•çš„é“¾æŽ¥ |
| `summary` | ä¸€è¡Œåˆ¤å®šæ‘˜è¦ |

## åˆ¤å®šç»“æžœçš„å«ä¹‰

- **fit** â€” åœ¨ä¸¤ä¸ªå®¢æˆ·ç«¯ç”»åƒä¸Šéƒ½å®Œå…¨å…¼å®¹åè®®ã€‚å¯ä»¥æ”¾å¿ƒå‘å¸ƒã€‚
- **not_fit** â€” çœŸå®žçš„åè®®å¤±è´¥ã€‚è¿™æ˜¯é»˜è®¤æƒ…å†µä¸‹å”¯ä¸€ä¼šå¡ä½åˆå¹¶çš„åˆ¤å®šã€‚
- **inconclusive** â€” æœåŠ¡å™¨è¿è¡Œäº†ï¼Œä½†æ— æ³•è¢«å®Œæ•´è¯„ä¼°ã€‚`reason` ä¼šè¯´æ˜ŽåŽŸå› ã€‚æœ€å¸¸è§çš„æ˜¯ `needs_credentials`ï¼šæœåŠ¡å™¨å®‰è£…å¹¶æ­£å¸¸å¯åŠ¨ï¼Œç„¶åŽå› ç¼ºå°‘ API å¯†é’¥è€Œé€€å‡ºã€‚è¿™é€šå¸¸æ²¡æœ‰é—®é¢˜ï¼Œå› æ­¤é™¤éžä½ æŠŠå®ƒåŠ å…¥ `fail-on`ï¼Œå¦åˆ™ `inconclusive` **ä¸ä¼š**å¡ä½åˆå¹¶ã€‚

å®‰å…¨å‘çŽ°å±žäºŽå¦ä¸€æ¡ç‹¬ç«‹çš„åˆ¤å®šè½´ã€‚`review` çš„å®‰å…¨åˆ¤å®šæ˜¯ç»™äººå®¡é˜…çš„ææ–™ï¼Œå®ƒä¸ä¼šæ”¹å˜å…¼å®¹æ€§åˆ¤å®šï¼Œä¹Ÿä¸ä¼šå•ç‹¬å¡ä½åˆå¹¶ã€‚

## ä¸¥æ ¼æ¨¡å¼

å¦‚æžœä½ ä¹Ÿå¸Œæœ›åœ¨æœåŠ¡å™¨æ— æ³•è¢«è¯„ä¼°æ—¶å¡ä½åˆå¹¶ï¼š

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## å¯å®¡è®¡æ€§

è¿™æ˜¯ä¸€ä¸ª composite actionï¼Œæ•´ä¸ªé—¨ç¦å°±æ˜¯ä¸€ä»½å¯è¯»çš„ shell è„šæœ¬ [`throne-gate.sh`](./throne-gate.sh)ï¼šæ²¡æœ‰ç¼–è¯‘åŽçš„äºŒè¿›åˆ¶æ–‡ä»¶ï¼Œæ²¡æœ‰æ‰“åŒ…çš„ JavaScriptï¼Œæ²¡æœ‰ä»»ä½•ä¼ é€’ä¾èµ–ã€‚å¯¹äºŽä¸€ä¸ªæ”¾è¿›å‘å¸ƒæµç¨‹çš„å·¥å…·ï¼Œä½ åº”è¯¥èƒ½è¯»æ‡‚å®ƒè¿è¡Œçš„æ¯ä¸€è¡Œã€‚è¿™é‡Œä½ å¯ä»¥ã€‚

## èŽ·å–å¯†é’¥

åˆ›å§‹å®¢æˆ·å¯†é’¥ä¸º `$29/æœˆ`ï¼Œä»·æ ¼é”å®š 12 ä¸ªæœˆã€‚è¯·å‘é‚®ä»¶è‡³ **hello@usethrone.dev**ï¼Œæˆ–æŸ¥çœ‹ [usethrone.dev/pricing](https://usethrone.dev/pricing)ã€‚

## ä½©æˆ´çŽ‹å† 

å¦‚æžœä½ çš„æœåŠ¡å™¨åˆ¤å®šä¸º `fit`ï¼Œå®ƒçš„è¯æ®è®°å½•ä¼šæä¾›ä¸€ä¸ªå®žæ—¶çš„ README å¾½ç« ï¼Œå¾½ç« ä¼šæ ¹æ®æœ€æ–°ä¸€æ¬¡æ‰«æè‡ªåŠ¨åˆ·æ–°ã€‚å¦‚æžœæŸæ¬¡å‘å¸ƒç ´åäº†åˆ¤å®šç»“æžœï¼Œå¾½ç« ä¼šè‡ªåŠ¨å¦‚å®žæ˜¾ç¤ºã€‚

## è®¸å¯è¯

MITã€‚è¯¦è§ [LICENSE](./LICENSE)ã€‚
