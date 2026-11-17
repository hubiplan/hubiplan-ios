import Foundation

public struct Category: Decodable, Equatable, Sendable {
    public var name: String
    public var color: String?

    enum CodingKeys: String, CodingKey { case name, color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color)
    }
}

/// Einzeltermin (bei Serien eine Wiederholung).
public struct Occurrence: Decodable, Equatable, Identifiable, Sendable {
    public var key: String
    public var eventId: Int
    public var title: String
    public var startsAt: String
    public var endsAt: String
    public var allDay: Bool
    public var location: String
    /// Anschrift des Ortes und Hinweis zum Termin (ältere Stände: fehlen)
    public var address: String
    public var note: String
    public var category: Category?
    public var isCancelled: Bool
    public var owner: String
    public var rsvpEnabled: Bool
    /// "yes", "no", "maybe" oder nil (noch keine Rückmeldung)
    public var myResponse: String?
    public var rsvpDeadline: String?

    public var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, title, location, address, note, category, owner
        case eventId = "event_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case isCancelled = "is_cancelled"
        case rsvpEnabled = "rsvp_enabled"
        case myResponse = "my_response"
        case rsvpDeadline = "rsvp_deadline"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        eventId = try c.decode(Int.self, forKey: .eventId)
        title = try c.decode(String.self, forKey: .title)
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? false
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        category = try c.decodeIfPresent(Category.self, forKey: .category)
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        rsvpEnabled = try c.decodeIfPresent(Bool.self, forKey: .rsvpEnabled) ?? false
        myResponse = try c.decodeIfPresent(String.self, forKey: .myResponse)
        rsvpDeadline = try c.decodeIfPresent(String.self, forKey: .rsvpDeadline)
    }

    public var start: Date? { Zeit.parse(startsAt) }
    public var end: Date? { Zeit.parse(endsAt) }

    /// Rückmeldung ist gefragt, fehlt aber noch (und der Termin findet statt).
    public var responseMissing: Bool { rsvpEnabled && !isCancelled && myResponse == nil }
}

struct EventList: Decodable {
    var items: [Occurrence]
}

/// Antwort, deren Inhalt die App (noch) nicht braucht.
struct Ignored: Decodable {}

/// Zeitangaben der Schnittstelle (ISO 8601, mit oder ohne Sekundenbruchteile).
public enum Zeit {
    public static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fraction = ISO8601DateFormatter()
        fraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fraction.date(from: text)
    }

    /// Tag als `JJJJ-MM-TT` für `from`/`to` der Terminliste.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Eigene Rückmeldung zu einem Termin (Detail).
public struct MyResponse: Decodable, Equatable, Sendable {
    /// "yes", "no" oder "maybe"
    public var status: String
    public var guests: Int
    public var note: String

    enum CodingKeys: String, CodingKey { case status, guests, note }

