import Foundation

// Verwaltung in der App (Schritt B3 der Android-App): Termine der Einheit, Absagen,
// Rückmeldungen ansehen und für ein Mitglied eintragen, einmaligen Termin anlegen.

extension AdminUnit {
    /// Bereich „Termine“ zeigen: mit Stufen nur bei „lesen“, früher sah jede Rolle die Termine.
    public var showsEvents: Bool {
        !stufen || permissions.contains("events.view") || permissions.contains("events.edit")
    }
}

/// Ein Termin in der Liste (bei Serien jeder Einzeltermin).
public struct AdminOccurrence: Decodable, Equatable, Sendable {
    public var key: String
    public var eventId: Int
    public var title: String
    public var startsAt: String
    public var endsAt: String
    public var originalStart: String?
    public var allDay: Bool
    public var location: String
    public var isCancelled: Bool
    public var isSeries: Bool
    public var owner: String
    public var canEdit: Bool
    public var rsvpEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case key, title, location, owner
        case eventId = "event_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case originalStart = "original_start"
        case allDay = "all_day"
        case isCancelled = "is_cancelled"
        case isSeries = "is_series"
        case canEdit = "can_edit"
        case rsvpEnabled = "rsvp_enabled"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
        eventId = try c.decode(Int.self, forKey: .eventId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt) ?? startsAt
        originalStart = try c.decodeIfPresent(String.self, forKey: .originalStart)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        isSeries = try c.decodeIfPresent(Bool.self, forKey: .isSeries) ?? false
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        rsvpEnabled = try c.decodeIfPresent(Bool.self, forKey: .rsvpEnabled) ?? false
    }

    /// Eindeutig in der Liste, auch wenn der Server keinen Schlüssel mitgibt.
    public var rowKey: String { key.isEmpty ? "\(eventId)-\(startsAt)" : key }

    /// Bei Serien der gewählte Einzeltermin, sonst nil (die Absage gilt dem ganzen Termin).
    public var occurrenceStart: String? { isSeries ? (originalStart ?? startsAt) : nil }

    /// Zweite Zeile der Liste: Ort, Einheit, Zu-/Absagen, Serie.
    public var detail: String {
        var parts = [location, owner].filter { !$0.isEmpty }
        if rsvpEnabled { parts.append(tr("Zu-/Absagen")) }
        if isSeries { parts.append(tr("Serie")) }
        return parts.joined(separator: " · ")
    }
}

public struct AdminEventList: Decodable, Equatable, Sendable {
    public var items: [AdminOccurrence]
    /// Darf neue Termine anlegen
    public var canManage: Bool
    /// Zu- und Absagen sind in der Einheit möglich
    public var rsvpAllowed: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case canManage = "can_manage"
        case rsvpAllowed = "rsvp_allowed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([AdminOccurrence].self, forKey: .items) ?? []
        canManage = try c.decodeIfPresent(Bool.self, forKey: .canManage) ?? false
        rsvpAllowed = try c.decodeIfPresent(Bool.self, forKey: .rsvpAllowed) ?? false
    }
}

/// Abweichung eines Einzeltermins von der Serie.
public struct EventException: Decodable, Equatable, Sendable {
    public var originalStart: String
    public var isCancelled: Bool
    public var note: String

    enum CodingKeys: String, CodingKey {
        case note
        case originalStart = "original_start"
        case isCancelled = "is_cancelled"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        originalStart = try c.decode(String.self, forKey: .originalStart)
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

public struct RsvpCounts: Decodable, Equatable, Sendable {
    public var yes: Int
    public var no: Int
    public var guests: Int
    public var persons: Int
    public var open: Int?

    enum CodingKeys: String, CodingKey { case yes, no, guests, persons, open }

    public init(yes: Int = 0, no: Int = 0, guests: Int = 0, persons: Int = 0, open: Int? = nil) {
        self.yes = yes
        self.no = no
        self.guests = guests
        self.persons = persons
        self.open = open
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        yes = try c.decodeIfPresent(Int.self, forKey: .yes) ?? 0
        no = try c.decodeIfPresent(Int.self, forKey: .no) ?? 0
        guests = try c.decodeIfPresent(Int.self, forKey: .guests) ?? 0
        persons = try c.decodeIfPresent(Int.self, forKey: .persons) ?? 0
        open = try c.decodeIfPresent(Int.self, forKey: .open)
    }

