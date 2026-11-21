import Foundation

// Sammelbestellungen im Mitgliederbereich (`/api/portal/<Zugang>/orders/`), Beschreibung in
// hubiplan/docs/app.md: Vereinskleidung, Festschrift oder reine Größenabfragen. Bis zur Frist
// bestellen, ändern und zurückziehen. Preise fehlen, wenn der Verein bezahlt. Verhalten wie in
// der Android-App (Ich › Bestellungen). Nichts davon wird auf dem Gerät gespeichert.

public struct OrderArticle: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var text: String
    /// Preis als Text („25.00“), leer ohne Preis oder wenn der Verein bezahlt
    public var price: String?
    public var variants: [String]
    /// Überschrift der Auswahl, etwa „Größe“
    public var variantLabel: String
    public var maxPerMember: Int?
    public var maxTotal: Int?
    /// noch verfügbar (nur mit Gesamtmenge)
    public var left: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, text, price, variants, left
        case variantLabel = "variant_label"
        case maxPerMember = "max_per_member"
        case maxTotal = "max_total"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        price = try c.decodeIfPresent(String.self, forKey: .price)
        variants = try c.decodeIfPresent([String].self, forKey: .variants) ?? []
        variantLabel = try c.decodeIfPresent(String.self, forKey: .variantLabel) ?? ""
        maxPerMember = try c.decodeIfPresent(Int.self, forKey: .maxPerMember)
        maxTotal = try c.decodeIfPresent(Int.self, forKey: .maxTotal)
        left = try c.decodeIfPresent(Int.self, forKey: .left)
    }

    /// Eingabefelder: je Größe oder Variante eins, ohne Auswahl ein Feld „Menge“ (leerer Text)
    public var choices: [String] { variants.isEmpty ? [""] : variants }

    /// Grenzen in einem Satz (wie im Browser).
    public var limitText: String {
        var parts: [String] = []
        if let n = maxPerMember { parts.append(tr("höchstens {n} je Mitglied", ["n": n])) }
        if let total = maxTotal {
            if let left {
                parts.append(tr("noch {n} von {m} verfügbar", ["n": left, "m": total]))
            } else {
                parts.append(tr("insgesamt {n}", ["n": total]))
            }
        }
        return parts.joined(separator: " · ")
    }
}

public struct MemberOrderLine: Decodable, Equatable, Sendable {
    public var article: Int
    public var name: String
    public var variant: String
    public var quantity: Int
    public var amount: String?

    enum CodingKeys: String, CodingKey { case article, name, variant, quantity, amount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        article = try c.decode(Int.self, forKey: .article)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        variant = try c.decodeIfPresent(String.self, forKey: .variant) ?? ""
        quantity = try c.decodeIfPresent(Int.self, forKey: .quantity) ?? 0
        amount = try c.decodeIfPresent(String.self, forKey: .amount)
    }
}

public struct OrderInvoice: Decodable, Equatable, Sendable {
    public var id: Int
    public var number: String
    public var outstanding: String?

    enum CodingKeys: String, CodingKey { case id, number, outstanding }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        outstanding = try c.decodeIfPresent(String.self, forKey: .outstanding)
    }

    /// Nichts mehr offen
    public var paid: Bool { (outstanding.flatMap(Geld.cents) ?? 0) == 0 }
}

public struct MemberOrder: Decodable, Equatable, Sendable {
    public var id: Int
    public var lines: [MemberOrderLine]
    public var note: String
    public var total: String?
    public var handedOut: Bool
    public var invoice: OrderInvoice?

    enum CodingKeys: String, CodingKey {
        case id, lines, note, total, invoice
        case handedOut = "handed_out"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        lines = try c.decodeIfPresent([MemberOrderLine].self, forKey: .lines) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        total = try c.decodeIfPresent(String.self, forKey: .total)
        handedOut = try c.decodeIfPresent(Bool.self, forKey: .handedOut) ?? false
        invoice = try c.decodeIfPresent(OrderInvoice.self, forKey: .invoice)
    }

    /// Bestellte Positionen als Text, je Zeile „2 × Poloshirt (M)“.
    public var linesText: String {
        lines.map { "\($0.quantity) × \($0.name)" + ($0.variant.isEmpty ? "" : " (\($0.variant))") }
            .joined(separator: "\n")
    }

    /// Startwerte im Formular: Menge je Artikel und Auswahl
    public var values: [String: Int] {
        Dictionary(lines.map { (orderKey($0.article, $0.variant), $0.quantity) }, uniquingKeysWith: +)
    }
}

