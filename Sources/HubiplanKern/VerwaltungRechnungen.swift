import Foundation

// Verwaltung in der App (Schritt B5 der Android-App): Rechnungen nachschlagen und
// eine Barzahlung buchen („Bar kassiert“), mit Quittung als PDF.

extension AdminUnit {
    /// Bereich „Rechnungen“ zeigen: mindestens lesen.
    public var showsBilling: Bool { permissions.contains("billing.view") || permissions.contains("billing.edit") }
    /// Barzahlungen buchen.
    public var canEditBilling: Bool { permissions.contains("billing.edit") }
}

public struct InvoiceLine: Decodable, Equatable, Sendable {
    public var text: String
    public var detail: String
    public var amount: String

    enum CodingKeys: String, CodingKey { case text, detail, amount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
    }
}

public struct InvoicePayment: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var date: String
    public var amount: String
    /// "cash": bar kassiert (dazu gibt es eine Quittung)
    public var method: String
    public var methodLabel: String
    public var accountName: String
    public var bookingNumber: String

    enum CodingKeys: String, CodingKey {
        case id, date, amount, method
        case methodLabel = "method_label"
        case accountName = "account_name"
        case bookingNumber = "booking_number"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? ""
        methodLabel = try c.decodeIfPresent(String.self, forKey: .methodLabel) ?? ""
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName) ?? ""
        bookingNumber = try c.decodeIfPresent(String.self, forKey: .bookingNumber) ?? ""
    }

    public var isCash: Bool { method == "cash" }

    /// Zeile unter dem Betrag: Datum, Zahlart, Konto, Buchungsnummer.
    public var detail: String {
        [Zeit.plainDate(date), methodLabel, accountName, bookingNumber.isEmpty ? "" : tr("Nr. {nummer}", ["nummer": bookingNumber])]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct InvoiceItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var number: String?
    /// "open", "paid", "cancelled", "draft" …
    public var status: String
    public var statusLabel: String
    public var recipientName: String
    public var departmentName: String?
    public var subject: String
    public var date: String
    public var dueDate: String
    public var total: String
    public var paid: String
    public var outstanding: String
    public var overdue: Bool
    public var lines: [InvoiceLine]
    public var payments: [InvoicePayment]

    enum CodingKeys: String, CodingKey {
        case id, number, status, subject, date, total, paid, outstanding, overdue, lines, payments
        case statusLabel = "status_label"
        case recipientName = "recipient_name"
        case departmentName = "department_name"
        case dueDate = "due_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decodeIfPresent(String.self, forKey: .number)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        recipientName = try c.decodeIfPresent(String.self, forKey: .recipientName) ?? ""
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        total = try c.decodeIfPresent(String.self, forKey: .total) ?? "0"
        paid = try c.decodeIfPresent(String.self, forKey: .paid) ?? "0"
        outstanding = try c.decodeIfPresent(String.self, forKey: .outstanding) ?? "0"
        overdue = try c.decodeIfPresent(Bool.self, forKey: .overdue) ?? false
        lines = try c.decodeIfPresent([InvoiceLine].self, forKey: .lines) ?? []
        payments = try c.decodeIfPresent([InvoicePayment].self, forKey: .payments) ?? []
    }

    /// Erste Zeile des Empfängers (darunter steht ggf. „z. Hd.“ o. Ä.).
    public var payer: String {
        recipientName.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    public var isOpen: Bool { status == "open" }
    public var isOverdue: Bool { isOpen && overdue }
    public var hasPaid: Bool { (Geld.cents(paid) ?? 0) > 0 }
    /// Offen und mit Restbetrag: hier lässt sich bar kassieren.
    public var canPayCash: Bool { isOpen && (Geld.cents(outstanding) ?? 0) > 0 }

    /// Betrag in der Liste: bei offenen der Rest, sonst die Summe.
    public var listAmount: String { Geld.format(isOpen ? outstanding : total) }

    /// Stand in der Liste: „überfällig“ oder der Stand vom Server.
    public var listStatus: String { isOverdue ? tr("überfällig") : statusLabel }

    /// Zeile unter dem Namen: Nummer, Betreff, Untereinheit.
    public var listDetail: String {
        [number ?? "", subject, departmentName ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Nummer und Betreff auf der Seite der Rechnung.
    public var headline: String {
        [number ?? "", subject].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// „vom 01.11.2026 · fällig 15.11.2026 · offen“ (oder „überfällig“)
    public var dates: String {
        tr("vom {datum} · fällig {faellig} · {stand}", ["datum": Zeit.plainDate(date), "faellig": Zeit.plainDate(dueDate), "stand": listStatus])
    }

    /// Dateiname der Quittung: nur Buchstaben, Ziffern und Bindestriche.
    public func receiptName(payment: Int) -> String {
        let mapped = String((number ?? "").map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") ? $0 : "-" })
        let clean = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return clean.isEmpty ? "Quittung-\(payment).pdf" : "Quittung-\(clean)-\(payment).pdf"
    }
}

public struct InvoicePage: Decodable, Equatable, Sendable {
    public var count: Int
    public var next: String?
    public var results: [InvoiceItem]

    enum CodingKeys: String, CodingKey { case count, next, results }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        next = try c.decodeIfPresent(String.self, forKey: .next)
        results = try c.decodeIfPresent([InvoiceItem].self, forKey: .results) ?? []
    }

    public var hasMore: Bool { next != nil }
}

public struct BillingAccount: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// "cash": Barkasse
    public var kind: String

    enum CodingKeys: String, CodingKey { case id, name, kind }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
    }
}

public struct BillingInfo: Decodable, Equatable, Sendable {
    public var accounts: [BillingAccount]
    public var canEdit: Bool

    enum CodingKeys: String, CodingKey {
        case accounts
        case canEdit = "can_edit"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try c.decodeIfPresent([BillingAccount].self, forKey: .accounts) ?? []
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
    }

    /// Barkassen, in die sich kassieren lässt.
    public var cashAccounts: [BillingAccount] { accounts.filter { $0.kind == "cash" } }
}

/// Ergebnis von „Bar kassiert“: die Rechnung danach und die Zahlung (für die Quittung).
public struct CashResult: Decodable, Equatable, Sendable {
    public var invoice: InvoiceItem
    public var payment: Int
}

/// Eingaben für „Bar kassiert“.
public struct CashDraft: Equatable, Sendable {
    /// Zugleich `Idempotency-Key`: erneutes Senden bucht nicht doppelt.
    public var key: String
    /// Eingabe wie „60,00“
    public var amount: String
    /// `TT.MM.JJJJ` oder `JJJJ-MM-TT`
    public var date = ""
    public var account: Int?

    /// `outstanding`: offener Betrag der Rechnung als Vorgabe.
    public init(outstanding: String, key: String = UUID().uuidString.lowercased()) {
        self.key = key
        amount = Geld.inputText(outstanding)
    }

    /// Hinweis zum Betrag; nil, wenn er passt (oder sich der offene Betrag nicht lesen lässt).
    public static func amountError(_ input: String, outstanding: String) -> String? {
        guard let value = Geld.parseInput(input).flatMap(Geld.cents) else { return tr("Bitte einen Betrag über 0 eingeben.") }
        guard let open = Geld.cents(outstanding) else { return nil }
        return value > open ? tr("Offen sind nur noch {betrag}.", ["betrag": Geld.format(cents: open)]) : nil
    }

    /// Inhalt der Anfrage; nil, solange Betrag, Datum oder Barkasse fehlen oder nicht passen.
    public func body(outstanding: String) -> [String: Any]? {
        guard let value = Geld.parseInput(amount), Self.amountError(amount, outstanding: outstanding) == nil,
              let day = MasterData.parseDate(date), let account
        else { return nil }
        return ["account": account, "amount": value, "date": day]
    }
}

extension Geld {
    /// „60.00“ → „60,00“ (Englisch „60.00“) für ein Eingabefeld; leer, wenn der Text kein Betrag ist.
    public static func inputText(_ amount: String) -> String {
        guard let value = cents(amount), value >= 0 else { return "" }
        return "\(value / 100)" + (Texte.language == "en" ? "." : ",") + String(format: "%02d", value % 100)
    }
}

extension AdminClient {
    /// Rechnungen, neueste zuerst; `search`: Name, Betreff oder Nummer; `openOnly`: nur offene.
    public func invoices(search: String, page: Int = 1, openOnly: Bool = true) async throws -> InvoicePage {
        let q = queryValue(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await api.expect("GET", base + "billing/invoices/?suche=\(q)&page=\(max(1, page))" + (openOnly ? "&offen=1" : ""))
    }

    public func invoice(_ id: Int) async throws -> InvoiceItem {
        try await api.expect("GET", base + "billing/invoices/\(id)/")
    }

    /// Konten für Zahlungen und ob Barzahlungen erlaubt sind.
    public func billingInfo() async throws -> BillingInfo {
        try await api.expect("GET", base + "billing/settings/")
    }

    /// Barzahlung zu einer Rechnung buchen; `key` schützt vor doppeltem Buchen.
    public func payCash(invoice id: Int, body: [String: Any], key: String) async throws -> (result: CashResult, change: AdminChange) {
        let response = try await api.raw("POST", base + "billing/invoices/\(id)/cash/", json: body, extra: [SignedFormat.idempotencyHeader: key])
        let result: CashResult = try decoded(response)
        return (result, AdminChange(response))
    }

    /// Quittung einer Barzahlung als PDF; nil, wenn sie nicht zu laden ist.
    public func cashReceipt(payment id: Int) async -> Data? {
        await api.image(base + "billing/payments/\(id)/receipt/")
    }
}
