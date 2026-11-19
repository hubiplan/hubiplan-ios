import Foundation

/// Zusatzleistungen, Zusatzfragen, Allergien und Erziehungsberechtigte bei der Anmeldung
/// (HUBIplan A5, F11, F13), gleiche Fälle wie `Anmeldungen.kt` in der Android-App.

/// Zusatzleistung mit Auswahl, z. B. Busfahrt oder Menü.
public struct AddOn: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var nameEn: String
    /// meal, other
    public var kind: String
    /// person, registration
    public var per: String
    public var required: Bool
    public var isActive: Bool
    public var choices: [AddOnChoice]

    enum CodingKeys: String, CodingKey {
        case id, name, kind, per, required, choices
        case nameEn = "name_en"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "other"
        per = try c.decodeIfPresent(String.self, forKey: .per) ?? "person"
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        choices = try c.decodeIfPresent([AddOnChoice].self, forKey: .choices) ?? []
    }

    public var label: String { Texte.language == "en" && !nameEn.isEmpty ? nameEn : name }
}

public struct AddOnChoice: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var nameEn: String
    public var amount: String
    public var free: Int?
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, amount, free
        case nameEn = "name_en"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        free = try c.decodeIfPresent(Int.self, forKey: .free)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    public var full: Bool { free == 0 }

    /// „Lachs (+3,00 €)“ bzw. „… – ausgebucht“
    public var label: String {
        let base = Texte.language == "en" && !nameEn.isEmpty ? nameEn : name
        let price = (Geld.cents(amount) ?? 0) > 0 ? " (+\(Geld.format(amount)))" : ""
        return base + price + (full ? " – " + tr("ausgebucht") : "")
    }
}

/// Zusatzfrage; "health" sind Allergien und Unverträglichkeiten (freiwillig, mit Einwilligung).
public struct Question: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    public var textEn: String
    /// text, yesno, choice, health
    public var kind: String
    public var choices: [String]
    public var required: Bool
    public var per: String
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, kind, choices, required, per
        case textEn = "text_en"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        textEn = try c.decodeIfPresent(String.self, forKey: .textEn) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        choices = try c.decodeIfPresent([String].self, forKey: .choices) ?? []
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        per = try c.decodeIfPresent(String.self, forKey: .per) ?? "registration"
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    public var label: String { Texte.language == "en" && !textEn.isEmpty ? textEn : text }
}

public struct Booking: Decodable, Equatable, Sendable {
    public var name: String
    public var amount: String

    enum CodingKeys: String, CodingKey { case name, amount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
    }

    /// „Busfahrt, Menü: Lachs (3,00 €)“
    public static func line(_ bookings: [Booking]) -> String {
        bookings.map { (Geld.cents($0.amount) ?? 0) > 0 ? "\($0.name) (\(Geld.format($0.amount)))" : $0.name }
            .joined(separator: ", ")
    }
}

/// Erziehungsberechtigte Person bei Teilnehmenden unter 18 (F13).
public struct Guardian: Codable, Equatable, Sendable {
    public var name: String
    public var phone: String
    public var email: String
    public var address: String

    public init(name: String = "", phone: String = "", email: String = "", address: String = "") {
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
    }

    enum CodingKeys: String, CodingKey { case name, phone, email, address }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
    }

    private static func filled(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespaces).isEmpty }

    public var complete: Bool { Self.filled(name) && Self.filled(phone) && Self.filled(email) }
    var given: Bool { Self.filled(name) || Self.filled(phone) }
}

/// Antwort auf eine Zusatzfrage: Text (auch Auswahl) oder Ja/Nein.
public enum Answer: Equatable, Sendable {
    case text(String)
    case yes(Bool)

    var json: Any {
        switch self {
        case .text(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .yes(let b): return b
        }
    }

    var blank: Bool {
        if case .text(let s) = self { return s.trimmingCharacters(in: .whitespaces).isEmpty }
        return false
    }
}

/// Zusatzangaben einer Person (oder der ganzen Anmeldung).
public struct RegistrationExtras: Equatable, Sendable {
    /// Zusatzleistung → Auswahl
    public var addons: [Int: Int]
    /// Frage → Antwort
    public var answers: [Int: Answer]
    public var health: String
    public var guardians: [Guardian]

    public init(addons: [Int: Int] = [:], answers: [Int: Answer] = [:], health: String = "", guardians: [Guardian] = []) {
        self.addons = addons
        self.answers = answers
        self.health = health
        self.guardians = guardians
    }

    /// Aufpreis der gewählten Zusatzleistungen in Cent.
    public func cents(_ offer: RegistrationOffer) -> Int {
        addons.reduce(0) { sum, pair in
            let choice = offer.addons.first { $0.id == pair.key }?.choices.first { $0.id == pair.value }
            return sum + (choice.flatMap { Geld.cents($0.amount) } ?? 0)
        }
    }

    /// Fehlt eine Pflichtangabe?
    public func gap(_ offer: RegistrationOffer, per: String, minor: Bool) -> RegistrationGap? {
        if offer.addons(per: per).contains(where: { $0.required && addons[$0.id] == nil }) { return .addon }
        if offer.questions(per: per).contains(where: { q in
            q.required && q.kind != "health" && (answers[q.id].map(\.blank) ?? true)
        }) { return .answer }
        if minor && !(guardians.first?.complete ?? false) { return .guardian }
        return nil
    }

    func json(minor: Bool, health asksHealth: Bool) -> [String: Any] {
        var result: [String: Any] = [:]
        if !addons.isEmpty {
            result["addons"] = Dictionary(uniqueKeysWithValues: addons.map { (String($0.key), $0.value) })
        }
        let given = answers.filter { !$0.value.blank }
        if !given.isEmpty {
            result["answers"] = Dictionary(uniqueKeysWithValues: given.map { (String($0.key), $0.value.json) })
        }
        let h = health.trimmingCharacters(in: .whitespacesAndNewlines)
        if asksHealth && !h.isEmpty { result["health"] = h }
        if minor {
            result["guardians"] = guardians.filter(\.given).map { g in
                [
                    "name": g.name.trimmingCharacters(in: .whitespaces),
                    "phone": g.phone.trimmingCharacters(in: .whitespaces),
                    "email": g.email.trimmingCharacters(in: .whitespaces),
                    "address": g.address.trimmingCharacters(in: .whitespacesAndNewlines),
                ]
            }
        }
        return result
    }
}

extension Teilnahme {
    /// Alter am ersten Tag unter 18? `birth` und `start` als ISO-Datum („2012-05-04“).
    public static func isMinor(_ birth: String?, start: String?) -> Bool {
        guard let birth, let start else { return false }
        let b = birth.prefix(10).split(separator: "-").compactMap { Int($0) }
        let s = start.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard b.count == 3, s.count == 3 else { return false }
        var age = s[0] - b[0]
        if (s[1], s[2]) < (b[1], b[2]) { age -= 1 }
        return age < 18
    }
}
