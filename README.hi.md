# Throne MCP Gate

[English](README.md) · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · **हिन्दी** · [日本語](README.ja.md) · [한국어](README.ko.md) · [Deutsch](README.de.md)

[![GitHub Marketplace पर Throne MCP Gate](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throne: एक MCP सर्वर पेस्ट करें, फ़ैसला पाएँ" width="840"></a>
</p>

> यह एक अनुवाद है। आधिकारिक स्रोत अंग्रेज़ी [README](README.md) है।

**ऐसे MCP सर्वर भेजना बंद करें जो असली क्लाइंट पर टूट जाते हैं।** यह Action आपके सर्वर को एक डिस्पोज़ेबल microVM में चलाता है, असली Claude Code और Cursor ट्रैफ़िक से कैलिब्रेट किए गए क्लाइंट व्यवहार के विरुद्ध नौ प्रोटोकॉल चरण दोहराता है, सोर्स में सुरक्षा समस्याओं को स्कैन करता है, और जब फ़ैसला बिगड़ता है तो बिल्ड को फ़ेल कर देता है।

हर रन एक सार्वजनिक प्रमाण रिकॉर्ड से लिंक होता है। जिस रन ने साबित न किया हो, उसके बिना कुछ भी दावा नहीं किया जाता।

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## क्यों

हर MCP डायरेक्टरी सिर्फ़ स्वयं-घोषित प्रविष्टियों की सूची है। कोई भी सर्वरों को असल में नहीं चलाता। Throne चलाता है: हर स्कैन पर एक नई Firecracker microVM, npm, PyPI या GitHub से इंस्टॉल, stdio पर लॉन्च, और बाद में नष्ट। नतीजा एक ऐसा फ़ैसला है जिस पर आप merge रोक सकते हैं, और जिसका प्रमाण कोई भी पढ़ सकता है।

## क्विकस्टार्ट

हर pull request पर जाँच लगाएँ, और फ़ैसले को कमेंट के रूप में वापस पोस्ट करें:

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # Action को फ़ैसले का कमेंट पोस्ट करने देता है

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # या "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

अगर आप PR कमेंट नहीं चाहते तो `permissions` ब्लॉक हटा दें, या `comment-on-pr: false` सेट करें।

## इनपुट

| इनपुट | ज़रूरी | डिफ़ॉल्ट | अर्थ |
|---|---|---|---|
| `target` | हाँ | | npm पैकेज (`@scope/name` या `name`), `uvx <pypi-name>`, या `https://github.com/owner/repo` |
| `api-key` | हाँ | | आपकी Throne API key। इसे repo secrets में रखें |
| `fail-on` | नहीं | `not_fit` | वे फ़ैसले जो merge रोकते हैं, कॉमा से अलग। सख़्त मोड के लिए `inconclusive` जोड़ें |
| `fail-on-security` | नहीं | `off` | सुरक्षा स्कैन को भी रोकने दें: `review` किसी भी निष्कर्ष पर रोकता है, `high` केवल उच्च-गंभीरता वाले पर, `off` कभी नहीं रोकता |
| `comment-on-pr` | नहीं | `true` | PR पर फ़ैसले का स्थायी कमेंट पोस्ट करें (`pull-requests: write` चाहिए) |
| `github-token` | नहीं | `${{ github.token }}` | PR कमेंट के लिए इस्तेमाल होने वाला टोकन |
| `api-base` | नहीं | `https://api.usethrone.dev` | केवल self-hosted या टेस्टिंग के लिए बदलें |
| `timeout-seconds` | नहीं | `600` | स्कैन के लिए कितने सेकंड तक प्रतीक्षा करें |

## आउटपुट

| आउटपुट | अर्थ |
|---|---|
| `verdict` | `fit`, `not_fit`, `inconclusive`, या `unknown` |
| `reason` | inconclusive होने पर: `needs_credentials`, `needs_arguments`, `needs_environment`, `unsupported_layout`, `install_timeout`, `no_handshake`, या `launch_error` |
| `security-verdict` | `clean`, `review`, या `not_run` |
| `security-findings` | सुरक्षा निष्कर्षों की कुल संख्या (`0` जब साफ़ हो या न चला हो) |
| `security-high` | उच्च-गंभीरता वाले सुरक्षा निष्कर्षों की संख्या |
| `scan-id` | वह स्कैन जिस पर यह फ़ैसला आधारित है |
| `record-url` | सार्वजनिक प्रमाण रिकॉर्ड |
| `summary` | एक पंक्ति में फ़ैसले का सार |

गेट फेल होने पर भी आउटपुट परिभाषित रहते हैं: यदि स्कैन में त्रुटि हो, टाइमआउट हो या वह अस्वीकार हो जाए, तो `if: always()` के तहत उन्हें पढ़ने वाले स्टेप को खाली स्ट्रिंग की बजाय `verdict: unknown`, `security-verdict: not_run` और `security-findings: 0` मिलता है।

## फ़ैसले का मतलब

- **fit** — दोनों क्लाइंट प्रोफ़ाइल पर पूरी प्रोटोकॉल संगतता। भेजने के लिए सुरक्षित।
- **not_fit** — असली प्रोटोकॉल विफलता। डिफ़ॉल्ट रूप से सिर्फ़ यही फ़ैसला merge रोकता है।
- **inconclusive** — सर्वर चला, पर पूरी तरह आँका नहीं जा सका। `reason` कारण बताता है। सबसे आम है `needs_credentials`: सर्वर ठीक से इंस्टॉल और लॉन्च होता है, फिर API key माँगते हुए बाहर निकल जाता है। यह आमतौर पर ठीक है, इसलिए जब तक आप इसे `fail-on` में न जोड़ें, `inconclusive` merge को **नहीं** रोकता।

सुरक्षा निष्कर्ष एक अलग धुरी हैं। `review` सुरक्षा फ़ैसला इंसान के पढ़ने की सामग्री है; यह संगतता फ़ैसले को कभी नहीं बदलता और अकेले merge नहीं रोकता।

## सख़्त मोड

जब सर्वर का आकलन न हो सके, तब भी रोकने के लिए:

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## ऑडिट-योग्यता

यह एक composite action है। पूरा गेट एक पठनीय shell स्क्रिप्ट [`throne-gate.sh`](./throne-gate.sh) है: कोई कंपाइल्ड बाइनरी नहीं, कोई बंडल किया हुआ JavaScript नहीं, कोई ट्रांज़िटिव डिपेंडेंसी नहीं। जिस टूल को आप अपने रिलीज़ पथ में रखते हैं, उसकी हर चलने वाली पंक्ति आपको पढ़ पाना चाहिए। यहाँ आप पढ़ सकते हैं।

## key कैसे पाएँ

Throne कुछ चुनिंदा फ़ाउंडिंग डिज़ाइन पार्टनर्स को शामिल कर रहा है। **hello@usethrone.dev** पर key का अनुरोध करें या [usethrone.dev/pricing](https://usethrone.dev/pricing) पर आवेदन करें। [usethrone.dev](https://usethrone.dev) पर मुफ़्त स्कैन के लिए किसी key की ज़रूरत नहीं है।

## ताज पहनें

अगर आपका सर्वर `fit` है, तो उसका प्रमाण रिकॉर्ड एक लाइव README बैज देता है जो नवीनतम स्कैन से फिर से रेंडर होता है। अगर कोई रिलीज़ कभी फ़ैसला तोड़ती है, तो बैज ख़ुद ही यह बता देगा।

## लाइसेंस

MIT। देखें [LICENSE](./LICENSE)।
