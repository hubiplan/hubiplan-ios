import Foundation

public struct Contact: Decodable, Equatable, Sendable {
    public var email: String
    public var phone: String
    public var street: String
    public var postalCode: String
    public var city: String
    public var country: String

    enum CodingKeys: String, CodingKey {
        case email, phone, street, city, country
        case postalCode = "postal_code"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        street = try c.decodeIfPresent(String.self, forKey: .street) ?? ""
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
    }

    /// Anschrift in Zeilen, ohne leere Teile.
    public var addressLines: [String] {
        [street, "\(postalCode) \(city)".trimmingCharacters(in: .whitespaces), country]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// Eigene Daten des Mitglieds (`/api/portal/<Zugang>/`).
public struct Profile: Decodable, Equatable, Sendable {
    public var kind: String
    public var displayName: String
    public var firstName: String
    public var lastName: String
    public var birthDate: String?
    public var clubNumber: String
    public var memberType: String?
    public var entryDate: String?
    public var departments: [String]
    public var contact: Contact?
    public var status: String
    /// Kündigung im Mitgliederbereich (HUBIplan #402; ältere Stände: fehlt)
    public var cancellation: CancellationInfo?

    enum CodingKeys: String, CodingKey {
        case kind, departments, contact, status, cancellation
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case birthDate = "birth_date"
        case clubNumber = "club_number"
        case memberType = "member_type"
        case entryDate = "entry_date"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "person"
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
        clubNumber = try c.decodeIfPresent(String.self, forKey: .clubNumber) ?? ""
        memberType = try c.decodeIfPresent(String.self, forKey: .memberType)
        entryDate = try c.decodeIfPresent(String.self, forKey: .entryDate)
        departments = try c.decodeIfPresent([String].self, forKey: .departments) ?? []
        contact = try c.decodeIfPresent(Contact.self, forKey: .contact)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        cancellation = try c.decodeIfPresent(CancellationInfo.self, forKey: .cancellation)
    }

    public var isOrganization: Bool { kind == "organization" }

    public var name: String {
        if isOrganization { return displayName.isEmpty ? lastName : displayName }
        return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }
}

public struct MyInvoice: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var number: String
    public var status: String
    public var statusLabel: String
    public var date: String?
    public var dueDate: String?
    public var subject: String
    public var total: String
    public var outstanding: String
    public var overdue: Bool
    public var issuerName: String
    public var departmentName: String?
    /// Zur Rechnung gibt es eine Stornorechnung als PDF
    public var hasCancellationPdf: Bool

    enum CodingKeys: String, CodingKey {
        case id, number, status, date, subject, total, outstanding, overdue
        case hasCancellationPdf = "has_cancellation_pdf"
        case statusLabel = "status_label"
        case dueDate = "due_date"
        case issuerName = "issuer_name"
        case departmentName = "department_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        total = try c.decodeIfPresent(String.self, forKey: .total) ?? "0"
        outstanding = try c.decodeIfPresent(String.self, forKey: .outstanding) ?? "0"
        overdue = try c.decodeIfPresent(Bool.self, forKey: .overdue) ?? false
        issuerName = try c.decodeIfPresent(String.self, forKey: .issuerName) ?? ""
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName)
        hasCancellationPdf = try c.decodeIfPresent(Bool.self, forKey: .hasCancellationPdf) ?? false
    }

    public var open: Bool { status == "open" }

