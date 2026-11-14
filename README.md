# HUBIplan-App für iPhone und iPad

**Die iOS-App zu [HUBIplan](https://github.com/hubiplan/hubiplan), der freien Vereinsverwaltung.**

Die App ist im Aufbau. Sie soll dasselbe können wie die
[Android-App](https://github.com/hubiplan/hubiplan-android): Termine mit Zu- und Absage,
Mitteilungen, Mitgliedsausweis, „Ich“ und die wichtigsten Verwaltungsaufgaben. Sie spricht nur
mit der HUBIplan-Instanz des eigenen Vereins, nie mit einem fremden Dienst.

> **English:** The iOS companion app for [HUBIplan](https://github.com/hubiplan/hubiplan),
> free membership management for clubs. Work in progress. It talks only to the member's own
> HUBIplan instance. The developer documentation is in German.

## Stand

| Stufe | Inhalt | Stand |
|---|---|---|
| I1 | Kern `HubiplanKern`: Schnittstelle, Verbinden, Formate, Push-Entschlüsselung | in Arbeit |
| I2 | Oberfläche: Verbinden, Termine, Mitteilungen, mehrere Konten | offen |
| I3 | Push über Apple (APNs) als verschlüsseltes Wecksignal | offen |
| I4 | „Ich“: Ausweis, Daten, Rechnungen, Versammlungen, Foto | offen |
| I5 | Kalender, Aufgaben, Helferdienste, Noten | offen |
| I6 | Verwaltung | offen |
| I7 | TestFlight und App Store | offen |

## Technik

- Swift und SwiftUI, ab iOS 17, für iPhone und iPad, Deutsch und Englisch.
- **`HubiplanKern`** (Swift-Paket in diesem Repo) enthält alles ohne Oberfläche: die
  Schnittstelle zu HUBIplan (`/api/app/v1/`, beschrieben in
  [docs/app.md](https://github.com/hubiplan/hubiplan/blob/main/docs/app.md)), das Verbinden per
  QR-Code, die unterschriebenen Formate und das Entschlüsseln von Web-Push (RFC 8291). Der Kern
  baut auch unter Linux; dort ersetzt [swift-crypto](https://github.com/apple/swift-crypto)
  (Apache-2.0) das CryptoKit von Apple.
- Formate und Verhalten folgen der Android-App; gleiche Fälle haben gleiche Tests.

## Bauen und testen

Voraussetzungen: Swift-Werkzeug ab 5.9 (Linux, WSL oder macOS; auch im offiziellen Docker-Abbild `swift`) und `testplatz` aus
[hubiplan](https://github.com/hubiplan/hubiplan/blob/main/docs/testserver.md).

```bash
scripts/test.sh
```

Die Oberfläche lässt sich nur unter macOS mit Xcode bauen. Es gibt keine automatische CI.

## Sicherheit

Sicherheitslücken bitte nicht öffentlich melden, sondern vertraulich über
**Security › Report a vulnerability** in diesem Repository.

## Lizenz

Copyright © 2026 Ralf Philipsen (Philipsen EDV)

[AGPL-3.0-or-later](LICENSE), wie HUBIplan.
