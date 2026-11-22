import Foundation

// Startseite der App in einem Abruf (`GET /api/portal/<Zugang>/start/`, Beschreibung in
// hubiplan/docs/app.md): der nächste Termin, was gerade wartet, und die Kacheln. Ältere
// HUBIplan-Stände kennen den Abruf nicht (404); dann zeigt „Start“, was die App aus der
// Terminliste weiß.

/// Eine Zeile unter „Für dich zu tun“. `target` nennt den Bereich; unbekannte zeigt die App nicht.
public struct StartTodo: Decodable, Equatable, Identifiable, Sendable {
    public var key: String
    public var title: String
    public var count: Int
    public var target: String

    public var id: String { key }

    enum CodingKeys: String, CodingKey { case key, title, count, target }

    public init(key: String, title: String, count: Int, target: String) {
        self.key = key
        self.title = title
        self.count = count
        self.target = target
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
    }
}

public struct StartSeite: Decodable, Equatable, Sendable {
    public var nextEvent: Occurrence?
    public var todo: [StartTodo]
    public var tiles: [HomeTile]

    enum CodingKeys: String, CodingKey {
        case nextEvent = "next_event"
        case todo, tiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nextEvent = try c.decodeIfPresent(Occurrence.self, forKey: .nextEvent)
        todo = try c.decodeIfPresent([StartTodo].self, forKey: .todo) ?? []
        tiles = try c.decodeIfPresent([HomeTile].self, forKey: .tiles) ?? []
    }
}

extension Api {
    /// Startseite der App; nil, wenn der HUBIplan-Stand den Abruf noch nicht kennt (404).
    public func start(accessId: Int) async throws -> StartSeite? {
        do {
            let seite: StartSeite = try await expect("GET", "/api/portal/\(accessId)/start/")
            return seite
        } catch let error as ApiError where error.status == 404 {
            return nil
        }
    }
}

extension Startseite {
    /// Bereiche unter „Ich“, in die eine Zeile „Für dich zu tun“ führen kann.
    public static let bereiche = ["surveys", "orders", "fee_proofs", "expenses", "training", "pinboard"]

    /// Zeilen unter „Für dich zu tun“: offene Rückmeldungen aus der Terminliste der App (sie
    /// stimmt gleich nach einer Zusage; `ohne`: der Termin, der schon oben steht), dazu vom
    /// Server, was sonst wartet. Unbekannte Ziele und leere Zeilen fallen weg.
    public static func zeilen(server: [StartTodo], termine: [Occurrence], ohne: Occurrence? = nil) -> [StartTodo] {
        var zeilen: [StartTodo] = []
        let offen = offeneRueckmeldungen(termine, ohne: ohne)
        if offen > 0 {
            zeilen.append(StartTodo(
                key: "rsvp",
                title: trn("{n} Termin wartet auf deine Rückmeldung", "{n} Termine warten auf deine Rückmeldung", offen),
                count: offen,
                target: "events"
            ))
        }
        zeilen += server.filter { $0.count > 0 && bereiche.contains($0.target) }
        return zeilen
    }

    /// Symbol einer Zeile „Für dich zu tun“.
    public static func symbol(_ target: String) -> Strichsymbol {
        switch target {
        case "surveys": return .umfrage
        case "orders": return .bestellung
        case "fee_proofs": return .nachweis
        case "expenses": return .geld
        case "training": return .training
        case "pinboard": return .pinnwand
        default: return .zuErledigen
        }
    }

    /// Monat eines Termins als Zwischenüberschrift der Terminliste: „November 2026“. Ganztägige
    /// Termine zählen nach dem Kalendertag der Verwaltung. Leer, wenn das Datum nicht lesbar ist.
    public static func monatTitel(
        _ termin: Occurrence, timeZone: TimeZone = .current, englisch: Bool = Texte.language == "en"
    ) -> String {
        guard let date = Zeit.parse(termin.startsAt) else { return "" }
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: englisch ? "en_GB" : "de_DE")
        format.timeZone = termin.allDay ? Zeit.kalenderZone : timeZone
        format.dateFormat = "LLLL yyyy"
        return format.string(from: date)
    }

    /// Eine Gruppe der Terminliste: Monat und seine Termine.
    public struct Monat: Equatable, Identifiable, Sendable {
        public let titel: String
        public var termine: [Occurrence]
        public var id: String { titel + "-" + (termine.first?.key ?? "") }
    }

    /// Termine in der Reihenfolge der Liste, gruppiert nach Monat.
    public static func monate(
        _ termine: [Occurrence], timeZone: TimeZone = .current, englisch: Bool = Texte.language == "en"
    ) -> [Monat] {
        var gruppen: [Monat] = []
        for termin in termine {
            let titel = monatTitel(termin, timeZone: timeZone, englisch: englisch)
            if let letzte = gruppen.indices.last, gruppen[letzte].titel == titel {
                gruppen[letzte].termine.append(termin)
            } else {
                gruppen.append(Monat(titel: titel, termine: [termin]))
            }
        }
        return gruppen
    }
}