public struct OrderCampaign: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var deadline: String?
    /// draft | open | closed
    public var state: String
    public var from: String
    public var clubPays: Bool
    public var ordered: Bool
    public var canOrder: Bool
    public var order: MemberOrder?
    /// nur in der Einzelansicht
    public var text: String
    public var articles: [OrderArticle]

    enum CodingKeys: String, CodingKey {
        case id, title, deadline, state, from, ordered, order, text, articles
        case clubPays = "club_pays"
        case canOrder = "can_order"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        deadline = try c.decodeIfPresent(String.self, forKey: .deadline)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "open"
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        clubPays = try c.decodeIfPresent(Bool.self, forKey: .clubPays) ?? false
        ordered = try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
        canOrder = try c.decodeIfPresent(Bool.self, forKey: .canOrder) ?? false
        order = try c.decodeIfPresent(MemberOrder.self, forKey: .order)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        articles = try c.decodeIfPresent([OrderArticle].self, forKey: .articles) ?? []
    }

    public var isOpen: Bool { state == "open" }
    /// Preise zeigen: nicht, wenn der Verein bezahlt
    public var showPrices: Bool { !clubPays }

    /// Zweite Zeile: Absender, Frist, „Der Verein bezahlt“ (wie im Browser).
    public var line: String {
        let date = Zeit.plainDate(deadline)
        var parts = [from]
        parts.append(isOpen ? tr("Bestellen bis {date}", ["date": date]) : tr("Bestellfrist vorbei ({date})", ["date": date]))
        if clubPays { parts.append(tr("Der Verein bezahlt")) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct OrderCampaignList: Decodable, Equatable, Sendable {
    public var campaigns: [OrderCampaign]

    enum CodingKeys: String, CodingKey { case campaigns }

    public init(campaigns: [OrderCampaign] = []) { self.campaigns = campaigns }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        campaigns = try c.decodeIfPresent([OrderCampaign].self, forKey: .campaigns) ?? []
    }

    /// Offene Sammelbestellungen ohne eigene Bestellung
    public var openCount: Int { campaigns.filter { $0.isOpen && !$0.ordered }.count }

    /// Kurzstand neben „Bestellungen“ unter „Ich“.
    public var summary: String {
        if openCount > 0 { return trn("1 offen, jetzt bestellen", "{n} offen, jetzt bestellen", openCount) }
        if campaigns.isEmpty { return tr("Gerade keine Sammelbestellung") }
        return tr("Vereinskleidung und mehr gemeinsam bestellen")
    }
}

/// Eine Zeile der Bestellung zum Senden (leer insgesamt: zurückziehen)
public struct OrderInput: Equatable, Sendable {
    public var article: Int
    public var variant: String
    public var quantity: Int

    public init(article: Int, variant: String, quantity: Int) {
        self.article = article
        self.variant = variant
        self.quantity = quantity
    }
}

public func orderKey(_ article: Int, _ variant: String) -> String { "\(article)|\(variant)" }

/// Zeilen zum Senden aus den Eingaben je Artikel und Auswahl (leere und 0 fallen weg).
public func orderInputs(_ articles: [OrderArticle], _ values: [String: Int]) -> [OrderInput] {
    articles.flatMap { a in
        a.choices.compactMap { v -> OrderInput? in
            let n = values[orderKey(a.id, v)] ?? 0
            return n > 0 ? OrderInput(article: a.id, variant: v, quantity: n) : nil
        }
    }
}

/// Summe der Eingaben in Euro als Text („60.00“), `nil` ohne Preise.
public func orderTotal(_ articles: [OrderArticle], _ inputs: [OrderInput]) -> String? {
    var cents = 0
    var priced = false
    for line in inputs {
        guard let text = articles.first(where: { $0.id == line.article })?.price,
              let price = Geld.cents(text) else { continue }
        priced = true
        cents += price * line.quantity
    }
    guard priced else { return nil }
    return String(format: "%d.%02d", cents / 100, cents % 100)
}

/// Nutzlast für `PUT …/order/`
public func orderPayload(_ inputs: [OrderInput], note: String) -> [String: Any] {
    [
        "lines": inputs.map { ["article": $0.article, "variant": $0.variant, "quantity": $0.quantity] as [String: Any] },
        "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
    ]
}

extension PortalAccess {
    /// „Bestellungen“ unter „Ich“ (ältere Server ohne Modul: aus)
    public var hasOrders: Bool { ordersEnabled }
}

extension Api {
    public func memberOrders(accessId: Int) async throws -> OrderCampaignList {
        try await expect("GET", "/api/portal/\(accessId)/orders/")
    }

    public func memberOrderCampaign(accessId: Int, id: Int) async throws -> OrderCampaign {
        try await expect("GET", "/api/portal/\(accessId)/orders/\(id)/")
    }

    /// Bestellung ersetzen
    public func placeOrder(accessId: Int, id: Int, lines: [OrderInput], note: String) async throws -> OrderCampaign {
        try await expect("PUT", "/api/portal/\(accessId)/orders/\(id)/order/", json: orderPayload(lines, note: note))
    }

    public func withdrawOrder(accessId: Int, id: Int) async throws -> OrderCampaign {
        try await expect("DELETE", "/api/portal/\(accessId)/orders/\(id)/order/")
    }
}
