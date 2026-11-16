import Foundation

// Mein Bereich wie in der Android-App und im Browser: Belegung anfragen, Kündigung, Meldungen zu
// Wettbewerben und Abwesenheiten in der Musik (`/api/portal/<Zugang>/…`). Die App speichert
// nichts davon.

// MARK: Belegung

/// Objekt, das Mitglieder anfragen dürfen (Vereinsheim, Räume, Material).
public struct BookableItem: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var kind: String
    public var title: String
    public var horizonDays: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case horizonDays = "horizon_days"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        horizonDays = try c.decodeIfPresent(Int.self, forKey: .horizonDays) ?? 0
    }
}

/// Belegte Zeit eines Objekts; fremde Buchungen heißen nur „Belegt“.
public struct BusyTime: Decodable, Equatable, Sendable {
    public var item: Int
    public var title: String
    public var startsAt: String
    public var endsAt: String
    public var allDay: Bool
    public var own: Bool

    enum CodingKeys: String, CodingKey {
        case item, title, own
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item = try c.decode(Int.self, forKey: .item)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        own = try c.decodeIfPresent(Bool.self, forKey: .own) ?? false
    }
}

/// Eigene Anfrage oder Buchung.
public struct OwnBooking: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var item: Int
    public var itemTitle: String
    public var title: String
    public var note: String
    public var startsAt: String
    public var endsAt: String
    public var allDay: Bool
    public var status: String
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, item, title, note, status, version
        case itemTitle = "item_title"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        item = try c.decodeIfPresent(Int.self, forKey: .item) ?? 0
        itemTitle = try c.decodeIfPresent(String.self, forKey: .itemTitle) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
    }

    /// Stornieren geht, solange die Anfrage offen oder bestätigt ist.
    public var cancellable: Bool { status == "requested" || status == "confirmed" }

    /// Stand in Worten.
    public var statusLabel: String { Belegung.statusLabel(status) }
}

public struct BookingWeek: Decodable, Equatable, Sendable {
    public var items: [BookableItem]
    public var occurrences: [BusyTime]
    public var own: [OwnBooking]

    enum CodingKeys: String, CodingKey { case items, occurrences, own }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([BookableItem].self, forKey: .items) ?? []
        occurrences = try c.decodeIfPresent([BusyTime].self, forKey: .occurrences) ?? []
        own = try c.decodeIfPresent([OwnBooking].self, forKey: .own) ?? []
    }

    /// Belegte Zeiten eines Objekts.
    public func busy(_ item: Int) -> [BusyTime] { occurrences.filter { $0.item == item } }
}

public enum Belegung {
    /// Der Kalendertag gilt in deutscher Zeit, wie auf dem Server.
    public static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    public static func statusLabel(_ status: String) -> String {
        switch status {
        case "requested": return tr("angefragt")
        case "confirmed": return tr("bestätigt")
        case "rejected": return tr("abgelehnt")
        case "cancelled": return tr("storniert")
        default: return status
        }
    }

    /// Montag der Woche von `date` (im Kalender `timeZone`), 0:00.
    public static func monday(_ date: Date, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        // Wochentag: 1 = Sonntag … 7 = Samstag
        let back = (calendar.component(.weekday, from: start) + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: start) ?? start
    }

    /// Ganztägig speichert der Server das Ende als 0:00 des Folgetags; angezeigt wird der letzte Tag.
    public static func shownEnd(_ endsAt: String, allDay: Bool) -> String {
        guard allDay, let end = Zeit.parse(endsAt) else { return endsAt }
        return EventTime.iso(end.addingTimeInterval(-1), timeZone: berlin)
    }

    /// Beginn und Ende einer Anfrage als ISO mit Zeitzone. Ganztägig zählen nur die Kalendertage
    /// (im Kalender `timeZone`), gesendet als 0:00 deutscher Zeit; der Server rechnet das Ende
    /// selbst auf den Folgetag. nil, wenn das Ende vor dem Beginn liegt.
    public static func requestTimes(start: Date, end: Date, allDay: Bool, timeZone: TimeZone = .current) -> (from: String, to: String)? {
        if allDay {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = timeZone
            var german = Calendar(identifier: .gregorian)
            german.timeZone = berlin
            func midnight(_ date: Date) -> Date? {
                german.date(from: local.dateComponents([.year, .month, .day], from: date))
            }
            guard let first = midnight(start), let last = midnight(end), last >= first else { return nil }
            return (EventTime.iso(first, timeZone: berlin), EventTime.iso(last, timeZone: berlin))
        }
        guard end > start else { return nil }
        return (EventTime.iso(start, timeZone: timeZone), EventTime.iso(end, timeZone: timeZone))
    }
}

