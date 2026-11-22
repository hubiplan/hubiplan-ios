# Sicherheit

Die HUBIplan-App für iPhone und iPad greift auf Mitgliederdaten, Bankverbindungen und die Kasse eines Vereins
zu und speichert Teile davon auf dem Gerät. Hinweise auf Sicherheitslücken nehmen wir
deshalb sehr ernst und sind für jede Meldung dankbar.

*Reports in English are welcome; see the [English summary](#english-summary) at the end.*

## Lücke melden

Bitte **kein öffentliches Issue**, sondern vertraulich über GitHub:
[Report a vulnerability](https://github.com/hubiplan/hubiplan-ios/security/advisories/new)
(im Repository unter **Security › Report a vulnerability**).

Hilfreich sind:

- betroffene Fassung (Version oder Commit), iOS-Version und betroffener Teil (z. B. Bildschirm,
  Speicher, Push),
- Schritte zum Nachvollziehen, am besten gegen ein eigenes HUBIplan mit Demodaten
  (`seed_testdata`),
- eingeschätzte Auswirkung: Wer kann was sehen oder ändern, was er nicht dürfte?

## Was dann passiert

- Wir bestätigen den Eingang in der Regel innerhalb von 7 Tagen.
- Wir prüfen die Meldung, halten dich auf dem Laufenden und stimmen eine Korrektur mit dir ab.
- Die Korrektur erscheint zuerst; Einzelheiten veröffentlichen wir danach als
  Sicherheitshinweis (GitHub Security Advisory), auf Wunsch mit Nennung deines Namens.
- Bitte gib uns bis zur Korrektur, höchstens 90 Tage ab Meldung, Zeit, bevor du Einzelheiten
  veröffentlichst.

## Unterstützte Fassungen

Die App ist im Aufbau und noch nicht im App Store. Korrekturen gibt es für den aktuellen Stand
von `main`, später auch für die jeweils neueste veröffentlichte Version; es gibt keine
Release-Zweige.

## Umfang

Gemeint ist der Code in diesem Repository: der Kern `HubiplanKern` und die Oberfläche.
Besonders interessant sind:

- Zugriff anderer Apps auf Daten, Geräteschlüssel oder Entwürfe der App,
- Daten, die unverschlüsselt oder außerhalb des Schlüsselbunds liegen (Geräteschlüssel,
  Vorstandsschlüssel, Mitgliedsausweis, Kassenentwürfe, Belegfotos),
- Umgehung der Sperre der Verwaltung (Face ID, Touch ID, Gerätecode, Sperre nach Pause),
- Schwächen bei Verbinden per QR-Code, Push-Entschlüsselung oder Zertifikatsprüfung,
- Verbindungen zu anderen Diensten als der HUBIplan-Instanz (außer dem Wecksignal über Apple),
- Push-Inhalte, die Apple oder das Push-Gateway im Klartext sehen,
- Daten eines Kontos, die in einem anderen verbundenen Konto oder nach dem Abmelden noch
  lesbar sind (z. B. zwischengespeicherte PDFs, Belege, Noten, Kalendereinträge),
- Push-Hinweise oder Links, die ein fremdes Konto oder einen fremden Mitgliedszugang öffnen
  oder Aktionen ohne Freischaltung auslösen,
- ein Standmodus, der mit dem Standzugang mehr als den eigenen Wettbewerb erreicht,
- Pinnwand-Beiträge mit Fotos, Umfragen, Bestellungen oder das Schießbuch, die nach dem
  Abmelden oder Kontowechsel noch auf dem Gerät lesbar sind,
- geöffnete Kalenderdateien (`.ics`) oder andere Apps, die über die App ohne Bestätigung Termine
  anlegen oder Aktionen auslösen,
- Anmelden an einer Versammlung, Einchecken zu einem Training oder Abstimmen für ein anderes
  Mitglied.

Liegt der Fehler in der Schnittstelle von HUBIplan, bitte
[dort melden](https://github.com/hubiplan/hubiplan/security/advisories/new); Lücken der Android-App in
[hubiplan-android](https://github.com/hubiplan/hubiplan-android/security/advisories/new).

Nicht gemeint sind Lücken in Fremdsoftware (bitte dort melden), reine Last- oder
Überlastungsangriffe, Social Engineering sowie Befunde ohne Auswirkung (z. B. Befunde, die ein
entsperrtes Gerät mit Jailbreak voraussetzen).

## Regeln fürs Prüfen

- Prüfe **nur gegen eine eigene HUBIplan-Installation** mit erfundenen Daten, z. B. mit
  `docker compose up` und `seed_testdata` (siehe
  [hubiplan](https://github.com/hubiplan/hubiplan#ausprobieren-mit-docker)).
- Keine Angriffe auf fremde HUBIplan-Instanzen oder echte Vereinsdaten, keine
  Überlastungsangriffe.
- Stößt du doch auf echte personenbezogene Daten, greife nicht weiter darauf zu, speichere
  nichts und melde es uns.

Wer sich an diese Regeln hält und in gutem Glauben handelt, hat von uns keine rechtlichen
Schritte zu erwarten.

## English summary

Please do **not** open a public issue. Report vulnerabilities privately via
[GitHub private vulnerability reporting](https://github.com/hubiplan/hubiplan-ios/security/advisories/new).
Bugs in the HUBIplan server API belong to
[HUBIplan](https://github.com/hubiplan/hubiplan/security/advisories/new). We usually
acknowledge reports within 7 days and ask you to keep details private until a fix is
available, for at most 90 days. The app is work in progress and not yet on the App Store; fixes go into `main`. There
are no release branches. Test only against your own HUBIplan installation with made-up data,
never against other people's instances or real member data. Good-faith research that follows
these rules will not face legal action from us.
