import Foundation

// Verbindliche Anmeldung mit Teilnahmegebühr am Termin (Modul „Anmeldungen“,
// GET/POST /api/portal/<Zugang>/events/<id>/registration/, Beschreibung in hubiplan/docs/app.md).
// Gleiche Formate und Fälle wie `Anmeldungen.kt` in der Android-App. Nichts davon wird gespeichert.

/// Kurzer Stand am Termin (`EventDetail.registration`).
public struct RegistrationBrief: Decodable, Equatable, Sendable {
    public var enabled: Bool
    /// not_yet, open, closed, full, cancelled
    public var state: String?
    public var stateText: String
    public var closesAt: String?
    public var free: Int?
    public var canRegister: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, state, free
        case stateText = "state_text"
        case closesAt = "closes_at"
        case canRegister = "can_register"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        state = try c.decodeIfPresent(String.self, forKey: .state)
        stateText = try c.decodeIfPresent(String.self, forKey: .stateText) ?? ""
        closesAt = try c.decodeIfPresent(String.self, forKey: .closesAt)
        free = try c.decodeIfPresent(Int.self, forKey: .free)
        canRegister = try c.decodeIfPresent(Bool.self, forKey: .canRegister) ?? false
    }
}

/// Preisstufe, die gerade gilt (oder als nächste kommt).
public struct RegistrationStep: Decodable, Equatable, Sendable {
    public var name: String
    public var amount: String
    public var untilDate: String?
    public var remaining: Int?

    enum CodingKeys: String, CodingKey {
        case name, amount, remaining
        case untilDate = "until_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        untilDate = try c.decodeIfPresent(String.self, forKey: .untilDate)
        remaining = try c.decodeIfPresent(Int.self, forKey: .remaining)
    }
}

public struct RegistrationPrice: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var nameEn: String
    /// all, members, guests
    public var applies: String
    public var ageFrom: Int?
    public var ageTo: Int?
    public var free: Int?
    public var isActive: Bool
    public var current: RegistrationStep?
    public var next: RegistrationStep?

    enum CodingKeys: String, CodingKey {
        case id, name, applies, free, current, next
        case nameEn = "name_en"
        case ageFrom = "age_from"
        case ageTo = "age_to"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn) ?? ""
        applies = try c.decodeIfPresent(String.self, forKey: .applies) ?? "all"
        ageFrom = try c.decodeIfPresent(Int.self, forKey: .ageFrom)
        ageTo = try c.decodeIfPresent(Int.self, forKey: .ageTo)
        free = try c.decodeIfPresent(Int.self, forKey: .free)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        current = try c.decodeIfPresent(RegistrationStep.self, forKey: .current)
        next = try c.decodeIfPresent(RegistrationStep.self, forKey: .next)
    }

    /// Name in der Sprache der App; ohne englischen Namen der deutsche.
    public var label: String { Texte.language == "en" && !nameEn.isEmpty ? nameEn : name }

    public var hasAge: Bool { ageFrom != nil || ageTo != nil }

    /// Gerade buchbar: aktiv, mit aktueller Preisstufe und nicht ausgebucht.
    public var bookable: Bool { isActive && current != nil && (free.map { $0 > 0 } ?? true) }

    public func fits(member: Bool) -> Bool {
        switch applies {
        case "members": return member
        case "guests": return !member
        default: return true
        }
    }

    /// „6 bis 13 Jahre“, „ab 18 Jahren“, „bis 5 Jahre“; ohne Altersgrenze nil.
    public var ageText: String? {
        switch (ageFrom, ageTo) {
        case let (a?, b?): return tr("{a} bis {b} Jahre", ["a": a, "b": b])
        case let (a?, nil): return tr("ab {a} Jahren", ["a": a])
        case let (nil, b?): return tr("bis {b} Jahre", ["b": b])
        default: return nil
        }
    }
}

public struct RegistrationOffer: Decodable, Equatable, Sendable {
    public var state: String
    public var stateText: String
    public var closesAt: String?
    public var free: Int?
    public var maxPersons: Int
    public var guestsAllowed: Bool
    public var terms: String
    public var prices: [RegistrationPrice]

    enum CodingKeys: String, CodingKey {
        case state, free, terms, prices
        case stateText = "state_text"
        case closesAt = "closes_at"
        case maxPersons = "max_persons"
        case guestsAllowed = "guests_allowed"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "open"
        stateText = try c.decodeIfPresent(String.self, forKey: .stateText) ?? ""
        closesAt = try c.decodeIfPresent(String.self, forKey: .closesAt)
        free = try c.decodeIfPresent(Int.self, forKey: .free)
        maxPersons = try c.decodeIfPresent(Int.self, forKey: .maxPersons) ?? 1
        guestsAllowed = try c.decodeIfPresent(Bool.self, forKey: .guestsAllowed) ?? false
        terms = try c.decodeIfPresent(String.self, forKey: .terms) ?? ""
        prices = try c.decodeIfPresent([RegistrationPrice].self, forKey: .prices) ?? []
    }

