import Foundation

// „Meine Ergebnisse“ und Ranglisten im Mitgliederbereich (wie Android, Wettbewerbe Schritt 5 und SB4).

public struct MyPlacing: Decodable, Equatable, Sendable {
    public var scoring: String
    public var place: Int?
    public var valueText: String
    public var field: Int?
    /// Einheit des Werts („Ringe“, „Teiler“); ältere Server senden sie nicht.
    public var unitLabel: String

    enum CodingKeys: String, CodingKey {
        case scoring, place, field
        case valueText = "value_text"
        case unitLabel = "unit_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scoring = try c.decodeIfPresent(String.self, forKey: .scoring) ?? ""
        place = try c.decodeIfPresent(Int.self, forKey: .place)
        valueText = try c.decodeIfPresent(String.self, forKey: .valueText) ?? ""
        field = try c.decodeIfPresent(Int.self, forKey: .field)
        unitLabel = try c.decodeIfPresent(String.self, forKey: .unitLabel) ?? ""
    }

    /// „Einzel: 2. Platz von 14 · 28 Ringe“; ohne Platz nur der Wert. Jede Zahl ist beschriftet.
    public var line: String {
        var parts: [String] = []
        if let place {
            parts.append(tr("{n}. Platz", ["n": place]) + (field.map { tr(" von {it}", ["it": $0]) } ?? ""))
        }
        let value = valueText.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty {
            if value.contains(where: { $0.isLetter }) {
                parts.append(value)
            } else if !unitLabel.isEmpty {
                parts.append("\(value) \(unitLabel)")
            } else {
                parts.append(tr("Wert {value}", ["value": value]))
            }
        }
        return "\(scoring): " + (parts.isEmpty ? tr("ohne Wertung") : parts.joined(separator: " · "))
    }
}

public struct MyStart: Decodable, Equatable, Identifiable, Sendable {
    public var competition: Int
    public var title: String
    public var date: String
    public var status: String
    public var statusLabel: String
    public var unitName: String
    public var results: [MyPlacing]
    public var id: Int { competition }

    enum CodingKeys: String, CodingKey {
        case competition, title, date, status, results
        case statusLabel = "status_label"
        case unitName = "unit_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        competition = try c.decode(Int.self, forKey: .competition)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        unitName = try c.decodeIfPresent(String.self, forKey: .unitName) ?? ""
        results = try c.decodeIfPresent([MyPlacing].self, forKey: .results) ?? []
    }

    /// Datum, Einheit und (außer bei endgültigen) der Stand.
    public var meta: String {
        [Zeit.plainDate(date), unitName, status == "endgueltig" ? "" : statusLabel]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct MyGrant: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var year: Int
    public var fullTitle: String
    public var trophyName: String

    enum CodingKeys: String, CodingKey {
        case id, year
        case fullTitle = "full_title"
        case trophyName = "trophy_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        fullTitle = try c.decodeIfPresent(String.self, forKey: .fullTitle) ?? ""
        trophyName = try c.decodeIfPresent(String.self, forKey: .trophyName) ?? ""
    }

    /// „Vereinsmeister 2027“; ein Preis ohne Jahr im Titel bekommt das Jahr dazu.
    public var line: String {
        let title = fullTitle.isEmpty ? trophyName : fullTitle
        return title.contains(String(year)) ? title : "\(title) \(year)"
    }
}

/// `GET /api/portal/<Zugang>/results/`: eigene Starts und Titel, keine fremden Namen.
public struct MyResults: Decodable, Equatable, Sendable {
    public var starts: [MyStart]
    public var grants: [MyGrant]

    enum CodingKeys: String, CodingKey { case starts, grants }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        starts = try c.decodeIfPresent([MyStart].self, forKey: .starts) ?? []
        grants = try c.decodeIfPresent([MyGrant].self, forKey: .grants) ?? []
    }

    public var isEmpty: Bool { starts.isEmpty && grants.isEmpty }
}

// MARK: Ranglisten

