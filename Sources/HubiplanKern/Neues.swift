import Foundation

// Gestaltung „Frisch mobil“, Etappe U4 (wie `NeuesPane` und `ichGruppen` der Android-App):
// Der Reiter „Neues“ fasst Mitteilungen, Pinnwand und Umfragen zusammen; „Ich“ gliedert
// „Mein Bereich“ in vier Gruppen.

public enum Neues {
    public static let mitteilungen = "mitteilungen"
    public static let pinnwand = "pinnwand"
    public static let umfragen = "umfragen"

    /// Teile, deren Modul an ist; Mitteilungen gibt es immer.
    public static func teile(pinnwand: Bool, umfragen: Bool) -> [String] {
        var teile = [mitteilungen]
        if pinnwand { teile.append(self.pinnwand) }
        if umfragen { teile.append(self.umfragen) }
        return teile
    }

    /// Gewählter Teil: der gewünschte, wenn es ihn für diesen Zugang gibt, sonst Mitteilungen.
    public static func wahl(_ teile: [String], _ wahl: String?) -> String {
        teile.first { $0 == wahl } ?? mitteilungen
    }

    public static func titel(_ teil: String) -> String {
        switch teil {
        case pinnwand: return tr("Pinnwand")
        case umfragen: return tr("Umfragen")
        default: return tr("Mitteilungen")
        }
    }

    /// Beschriftung eines Teils: mit Zahl, wenn dort etwas wartet („Pinnwand (2)“).
    public static func beschriftung(_ teil: String, _ anzahl: Int) -> String {
        anzahl > 0 ? "\(titel(teil)) (\(Design.zaehlerText(anzahl)))" : titel(teil)
    }
}

/// Gruppen unter „Ich › Mein Bereich“.
public enum IchGruppe: String, CaseIterable, Sendable {
    case geld, mitmachen, verein, daten

    public var titel: String {
        switch self {
        case .geld: return tr("Geld")
        case .mitmachen: return tr("Mitmachen")
        case .verein: return tr("Verein")
        case .daten: return tr("Meine Daten")
        }
    }

    /// Gruppe eines Bereichs; nil: der Bereich steht im Reiter „Neues“ (Pinnwand, Umfragen)
    /// oder ist unbekannt.
    public static func gruppe(_ bereich: String) -> IchGruppe? {
        switch bereich {
        case "rechnungen", "lastschrift", "nachweise", "bestellungen", "auslagen": return .geld
        case "training", "ergebnisse", "abwesenheiten", "belegung": return .mitmachen
        case "versammlungen", "dokumente": return .verein
        case "daten", "kuendigung", "mitarbeiter": return .daten
        default: return nil
        }
    }

    /// Reihenfolge der Bereiche innerhalb von „Mein Bereich“.
    public static let bereiche = [
        "rechnungen", "lastschrift", "nachweise", "bestellungen", "auslagen",
        "training", "ergebnisse", "abwesenheiten", "belegung",
        "versammlungen", "dokumente",
        "daten", "kuendigung", "mitarbeiter",
    ]

    /// Vorhandene Bereiche in ihren Gruppen, in fester Reihenfolge; leere Gruppen fallen weg.
    public static func gruppen(_ vorhanden: Set<String>) -> [(gruppe: IchGruppe, bereiche: [String])] {
        var gruppen: [(gruppe: IchGruppe, bereiche: [String])] = []
        for gruppe in allCases {
            let liste = bereiche.filter { vorhanden.contains($0) && IchGruppe.gruppe($0) == gruppe }
            if !liste.isEmpty { gruppen.append((gruppe: gruppe, bereiche: liste)) }
        }
        return gruppen
    }
}

/// Einstellung „Darstellung“ unter „Mein Konto“: wie das Gerät, hell oder dunkel.
public enum Darstellung {
    public static let hell = "hell"
    public static let dunkel = "dunkel"
    /// Leer heißt: wie das Gerät.
    public static let werte = ["", hell, dunkel]

    /// Dunkel zeigen? Die eigene Wahl gilt vor dem Gerät; Unbekanntes folgt dem Gerät.
    public static func istDunkel(_ wahl: String, geraetDunkel: Bool) -> Bool {
        switch wahl {
        case hell: return false
        case dunkel: return true
        default: return geraetDunkel
        }
    }

    public static func name(_ wahl: String) -> String {
        switch wahl {
        case hell: return tr("Hell")
        case dunkel: return tr("Dunkel")
        default: return tr("Wie das Gerät")
        }
    }
}
