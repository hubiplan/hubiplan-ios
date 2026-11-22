import HubiplanKern
import SwiftUI

/// Reiter der Leiste: Beschriftung und Symbol aus dem gemeinsamen Symbolsatz beider Apps.
enum Reiter {
    /// Eigene Wahl für den fünften Reiter (Name des Reiters); leer = Vorgabe je Rolle
    static let wahlSchluessel = "fuenfterReiter"

    static func titel(_ reiter: String) -> String {
        switch reiter {
        case "start": return tr("Start")
        case "termine": return tr("Termine")
        case "mitteilungen": return tr("Neues")
        case "ausweis": return tr("Ich")
        case "verwaltung": return tr("Verwaltung")
        case "noten": return tr("Noten")
        case "aufgaben": return tr("Aufgaben")
        default: return reiter
        }
    }

    static func symbol(_ reiter: String) -> Strichsymbol {
        switch reiter {
        case "start": return .start
        case "termine": return .termine
        case "mitteilungen": return .neues
        case "ausweis": return .ich
        case "verwaltung": return .verwaltung
        case "noten": return .noten
        case "aufgaben": return .aufgaben
        default: return .info
        }
    }

    /// Marke eines Reiters in der Leiste; „Verwaltung“ heißt dort kurz „Verwalten“ wie auf Android.
    static func marke(_ reiter: String) -> some View {
        Label {
            Text(reiter == "verwaltung" ? tr("Verwalten") : titel(reiter))
        } icon: {
            Image(uiImage: SymbolZeichner.bild(symbol(reiter)))
        }
    }
}

extension AppModel {
    /// Bereiche dieses Kontos für den fünften Reiter, in der Reihenfolge der Vorgabe.
    var fuenfteReiter: [String] {
        Zustand.fuenfteReiter(
            verwaltung: !(adminOverview?.allUnits.isEmpty ?? true),
            noten: accesses.contains { $0.hasScores },
            aufgaben: accesses.contains { $0.hasTodos || $0.hasHelpers }
        )
    }
}

/// „Mein Konto › Einstellungen“: welcher Bereich unten in der Leiste steht.
struct FuenfterReiterWahl: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Reiter.wahlSchluessel) private var wahl = ""

    var body: some View {
        Section {
            Picker(tr("Fünfter Reiter"), selection: Binding(
                get: { Zustand.fuenfterReiter(model.fuenfteReiter, wahl: wahl) ?? "" },
                set: { wahl = $0 }
            )) {
                ForEach(model.fuenfteReiter, id: \.self) { reiter in
                    Text(Reiter.titel(reiter)).tag(reiter)
                }
            }
        } footer: {
            Text(tr("Welcher Bereich unten in der Leiste steht. Die anderen erreichst du über „Start“."))
        }
    }
}

