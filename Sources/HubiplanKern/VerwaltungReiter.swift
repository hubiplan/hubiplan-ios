import Foundation

// Konten ohne Mitgliederbereich (z. B. Kassierer ohne eigene Mitgliedschaft oder eine Einheit, die
// nur das Kassenbuch nutzt): Statt Start, Termine, Neues stehen Bereiche der Verwaltung in der
// Leiste. „Start“ (Zu erledigen, Neu), bis zu drei Reiter aus den Rechten und „Ich“. Gleiche Regel
// wie `verwaltungReiter` der Android-App.

/// Reiter der Verwaltung in der Leiste.
public struct VerwaltungReiter: Equatable, Sendable, Identifiable {
    public static let start = "start"
    public static let ich = "ich"
    public static let mehr = "mehr"
    /// Plätze zwischen „Start“ und „Ich“: zusammen höchstens fünf Reiter auf dem iPhone.
    public static let mittlere = 3

    public var key: String
    public var titel: String
    public var symbol: Strichsymbol
    /// Bereiche dieses Reiters, Reihenfolge wie in `AdminUnit.sections`
    public var bereiche: [AdminSection]
    /// Genau ein Bereich: Der Reiter öffnet ihn direkt, ohne Liste davor
    public var einzeln: Bool

    public var id: String { key }

    public init(key: String, titel: String, symbol: Strichsymbol, bereiche: [AdminSection], einzeln: Bool = false) {
        self.key = key
        self.titel = titel
        self.symbol = symbol
        self.bereiche = bereiche
        self.einzeln = einzeln
    }

    private static func einzelner(_ bereich: AdminSection) -> VerwaltungReiter {
        VerwaltungReiter(key: "s:\(bereich.rawValue)", titel: bereich.kurz, symbol: bereich.symbol, bereiche: [bereich], einzeln: true)
    }

    private static func aus(_ gruppe: BereichsGruppe) -> VerwaltungReiter {
        if gruppe.bereiche.count == 1 { return einzelner(gruppe.bereiche[0]) }
        return VerwaltungReiter(key: "g:\(gruppe.key)", titel: gruppe.titel, symbol: gruppe.bereiche[0].symbol, bereiche: gruppe.bereiche)
    }

    /// Reiter der Verwaltung ohne „Ich“: zuerst „Start“, dann je Bereich ein Reiter, solange es
    /// höchstens `mittlere` Bereiche sind; sonst die Gruppen der Startliste, bei mehr als
    /// `mittlere` Gruppen die letzten unter „Mehr“.
    public static func reiter(_ sections: [AdminSection], _ menuGroups: [MenuGroup]) -> [VerwaltungReiter] {
        let anfang = VerwaltungReiter(key: start, titel: tr("Start"), symbol: .start, bereiche: sections.filter { $0 == .tasks })
        let bereiche = sections.filter { $0 != .tasks }
        var mitte: [VerwaltungReiter]
        if bereiche.count <= mittlere {
            mitte = bereiche.map(einzelner)
        } else {
            let gruppen = VerwaltungGruppe.gruppen(bereiche, menuGroups)
            if gruppen.count <= mittlere {
                mitte = gruppen.map(aus)
            } else {
                mitte = gruppen.prefix(mittlere - 1).map(aus)
                mitte.append(VerwaltungReiter(
                    key: mehr, titel: tr("Mehr"), symbol: .ordner,
                    bereiche: gruppen.dropFirst(mittlere - 1).flatMap(\.bereiche)
                ))
            }
        }
        return [anfang] + mitte
    }

    /// Nur die Verwaltung: Konto ohne Zugang zum Mitgliederbereich, aber mit etwas zu verwalten.
    public static func nurVerwaltung(geladen: Bool, zugaenge: Int, verwaltet: Bool) -> Bool {
        geladen && zugaenge == 0 && verwaltet
    }

    /// Gewählter Reiter, solange es ihn gibt; sonst „Start“.
    public static func gewaehlt(_ reiter: [VerwaltungReiter], _ key: String) -> VerwaltungReiter? {
        reiter.first { $0.key == key } ?? reiter.first
    }
}

extension AdminSection {
    /// Kurzer Name eines Bereichs für die Leiste (einzeilig).
    public var kurz: String {
        switch self {
        case .todos: return tr("Aufgaben")
        case .applications: return tr("Anträge")
        case .bookings: return tr("Belegung")
        case .meetings: return tr("Versammlung")
        case .occasions: return tr("Jubiläen")
        case .partners: return tr("Partner")
        case .qualifications: return tr("Nachweise")
        default: return titel
        }
    }
}
