# SAP CX Radar

iPhone-App (SwiftUI, iOS 18+), die aktuelle News, Releases und Roadmap-Beiträge zu
**SAP Sales Cloud V2**, **SAP Service Cloud V2** und **SAP Field Service Management** sammelt.

## Funktionen
- **News:** Beiträge aus der SAP Community (CX-Blogs + gezielte Suchen) und dem SAP News Center,
  automatisch den Produkten zugeordnet, mit Filter, Suche und Gelesen-Status
- **Roadmap:**
  - *Explorer:* der SAP Roadmap Explorer direkt in der App. Anmeldung mit SAP-ID auf SAPs eigener
    Login-Seite; die Sitzung bleibt gespeichert (die App selbst speichert keine Zugangsdaten).
    Roadmap-Seiten lassen sich als Favorit für Sales V2, Service V2 und FSM speichern.
  - *Beiträge:* nur Release-Highlights, Pre-Release-Briefings, Roadmap-Beiträge
- **Merkliste:** Beiträge per Wisch merken
- **Links:** Roadmap Explorer, What's New Viewer, Produkt-Dokumentation
- **Suche:** globale Suche über alle News, Merkliste und Links, plus Live-Suche in der gesamten SAP Community

## Aufbau
| Datei | Inhalt |
|---|---|
| `FeedSources.swift` | RSS-Quellen und Links |
| `RSSParser.swift` | RSS-Parser, HTML→Text |
| `Classifier.swift` | Produkt- und Release/Roadmap-Erkennung |
| `NewsStore.swift` | Laden, Deduplizieren, Filtern, Speichern |
| `NewsListView.swift`, `OtherViews.swift` | Oberfläche |
| `RoadmapExplorerView.swift` | Roadmap-Tab: SAP Roadmap Explorer (WKWebView mit SAP-Login) |
| `SearchView.swift` | Globale Suche |

## Bauen
`SAPCXRadar.xcodeproj` in Xcode öffnen und starten, oder:

```bash
xcodebuild -project SAPCXRadar.xcodeproj -scheme SAPCXRadar -sdk iphonesimulator build
```
