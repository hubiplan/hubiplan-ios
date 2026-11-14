import Foundation

// Verwaltung in der App (Schritt B4 der Android-App): Kassenbuch mit Kontoständen,
// letzten Buchungen, Belegen und „Neue Buchung“ mit Belegfoto.

/// Formular mit einer Datei (`multipart/form-data`).
public struct Multipart: Equatable, Sendable {
    public var contentType: String
    public var body: Data

    /// `boundary`: Trennzeile; darf im Inhalt nicht vorkommen (Vorgabe: zufällig).
    public init(fields: [(name: String, value: String)], file: Data, fileName: String, fileType: String, boundary: String = "hubiplan-" + UUID().uuidString) {
        var out = Data()
        func add(_ text: String) { out.append(Data(text.utf8)) }
        // Namen und Dateiname kommen aus dem Code; Anführungszeichen und Zeilenwechsel trotzdem entfernen
        func clean(_ text: String) -> String { text.filter { $0 != "\"" && $0 != "\r" && $0 != "\n" } }
        for field in fields {
            add("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(clean(field.name))\"\r\n\r\n\(field.value)\r\n")
        }
        add("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(clean(fileName))\"\r\nContent-Type: \(clean(fileType))\r\n\r\n")
        out.append(file)
        add("\r\n--\(boundary)--\r\n")
        contentType = "multipart/form-data; boundary=\(boundary)"
        body = out
    }
}

extension AdminUnit {
    /// Bereich „Kassenbuch“ zeigen: mindestens lesen.
    public var showsFinance: Bool { permissions.contains("finance.view") || permissions.contains("finance.edit") }
    /// Buchen und Belege nachreichen.
    public var canEditFinance: Bool { permissions.contains("finance.edit") }
}

public struct FinanceAccount: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// "cash": Barkasse
    public var kind: String
    public var kindLabel: String
    public var balance: String?
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, kind, balance
        case kindLabel = "kind_label"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        balance = try c.decodeIfPresent(String.self, forKey: .balance)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    /// Vorgabe für eine neue Buchung: meist die Barkasse.
    public static func preferred(_ accounts: [FinanceAccount]) -> FinanceAccount? {
        accounts.first { $0.kind == "cash" } ?? accounts.first
    }
}

public struct FinanceCategory: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// "income", "expense" oder "both"
    public var kind: String
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    /// Kategorien, die zu einer Einnahme oder Ausgabe passen.
    public static func matching(_ categories: [FinanceCategory], kind: String) -> [FinanceCategory] {
        categories.filter { $0.isActive && ($0.kind == kind || $0.kind == "both") }
    }
}

public struct ReceiptInfo: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var contentType: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case contentType = "content_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
    }

    public var isImage: Bool { contentType.hasPrefix("image/") }
}

public struct BookingItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var displayNumber: String
    public var date: String
    /// "income", "expense" oder "transfer"
    public var kind: String
    public var kindLabel: String
    public var amount: String
    public var accountName: String
    public var toAccountName: String?
    public var categoryName: String?
    public var text: String
    public var counterparty: String
    public var receipts: [ReceiptInfo]

    enum CodingKeys: String, CodingKey {
        case id, date, kind, amount, text, counterparty, receipts
        case displayNumber = "display_number"
        case kindLabel = "kind_label"
        case accountName = "account_name"
        case toAccountName = "to_account_name"
        case categoryName = "category_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        displayNumber = try c.decodeIfPresent(String.self, forKey: .displayNumber) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName) ?? ""
        toAccountName = try c.decodeIfPresent(String.self, forKey: .toAccountName)
        categoryName = try c.decodeIfPresent(String.self, forKey: .categoryName)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        counterparty = try c.decodeIfPresent(String.self, forKey: .counterparty) ?? ""
        receipts = try c.decodeIfPresent([ReceiptInfo].self, forKey: .receipts) ?? []
    }

    /// Buchungstext, sonst die Art.
    public var title: String { text.trimmingCharacters(in: .whitespaces).isEmpty ? kindLabel : text }

    /// Betrag mit Vorzeichen: Einnahmen „+“, Ausgaben „−“, Umbuchungen ohne.
    public var signedAmount: String {
        let sign = kind == "income" ? "+" : (kind == "expense" ? "−" : "")
        return sign + Geld.format(amount)
    }

    /// Konto; bei Umbuchungen „von → nach“.
    public var accounts: String {
        kind == "transfer" ? "\(accountName) → \(toAccountName ?? "")" : accountName
    }

    /// Zeile über dem Titel: Datum und Nummer.
    public var head: String {
        tr("{datum} · Nr. {nummer}", ["datum": Zeit.plainDate(date), "nummer": displayNumber])
    }

    /// Zeile unter dem Titel in der Liste: Kategorie, Gegenseite, Konto, „ohne Beleg“.
    public var detail: String {
        var parts = [categoryName ?? "", counterparty, accounts].filter { !$0.isEmpty }
        if receipts.isEmpty { parts.append(tr("ohne Beleg")) }
        return parts.joined(separator: " · ")
    }

    /// Angaben auf der Seite der Buchung: Nummer, Datum, Kategorie, Konto, Gegenseite.
    public var facts: String {
        [tr("Nr. {nummer}", ["nummer": displayNumber]), Zeit.plainDate(date), categoryName ?? "", accounts, counterparty]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct BookingPage: Decodable, Equatable, Sendable {
    public var count: Int
    public var next: String?
    public var results: [BookingItem]

    enum CodingKeys: String, CodingKey { case count, next, results }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        next = try c.decodeIfPresent(String.self, forKey: .next)
        results = try c.decodeIfPresent([BookingItem].self, forKey: .results) ?? []
    }

    public var hasMore: Bool { next != nil }
}

