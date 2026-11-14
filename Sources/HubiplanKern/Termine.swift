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

extension Api {
    /// Termine des Zugangs zwischen `from` und `to` (je `JJJJ-MM-TT`).
    public func events(accessId: Int, from: String, to: String) async throws -> [Occurrence] {
        let list: EventList = try await expect("GET", "/api/portal/\(accessId)/events/?from=\(from)&to=\(to)")
        return list.items
    }

    /// Zu- oder Absage: `status` "yes", "no" oder "maybe".
    public func respond(accessId: Int, eventId: Int, status: String, guests: Int = 0, note: String = "") async throws {
        let _: Ignored = try await expect(
            "PUT", "/api/portal/\(accessId)/events/\(eventId)/response/",
            json: ["status": status, "guests": guests, "note": note]
        )
    }

    /// Rückmeldung zurücknehmen.
    public func withdraw(accessId: Int, eventId: Int) async throws {
        let _: Ignored = try await expect("DELETE", "/api/portal/\(accessId)/events/\(eventId)/response/")
    }
}
