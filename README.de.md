# Throne MCP Gate

[English](README.md) · [简体中文](README.zh-CN.md) · [Русский](README.ru.md) · [हिन्दी](README.hi.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · **Deutsch**

[![Throne MCP Gate im GitHub Marketplace](https://img.shields.io/badge/Marketplace-Throne%20MCP%20Gate-1F9D55?logo=github&logoColor=white)](https://github.com/marketplace/actions/throne-mcp-gate)
[![test](https://github.com/usethrone/throne-ci/actions/workflows/test.yml/badge.svg)](https://github.com/usethrone/throne-ci/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0E0E10.svg)](LICENSE)

<p align="center">
  <a href="https://usethrone.dev"><img src="assets/hero.png" alt="Throne: MCP-Server einfügen, Urteil erhalten" width="840"></a>
</p>

**Hören Sie auf, MCP-Server auszuliefern, die bei echten Clients kaputtgehen.** Diese Action führt Ihren Server in einer wegwerfbaren microVM aus, spielt neun Protokollschritte gegen Client-Verhalten ab, das aus aufgezeichnetem Claude-Code- und Cursor-Traffic kalibriert wurde, prüft den Quellcode auf Sicherheitsprobleme und lässt den Build fehlschlagen, wenn das Urteil sich verschlechtert.

Jeder Lauf verweist auf einen öffentlichen Nachweis-Datensatz. Nichts wird behauptet ohne die Ausführung, die es bewiesen hat.

```yaml
- uses: usethrone/throne-ci@v1
  with:
    target: "@your-scope/your-mcp-server"
    api-key: ${{ secrets.THRONE_API_KEY }}
```

## Warum

Jedes MCP-Verzeichnis listet selbst gemeldete Einträge. Niemand führt die Server aus. Throne schon: eine frische Firecracker-microVM pro Scan, installiert aus npm, PyPI oder GitHub, über stdio gestartet und danach wieder abgebaut. Das Ergebnis ist ein Urteil, auf dessen Basis Sie einen Merge blockieren können, gestützt durch Belege, die jeder lesen kann.

## Schnellstart

Jeden Pull Request prüfen und das Urteil als Kommentar posten:

```yaml
name: throne-gate
on:
  pull_request:

permissions:
  contents: read
  pull-requests: write   # erlaubt der Action, den Urteils-Kommentar zu posten

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: usethrone/throne-ci@v1
        with:
          target: "@your-scope/your-mcp-server"   # oder "uvx your-package" / https://github.com/you/repo
          api-key: ${{ secrets.THRONE_API_KEY }}
```

Lassen Sie den `permissions`-Block weg, wenn Sie keine PR-Kommentare möchten, oder setzen Sie `comment-on-pr: false`.

## Eingaben

| Eingabe | erforderlich | Standard | Bedeutung |
|---|---|---|---|
| `target` | ja | | npm-Paket (`@scope/name` oder `name`), `uvx <pypi-name>` oder `https://github.com/owner/repo` |
| `api-key` | ja | | Ihr Throne-API-Schlüssel. Im Repository-Secret aufbewahren |
| `fail-on` | nein | `not_fit` | kommagetrennte Urteile, die den Merge blockieren. `inconclusive` für den strengen Modus hinzufügen |
| `fail-on-security` | nein | `off` | den Sicherheitsscan ebenfalls blockieren lassen: `review` blockiert bei jedem Befund, `high` nur bei einem mit hohem Schweregrad, `off` blockiert nie |
| `comment-on-pr` | nein | `true` | einen fixierten Urteils-Kommentar am PR posten (benötigt `pull-requests: write`) |
| `github-token` | nein | `${{ github.token }}` | Token für den PR-Kommentar |
| `api-base` | nein | `https://api.usethrone.dev` | nur für Self-Hosting oder Tests überschreiben |
| `timeout-seconds` | nein | `600` | nach dieser Zeit das Warten auf den Scan aufgeben |

## Ausgaben

| Ausgabe | Bedeutung |
|---|---|
| `verdict` | `fit`, `not_fit`, `inconclusive` oder `unknown` |
| `reason` | bei inconclusive: `needs_credentials`, `needs_arguments`, `needs_environment`, `unsupported_layout`, `install_timeout`, `no_handshake` oder `launch_error` |
| `security-verdict` | `clean`, `review` oder `not_run` |
| `security-findings` | Gesamtzahl der Sicherheitsbefunde (`0`, wenn sauber oder nicht ausgeführt) |
| `security-high` | Anzahl der Sicherheitsbefunde mit hohem Schweregrad |
| `scan-id` | der Scan, der dieses Urteil stützt |
| `record-url` | öffentlicher Nachweis-Datensatz |
| `summary` | einzeilige Urteilszusammenfassung |

Die Ausgaben bleiben auch dann definiert, wenn das Gate fehlschlägt: Schlägt der Scan fehl, läuft er in den Timeout oder wird er abgelehnt, sieht ein Schritt, der sie unter `if: always()` liest, `verdict: unknown`, `security-verdict: not_run` und `security-findings: 0` statt leerer Zeichenketten.

```yaml
      - uses: usethrone/throne-ci@v1
        id: throne
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
      - run: echo "Verdict was ${{ steps.throne.outputs.verdict }} — ${{ steps.throne.outputs.record-url }}"
```

## Was das Urteil bedeutet

- **fit** — vollständige Protokollkompatibilität auf beiden Client-Profilen. Sicher auszuliefern.
- **not_fit** — ein echtes Protokollversagen. Das einzige Urteil, das standardmäßig blockiert.
- **inconclusive** — der Server lief, konnte aber nicht vollständig beurteilt werden. `reason` nennt den Grund. Am häufigsten ist `needs_credentials`: Der Server installiert und startet sauber und beendet sich dann mit der Bitte um einen API-Schlüssel. Das ist meist in Ordnung, daher blockiert `inconclusive` **nicht**, sofern Sie es nicht zu `fail-on` hinzufügen.

Sicherheitsbefunde sind eine eigene Achse. Ein `review`-Sicherheitsurteil ist Material, das ein Mensch lesen sollte; es ändert das Kompatibilitätsurteil standardmäßig nie und blockiert keinen Merge. Wenn es etwas zu prüfen gibt, weist die Action stets in einer Warn-Annotation darauf hin und listet die Befunde nach Schweregrad in der Job-Zusammenfassung auf — das Blockieren aktivieren Sie mit `fail-on-security` (siehe unten).

## Strenger Modus

Um auch zu blockieren, wenn der Server nicht beurteilt werden konnte:

```yaml
        with:
          target: "@your-scope/your-mcp-server"
          api-key: ${{ secrets.THRONE_API_KEY }}
          fail-on: "not_fit,inconclusive"
```

## Nachvollziehbarkeit

Dies ist eine Composite Action. Das gesamte Gate ist ein einziges, lesbares Shell-Skript, [`throne-gate.sh`](./throne-gate.sh): keine kompilierte Binärdatei, kein gebündeltes JavaScript, keine transitiven Abhängigkeiten. Bei einem Werkzeug, das Sie in Ihren Release-Pfad stellen, sollten Sie jede Zeile lesen können, die es ausführt. Das können Sie.

## Einen Schlüssel erhalten

Throne nimmt eine kleine Gruppe von Founding Design Partnern auf. Fordern Sie einen Schlüssel unter **hello@usethrone.dev** an oder bewerben Sie sich auf [usethrone.dev/pricing](https://usethrone.dev/pricing). Der kostenlose Scan auf [usethrone.dev](https://usethrone.dev) benötigt keinen Schlüssel.

## Die Krone tragen

Wenn Ihr Server `fit` ist, bietet sein Nachweis-Datensatz ein Live-README-Badge, das sich aus dem neuesten Scan neu rendert. Sollte ein Release das Urteil je verschlechtern, sagt das Badge es von selbst.

## Lizenz

MIT. Siehe [LICENSE](./LICENSE).