/// Liste, die der Server als Feld oder seitenweise (`results`) liefert.
struct Listed<Row: Decodable>: Decodable {
    var rows: [Row]

    enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        if let plain = try? decoder.singleValueContainer().decode([Row].self) {
            rows = plain
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rows = try c.decodeIfPresent([Row].self, forKey: .results) ?? []
        }
    }
}

/// Neue Buchung aus der App: Eingaben, bis sie gesendet ist.
public struct BookingDraft: Equatable, Sendable {
    /// Zugleich `Idempotency-Key`: erneutes Senden bucht nicht doppelt.
    public var key: String
    /// "expense" oder "income"
    public var kind = "expense"
    /// Eingabe wie „23,40“
    public var amount = ""
    /// `TT.MM.JJJJ` oder `JJJJ-MM-TT`
    public var date = ""
    public var text = ""
    public var counterparty = ""
    public var account: Int?
    public var category: Int?

    public init(key: String = UUID().uuidString.lowercased()) {
        self.key = key
    }

    /// Felder der Anfrage; nil, solange Betrag, Datum, Text, Konto oder (wo es welche gibt)
    /// die Kategorie fehlen. `categories`: alle Kategorien der Einheit.
    public func fields(categories: [FinanceCategory]) -> [(name: String, value: String)]? {
        let label = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard let value = Geld.parseInput(amount), let day = MasterData.parseDate(date), let account, !label.isEmpty else { return nil }
        let fitting = FinanceCategory.matching(categories, kind: kind)
        let chosen = fitting.first { $0.id == category }
        if !fitting.isEmpty, chosen == nil { return nil }
        var out: [(name: String, value: String)] = [
            ("date", day), ("kind", kind), ("amount", value), ("account", String(account)),
        ]
        if let chosen { out.append(("category", String(chosen.id))) }
        out.append(("text", label))
        let other = String(counterparty.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if !other.isEmpty { out.append(("counterparty", other)) }
        return out
    }
}

extension Geld {
    /// „23,40“, „23.4“ oder „1.234,50“ → „23.40“ (positiv, höchstens zwei Nachkommastellen,
    /// höchstens 99.999.999,99); sonst nil.
    public static func parseInput(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("€") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
        t = t.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: "")
        if t.contains(",") {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        guard !t.hasPrefix("-"), let value = cents(t), value > 0, value <= 9_999_999_999 else { return nil }
        return String(format: "%d.%02d", value / 100, value % 100)
    }
}

extension AdminClient {
    /// Aktive Konten mit Stand.
    public func accounts() async throws -> [FinanceAccount] {
        let list: Listed<FinanceAccount> = try await api.expect("GET", base + "finance/accounts/")
        return list.rows.filter(\.isActive)
    }

    /// Aktive Kategorien.
    public func categories() async throws -> [FinanceCategory] {
        let list: Listed<FinanceCategory> = try await api.expect("GET", base + "finance/categories/")
        return list.rows.filter(\.isActive)
    }

    /// Buchungen, neueste zuerst; `withoutReceipt`: nur die ohne Beleg.
    public func bookings(page: Int = 1, withoutReceipt: Bool = false) async throws -> BookingPage {
        try await api.expect("GET", base + "finance/bookings/?page=\(max(1, page))&page_size=30" + (withoutReceipt ? "&ohne_beleg=1" : ""))
    }

    public func booking(_ id: Int) async throws -> BookingItem {
        try await api.expect("GET", base + "finance/bookings/\(id)/")
    }

    /// Belegbild; nil, wenn es nicht zu laden ist.
    public func receipt(_ id: Int) async -> Data? {
        await api.image(base + "finance/receipts/\(id)/")
    }

    /// Buchung mit Beleg in einem Schritt; `key` schützt vor doppeltem Buchen.
    public func book(fields: [(name: String, value: String)], jpeg: Data, key: String) async throws -> BookingItem {
        let form = Multipart(fields: fields, file: jpeg, fileName: "beleg.jpg", fileType: "image/jpeg")
        let response = try await api.raw("POST", base + "finance/app-booking/", form: form, extra: [SignedFormat.idempotencyHeader: key])
        return try decoded(response)
    }

    /// Beleg zu einer vorhandenen Buchung nachreichen.
    public func addReceipt(booking id: Int, jpeg: Data) async throws {
        let form = Multipart(fields: [], file: jpeg, fileName: "beleg.jpg", fileType: "image/jpeg")
        let response = try await api.raw("POST", base + "finance/bookings/\(id)/receipts/", form: form)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
    }

    func decoded<T: Decodable>(_ response: HttpResponse) throws -> T {
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
        guard let value = try? JSONDecoder().decode(T.self, from: response.body) else {
            throw ApiError(status: response.status, code: "format")
        }
        return value
    }
}