    /// Nummer, Datum und Aussteller in einer Zeile.
    public var headline: String {
        [number, Zeit.plainDate(date), departmentName ?? issuerName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Zustand in Worten: bei offenen Rechnungen Betrag und Fälligkeit.
    public var stateText: String {
        guard open else { return statusLabel }
        return tr("Offen: {betrag}, fällig am {datum}", ["betrag": Geld.format(outstanding), "datum": Zeit.plainDate(dueDate)])
    }
}

/// Beitrag, den die eigene Einheit über eine Sammelrechnung zahlt (die Rechnung bekommt sie).
public struct CollectiveLine: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var number: String
    public var date: String?
    public var subject: String
    public var departmentName: String
    public var amount: String
    public var statusLabel: String

    enum CodingKeys: String, CodingKey {
        case id, number, date, subject, amount
        case departmentName = "department_name"
        case statusLabel = "status_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName) ?? ""
        amount = try c.decodeIfPresent(String.self, forKey: .amount) ?? "0"
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
    }

    public var title: String { subject.isEmpty ? number : subject }
    /// Einheit, Datum, Betrag und Stand.
    public var line: String {
        [departmentName, Zeit.plainDate(date), Geld.format(amount), statusLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct MyInvoices: Decodable, Equatable, Sendable {
    public var invoices: [MyInvoice]
    public var collective: [CollectiveLine]

    enum CodingKeys: String, CodingKey { case invoices, collective }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        invoices = try c.decodeIfPresent([MyInvoice].self, forKey: .invoices) ?? []
        collective = try c.decodeIfPresent([CollectiveLine].self, forKey: .collective) ?? []
    }

    /// Offene zuerst, sonst wie geliefert (neueste oben).
    public var sorted: [MyInvoice] { invoices.filter(\.open) + invoices.filter { !$0.open } }

    /// Für die Seite „Ich“: offene Rechnungen (höchstens drei), ohne offene nur die neueste.
    /// Alle stehen auf einer eigenen Seite (UX-Audit 16.11., IOS-17).
    public var preview: [MyInvoice] {
        let open = invoices.filter(\.open)
        return open.isEmpty ? Array(invoices.prefix(1)) : Array(open.prefix(3))
    }

    /// Summe der offenen Beträge als Text, nil ohne offene.
    public var openSum: String? {
        let amounts = invoices.filter(\.open).compactMap { Geld.cents($0.outstanding) }
        return amounts.isEmpty ? nil : Geld.format(cents: amounts.reduce(0, +))
    }
}

/// Beträge der Schnittstelle („60.00“) für die Anzeige („60,00 €“), ohne Rundungsfehler.
public enum Geld {
    /// Betrag in Cent; nil, wenn der Text kein Betrag mit höchstens zwei Nachkommastellen ist.
    public static func cents(_ amount: String) -> Int? {
        var text = amount.trimmingCharacters(in: .whitespaces)
        let negative = text.hasPrefix("-")
        if negative { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = parts.first, !whole.isEmpty, whole.count <= 12,
              whole.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 2, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        while fraction.count < 2 { fraction += "0" }
        guard let euros = Int(whole), let rest = Int(fraction) else { return nil }
        let value = euros * 100 + rest
        return negative ? -value : value
    }

    public static func format(cents: Int) -> String {
        let digits = String(abs(cents) / 100)
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { grouped += "." }
            grouped.append(digit)
        }
        let sign = cents < 0 ? "-" : ""
        let rest = String(format: "%02d", abs(cents) % 100)
        // Englisch (britisch): „€1,234.50“
        if Texte.language == "en" { return sign + "€" + grouped.replacingOccurrences(of: ".", with: ",") + "." + rest }
        return sign + grouped + "," + rest + "\u{00A0}€"
    }

    /// „1234.5“ → „1.234,50 €“ (Englisch „€1,234.50“); leer, wenn der Text kein Betrag ist.
    public static func format(_ amount: String?) -> String {
        guard let amount, let value = cents(amount) else { return "" }
        return format(cents: value)
    }
}

extension Zeit {
    /// Datum ohne Uhrzeit („2026-11-20“) als „20.11.2026“ (Englisch „20/11/2026“, wie in der
    /// Android-App); leer, wenn es keines ist. Taugt auch als Vorgabe für ein Eingabefeld.
    public static func plainDate(_ iso: String?) -> String {
        guard let iso else { return "" }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return "" }
        let mark = Texte.language == "en" ? "/" : "."
        return parts[2] + mark + parts[1] + mark + parts[0]
    }

    /// Zeitpunkt als Datum ohne Wochentag, in derselben Form wie `plainDate` („20.11.2026“,
    /// Englisch „20/11/2026“), damit ein Datum überall gleich aussieht.
    public static func datum(_ date: Date, timeZone: TimeZone = .current) -> String {
        plainDate(day(date, timeZone: timeZone))
    }

    /// Datum und Uhrzeit („20.11.2026, 18:30“), Uhrzeit immer mit 24 Stunden.
    public static func datumUhrzeit(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return datum(date, timeZone: timeZone) + ", " + String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

extension Api {
    public func profile(accessId: Int) async throws -> Profile {
        try await expect("GET", "/api/portal/\(accessId)/")
    }

    public func myInvoices(accessId: Int) async throws -> MyInvoices {
        try await expect("GET", "/api/portal/\(accessId)/invoices/")
    }
}
