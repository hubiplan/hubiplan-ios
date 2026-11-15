import Foundation

/// Einheit, an deren Mitglieder dieses Konto Kurzmitteilungen senden darf.
public struct Sender: Decodable, Equatable, Identifiable, Hashable, Sendable {
    public var key: String
    public var name: String
    public var type: String
    public var id: Int
    public var club: String

    enum CodingKeys: String, CodingKey { case key, name, type, id, club }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try c.decode(String.self, forKey: .type)
        id = try c.decode(Int.self, forKey: .id)
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? ""
    }

    /// Name mit Verein in Klammern, wenn er nicht derselbe ist.
    public var label: String { club.isEmpty || club == name ? name : "\(name) (\(club))" }
}

public struct Senders: Decodable, Equatable, Sendable {
    public var senders: [Sender]
    public var maxBody: Int

    enum CodingKeys: String, CodingKey {
        case senders
        case maxBody = "max_body"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        senders = try c.decodeIfPresent([Sender].self, forKey: .senders) ?? []
        maxBody = try c.decodeIfPresent(Int.self, forKey: .maxBody) ?? 500
    }
}

/// Antwort auf Vorschau (`counts`) bzw. Senden (`sent`).
public struct SendResult: Decodable, Equatable, Sendable {
    public var counts: [String: Int]
    public var sent: [String: Int]

    enum CodingKeys: String, CodingKey { case counts, sent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        sent = try c.decodeIfPresent([String: Int].self, forKey: .sent) ?? [:]
    }
}

/// Empfänger einer Kurzmitteilung in Worten (wie Android).
public enum Empfaenger {
    public static func total(_ counts: [String: Int]) -> Int {
        ["app", "mail", "portal", "letter"].reduce(0) { $0 + (counts[$1] ?? 0) }
    }

    /// „geht an 43 Mitglieder, davon 31 per App, 12 per E-Mail“
    public static func summary(_ counts: [String: Int]) -> String {
        let app = counts["app"] ?? 0, mail = counts["mail"] ?? 0, portal = counts["portal"] ?? 0
        var parts: [String] = []
        if app > 0 { parts.append(tr("{app} per App", ["app": app])) }
        if mail > 0 { parts.append(tr("{mail} per E-Mail", ["mail": mail])) }
        if portal > 0 { parts.append(tr("{portal} nur im Mitgliederbereich", ["portal": portal])) }
        guard !parts.isEmpty else { return tr("geht an niemanden") }
        let who = trn("1 Mitglied", "{n} Mitglieder", total(counts))
        return tr("geht an {who}, davon {parts}", ["who": who, "parts": parts.joined(separator: ", ")])
    }
}

extension Api {
    /// Einheiten, an die dieses Konto senden darf (leer: kein Knopf).
    public func senders() async throws -> Senders {
        try await expect("GET", "/api/app/v1/send/")
    }

    /// Kurzmitteilung: `confirm` false zählt nur die Empfänger, true sendet.
    /// Prüffehler des Servers (`{"body": ["…"]}`) kommen als Meldung zurück.
    public func sendShort(_ sender: Sender, subject: String, body: String, confirm: Bool) async throws -> SendResult {
        let response = try await raw("POST", "/api/app/v1/send/\(sender.type)/\(sender.id)/",
                                     json: ["subject": subject, "body": body, "confirm": confirm])
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            let message = fields.message.isEmpty ? Api.firstFieldMessage(response.body) : fields.message
            throw ApiError(status: response.status, code: fields.code, message: message)
        }
        do {
            return try JSONDecoder().decode(SendResult.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }

    /// Erste Meldung aus Prüffehlern je Feld, z. B. `{"subject": ["Bitte ausfüllen."]}`.
    static func firstFieldMessage(_ body: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
        for key in object.keys.sorted() {
            if let list = object[key] as? [String], let first = list.first, !first.isEmpty { return first }
            if let text = object[key] as? String, key != "code", !text.isEmpty { return text }
        }
        return ""
    }
}