// MARK: Kündigung

public struct CancellationItem: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var exitDate: String?
    public var message: String
    /// pending, accepted, rejected, withdrawn
    public var status: String
    public var statusLabel: String
    public var response: String
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, message, status, response
        case exitDate = "exit_date"
        case statusLabel = "status_label"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        exitDate = try c.decodeIfPresent(String.self, forKey: .exitDate)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        response = try c.decodeIfPresent(String.self, forKey: .response) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    public var pending: Bool { status == "pending" }
}

/// Angaben unter „Meine Daten“ (HUBIplan #402): darf gekündigt werden, ab wann, offene Kündigung.
public struct CancellationInfo: Decodable, Equatable, Sendable {
    public var enabled: Bool
    public var possible: Bool
    public var earliestDate: String?
    /// Regel in Worten, z. B. „mit einer Frist von 3 Monaten zum Ende des Geschäftsjahres“
    public var rule: String
    public var plannedExit: String?
    public var requests: [CancellationItem]

    enum CodingKeys: String, CodingKey {
        case enabled, possible, rule, requests
        case earliestDate = "earliest_date"
        case plannedExit = "planned_exit"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        possible = try c.decodeIfPresent(Bool.self, forKey: .possible) ?? false
        earliestDate = try c.decodeIfPresent(String.self, forKey: .earliestDate)
        rule = try c.decodeIfPresent(String.self, forKey: .rule) ?? ""
        plannedExit = try c.decodeIfPresent(String.self, forKey: .plannedExit)
        requests = try c.decodeIfPresent([CancellationItem].self, forKey: .requests) ?? []
    }

    public var pending: CancellationItem? { requests.first { $0.pending } }

    /// Abschnitt zeigen: eingeschaltet oder schon Kündigungen da (wie im Browser).
    public var shown: Bool { enabled || !requests.isEmpty }

    /// Ist `day` (`JJJJ-MM-TT`) zu früh?
    public func tooEarly(_ day: String) -> Bool {
        guard let earliestDate else { return false }
        return day < String(earliestDate.prefix(10))
    }
}

// MARK: Meldungen

/// Wofür das Mitglied gemeldet ist (nur abgegebene oder bestätigte Meldungen).
public struct MyEntry: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var organizer: String
    public var date: String?
    public var location: String
    public var group: String
    public var position: String
    public var substitute: Bool
    public var confirmed: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, organizer, date, location, group, position, substitute, confirmed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        organizer = try c.decodeIfPresent(String.self, forKey: .organizer) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        position = try c.decodeIfPresent(String.self, forKey: .position) ?? ""
        substitute = try c.decodeIfPresent(Bool.self, forKey: .substitute) ?? false
        confirmed = try c.decodeIfPresent(Bool.self, forKey: .confirmed) ?? false
    }

    /// Liegt das Datum vor `today` (`JJJJ-MM-TT`)? Ohne Datum: kommend.
    public func past(today: String) -> Bool {
        guard let date else { return false }
        return String(date.prefix(10)) < today
    }

    /// „Gemeldet in Mannschaft 1 als Schütze 2 (Ersatz), vom Veranstalter bestätigt“
    public var line: String {
        var out = tr("Gemeldet in {group}", ["group": group])
        if !position.isEmpty { out += tr(" als {position}", ["position": position]) }
        if substitute { out += tr(" (Ersatz)") }
        if confirmed { out += tr(", vom Veranstalter bestätigt") }
        return out
    }

    /// Datum, Ort und Veranstalter in einer Zeile.
    public var meta: String {
        [
            Zeit.plainDate(date),
            location,
            organizer.isEmpty ? "" : tr("Veranstalter: {organizer}", ["organizer": organizer]),
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: Abwesenheiten (Musik)

public struct MusicAbsence: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var startsAt: String
    public var endsAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }
}

