import Foundation

// Auslagen im Mitgliederbereich (`/api/portal/<Zugang>/expenses/`), Beschreibung in
// hubiplan/docs/auslagen.md. Verhalten wie in der Android-App (Ich › Auslagen): selbst bezahlte
// Ausgaben mit Foto des Belegs melden, Rückfragen der Kasse beantworten, Stand sehen.
// Nichts davon wird auf dem Gerät gespeichert.

public struct ExpensePayee: Decodable, Equatable, Sendable {
    public var holder: String
    public var iban: String

    public init(holder: String = "", iban: String = "") {
        self.holder = holder
        self.iban = iban
    }

    enum CodingKeys: String, CodingKey { case holder, iban }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        holder = try c.decodeIfPresent(String.self, forKey: .holder) ?? ""
        iban = try c.decodeIfPresent(String.self, forKey: .iban) ?? ""
    }
}

public struct ExpenseOptions: Decodable, Equatable, Sendable {
    public var maySubmit: Bool
    public var mileageEnabled: Bool
    public var kmRate: String
    public var payee: ExpensePayee?

    public init(maySubmit: Bool = false, mileageEnabled: Bool = false, kmRate: String = "0.30", payee: ExpensePayee? = nil) {
        self.maySubmit = maySubmit
        self.mileageEnabled = mileageEnabled
        self.kmRate = kmRate
        self.payee = payee
    }

    enum CodingKeys: String, CodingKey {
        case payee
        case maySubmit = "may_submit"
        case mileageEnabled = "mileage_enabled"
        case kmRate = "km_rate"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maySubmit = try c.decodeIfPresent(Bool.self, forKey: .maySubmit) ?? false
        mileageEnabled = try c.decodeIfPresent(Bool.self, forKey: .mileageEnabled) ?? false
        kmRate = try c.decodeIfPresent(String.self, forKey: .kmRate) ?? "0.30"
        payee = try c.decodeIfPresent(ExpensePayee.self, forKey: .payee)
    }
}

public struct ExpenseFile: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String

    enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

public struct ExpenseEvent: Decodable, Equatable, Sendable {
    public var kind: String
    public var label: String
    public var who: String
    public var text: String
    public var at: String

    enum CodingKeys: String, CodingKey { case kind, label, who, text, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        who = try c.decodeIfPresent(String.self, forKey: .who) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        at = try c.decodeIfPresent(String.self, forKey: .at) ?? ""
    }
}

public struct ExpenseClaim: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var number: String
    /// expense, mileage oder advance
    public var kind: String
    /// draft, submitted, question, confirmed, approved, paid, rejected, withdrawn, waived
    public var status: String
    public var statusLabel: String
    public var purpose: String
    public var purchaseDate: String?
    public var payout: String
    public var total: String
    public var amountDue: String
    public var approvedAmount: String?
    public var reduceReason: String
    public var rejectReason: String
    public var submittedAt: String?
    public var createdAt: String?
    public var files: [ExpenseFile]
    public var events: [ExpenseEvent]
    public var canEdit: Bool
    public var canWithdraw: Bool
    public var problems: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, number, kind, status, purpose, payout, total, files, events, problems
        case statusLabel = "status_label"
        case purchaseDate = "purchase_date"
        case amountDue = "amount_due"
        case approvedAmount = "approved_amount"
        case reduceReason = "reduce_reason"
        case rejectReason = "reject_reason"
        case submittedAt = "submitted_at"
        case createdAt = "created_at"
        case canEdit = "can_edit"
        case canWithdraw = "can_withdraw"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "expense"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        purchaseDate = try c.decodeIfPresent(String.self, forKey: .purchaseDate)
        payout = try c.decodeIfPresent(String.self, forKey: .payout) ?? "bank"
        total = try c.decodeIfPresent(String.self, forKey: .total) ?? "0"
        amountDue = try c.decodeIfPresent(String.self, forKey: .amountDue) ?? "0"
        approvedAmount = try c.decodeIfPresent(String.self, forKey: .approvedAmount)
        reduceReason = try c.decodeIfPresent(String.self, forKey: .reduceReason) ?? ""
        rejectReason = try c.decodeIfPresent(String.self, forKey: .rejectReason) ?? ""
        submittedAt = try c.decodeIfPresent(String.self, forKey: .submittedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        files = try c.decodeIfPresent([ExpenseFile].self, forKey: .files) ?? []
        events = try c.decodeIfPresent([ExpenseEvent].self, forKey: .events) ?? []
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        canWithdraw = try c.decodeIfPresent(Bool.self, forKey: .canWithdraw) ?? false
        problems = try c.decodeIfPresent([String: String].self, forKey: .problems) ?? [:]
    }

    /// Die Kasse wartet auf eine Antwort.
    public var asksMe: Bool { status == "question" }
    /// Letzte Rückfrage der Kasse.
    public var question: String? { events.last { $0.kind == "question" }?.text }
    /// Beleg ergänzen (nicht bei Fahrtkosten).
    public var canAddFile: Bool { canEdit && kind == "expense" }
    /// Entwurf ohne Nummer: wird gelöscht statt zurückgezogen.
    public var isLooseDraft: Bool { status == "draft" && number.isEmpty }
    /// Zweite Zeile: Betrag, Stand und Datum.
    public var line: String {
        var parts = [Geld.format(amountDue)]
        if !statusLabel.isEmpty { parts.append(statusLabel) }
        if let day = submittedAt.flatMap(Zeit.parse) {
            parts.append(tr("eingereicht am {day}", ["day": day.formatted(.dateTime.day().month().year().locale(Texte.locale))]))
        }
        return parts.joined(separator: " · ")
    }
}