public struct RankingSummary: Decodable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var date: String
    public var location: String
    public var own: Bool
    public var organizer: String
    public var live: Bool
    public var provisional: Bool

    enum CodingKeys: String, CodingKey { case id, title, date, location, own, organizer, live, provisional }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        own = try c.decodeIfPresent(Bool.self, forKey: .own) ?? true
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer) ?? ""
        live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? false
        provisional = try c.decodeIfPresent(Bool.self, forKey: .provisional) ?? false
    }

    /// „14.06.2027 · Schützenhaus · läuft“
    public var line: String {
        [Zeit.plainDate(date), location, own ? "" : organizer, live ? tr("läuft") : (provisional ? tr("vorläufig") : "")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct Rankings: Decodable, Equatable, Sendable {
    public var competitions: [RankingSummary]

    enum CodingKeys: String, CodingKey { case competitions }

    public init(competitions: [RankingSummary] = []) { self.competitions = competitions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        competitions = try c.decodeIfPresent([RankingSummary].self, forKey: .competitions) ?? []
    }
}

public struct RankingRow: Decodable, Equatable, Sendable {
    public var place: Int?
    public var name: String
    public var value: String
    public var unit: String
    public var club: String
    public var prize: Bool
    public var note: String
    public var outOfCompetition: Bool

    enum CodingKeys: String, CodingKey {
        case place, name, value, unit, club, prize, note
        case outOfCompetition = "out_of_competition"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        place = try c.decodeIfPresent(Int.self, forKey: .place)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? ""
        prize = try c.decodeIfPresent(Bool.self, forKey: .prize) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        outOfCompetition = try c.decodeIfPresent(Bool.self, forKey: .outOfCompetition) ?? false
    }

    /// „1. Max M. (Zug 1) · 30“, außer Konkurrenz und Vermerk dahinter.
    public var line: String {
        var who = name.isEmpty ? tr("ohne Namen") : name
        let extra = [unit, club].filter { !$0.isEmpty }
        if !extra.isEmpty { who += " (" + extra.joined(separator: ", ") + ")" }
        var text = (place.map { "\($0). " } ?? "") + who
        if !value.isEmpty { text += " · " + value }
        if outOfCompetition { text += " · " + tr("außer Konkurrenz") }
        if !note.isEmpty { text += " · " + note }
        return text
    }
}

public struct RankingScoring: Decodable, Equatable, Sendable {
    public var name: String
    public var rows: [RankingRow]
    public var complete: Bool

    enum CodingKeys: String, CodingKey { case name, rows, complete }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        rows = try c.decodeIfPresent([RankingRow].self, forKey: .rows) ?? []
        complete = try c.decodeIfPresent(Bool.self, forKey: .complete) ?? true
    }
}

public struct RankingPrize: Decodable, Equatable, Sendable {
    public var name: String
    public var fallen: Bool
    public var winner: String
    public var unit: String
    public var shot: Int?

    enum CodingKeys: String, CodingKey { case name, fallen, winner, unit, shot }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        fallen = try c.decodeIfPresent(Bool.self, forKey: .fallen) ?? false
        winner = try c.decodeIfPresent(String.self, forKey: .winner) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        shot = try c.decodeIfPresent(Int.self, forKey: .shot)
    }

    /// „Kopf: Max M. (Zug 1), 37. Schuss“ bzw. „Kopf: noch dran“
    public var line: String {
        guard fallen else { return tr("{name}: noch dran", ["name": name]) }
        let who = [winner, unit.isEmpty ? "" : "(\(unit))"].filter { !$0.isEmpty }.joined(separator: " ")
        let parts = [who, shot.map { tr("{n}. Schuss", ["n": $0]) } ?? ""].filter { !$0.isEmpty }
        return name + ": " + (parts.isEmpty ? tr("gefallen") : parts.joined(separator: ", "))
    }
}

public struct RankingTitle: Decodable, Equatable, Sendable {
    public var title: String
    public var name: String

    enum CodingKeys: String, CodingKey { case title, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

public struct RankingDetail: Decodable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var live: Bool
    public var final: Bool
    public var scorings: [RankingScoring]
    public var prizes: [RankingPrize]
    public var titles: [RankingTitle]
    public var version: String
    public var pollSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, live, final, scorings, prizes, titles, version
        case pollSeconds = "poll_seconds"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        live = try c.decodeIfPresent(Bool.self, forKey: .live) ?? false
        final = try c.decodeIfPresent(Bool.self, forKey: .final) ?? false
        scorings = try c.decodeIfPresent([RankingScoring].self, forKey: .scorings) ?? []
        prizes = try c.decodeIfPresent([RankingPrize].self, forKey: .prizes) ?? []
        titles = try c.decodeIfPresent([RankingTitle].self, forKey: .titles) ?? []
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        pollSeconds = try c.decodeIfPresent(Int.self, forKey: .pollSeconds)
    }

    /// Nachfragen, solange der Wettbewerb nicht endgültig ist und der Server eine Pause nennt (mind. 5 s).
    public var pollEvery: Int? {
        guard !final, let pollSeconds else { return nil }
        return max(5, pollSeconds)
    }
}

public struct RankingVersion: Decodable, Equatable, Sendable {
    public var version: String
    public var final: Bool

    enum CodingKeys: String, CodingKey { case version, final }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        final = try c.decodeIfPresent(Bool.self, forKey: .final) ?? false
    }
}

extension PortalAccess {
    /// „Ergebnisse“ unter „Ich“ (Modul Wettbewerbe)
    public var hasResults: Bool { has(module: "competitions", fallback: competitionsEnabled) }
}

extension Api {
    public func myResults(accessId: Int) async throws -> MyResults {
        try await expect("GET", "/api/portal/\(accessId)/results/")
    }

    /// Ranglisten wie auf der Webseite des Vereins. Ältere Stände kennen sie nicht (404): leer.
    public func rankings(accessId: Int) async throws -> Rankings {
        do {
            return try await expect("GET", "/api/portal/\(accessId)/rankings/")
        } catch let error as ApiError where error.status == 404 {
            return Rankings()
        }
    }

    static func rankingPath(_ accessId: Int, _ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let safe = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "/api/portal/\(accessId)/rankings/\(safe)/"
    }

    public func ranking(accessId: Int, id: String) async throws -> RankingDetail {
        try await expect("GET", Api.rankingPath(accessId, id))
    }

    public func rankingVersion(accessId: Int, id: String) async throws -> RankingVersion {
        try await expect("GET", Api.rankingPath(accessId, id) + "?version=1")
    }
}