    /// Tarife für ein Mitglied bzw. einen Gast, die sich gerade buchen lassen.
    public func prices(member: Bool) -> [RegistrationPrice] { prices.filter { $0.bookable && $0.fits(member: member) } }
}

public struct RegistrationParticipant: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var priceName: String
    public var amount: String
    /// active, cancelled
    public var status: String

    enum CodingKeys: String, CodingKey {
        case id, name, amount, status
        case priceName = "price_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        priceName = try c.decodeIfPresent(String.self, forKey: .priceName) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
    }

    /// „Kim Muster: Kinder, 15,00 €“ bzw. mit „(abgemeldet)“.
    public var line: String {
        let price = (Geld.cents(amount) ?? 0) > 0 ? "\(priceName), \(Geld.format(amount))" : priceName
        return "\(name): \(price)" + (status == "active" ? "" : " (\(tr("abgemeldet")))")
    }
}

public struct RegistrationInvoice: Decodable, Equatable, Sendable {
    public var number: String
    public var total: String
    public var paid: String
    public var dueDate: String?

    enum CodingKeys: String, CodingKey {
        case number, total, paid
        case dueDate = "due_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        total = try c.decodeIfPresent(String.self, forKey: .total) ?? "0"
        paid = try c.decodeIfPresent(String.self, forKey: .paid) ?? "0"
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
    }
}

public struct MyRegistration: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var number: String
    /// registered, cancelled
    public var status: String
    public var total: String
    /// free, open, partly, paid, cancelled
    public var paidState: String
    public var participants: [RegistrationParticipant]
    public var invoice: RegistrationInvoice?

    enum CodingKeys: String, CodingKey {
        case id, number, status, total, participants, invoice
        case paidState = "paid_state"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "registered"
        total = try c.decodeIfPresent(String.self, forKey: .total) ?? "0"
        paidState = try c.decodeIfPresent(String.self, forKey: .paidState) ?? "open"
        participants = try c.decodeIfPresent([RegistrationParticipant].self, forKey: .participants) ?? []
        invoice = try c.decodeIfPresent(RegistrationInvoice.self, forKey: .invoice)
    }

    public var active: Bool { status == "registered" }

    /// Zahlungsstand in Worten, wie in der Android-App.
    public var paidText: String {
        switch paidState {
        case "free": return tr("kostenlos")
        case "paid": return tr("bezahlt")
        case "partly": return tr("teilweise bezahlt")
        case "cancelled": return tr("abgemeldet")
        default: return tr("offen")
        }
    }
}

public struct RegistrationPerson: Decodable, Equatable, Sendable, Identifiable {
    public var membershipId: Int
    public var name: String
    public var registered: Bool
    public var hasBirthDate: Bool
    public var id: Int { membershipId }

    enum CodingKeys: String, CodingKey {
        case name, registered
        case membershipId = "membership_id"
        case hasBirthDate = "has_birth_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        membershipId = try c.decode(Int.self, forKey: .membershipId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        registered = try c.decodeIfPresent(Bool.self, forKey: .registered) ?? false
        hasBirthDate = try c.decodeIfPresent(Bool.self, forKey: .hasBirthDate) ?? false
    }
}

public struct MemberRegistration: Decodable, Equatable, Sendable {
    public var offer: RegistrationOffer
    public var canCancel: Bool
    public var persons: [RegistrationPerson]
    public var mine: [MyRegistration]

    enum CodingKeys: String, CodingKey {
        case offer, persons, mine
        case canCancel = "can_cancel"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offer = try c.decode(RegistrationOffer.self, forKey: .offer)
        canCancel = try c.decodeIfPresent(Bool.self, forKey: .canCancel) ?? false
        persons = try c.decodeIfPresent([RegistrationPerson].self, forKey: .persons) ?? []
        mine = try c.decodeIfPresent([MyRegistration].self, forKey: .mine) ?? []
    }
}

/// Eine Person im Anmeldeformular: Mitglied (mit `membershipId`) oder Gast (mit `name`).
public struct RegistrationChoice: Equatable, Sendable {
    public var membershipId: Int?
    public var name: String
    public var priceId: Int
    /// ISO-Datum, nur bei Tarifen mit Altersgrenze ohne bekanntes Geburtsdatum
    public var birthDate: String?

