import Foundation

// Verwaltung in der App: Quittung mit Unterschrift (Bargeld gegen zwei Unterschriften),
// wie in der Android-App. Anlegen, beide Unterschriften, Abschluss mit Belegnummer.

/// Unterschrift aus dem Zeichenfeld: nur Linien in Bildschirmpunkten, keine Zeit, kein Druck.
public struct SignatureStrokes: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Linien, jede eine Folge von Punkten `[x, y]`
    public var strokes: [[[Int]]]

    public init(width: Int, height: Int, strokes: [[[Int]]]) {
        self.width = width
        self.height = height
        self.strokes = strokes
    }

    /// Aus gezeichneten Linien; nil, wenn das Feld zu klein oder keine Linie mit zwei Punkten da ist.
    public init?(width: Double, height: Double, lines: [[(x: Double, y: Double)]]) {
        let drawn = lines.filter { $0.count > 1 }
        guard width >= 10, height >= 10, !drawn.isEmpty else { return nil }
        self.width = Int(width)
        self.height = Int(height)
        strokes = drawn.map { line in line.map { [Int($0.x), Int($0.y)] } }
    }

    /// Linien zum Zeichnen.
    public var lines: [[(x: Double, y: Double)]] {
        strokes.map { line in line.filter { $0.count == 2 }.map { (Double($0[0]), Double($0[1])) } }
    }

    var json: [String: Any] { ["width": width, "height": height, "strokes": strokes] }
}

/// Hinterlegte Unterschrift, wie der Server sie ausgibt (Punkte je Linie hintereinander).
public struct SignatureShape: Decodable, Equatable, Sendable {
    public var w: Int
    public var h: Int
    public var s: [[Int]]

    enum CodingKeys: String, CodingKey { case w, h, s }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        w = try c.decodeIfPresent(Int.self, forKey: .w) ?? 1000
        h = try c.decodeIfPresent(Int.self, forKey: .h) ?? 0
        s = try c.decodeIfPresent([[Int]].self, forKey: .s) ?? []
    }

    public var lines: [[(x: Double, y: Double)]] {
        s.map { flat in
            stride(from: 0, to: flat.count - 1, by: 2).map { (Double(flat[$0]), Double(flat[$0 + 1])) }
        }
    }
}

public struct StoredSignature: Decodable, Equatable, Sendable {
    public var signature: SignatureShape?
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case signature
        case updatedAt = "updated_at"
    }
}

public struct CashReceiptItem: Decodable, Equatable, Sendable {
    public var id: Int
    /// "in": Verein erhält Geld, "out": Verein zahlt aus
    public var direction: String
    /// "draft", abgeschlossen oder storniert
    public var status: String
    public var statusLabel: String
    public var counterpartyName: String
    public var amount: String
    public var purpose: String
    public var accountName: String
    public var number: String
    public var receiptDate: String?

    enum CodingKeys: String, CodingKey {
        case id, direction, status, amount, purpose, number
        case statusLabel = "status_label"
        case counterpartyName = "counterparty_name"
        case accountName = "account_name"
        case receiptDate = "receipt_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        direction = try c.decodeIfPresent(String.self, forKey: .direction) ?? "out"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        counterpartyName = try c.decodeIfPresent(String.self, forKey: .counterpartyName) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName) ?? ""
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        receiptDate = try c.decodeIfPresent(String.self, forKey: .receiptDate)
    }
}

/// Quittung, die in der App vorbereitet und unterschrieben wird.
public struct ReceiptDraft: Equatable, Sendable {
    /// Zugleich `Idempotency-Key` für das Anlegen auf dem Server.
    public var key: String
    /// `Idempotency-Key` für den Abschluss (ein Schlüssel gilt nur für einen Schritt).
    public var finalizeKey: String
    /// Verein erhält Geld (sonst zahlt er aus)
    public var receives = false
    public var name = ""
    public var email = ""
    /// Eingabe wie „23,40“
    public var amount = ""
    public var purpose = ""
    public var account: Int?
    public var category: Int?
    /// Kassierer: hinterlegte Unterschrift einsetzen statt `treasurer`
    public var useStored = true
    public var treasurer: SignatureStrokes?
    public var treasurerAt = ""
    public var counterparty: SignatureStrokes?
    public var counterpartyAt = ""
    /// Zahler unterschreibt nicht (nur wenn der Verein Geld erhält): Grund
    public var declined = ""
    public var sendMail = true
    /// Kennung auf dem Server, sobald angelegt
    public var serverId: Int?

    public init(key: String = UUID().uuidString.lowercased(), finalizeKey: String = UUID().uuidString.lowercased()) {
        self.key = key
        self.finalizeKey = finalizeKey
    }

    public var kind: String { receives ? "income" : "expense" }
    public var parsedAmount: String? { Geld.parseInput(amount) }