    public init(status: String, guests: Int = 0, note: String = "") {
        self.status = status
        self.guests = guests
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        guests = try c.decodeIfPresent(Int.self, forKey: .guests) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// Zu- und Absagen eines Termins aus Sicht des Mitglieds (wie `Rsvp` in der Android-App).
public struct Rsvp: Decodable, Equatable, Sendable {
    public var enabled: Bool
    public var deadline: String?
    public var capacity: Int?
    public var guestsAllowed: Bool
    public var maxGuests: Int
    /// Freie Plätze (nur mit Höchstzahl)
    public var free: Int?
    public var mine: MyResponse?
    public var canRespond: Bool
    /// Warum keine Rückmeldung möglich ist (Anmeldeschluss vorbei, ausgebucht, nicht eingeladen)
    public var reason: String
    /// Je Termin einschaltbar: „Vielleicht“ und Bemerkung (mit eigener Frage)
    public var maybeAllowed: Bool
    public var noteAllowed: Bool
    public var noteQuestion: String

    enum CodingKeys: String, CodingKey {
        case enabled, deadline, capacity, free, mine, reason
        case guestsAllowed = "guests_allowed"
        case maxGuests = "max_guests"
        case canRespond = "can_respond"
        case maybeAllowed = "maybe_allowed"
        case noteAllowed = "note_allowed"
        case noteQuestion = "note_question"
    }

    public init() {
        enabled = false
        guestsAllowed = false
        maxGuests = 10
        canRespond = false
        reason = ""
        maybeAllowed = false
        noteAllowed = false
        noteQuestion = ""
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline)
        capacity = try c.decodeIfPresent(Int.self, forKey: .capacity)
        guestsAllowed = try c.decodeIfPresent(Bool.self, forKey: .guestsAllowed) ?? false
        maxGuests = try c.decodeIfPresent(Int.self, forKey: .maxGuests) ?? 10
        free = try c.decodeIfPresent(Int.self, forKey: .free)
        mine = try c.decodeIfPresent(MyResponse.self, forKey: .mine)
        canRespond = try c.decodeIfPresent(Bool.self, forKey: .canRespond) ?? false
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        maybeAllowed = try c.decodeIfPresent(Bool.self, forKey: .maybeAllowed) ?? false
        noteAllowed = try c.decodeIfPresent(Bool.self, forKey: .noteAllowed) ?? false
        noteQuestion = try c.decodeIfPresent(String.self, forKey: .noteQuestion) ?? ""
    }
}

/// Routenlinks zum Ort (OpenStreetMap, Google Maps).
public struct MapLinks: Decodable, Equatable, Sendable {
    public var osm: String?
    public var google: String?

    public init(osm: String? = nil, google: String? = nil) {
        self.osm = osm
        self.google = google
    }
}

/// Anhang eines Termins.
public struct EventFile: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    /// Anzeigename; bei verknüpften Dokumenten der Titel aus der Ablage
    public var name: String
    public var contentType: String
    /// Dateiname (bei Dokumenten die neueste Fassung); leer bei älteren Servern
    public var fileName: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case contentType = "content_type"
        case fileName = "file_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
    }

    /// Name der Datei zum Ansehen (mit Endung, soweit bekannt).
    public var shownName: String { fileName.isEmpty ? name : fileName }
}

/// Ein Termin mit allen Angaben (Detailseite, wie `EventDetail` in der Android-App).
/// Bei Serien gelten Datum, Ort und Absage des gewählten Einzeltermins (`Occurrence`).
public struct EventDetail: Decodable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var description: String
    public var location: String
    public var address: String
    public var directions: String
    public var latitude: Double?
    public var longitude: Double?
    public var mapLinks: MapLinks
    public var isCancelled: Bool
    public var cancelNote: String
    public var owner: String
    public var rsvp: Rsvp
    public var attachments: [EventFile]

    enum CodingKeys: String, CodingKey {
        case id, title, description, location, address, directions, latitude, longitude, owner, rsvp, attachments
        case mapLinks = "map_links"
        case isCancelled = "is_cancelled"
        case cancelNote = "cancel_note"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        directions = try c.decodeIfPresent(String.self, forKey: .directions) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        mapLinks = try c.decodeIfPresent(MapLinks.self, forKey: .mapLinks) ?? MapLinks()
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        cancelNote = try c.decodeIfPresent(String.self, forKey: .cancelNote) ?? ""
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        rsvp = try c.decodeIfPresent(Rsvp.self, forKey: .rsvp) ?? Rsvp()
        attachments = try c.decodeIfPresent([EventFile].self, forKey: .attachments) ?? []
    }
}

/// Texte zur eigenen Rückmeldung, gleich wie in der Android-App (UX-Audit 16.11., IOS-05).
public enum Rueckmeldung {
    /// Abzeichen in der Terminliste: „Zugesagt“, „Nicht dabei“, „Vielleicht“, „Noch offen“;
    /// ein ausgefallener Termin heißt „Abgesagt“. Ohne Rückmeldung am Termin: nil.
    public static func abzeichen(abgesagt: Bool, rsvp: Bool, antwort: String?) -> String? {
        if abgesagt { return tr("Abgesagt") }
        guard rsvp else { return nil }
        switch antwort {
        case "yes": return tr("Zugesagt")
        case "no": return tr("Nicht dabei")
        case "maybe": return tr("Vielleicht")
        default: return tr("Noch offen")
        }
    }