public struct ExpenseOverview: Decodable, Equatable, Sendable {
    public var claims: [ExpenseClaim]
    public var options: ExpenseOptions

    public init(claims: [ExpenseClaim] = [], options: ExpenseOptions = ExpenseOptions()) {
        self.claims = claims
        self.options = options
    }

    enum CodingKeys: String, CodingKey { case claims, options }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claims = try c.decodeIfPresent([ExpenseClaim].self, forKey: .claims) ?? []
        options = try c.decodeIfPresent(ExpenseOptions.self, forKey: .options) ?? ExpenseOptions()
    }

    /// Kurzstand neben „Auslagen“ unter „Ich“.
    public var summary: String {
        let asks = claims.filter(\.asksMe).count
        let open = claims.filter { ["submitted", "confirmed", "approved"].contains($0.status) }.count
        if asks > 0 { return trn("1 Rückfrage der Kasse", "{n} Rückfragen der Kasse", asks) }
        if open > 0 { return trn("1 in Bearbeitung", "{n} in Bearbeitung", open) }
        return tr("Selbst Bezahltes erstattet bekommen")
    }
}

/// Eingaben einer neuen Auslage, bis sie gesendet ist.
public struct ExpenseDraft: Equatable, Sendable {
    public var kind = "expense"
    public var purpose = ""
    /// JJJJ-MM-TT
    public var date = ""
    public var amounts: [String] = [""]
    public var route = ""
    public var km = ""
    public var payout = "bank"
    public var holder = ""
    public var iban = ""

    public init(date: String = "", payee: ExpensePayee? = nil) {
        self.date = date
        holder = payee?.holder ?? ""
        iban = payee?.iban ?? ""
    }

    /// Formularfelder für POST …/expenses/ (Positionen und Bankverbindung als JSON-Text,
    /// Belege als „file“). Ungültige Beträge fehlen, der Server meldet sie dann.
    public func fields(submit: Bool) -> [(name: String, value: String)] {
        var out: [(name: String, value: String)] = [
            ("kind", kind),
            ("purpose", purpose.trimmingCharacters(in: .whitespacesAndNewlines)),
            ("payout", payout),
            ("source", "app"),
        ]
        if kind != "advance" { out.append(("purchase_date", date)) }
        if kind == "mileage" {
            out.append(("route", route.trimmingCharacters(in: .whitespacesAndNewlines)))
            out.append(("km", parseKm(km) ?? ""))
        } else {
            let lines = amounts.compactMap(Geld.parseInput).map { ["amount": $0, "text": ""] }
            out.append(("lines", jsonText(lines)))
        }
        if payout == "bank" {
            out.append(("payee", jsonText(["holder": holder.trimmingCharacters(in: .whitespaces), "iban": cleanIban(iban)])))
        } else {
            out.append(("payee", ""))
        }
        if submit { out.append(("submit", "true")) }
        return out
    }
}

