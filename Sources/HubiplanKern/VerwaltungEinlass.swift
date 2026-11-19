import Foundation

// Einlass vor Ort bei Terminen mit Anmeldung (HUBIplan A6/A7), wie in der Android-App:
// Liste aller Angemeldeten, Karte scannen oder von Hand einlassen, Abendkasse über die
// Barzahlung zur Rechnung. GET/POST …/events/<id>/registration/checkin/ (hubiplan docs/app.md)

public struct CheckInBooking: Decodable, Equatable, Sendable {
    public var name: String
    public var redeemedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case redeemedAt = "redeemed_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        redeemedAt = try c.decodeIfPresent(String.self, forKey: .redeemedAt)
    }
}

public struct CheckInRow: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var priceName: String
    public var number: String
    public var contact: String
    public var paidState: String
    public var invoiceId: Int?
    public var invoiceNumber: String
    public var outstanding: String
    public var checkedInAt: String?
    public var checkedInVia: String
    public var minor: Bool
    public var bookings: [CheckInBooking]

    enum CodingKeys: String, CodingKey {
        case id, name, number, contact, outstanding, minor, bookings
        case priceName = "price_name"
        case paidState = "paid_state"
        case invoiceId = "invoice_id"
        case invoiceNumber = "invoice_number"
        case checkedInAt = "checked_in_at"
        case checkedInVia = "checked_in_via"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        priceName = try c.decodeIfPresent(String.self, forKey: .priceName) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        contact = try c.decodeIfPresent(String.self, forKey: .contact) ?? ""
        paidState = try c.decodeIfPresent(String.self, forKey: .paidState) ?? ""
        invoiceId = try c.decodeIfPresent(Int.self, forKey: .invoiceId)
        invoiceNumber = try c.decodeIfPresent(String.self, forKey: .invoiceNumber) ?? ""
        outstanding = try c.decodeIfPresent(String.self, forKey: .outstanding) ?? "0.00"
        checkedInAt = try c.decodeIfPresent(String.self, forKey: .checkedInAt)
        checkedInVia = try c.decodeIfPresent(String.self, forKey: .checkedInVia) ?? ""
        minor = try c.decodeIfPresent(Bool.self, forKey: .minor) ?? false
        bookings = try c.decodeIfPresent([CheckInBooking].self, forKey: .bookings) ?? []
    }

    public var checkedIn: Bool { checkedInAt != nil }

    /// Noch etwas zu zahlen (Abendkasse).
    public var owes: Bool { invoiceId != nil && (Geld.cents(outstanding) ?? 0) > 0 }

    /// Zweite Zeile: Anmeldenummer, Tarif, Zahlungsstand.
    public var detail: String {
        var parts = [number, priceName].filter { !$0.isEmpty }
        switch paidState {
        case "paid": parts.append(tr("bezahlt"))
        case "open", "partly": parts.append(tr("offen: {amount}", ["amount": Geld.format(outstanding)]))
        case "free": parts.append(tr("kostenlos"))
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

public struct CheckInList: Decodable, Equatable, Sendable {
    public var eventId: Int
    public var title: String
    public var canEdit: Bool
    public var canCash: Bool
    public var participants: [CheckInRow]
    public var checkedIn: Int

    enum CodingKeys: String, CodingKey {
        case title, participants
        case eventId = "event_id"
        case canEdit = "can_edit"
        case canCash = "can_cash"
        case checkedIn = "checked_in"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try c.decodeIfPresent(Int.self, forKey: .eventId) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        canCash = try c.decodeIfPresent(Bool.self, forKey: .canCash) ?? false
        participants = try c.decodeIfPresent([CheckInRow].self, forKey: .participants) ?? []
        checkedIn = try c.decodeIfPresent(Int.self, forKey: .checkedIn) ?? participants.filter(\.checkedIn).count
    }

    /// Suche nach Name, Anmeldenummer oder Anmeldendem, ohne Groß- und Kleinschreibung.
    public func filtered(_ query: String) -> [CheckInRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return participants }
        return participants.filter { r in [r.name, r.number, r.contact].contains { $0.lowercased().contains(q) } }
    }

    /// Liste mit einer geänderten Zeile und neu gezählten Eingelassenen.
    public func with(_ row: CheckInRow) -> CheckInList {
        var copy = self
        copy.participants = participants.map { $0.id == row.id ? row : $0 }
        copy.checkedIn = copy.participants.filter(\.checkedIn).count
        return copy
    }

    /// So zeigen, wie die Liste nach den wartenden Schritten aussieht.
    public func with(pending queue: [PendingCheckIn], now: String) -> CheckInList {
        queue.reduce(self) { list, step in
            guard var row = list.participants.first(where: { $0.id == step.participant }) else { return list }
            row.checkedInAt = step.undo ? nil : (row.checkedInAt ?? now)
            return list.with(row)
        }
    }

    /// Text „{n} von {count} eingelassen“.
    public var stand: String {
        tr("{n} von {count} eingelassen", ["n": checkedIn, "count": participants.count])
    }
}

public struct CheckInResult: Decodable, Equatable, Sendable {
    public var result: String
    public var message: String
    public var participant: CheckInRow?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        result = try c.decodeIfPresent(String.self, forKey: .result) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        participant = try c.decodeIfPresent(CheckInRow.self, forKey: .participant)
    }

    enum CodingKeys: String, CodingKey { case result, message, participant }

    /// Grün nur bei erfolgreichem Einlass, alles andere fällt auf.
    public var good: Bool { result == "ok" || result == "undone" }
}

/// Ohne Netz abgehakt: wird beim nächsten Kontakt nachgereicht (Reihenfolge bleibt).
public struct PendingCheckIn: Equatable, Sendable {
    public var participant: Int
    public var undo: Bool

    public init(participant: Int, undo: Bool) {
        self.participant = participant
        self.undo = undo
    }

    /// Neuer Schritt ersetzt einen älteren für dieselbe Person; Einlassen und Zurücknehmen heben sich auf.
    public static func queue(_ queue: [PendingCheckIn], _ step: PendingCheckIn) -> [PendingCheckIn] {
        let old = queue.first { $0.participant == step.participant }
        let rest = queue.filter { $0.participant != step.participant }
        if let old, old.undo != step.undo { return rest }
        return rest + [step]
    }
}

/// Wie oft die Einlassliste neu geladen wird (wie im Browser und in Android).
public let checkInRefreshSeconds: UInt64 = 10

extension AdminClient {
    public func checkIns(_ eventId: Int) async throws -> CheckInList {
        try await api.expect("GET", base + "events/\(eventId)/registration/checkin/")
    }

    /// Karte (`code`) oder Person (`participant`) einlassen, mit `undo` zurücknehmen.
    public func checkIn(_ eventId: Int, code: String? = nil, participant: Int? = nil, undo: Bool = false) async throws -> CheckInResult {
        var body: [String: Any] = [:]
        if let code { body["code"] = String(code.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)) }
        if let participant { body["participant"] = participant }
        if undo { body["undo"] = true }
        return try await api.expect("POST", base + "events/\(eventId)/registration/checkin/", json: body)
    }
}
