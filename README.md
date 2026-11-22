# HUBIplan-App für iPhone und iPad

**Die iOS-App zu [HUBIplan](https://github.com/hubiplan/hubiplan), der freien Vereinsverwaltung.**

Die App ist im Aufbau. Sie soll dasselbe können wie die
[Android-App](https://github.com/hubiplan/hubiplan-android): Termine mit Zu- und Absage,
Mitteilungen, Mitgliedsausweis, „Ich“ und die wichtigsten Verwaltungsaufgaben. Sie spricht nur
mit der HUBIplan-Instanz des eigenen Vereins, nie mit einem fremden Dienst.

> **English:** The iOS companion app for [HUBIplan](https://github.com/hubiplan/hubiplan),
> free membership management for clubs. Work in progress. It talks only to the member's own
> HUBIplan instance. The developer documentation is in German. Issues and security reports in
> English are welcome.

## Stand

| Stufe | Inhalt | Stand |
|---|---|---|
| I1 | Kern `HubiplanKern`: Schnittstelle, Verbinden, Formate, Push-Entschlüsselung | fertig |
| I2 | Oberfläche: Verbinden (QR-Code, E-Mail und Passwort, Passkey, Browser mit Prüfwert), Prüfung von Instanz und Mindestversion vor dem Verbinden, Termine mit Detail, Vielleicht, Begleitung und Bemerkung, Kennzeichen „nur Vorstand“, Anmeldung mit Teilnahmegebühr (Tarif, Zusatzleistungen und -fragen, Warteliste, Abmelden mit Gebührenvorschau, Ersatzperson) und Eintrittskarte mit QR-Code, Mitteilungen, mehrere Konten und Zugänge, Geräteschlüssel in der Secure Enclave, „Mein Konto“ mit Hilfe der Instanz, „Über die App“ mit Lizenzen und „Konto und Daten löschen“ | fertig |
| I3 | Push über Apple (APNs) als verschlüsseltes Wecksignal | in Arbeit (Kern: Anmelden und Entschlüsseln; App-Teil braucht das Apple-Entwicklerkonto) |
| I4 | „Ich“: Ausweis, Daten, Rechnungen, Versammlungen, Umfragen, Auslagen, Dokumente, Foto | weitgehend fertig (Ausweis mit QR-Code, auch ohne Netz, und als Wallet-Pass; eigene Daten, Rechnungen als PDF, Lastschriftmandat; Versammlungen mit Anträgen und Protokollen, live per QR-Code anmelden, online teilnehmen und abstimmen; Umfragen beantworten mit Ergebnis; Wettbewerbe mit Ergebnissen und Ranglisten; Auslagen mit Belegfoto melden; Beitragsnachweise einreichen; Training mit Einchecken per QR-Code, Anwesenheit, Schießbuch nach § 14 WaffG und Trainings leiten; Belegung anfragen, Kündigung, Meldungen, Abwesenheiten; Mitarbeiter für Ansprechpartner einer Firma; Dokumente) |
| I5 | Kalender, Aufgaben, Helferdienste, Noten | in Arbeit (Gerätekalender, Aufgaben, Helferdienste, Noten mit Notenmappen, Suche und Notenpult, das live der Vorgabe der Leitung folgt; noch ohne Ablage der Noten auf dem Gerät und Hörbeispiele) |
| I6 | Verwaltung | in Arbeit (Freischalten mit Passwort und Zwei-Faktor-Code oder Passkey, Vorstandsschlüssel im Schlüsselbund hinter Face ID, Touch ID oder Gerätecode, offene Punkte, Bereiche in der Reihenfolge des Hauptmenüs, Kurzmitteilung an die Mitglieder einer Einheit, Mitglieder zum Nachschlagen, Änderungsmeldungen und Fotos entscheiden mit „Rückgängig“, Ausweis prüfen, Stammdaten und Kontakt ändern, Geburtstage und Jubiläen, Termine mit Absagen, Rückmeldungen und „Neuer Termin“, Einlass mit Kamera, von Hand und Abendkasse, Kassenbuch mit Belegfoto und Quittung mit Unterschrift, Rechnungen mit „Bar kassiert“ und Quittung, Aufgaben verteilen, Geschäftspartner, Qualifikationen und Fristen zum Nachschlagen, Wettbewerbe mit Standmodus, Mitgliedsart und Untereinheit wechseln, Austritt und Wiedereintritt mit Vorschau der Folgen, Ehrungen, Zusatzfelder, Bankverbindung, Aufnahme neuer Mitglieder mit Dublettenprüfung, Beitrittsanträge prüfen, zustimmen, aufnehmen oder ablehnen, Belegungsanfragen freigeben, Versammlung leiten mit Anwesenheit, Einlass per Ausweis, QR-Code zur Anmeldung per App und Abstimmungen, Buchungen und unterschriebene Quittungen ohne Netz als verschlüsselter Entwurf, der bei Abmeldung durch den Server in eine Quarantäne geht statt verloren) |
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
- **Gestaltung „Frisch mobil“:** Werte (`Sources/HubiplanKern/Gestaltung/werte.json`) und
  Symbolsatz (`symbole.json`, Raster 24, Strich 1,75) sind dieselben Dateien wie in der
  Android-App; `GestaltungTests` hält ihre Prüfsummen fest und vergleicht die Werte im Code
  (`Design`, `Symbolsatz`). Wer einen Wert oder ein Symbol ändert, ändert die Datei in beiden
  Apps. Die Schrift Inter (SIL Open Font License 1.1, `App/HUBIplan/Schrift/`) liegt bei;
  `Font.hubi(.body)` liefert sie in den Stufen des Systems. Seiten setzen sich aus den
  Bausteinen in `App/HUBIplan/Bausteine.swift` zusammen (`Karte`, `Abschnittstitel`, `Zeile`,
  `Zaehler`, `Leerzustand`, `Platzhalter`, `SymbolBild`).
- **Reiter wie in der Android-App:** Start, Termine, Neues, Ich und ein fünfter je Rolle
  (Verwaltung, sonst Noten, sonst Aufgaben; `Zustand.fuenfterReiter`, wählbar unter „Mein Konto ›
  Einstellungen“). Was nicht in der Leiste steht, ist auf „Start“ unter „Schnell erreichbar“.
- **Einführung:** „Start“ zeigt nach dem Umbau einmal die Karte „So findest du dich zurecht“
  (`Einfuehrung.zeigt`; der Stand steht in den Einstellungen des Geräts, eine höhere Zahl zeigt
  sie allen noch einmal).
- **„Neues“** fasst Mitteilungen, Pinnwand und Umfragen zusammen (`Neues.teile`); **„Ich“** zeigt
  den Ausweis und „Mein Bereich“ in vier Gruppen: Geld, Mitmachen, Verein, Meine Daten
  (`IchGruppe.gruppen`). Unter „Mein Konto › Einstellungen“ lässt sich die Darstellung wählen: wie
  das Gerät, hell oder dunkel.
- **Verwaltung als Arbeitsplatz** (`VerwaltungStart.swift`): oben „Ausweis prüfen“ und „Neu“
  (Quittung, Buchung, Termin, Aufgabe je nach Rechten), darunter „Zu erledigen“ mit Zähler, die
  Kacheln und die Bereiche in den Gruppen des Hauptmenüs im Browser; die Suche schränkt ein.
- **Formulare schützen angefangene Eingaben:** Eingabeblätter mit `eingabeschutz` („Abbrechen“ fragt
  nach, Herunterwischen ruht), Formulare auf einer Seite melden mit `entwurf`, und die Seite fragt
  bei „Zurück“ nach (`zurueckSchutz`); `FormulareTests` prüft, dass keines fehlt.
- **„Für dich zu tun“ auf „Start“** kommt aus `portal/<Zugang>/start/` (`Start.swift`); ältere
  HUBIplan-Stände ohne diesen Abruf zeigen, was die App aus der Terminliste weiß. Die Terminliste
  ist nach Monaten gegliedert und lässt sich auf Termine ohne Rückmeldung einschränken.

## Bauen und testen

Voraussetzungen: Swift-Werkzeug ab 5.9 (Linux, WSL oder macOS; auch im offiziellen Docker-Abbild `swift`) und `testplatz` aus
[hubiplan](https://github.com/hubiplan/hubiplan/blob/main/docs/testserver.md).

```bash
scripts/test.sh
```

Die Oberfläche (`App/`) lässt sich nur unter macOS mit Xcode bauen. Das Xcode-Projekt wird mit
[XcodeGen](https://github.com/yonaskolb/XcodeGen) erzeugt und nicht eingecheckt:

```bash
xcodegen generate --spec App/project.yml
open App/HUBIplan.xcodeproj
```

Ohne Mac baut der Lauf „iOS bauen“ auf GitHub Actions die App für den Simulator. Er startet
nur von Hand (`workflow_dispatch`); automatische Auslöser gibt es nicht.

## Mitwirken

Fehlermeldungen, Ideen und Pull Requests sind willkommen: [CONTRIBUTING.md](CONTRIBUTING.md).
Bitte nur erfundene Daten in Code, Tests und Bildschirmfotos, und keine Analyse-, Werbe- oder
anderen Fremddienste.

## Sicherheit

Sicherheitslücken bitte **nicht** als öffentliches Issue melden, sondern vertraulich über
[GitHub](https://github.com/hubiplan/hubiplan-ios/security/advisories/new). Einzelheiten:
[SECURITY.md](SECURITY.md).

## Lizenz

Copyright © 2026 Ralf Philipsen (Philipsen EDV)

Die HUBIplan-App ist freie Software: Sie dürfen sie unter den Bedingungen der **GNU Affero
General Public License**, wie von der Free Software Foundation veröffentlicht, weitergeben
und/oder ändern, entweder gemäß Version 3 der Lizenz oder (nach Ihrer Wahl) jeder späteren
Version (`AGPL-3.0-or-later`), wie HUBIplan selbst.

Die App wird in der Hoffnung verbreitet, dass sie nützlich ist, aber **ohne jede
Gewährleistung**, sogar ohne die implizite Gewährleistung der Marktreife oder der Eignung
für einen bestimmten Zweck. Einzelheiten stehen in der Lizenz. Den vollständigen
Lizenztext (englisch, maßgeblich) enthält die Datei [LICENSE](LICENSE).

Einzige Abhängigkeit ist [swift-crypto](https://github.com/apple/swift-crypto) (Apache-2.0),
und nur unter Linux.