    /// Satz zum Stand in der Detailseite.
    public static func stand(_ mine: MyResponse?) -> String {
        switch mine?.status {
        case "yes":
            let count = mine?.guests ?? 0
            return count > 0
                ? trn("Du hast zugesagt (mit 1 Begleitung).", "Du hast zugesagt (mit {n} Begleitungen).", count)
                : tr("Du hast zugesagt.")
        case "no": return tr("Du hast abgesagt.")
        case "maybe": return tr("Du hast mit „Vielleicht“ geantwortet.")
        default: return tr("Du hast dich noch nicht zurückgemeldet.")
        }
    }

    /// Bestätigung nach einer Änderung; `status` nil: zurückgenommen.
    public static func gespeichert(_ status: String?) -> String {
        switch status {
        case "yes": return tr("Deine Zusage ist gespeichert.")
        case "no": return tr("Deine Absage ist gespeichert.")
        case "maybe": return tr("Deine Antwort „Vielleicht“ ist gespeichert.")
        default: return tr("Deine Rückmeldung ist zurückgenommen.")
        }
    }

    /// Höchstlänge der Bemerkung (wie Android und Server).
    public static let maxNote = 200
}

/// Fehler bei Rückmeldungen, je Termin gemerkt (UX-Audit 16.11., IOS-01): Ein Abgleich der
/// Liste löscht sie nicht, nur eine neue Rückmeldung zu demselben Termin oder ein Kontowechsel.
public struct RueckmeldungsFehler: Equatable, Sendable {
    private var texts: [Int: String] = [:]

    public init() {}

    public subscript(eventId: Int) -> String? { texts[eventId] }

    /// Vor einer neuen Rückmeldung: alten Fehler dieses Termins vergessen.
    public mutating func start(_ eventId: Int) { texts[eventId] = nil }

    public mutating func failed(_ eventId: Int, _ text: String) { texts[eventId] = text }

    /// Nach dem Abgleich: Fehler zu Terminen, die es nicht mehr gibt, fallen weg; alle anderen bleiben.
    public mutating func keep(only events: [Occurrence]) {
        let ids = Set(events.map(\.eventId))
        texts = texts.filter { ids.contains($0.key) }
    }

    public var isEmpty: Bool { texts.isEmpty }
}

extension Api {
    /// Termine des Zugangs zwischen `from` und `to` (je `JJJJ-MM-TT`).
    public func events(accessId: Int, from: String, to: String) async throws -> [Occurrence] {
        let list: EventList = try await expect("GET", "/api/portal/\(accessId)/events/?from=\(from)&to=\(to)")
        return list.items
    }

    /// Ein Termin mit Beschreibung, Anfahrt, Anhängen und Rückmeldung.
    public func event(accessId: Int, eventId: Int) async throws -> EventDetail {
        try await expect("GET", "/api/portal/\(accessId)/events/\(eventId)/")
    }

    /// Zu- oder Absage: `status` "yes", "no" oder "maybe". Gibt den Termin danach zurück
    /// (ältere Stände ohne Inhalt: nil).
    @discardableResult
    public func respond(accessId: Int, eventId: Int, status: String, guests: Int = 0, note: String = "") async throws -> EventDetail? {
        let response = try await checked("PUT", "/api/portal/\(accessId)/events/\(eventId)/response/", json: [
            "status": status, "guests": guests, "note": String(note.prefix(Rueckmeldung.maxNote)),
        ])
        return try? JSONDecoder().decode(EventDetail.self, from: response.body)
    }

    /// Rückmeldung zurücknehmen.
    @discardableResult
    public func withdraw(accessId: Int, eventId: Int) async throws -> EventDetail? {
        let response = try await checked("DELETE", "/api/portal/\(accessId)/events/\(eventId)/response/")
        return try? JSONDecoder().decode(EventDetail.self, from: response.body)
    }

    /// Anhang eines Termins (zum Ansehen).
    public func eventAttachment(accessId: Int, eventId: Int, attachmentId: Int) async throws -> Data {
        try await file("/api/portal/\(accessId)/events/\(eventId)/attachments/\(attachmentId)/")
    }
}