    public init(membershipId: Int?, name: String = "", priceId: Int, birthDate: String? = nil) {
        self.membershipId = membershipId
        self.name = name
        self.priceId = priceId
        self.birthDate = birthDate
    }
}

public enum RegistrationGap: Equatable, Sendable {
    case nobody, tooMany, name, birthDate, terms

    public func text(max: Int) -> String {
        switch self {
        case .nobody: return tr("Bitte mindestens eine Person anmelden.")
        case .tooMany: return tr("Höchstens {n} Personen je Anmeldung.", ["n": max])
        case .name: return tr("Bitte für jede Person den Namen angeben.")
        case .birthDate: return tr("Für diesen Tarif brauchen wir das Geburtsdatum.")
        case .terms: return tr("Bitte die Teilnahmebedingungen bestätigen.")
        }
    }
}

public enum Teilnahme {
    /// Inhalt von POST …/registration/ (Kennzeichen `app`: angemeldet über die App).
    public static func payload(_ persons: [RegistrationChoice], note: String, termsAccepted: Bool) -> [String: Any] {
        let list: [[String: Any]] = persons.map { p in
            var item: [String: Any] = ["membership_id": p.membershipId.map { $0 as Any } ?? NSNull(), "price_id": p.priceId]
            if p.membershipId == nil { item["name"] = p.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let birth = p.birthDate { item["birth_date"] = birth }
            return item
        }
        return [
            "persons": list,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
            "terms_accepted": termsAccepted,
            "app": true,
        ]
    }

    /// Voraussichtliche Summe in Cent nach den aktuellen Preisstufen; verbindlich rechnet der Server.
    public static func sumCents(_ offer: RegistrationOffer, _ persons: [RegistrationChoice]) -> Int {
        persons.reduce(0) { sum, p in
            let amount = offer.prices.first { $0.id == p.priceId }?.current?.amount
            return sum + (amount.flatMap(Geld.cents) ?? 0)
        }
    }

    /// Lücke im Formular vor dem Abschicken (wie auf dem Server), sonst nil.
    public static func missing(
        _ offer: RegistrationOffer,
        _ persons: [RegistrationChoice],
        needsBirthDate: (RegistrationChoice) -> Bool,
        termsAccepted: Bool
    ) -> RegistrationGap? {
        if persons.isEmpty { return .nobody }
        if persons.count > offer.maxPersons { return .tooMany }
        if persons.contains(where: { $0.membershipId == nil && $0.name.trimmingCharacters(in: .whitespaces).isEmpty }) { return .name }
        if persons.contains(where: { needsBirthDate($0) && $0.birthDate == nil }) { return .birthDate }
        if !offer.terms.isEmpty && !termsAccepted { return .terms }
        return nil
    }

    /// „Erwachsene: 29,00 € (Early Bird) · danach 35,00 €“
    public static func priceLine(_ p: RegistrationPrice) -> String {
        guard let now = p.current else { return p.label + ": " + tr("nicht mehr buchbar") }
        let step = now.name.isEmpty ? "" : " (\(now.name))"
        let next = p.next.map { tr(" · danach {amount}", ["amount": Geld.format($0.amount)]) } ?? ""
        return p.label + ": " + Geld.format(now.amount) + step + next
    }

    /// Zusatzzeile: Alter, nur Mitglieder/Gäste, Restplätze zum Preis; leer, wenn nichts gilt.
    public static func priceExtra(_ p: RegistrationPrice) -> String {
        var parts: [String] = []
        if let age = p.ageText { parts.append(age) }
        if p.applies == "members" { parts.append(tr("nur Mitglieder")) }
        if p.applies == "guests" { parts.append(tr("nur Gäste")) }
        if let left = p.current?.remaining { parts.append(tr("noch {n} zu diesem Preis", ["n": left])) }
        return parts.joined(separator: " · ")
    }
}

extension Api {
    public func memberRegistration(accessId: Int, eventId: Int) async throws -> MemberRegistration {
        try await expect("GET", "/api/portal/\(accessId)/events/\(eventId)/registration/")
    }

    public func register(accessId: Int, eventId: Int, payload: [String: Any]) async throws -> MemberRegistration {
        try await expect("POST", "/api/portal/\(accessId)/events/\(eventId)/registration/", json: payload)
    }

    public func cancelRegistration(accessId: Int, eventId: Int, registrationId: Int) async throws -> MemberRegistration {
        try await expect("POST", "/api/portal/\(accessId)/events/\(eventId)/registration/\(registrationId)/cancel/", json: [:])
    }
}