private func jsonText(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "" }
    return String(decoding: data, as: UTF8.self)
}

/// Kilometer „12,5“ → „12.5“; sonst nil (0 oder über 5000).
public func parseKm(_ text: String) -> String? {
    let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    guard !t.isEmpty, t.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }), t.filter({ $0 == "." }).count <= 1,
          let value = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")), value > 0, value <= 5000
    else { return nil }
    var parts = t.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    var whole = String(parts[0].drop { $0 == "0" })
    if whole.isEmpty { whole = "0" }
    parts[0] = whole
    if parts.count == 2 {
        let fraction = String(parts[1].reversed().drop { $0 == "0" }.reversed())
        return fraction.isEmpty ? whole : whole + "." + fraction
    }
    return whole
}

/// IBAN ohne Leerzeichen, groß geschrieben.
public func cleanIban(_ text: String) -> String {
    String(text.filter { !$0.isWhitespace }).uppercased()
}

/// Feldfehler aus einer Antwort `{"feld": ["…"]}`, zusammengefasst als ein Text.
func fieldMessages(_ body: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
    var out: [String] = []
    for key in object.keys.sorted() where key != "code" {
        if let list = object[key] as? [Any], let first = list.first as? String {
            out.append(first)
        } else if let text = object[key] as? String {
            out.append(text)
        }
    }
    return out.joined(separator: " ")
}

extension Api {
    public func memberExpenses(accessId: Int) async throws -> ExpenseOverview {
        try await expect("GET", "/api/portal/\(accessId)/expenses/")
    }

    public func memberExpense(accessId: Int, id: Int) async throws -> ExpenseClaim {
        try await expect("GET", "/api/portal/\(accessId)/expenses/\(id)/")
    }

    /// Neue Auslage mit Fotos in einem Schritt; `key` schützt vor doppeltem Anlegen.
    public func createExpense(accessId: Int, draft: ExpenseDraft, submit: Bool, photos: [Data], key: String) async throws -> ExpenseClaim {
        let files = photos.enumerated().map { (name: "beleg-\($0.offset + 1).jpg", data: $0.element, type: "image/jpeg") }
        let form = Multipart(fields: draft.fields(submit: submit), files: files)
        let response = try await raw("POST", "/api/portal/\(accessId)/expenses/", form: form, extra: [SignedFormat.idempotencyHeader: key])
        return try expenseDecoded(response)
    }

    public func addExpensePhoto(accessId: Int, id: Int, jpeg: Data) async throws -> ExpenseClaim {
        let form = Multipart(fields: [], file: jpeg, fileName: "beleg.jpg", fileType: "image/jpeg")
        let response = try await raw("POST", "/api/portal/\(accessId)/expenses/\(id)/files/", form: form)
        return try expenseDecoded(response)
    }

    /// submit, withdraw oder answer (mit `text`).
    public func expenseAction(accessId: Int, id: Int, action: String, text: String? = nil) async throws {
        let body: [String: Any] = text.map { ["text": $0] } ?? [:]
        let _: Ignored = try await expect("POST", "/api/portal/\(accessId)/expenses/\(id)/\(action)/", json: body)
    }

    /// Entwurf ohne Nummer löschen.
    public func deleteExpense(accessId: Int, id: Int) async throws {
        let _: Ignored = try await expect("DELETE", "/api/portal/\(accessId)/expenses/\(id)/")
    }

    private func expenseDecoded(_ response: HttpResponse) throws -> ExpenseClaim {
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            let message = fields.message.isEmpty ? fieldMessages(response.body) : fields.message
            throw ApiError(status: response.status, code: fields.code, message: message)
        }
        do {
            return try JSONDecoder().decode(ExpenseClaim.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }
}

extension PortalAccess {
    /// Bereich „Auslagen“ unter „Ich“ (Modul Auslagen erstatten; Ansprechpartner von Firmen nicht).
    public var hasExpenses: Bool { expensesEnabled && !(memberKind == "organization" && !memberName.isEmpty) }
}
