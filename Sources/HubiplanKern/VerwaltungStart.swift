import Foundation

// Gestaltung „Frisch mobil“, Etappe U5 (wie `AdminStart` der Android-App): Die Verwaltung beginnt
// als Arbeitsplatz. Oben „Ausweis prüfen“ und „Neu“, darunter „Zu erledigen“ mit Zähler, die
// Kacheln und die Bereiche in den Gruppen des Hauptmenüs im Browser; eine Suche schränkt ein.

/// Gruppen der Startliste, wie die Gruppen des Hauptmenüs im Browser.
public enum VerwaltungGruppe: String, CaseIterable, Sendable {
    case planen, verein, vereinsleben, verwaltung

    public var titel: String {
        switch self {
        case .planen: return tr("Planen")
        case .verein: return tr("Verein")
        case .vereinsleben: return tr("Vereinsleben")
        case .verwaltung: return tr("Verwaltung")
        }
    }

    /// Bereiche in ihren Gruppen, Reihenfolge wie in `AdminUnit.sections`; leere Gruppen fallen weg.
    public static func gruppen(_ bereiche: [AdminSection]) -> [(gruppe: VerwaltungGruppe, bereiche: [AdminSection])] {
        var gruppen: [(gruppe: VerwaltungGruppe, bereiche: [AdminSection])] = []
        for gruppe in allCases {
            let liste = bereiche.filter { $0.gruppe == gruppe }
            if !liste.isEmpty { gruppen.append((gruppe: gruppe, bereiche: liste)) }
        }
        return gruppen
    }

    /// Suche auf der Startliste: Bereiche, deren Name oder Beschreibung alle Wörter enthält.
    public static func suche(_ bereiche: [AdminSection], _ text: String) -> [AdminSection] {
        let woerter = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        if woerter.isEmpty { return bereiche }
        return bereiche.filter { bereich in
            let heu = "\(bereich.titel) \(bereich.hinweis)".lowercased()
            return woerter.allSatisfy { heu.contains($0) }
        }
    }
}

extension AdminSection {
    /// Gruppe eines Bereichs; nil: „Zu erledigen“ steht für sich über den Gruppen.
    public var gruppe: VerwaltungGruppe? {
        switch self {
        case .tasks: return nil
        case .events, .todos, .obligations: return .planen
        case .members, .applications, .occasions, .qualifications: return .verein
        case .meetings, .bookings, .competitions: return .vereinsleben
        case .finance, .billing, .partners: return .verwaltung
        }
    }

    public var titel: String {
        switch self {
        case .tasks: return tr("Zu erledigen")
        case .events: return tr("Termine")
        case .todos: return tr("Aufgaben verteilen")
        case .obligations: return tr("Fristen")
        case .members: return tr("Mitglieder")
        case .applications: return tr("Beitrittsanträge")
        case .meetings: return tr("Versammlung leiten")
        case .bookings: return tr("Belegung freigeben")
        case .occasions: return tr("Jubiläen und Geburtstage")
        case .qualifications: return tr("Qualifikationen")
        case .competitions: return tr("Wettbewerbe")
        case .finance: return tr("Kassenbuch")
        case .billing: return tr("Rechnungen")
        case .partners: return tr("Geschäftspartner")
        }
    }

    /// Ein Satz dazu, was man in dem Bereich tut.
    public var hinweis: String {
        switch self {
        case .tasks: return tr("Datenänderungen, Fotos und Termine, die auf dich warten")
        case .events: return tr("Absagen, Rückmeldungen eintragen, neuer Termin")
        case .todos: return tr("Aufgaben anlegen, erledigen und wieder öffnen")
        case .obligations: return tr("Vereinspflichten mit Frist und Zuständigkeit")
        case .members: return tr("Suchen, anrufen, Mitgliedsakte öffnen")
        case .applications: return tr("Anträge prüfen, zustimmen, aufnehmen oder ablehnen")
        case .meetings: return tr("Anwesenheit, Einlass per Ausweis, QR-Code, Abstimmungen")
        case .bookings: return tr("Anfragen für Räume und Plätze bestätigen oder ablehnen")
        case .occasions: return tr("Geburtstage und Jubiläen der nächsten Wochen")
        case .qualifications: return tr("Nachweise, die bald ablaufen")
        case .competitions: return tr("Ergebnisse am Stand erfassen, auch ohne Empfang")
        case .finance: return tr("Kontostände, Buchungen, Beleg fotografieren")
        case .billing: return tr("Offene und bezahlte Rechnungen, bar kassieren")
        case .partners: return tr("Lieferanten, Sponsoren und Ansprechpartner nachschlagen")
        }
    }

    /// Strichsymbol eines Bereichs (gemeinsamer Symbolsatz beider Apps).
    public var symbol: Strichsymbol {
        switch self {
        case .tasks: return .zuErledigen
        case .todos: return .aufgaben
        case .members: return .mitglieder
        case .applications: return .antrag
        case .bookings: return .belegung
        case .meetings: return .versammlung
        case .events: return .termine
        case .finance: return .kassenbuch
        case .billing: return .rechnung
        case .occasions: return .jubilaeum
        case .competitions: return .wettbewerb
        case .partners: return .partner
        case .qualifications: return .qualifikation
        case .obligations: return .frist
        }
    }
}

/// Was der Knopf „Neu“ auf der Startliste der Verwaltung anlegen kann.
public enum NeuAktion: String, CaseIterable, Identifiable, Sendable {
    case quittung, buchung, termin, aufgabe

    public var id: String { rawValue }

    public var titel: String {
        switch self {
        case .quittung: return tr("Neue Quittung")
        case .buchung: return tr("Neue Buchung")
        case .termin: return tr("Neuer Termin")
        case .aufgabe: return tr("Neue Aufgabe")
        }
    }

    public var symbol: Strichsymbol {
        switch self {
        case .quittung: return .rechnung
        case .buchung: return .kassenbuch
        case .termin: return .termine
        case .aufgabe: return .aufgaben
        }
    }
}

extension AdminUnit {
    /// Aktionen unter „Neu“ je nach Rechten. Ob Termine angelegt werden dürfen, weiß erst der
    /// Server; der Bereich „Termine“ öffnet das Formular nur dann.
    public var neuAktionen: [NeuAktion] {
        var liste: [NeuAktion] = []
        if !isDepartment, canEditFinance { liste += [.quittung, .buchung] }
        if showsEvents { liste.append(.termin) }
        if showsTodos { liste.append(.aufgabe) }
        return liste
    }
}