    /// „12 Zusagen (14 Personen) · 3 Absagen · 5 offen“
    public var text: String {
        var parts = [
            trn("1 Zusage", "{n} Zusagen", yes) + (persons != yes ? " " + tr("({n} Personen)", ["n": persons]) : ""),
            trn("1 Absage", "{n} Absagen", no),
        ]
        if let open { parts.append(tr("{n} offen", ["n": open])) }
        return parts.joined(separator: " · ")
    }
}

public struct AdminRsvp: Decodable, Equatable, Sendable {
    public var enabled: Bool
    public var deadline: String?
    public var capacity: Int?
    public var guestsAllowed: Bool
    public var maxGuests: Int
    public var free: Int?
    public var canViewList: Bool
    public var canEnter: Bool
    public var summary: RsvpCounts?

    enum CodingKeys: String, CodingKey {
        case enabled, deadline, capacity, free, summary
        case guestsAllowed = "guests_allowed"
        case maxGuests = "max_guests"
        case canViewList = "can_view_list"
        case canEnter = "can_enter"
    }

    public init() {
        enabled = false
        guestsAllowed = false
        maxGuests = 0
        canViewList = false
        canEnter = false
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline)
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
        guestsAllowed = try c.decodeIfPresent(Bool.self, forKey: .guestsAllowed) ?? false
        maxGuests = try c.decodeIfPresent(Int.self, forKey: .maxGuests) ?? 0
        free = try c.decodeIfPresent(Int.self, forKey: .free)
        canViewList = try c.decodeIfPresent(Bool.self, forKey: .canViewList) ?? false
        canEnter = try c.decodeIfPresent(Bool.self, forKey: .canEnter) ?? false
        summary = try c.decodeIfPresent(RsvpCounts.self, forKey: .summary)
    }
}

/// Ein Termin mit allen Angaben für die Verwaltung.
public struct AdminEvent: Decodable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var description: String
    public var location: String
    public var allDay: Bool
    public var startsAt: String
    public var endsAt: String
    public var visibilityLabel: String
    public var `repeat`: String
    public var repeatLabel: String
    public var isCancelled: Bool
    public var cancelNote: String
    public var owner: String
    public var canEdit: Bool
    public var exceptions: [EventException]
    public var rsvp: AdminRsvp

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, owner, exceptions, rsvp
        case allDay = "all_day"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case visibilityLabel = "visibility_label"
        case `repeat`
        case repeatLabel = "repeat_label"
        case isCancelled = "is_cancelled"
        case cancelNote = "cancel_note"
        case canEdit = "can_edit"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt) ?? startsAt
        visibilityLabel = try c.decodeIfPresent(String.self, forKey: .visibilityLabel) ?? ""
        `repeat` = try c.decodeIfPresent(String.self, forKey: .repeat) ?? "none"
        repeatLabel = try c.decodeIfPresent(String.self, forKey: .repeatLabel) ?? ""
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        cancelNote = try c.decodeIfPresent(String.self, forKey: .cancelNote) ?? ""
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        exceptions = try c.decodeIfPresent([EventException].self, forKey: .exceptions) ?? []
        rsvp = try c.decodeIfPresent(AdminRsvp.self, forKey: .rsvp) ?? AdminRsvp()
    }

    public var isSeries: Bool { `repeat` != "none" }

    /// Stand eines Termins, wie er gezeigt wird: bei Serien der gewählte Einzeltermin.
    public struct Shown: Equatable, Sendable {
        /// Einzeltermin einer Serie (`original_start`); nil: der ganze Termin
        public var single: String?
        public var start: String
        public var end: String
        public var cancelled: Bool
        public var note: String
    }

    /// `occurrence`: gewählter Einzeltermin aus der Liste; zählt nur bei Serien.
    public func shown(occurrence: String?) -> Shown {
        guard isSeries, let single = occurrence else {
            return Shown(single: nil, start: startsAt, end: endsAt, cancelled: isCancelled, note: cancelNote)
        }
        let exception = exceptions.first { EventTime.sameInstant($0.originalStart, single) }
        return Shown(
            single: single, start: single, end: EventTime.shiftEnd(start: startsAt, end: endsAt, occurrence: single),
            cancelled: exception?.isCancelled == true, note: exception?.note ?? ""
        )
    }

    /// Zeile unter dem Titel: Ort, Sichtbarkeit, Wiederholung, Einheit.
    public var detail: String {
        [location, visibilityLabel, isSeries ? repeatLabel : "", owner].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Rückmeldung eines Mitglieds.
public struct ResponseRow: Decodable, Equatable, Sendable {
    public var membershipId: Int
    public var name: String
    public var departments: String
    public var status: String?
    public var guests: Int
    public var note: String
    public var source: String?

    enum CodingKeys: String, CodingKey {
        case name, departments, status, guests, note, source
        case membershipId = "membership_id"
    }

    public init(membershipId: Int, name: String, departments: String = "", status: String? = nil, guests: Int = 0, note: String = "", source: String? = nil) {
        self.membershipId = membershipId
        self.name = name
        self.departments = departments
        self.status = status
        self.guests = guests
        self.note = note
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        membershipId = try c.decode(Int.self, forKey: .membershipId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        departments = try c.decodeIfPresent(String.self, forKey: .departments) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status)
        guests = try c.decodeIfPresent(Int.self, forKey: .guests) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }

    /// Name, mit Begleitung „Erika Musterfrau + 1“.
    public var title: String { guests > 0 ? "\(name) + \(guests)" : name }

    /// Zweite Zeile: Untereinheiten, Notiz, „vom Vorstand eingetragen“.
    public var detail: String {
        var parts = [departments, note].filter { !$0.isEmpty }
        if source == "board" { parts.append(tr("vom Vorstand eingetragen")) }
        return parts.joined(separator: " · ")
    }
}

public struct AdminResponses: Decodable, Equatable, Sendable {
    public var summary: RsvpCounts
    public var capacity: Int?
    public var items: [ResponseRow]
    /// Eingeladene ohne Rückmeldung
    public var open: [ResponseRow]

    enum CodingKeys: String, CodingKey { case summary, capacity, items, open }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decodeIfPresent(RsvpCounts.self, forKey: .summary) ?? RsvpCounts()
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
        items = try c.decodeIfPresent([ResponseRow].self, forKey: .items) ?? []
        open = try c.decodeIfPresent([ResponseRow].self, forKey: .open) ?? []
    }

    public enum Tab: String, Sendable, CaseIterable {
        case yes, no, open
    }

    public func count(_ tab: Tab) -> Int {
        switch tab {
        case .yes: return summary.yes
        case .no: return summary.no
        case .open: return open.count
        }
    }

    /// Zeilen eines Reiters; `search`: Teil des Namens, Groß/Klein egal.
    public func rows(_ tab: Tab, search: String = "") -> [ResponseRow] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = tab == .open ? open : items.filter { ($0.status == "yes") == (tab == .yes) }
        return q.isEmpty ? list : list.filter { $0.name.lowercased().contains(q) }
    }
}