/// Reiter „Start“ (Gestaltung „Frisch mobil“): der nächste Termin mit Zusage und Absage, was
/// gerade auf dich wartet, die Kacheln der Startseite und kurze Wege zu den Bereichen, die nicht
/// in der Leiste stehen.
struct StartView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var tab: String
    /// Bereiche, die auf diesem Gerät nicht in der Leiste stehen
    let weitere: [String]
    @State private var path: [String] = []
    @State private var blatt: Blatt?

    private struct Blatt: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.offlineSince != nil {
                    OfflineStand()
                } else if let message = model.error {
                    Section {
                        MeldungText(message, .fehler)
                        Button(tr("Erneut versuchen")) { Task { await model.refresh() } }
                    }
                }
                let naechster = Startseite.naechsterTermin(model.events)
                Section {
                    if model.accesses.isEmpty && !model.loading && model.error == nil {
                        Text(tr("Du hast noch keinen Zugang zum Mitgliederbereich. Bitte wende dich an deinen Verein."))
                            .foregroundStyle(.secondary)
                    } else if let naechster {
                        TerminZeile(event: naechster)
                    } else if model.loading {
                        Platzhalter(zeilen: 1)
                    } else {
                        Text(tr("Keine Termine in den nächsten Monaten.")).foregroundStyle(.secondary)
                    }
                    Button(tr("Alle Termine")) { tab = "termine" }
                } header: {
                    Text(tr("Nächster Termin"))
                }
                let zeilen = Startseite.zeilen(server: model.startTodo, termine: model.events, ohne: naechster)
                let ungelesen = model.unreadCirculars.count
                if !zeilen.isEmpty || ungelesen > 0 {
                    Section {
                        ForEach(zeilen) { zeile in
                            if zeile.target == "events" {
                                StartZeile(titel: zeile.title, symbol: Startseite.symbol(zeile.target), anzahl: zeile.count) {
                                    tab = "termine"
                                }
                            } else {
                                NavigationLink {
                                    StartBereich(target: zeile.target)
                                } label: {
                                    StartMarke(titel: zeile.title, symbol: Startseite.symbol(zeile.target), anzahl: zeile.count)
                                }
                            }
                        }
                        if ungelesen > 0 {
                            StartZeile(
                                titel: trn("{n} neue Mitteilung", "{n} neue Mitteilungen", ungelesen),
                                symbol: .mitteilung, anzahl: ungelesen
                            ) { tab = "mitteilungen" }
                        }
                    } header: {
                        Text(tr("Für dich zu tun"))
                    }
                }
                // Kacheln wie auf der Startseite im Browser: mit Anlass von selbst
                if let access = model.access {
                    KachelnUebersicht(
                        reloadKey: "p\(access.id)",
                        load: { await model.memberTiles() },
                        save: { await model.setMemberTile($0, $1) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    StartZeile(titel: tr("Ausweis zeigen"), symbol: .ausweis) { tab = "ausweis" }
                    ForEach(weitere, id: \.self) { reiter in
                        if reiter == "verwaltung" {
                            NavigationLink {
                                VerwaltungView()
                            } label: {
                                StartMarke(titel: Reiter.titel(reiter), symbol: Reiter.symbol(reiter))
                            }
                        } else {
                            StartZeile(titel: Reiter.titel(reiter), symbol: Reiter.symbol(reiter)) { blatt = Blatt(id: reiter) }
                        }
                    }
                } header: {
                    Text(tr("Schnell erreichbar"))
                }
            }
            .navigationTitle(tr("Start"))
            .navigationDestination(for: String.self) { key in
                if let event = model.events.first(where: { $0.key == key }) {
                    TerminDetailView(event: event, series: model.events.filter { $0.eventId == event.eventId }.count > 1)
                } else {
                    Text(tr("Diesen Termin gibt es nicht mehr.")).foregroundStyle(.secondary)
                }
            }
            .zugangsWahl()
            .refreshable { await model.refresh() }
            .lesebreite()
        }
        // Noten und Aufgaben bringen ihre eigene Navigation mit: als Blatt über „Start“
        .sheet(item: $blatt) { blatt in
            if blatt.id == "noten" { NotenView() } else { AufgabenView() }
        }
    }
}

/// Bereich, in den eine Zeile „Für dich zu tun“ führt (Ziele wie in `Startseite.bereiche`).
private struct StartBereich: View {
    let target: String

    var body: some View {
        switch target {
        case "surveys": UmfragenView()
        case "orders": BestellungenView()
        case "fee_proofs": BeitragsnachweiseView()
        case "expenses": AuslagenView()
        case "training": TrainingView()
        default: PinnwandView()
        }
    }
}

/// Symbolkopf und Titel einer Zeile auf „Start“.
private struct StartMarke: View {
    let titel: String
    let symbol: Strichsymbol
    var anzahl = 0

    var body: some View {
        HStack(spacing: Design.Abstand.mittel) {
            SymbolKopf(symbol)
            Text(titel).font(.hubi(.body)).foregroundStyle(Color.primary)
            Spacer(minLength: Design.Abstand.klein)
            Zaehler(anzahl)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Zeile auf „Start“, die zu einem Reiter oder Bereich führt.
private struct StartZeile: View {
    let titel: String
    let symbol: Strichsymbol
    var anzahl = 0
    let aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: Design.Abstand.klein) {
                StartMarke(titel: titel, symbol: symbol, anzahl: anzahl)
                SymbolBild(.weiter, groesse: 16).foregroundStyle(Color.secondary)
            }
        }
    }
}
