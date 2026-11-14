# Hinweise für die Arbeit an hubiplan-ios

Projektregeln (gelten wie im Hauptprojekt `hubiplan`):

- **Kern lokal bauen und testen**, mit `scripts/test.sh` (Swift-Paket `HubiplanKern`, läuft
  unter Linux/WSL und macOS). Auf gemeinsam genutzten Test- oder Produktivservern keine Tests.
- **Tests nur über `scripts/test.sh`**: Es holt sich einen lokalen Testplatz mit `testplatz`
  (aus `hubiplan/scripts/testplatz.sh`, siehe `hubiplan/docs/testserver.md`).
- **Oberfläche (SwiftUI) braucht macOS.** Ohne Mac läuft dafür ein macOS-Lauf auf GitHub
  Actions, **nur von Hand** (`workflow_dispatch`), ohne automatische Auslöser und sparsam.
  Alles, was ohne Oberfläche prüfbar ist, gehört in den Kern.
- Ohne erfolgreichen Lauf keine erfolgreichen Builds oder Tests behaupten; stattdessen die
  tatsächlich durchgeführten Prüfungen nennen.
- Temporäre Dateien im lokal konfigurierten Temp-Verzeichnis ablegen.
- Keine Passwörter, Signaturschlüssel, Zertifikate, APNs-Schlüssel oder Geheimnisse ins Repo
  oder in Chats.
- Keine internen Chat- oder Sitzungslinks, privaten Konzeptpfade, nicht öffentlichen Hostnamen
  oder realen Betriebsdaten in Dateien, Commit-Nachrichten oder Pull Requests.
- Nur erfundene Daten in Tests und Beispielen.
- Sprache in Oberfläche, Doku und Commits: Deutsch. **Neue Texte in der App gleich auch auf
  Englisch.**
- **Jeder PR füllt „Für die Änderungshinweise“** der PR-Vorlage aus (Deutsch und Englisch).
  Versionen und Tags nur nach ausdrücklicher Freigabe durch den Herausgeber.
- Die App spricht nur mit der HUBIplan-Instanz des Mitglieds (`/api/app/v1/`, `/api/portal/…`),
  Beschreibung in `hubiplan/docs/app.md`. Keine Analyse-, Werbe- oder anderen Fremddienste;
  Push nur als verschlüsseltes Wecksignal über Apple (APNs).
- Verhalten und Formate folgen der Android-App (`hubiplan-android`); gleiche Fälle bekommen
  gleiche Tests.
- Neue Abhängigkeiten müssen mit der AGPL-3.0 verträglich sein und sparsam bleiben.