/// Zeitangaben für Termine der Verwaltung.
public enum EventTime {
    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    public static func sameInstant(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        if let x = Zeit.parse(a), let y = Zeit.parse(b) { return x == y }
        return a == b
    }

    /// Ende eines Einzeltermins einer Serie: gleiche Dauer wie der erste Termin.
    public static func shiftEnd(start: String, end: String, occurrence: String) -> String {
        guard let s = Zeit.parse(start), let e = Zeit.parse(end), let o = Zeit.parse(occurrence) else { return occurrence }
        return iso(o.addingTimeInterval(e.timeIntervalSince(s)), timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
    }

    /// `HH:MM` (auch `H:MM`) → Stunde und Minute; nil, wenn es keine Uhrzeit ist.
    public static func parseTime(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60
        else { return nil }
        return (hour, minute)
    }

    static func iso(_ date: Date, timeZone: TimeZone) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        format.timeZone = timeZone
        return format.string(from: date)
    }

    /// Beginn und Ende für die Anfrage. `day`: `TT.MM.JJJJ` oder `JJJJ-MM-TT`. Ganztägig:
    /// Mitternacht in deutscher Zeit, auch wenn das Telefon woanders ist. Ohne Ende zwei
    /// Stunden; ein Ende vor dem Beginn liegt am nächsten Tag. nil bei ungültiger Eingabe.
    public static func range(day: String, start: String, end: String, allDay: Bool, timeZone: TimeZone = .current) -> (from: String, to: String)? {
        guard let iso = MasterData.parseDate(day) else { return nil }
        let numbers = iso.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = allDay ? berlin : timeZone
        func at(_ hour: Int, _ minute: Int) -> Date? {
            calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2], hour: hour, minute: minute))
        }
        if allDay {
            guard let midnight = at(0, 0) else { return nil }
            let text = self.iso(midnight, timeZone: berlin)
            return (text, text)
        }
        guard let from = parseTime(start), let begin = at(from.hour, from.minute) else { return nil }
        var finish = begin.addingTimeInterval(2 * 3600)
        if !end.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let to = parseTime(end), let sameDay = at(to.hour, to.minute) else { return nil }
            finish = sameDay > begin ? sameDay : (calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay)
        }
        return (self.iso(begin, timeZone: timeZone), self.iso(finish, timeZone: timeZone))
    }
}