public struct OwnAbsences: Decodable, Equatable, Sendable {
    /// Aktives Musikerprofil vorhanden
    public var enabled: Bool
    public var items: [MusicAbsence]

    enum CodingKeys: String, CodingKey { case enabled, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        items = try c.decodeIfPresent([MusicAbsence].self, forKey: .items) ?? []
    }
}

// MARK: Schnittstelle

extension Api {
    /// POST/DELETE mit Prüffehlern je Feld als Meldung (z. B. `{"exit_date": ["Frühestens …"]}`).
    func portalSend<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil, key: String? = nil) async throws -> T {
        let response = try await raw(method, path, json: json, extra: key.map { [SignedFormat.idempotencyHeader: $0] } ?? [:])
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            let message = fields.message.isEmpty ? Api.firstFieldMessage(response.body) : fields.message
            throw ApiError(status: response.status, code: fields.code, message: message)
        }
        if let ignored = Ignored() as? T { return ignored }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }

    /// Woche ab `monday` (`JJJJ-MM-TT`): anfragbare Objekte, belegte Zeiten, eigene Anfragen.
    public func bookings(accessId: Int, monday: String) async throws -> BookingWeek {
        try await expect("GET", "/api/portal/\(accessId)/bookings/?start=\(monday)")
    }

    /// Anfrage stellen; die Verwaltung bestätigt oder lehnt ab (Mail an das Mitglied).
    public func requestBooking(
        accessId: Int, item: Int, title: String, note: String, startsAt: String, endsAt: String, allDay: Bool
    ) async throws -> OwnBooking {
        try await portalSend("POST", "/api/portal/\(accessId)/bookings/", json: [
            "item": item, "title": title, "note": note, "starts_at": startsAt, "ends_at": endsAt, "all_day": allDay,
        ])
    }

    /// Eigene Anfrage oder Buchung stornieren (mit Versionsstand).
    public func cancelBooking(accessId: Int, booking: OwnBooking) async throws -> OwnBooking {
        try await portalSend("POST", "/api/portal/\(accessId)/bookings/\(booking.id)/cancel/", json: ["version": booking.version])
    }

    /// Mitgliedschaft kündigen; ohne `exitDate` zum frühesten Termin.
    public func cancelMembership(accessId: Int, exitDate: String?, message: String) async throws -> CancellationItem {
        var body: [String: Any] = ["message": message, "confirm": true]
        if let exitDate { body["exit_date"] = exitDate }
        return try await portalSend("POST", "/api/portal/\(accessId)/cancellation/", json: body)
    }

    public func withdrawCancellation(accessId: Int, id: Int) async throws -> CancellationItem {
        try await portalSend("DELETE", "/api/portal/\(accessId)/cancellation/\(id)/")
    }

    /// Wofür das Mitglied gemeldet ist (leer, wenn das Modul Meldungen aus ist).
    public func myEntries(accessId: Int) async throws -> [MyEntry] {
        try await expect("GET", "/api/portal/\(accessId)/entries/")
    }

    public func myAbsences(accessId: Int) async throws -> OwnAbsences {
        try await expect("GET", "/api/portal/\(accessId)/music/absences/")
    }

    /// Abwesenheit eintragen oder ändern (`id`). `key` ist der `Idempotency-Key`: derselbe
    /// Schlüssel beim Wiederholen verhindert doppelte Einträge.
    public func saveAbsence(accessId: Int, id: Int?, startsAt: String, endsAt: String, key: String) async throws -> MusicAbsence {
        var body: [String: Any] = ["action": "save", "starts_at": startsAt, "ends_at": endsAt]
        if let id { body["id"] = id }
        return try await portalSend("POST", "/api/portal/\(accessId)/music/absences/", json: body, key: key)
    }

    public func deleteAbsence(accessId: Int, id: Int, key: String) async throws {
        let _: Ignored = try await portalSend("POST", "/api/portal/\(accessId)/music/absences/",
                                              json: ["action": "delete", "id": id], key: key)
    }
}