    /// Name, Zweck, Betrag, Barkasse und Kategorie stehen fest.
    public var formReady: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !purpose.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedAmount != nil && account != nil && category != nil
    }

    /// `stored`: Gibt es eine hinterlegte Unterschrift des Kassierers?
    public func treasurerReady(stored: Bool) -> Bool { treasurer != nil || (useStored && stored) }

    public var counterpartyReady: Bool {
        counterparty != nil || (receives && !declined.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Ändern sich die unterschriebenen Angaben, gelten die Unterschriften nicht mehr.
    public mutating func signedChanged() {
        treasurer = nil
        counterparty = nil
        declined = ""
    }

    /// Was der Kassierer mit seiner Unterschrift bestätigt.
    public var treasurerText: String {
        let values: [String: Any] = ["betrag": Geld.format(parsedAmount), "name": name.trimmingCharacters(in: .whitespaces), "zweck": purpose.trimmingCharacters(in: .whitespaces)]
        return receives
            ? tr("{betrag} von {name} erhalten. Zweck: {zweck}", values)
            : tr("{betrag} an {name} ausgezahlt. Zweck: {zweck}", values)
    }

    /// Was die Gegenseite mit ihrer Unterschrift bestätigt (wie auf dem Server).
    public func counterpartyText(unitName: String) -> String {
        let values: [String: Any] = ["betrag": Geld.format(parsedAmount), "einheit": unitName, "zweck": purpose.trimmingCharacters(in: .whitespaces)]
        return receives
            ? tr("Ich habe {betrag} an {einheit} gezahlt. Zweck: {zweck}", values)
            : tr("Ich habe {betrag} von {einheit} erhalten. Zweck: {zweck}", values)
    }

    /// Inhalt zum Anlegen; nil, solange Angaben fehlen.
    var createBody: [String: Any]? {
        guard formReady, let value = parsedAmount, let account, let category else { return nil }
        return [
            "direction": receives ? "in" : "out",
            "counterparty_name": name.trimmingCharacters(in: .whitespaces),
            "email": email.trimmingCharacters(in: .whitespaces),
            "amount": value,
            "purpose": purpose.trimmingCharacters(in: .whitespaces),
            "account": account, "category": category,
        ]
    }

    var treasurerBody: [String: Any] {
        guard let treasurer else {
            var body: [String: Any] = ["use_stored": true]
            if !treasurerAt.isEmpty { body["signed_at"] = treasurerAt }
            return body
        }
        var body = treasurer.json
        if !treasurerAt.isEmpty { body["signed_at"] = treasurerAt }
        return body
    }

    /// nil: Die Unterschrift der Gegenseite fehlt.
    var counterpartyBody: [String: Any]? {
        if let counterparty {
            var body = counterparty.json
            if !counterpartyAt.isEmpty { body["signed_at"] = counterpartyAt }
            return body
        }
        let reason = declined.trimmingCharacters(in: .whitespaces)
        return receives && !reason.isEmpty ? ["declined": reason] : nil
    }

    var mail: Bool { sendMail && !email.trimmingCharacters(in: .whitespaces).isEmpty }
}

extension Zeit {
    /// Zeitpunkt mit Abstand zur Weltzeit, ohne Sekundenbruchteile (`2026-11-14T19:30:00+01:00`).
    public static func stamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        EventTime.iso(date, timeZone: timeZone)
    }
}

extension Api {
    static let signaturePath = "/api/app/v1/admin/signature/"
}

extension AdminClient {
    /// Eigene hinterlegte Unterschrift (gilt für alle Einheiten).
    public func storedSignature() async throws -> StoredSignature {
        try await api.expect("GET", Api.signaturePath)
    }

    /// Vorbereitete Quittung senden und abschließen: anlegen, beide Unterschriften, Abschluss.
    /// Jeder Schritt lässt sich wiederholen (`Idempotency-Key`; `created` meldet die Kennung
    /// auf dem Server, damit ein neuer Versuch dort weitermacht).
    public func submitReceipt(_ draft: ReceiptDraft, created: (Int) -> Void) async throws -> CashReceiptItem {
        let id: Int
        if let known = draft.serverId {
            let current: CashReceiptItem = try await api.expect("GET", base + "finance/cash-receipts/\(known)/")
            if current.status != "draft" { return current }
            // Korrektur von Barkasse und Kategorie auch auf dem Server ankommen lassen;
            // beide sind nicht unterschrieben, die Unterschriften bleiben gültig
            guard let account = draft.account, let category = draft.category else { throw ApiError(status: 0, code: "format") }
            _ = try await change("PATCH", "finance/cash-receipts/\(known)/", ["account": account, "category": category])
            id = known
        } else {
            guard let body = draft.createBody else { throw ApiError(status: 0, code: "format") }
            let response = try await api.raw("POST", base + "finance/cash-receipts/", json: body, extra: [SignedFormat.idempotencyHeader: draft.key])
            let item: CashReceiptItem = try decoded(response)
            id = item.id
            created(id)
        }
        guard let other = draft.counterpartyBody else {
            throw ApiError(status: 400, message: tr("Die Unterschrift der Gegenseite fehlt."))
        }
        _ = try await change("PUT", "finance/cash-receipts/\(id)/signatures/treasurer/", draft.treasurerBody)
        _ = try await change("PUT", "finance/cash-receipts/\(id)/signatures/counterparty/", other)
        let done = try await api.raw(
            "POST", base + "finance/cash-receipts/\(id)/finalize/",
            json: ["confirmed": true, "send": draft.mail], extra: [SignedFormat.idempotencyHeader: draft.finalizeKey]
        )
        return try decoded(done)
    }
}