/// Eingaben für „Neuer Termin“: einmalig, mit Sichtbarkeit und Zu-/Absagen.
public struct EventDraft: Equatable, Sendable {
    public var title = ""
    /// `TT.MM.JJJJ` oder `JJJJ-MM-TT`
    public var day = ""
    public var start = "19:00"
    public var end = ""
    public var allDay = false
    public var location = ""
    public var description = ""
    /// "members", "board" oder "public"
    public var visibility = "members"
    public var rsvp = false
    public var guests = false
    /// Anmeldeschluss als Tag; leer: keiner
    public var deadline = ""
    public var notify = false

    public init() {}

    public static var visibilities: [(key: String, label: String)] {
        [("members", tr("Mitglieder")), ("board", tr("nur Vorstand")), ("public", tr("nach außen öffentlich"))]
    }

    /// Zu- und Absagen nur bei Terminen für Mitglieder (wie im Browser).
    public func canRsvp(allowed: Bool) -> Bool { allowed && visibility != "board" }

    /// Inhalt der Anfrage; nil, solange Titel, Tag, Zeit oder Anmeldeschluss nicht stimmen.
    public func body(rsvpAllowed: Bool, timeZone: TimeZone = .current) -> [String: Any]? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let times = EventTime.range(day: day, start: start, end: end, allDay: allDay, timeZone: timeZone) else { return nil }
        let withRsvp = rsvp && canRsvp(allowed: rsvpAllowed)
        var out: [String: Any] = [
            "title": name, "starts_at": times.from, "ends_at": times.to, "all_day": allDay,
            "location": location.trimmingCharacters(in: .whitespaces),
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
            "visibility": visibility, "rsvp_enabled": withRsvp,
        ]
        if withRsvp {
            out["rsvp_guests"] = guests
            if !deadline.trimmingCharacters(in: .whitespaces).isEmpty {
                // Anmeldeschluss am Ende des Tages
                guard let last = EventTime.range(day: deadline, start: "23:59", end: "", allDay: false, timeZone: timeZone) else { return nil }
                out["rsvp_deadline"] = last.from
            }
            out["notify"] = notify
        }
        return out
    }
}

extension AdminClient {
    /// Termine der Einheit von `from` bis `to` (je `JJJJ-MM-TT`).
    public func events(from: String, to: String) async throws -> AdminEventList {
        try await api.expect("GET", base + "events/?from=\(queryValue(from))&to=\(queryValue(to))")
    }

    public func event(_ id: Int) async throws -> AdminEvent {
        try await api.expect("GET", base + "events/\(id)/")
    }

    /// Einmaligen Termin anlegen (Inhalt aus `EventDraft.body`).
    public func createEvent(_ values: [String: Any]) async throws -> (event: AdminEvent, change: AdminChange) {
        let response = try await api.raw("POST", base + "events/", json: values)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
        guard let event = try? JSONDecoder().decode(AdminEvent.self, from: response.body) else {
            throw ApiError(status: response.status, code: "format")
        }
        return (event, AdminChange(response))
    }

    /// Ganzen Termin absagen oder die Absage zurücknehmen; `notify`: Eingeladene per E-Mail.
    public func cancelEvent(_ id: Int, cancelled: Bool, note: String = "", notify: Bool = false) async throws -> AdminChange {
        try await change("PATCH", "events/\(id)/", ["is_cancelled": cancelled, "cancel_note": note, "notify": notify])
    }

    /// Einen Termin einer Serie absagen oder wieder wie in der Serie führen.
    public func cancelOccurrence(_ id: Int, originalStart: String, cancelled: Bool, note: String = "") async throws -> AdminChange {
        if cancelled {
            return try await change("PUT", "events/\(id)/occurrence/", ["original_start": originalStart, "is_cancelled": true, "note": note])
        }
        return try await change("DELETE", "events/\(id)/occurrence/", ["original_start": originalStart])
    }

    public func responses(_ id: Int) async throws -> AdminResponses {
        try await api.expect("GET", base + "events/\(id)/responses/")
    }

    /// Zu- oder Absage für ein Mitglied eintragen (z. B. nach einem Anruf); `status`: "yes" oder "no".
    public func setResponse(_ id: Int, membership: Int, status: String, guests: Int, note: String) async throws -> AdminChange {
        try await change("PUT", "events/\(id)/responses/", ["membership_id": membership, "status": status, "guests": guests, "note": note])
    }

    public func deleteResponse(_ id: Int, membership: Int) async throws -> AdminChange {
        try await change("DELETE", "events/\(id)/responses/\(membership)/", nil)
    }
}
