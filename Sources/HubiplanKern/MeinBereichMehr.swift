import Foundation

// Weitere Teile von „Mein Bereich“ wie in der Android-App: Lastschriftmandat (nur ansehen),
// Bereich „Mitarbeiter“ für Organisationen und der Ausweis als Apple-Wallet-Pass.

public struct MyMandate: Decodable, Equatable, Sendable {
    public var reference: String
    public var schemeLabel: String
    public var statusLabel: String
    public var holder: String
    public var ibanMasked: String
    public var signedOn: String?

    enum CodingKeys: String, CodingKey {
        case reference, holder
        case schemeLabel = "scheme_label"
        case statusLabel = "status_label"
        case ibanMasked = "iban_masked"
        case signedOn = "signed_on"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reference = try c.decodeIfPresent(String.self, forKey: .reference) ?? ""
        schemeLabel = try c.decodeIfPresent(String.self, forKey: .schemeLabel) ?? ""
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        holder = try c.decodeIfPresent(String.self, forKey: .holder) ?? ""
        ibanMasked = try c.decodeIfPresent(String.self, forKey: .ibanMasked) ?? ""
        signedOn = try c.decodeIfPresent(String.self, forKey: .signedOn)
    }

    /// Zeilen für die Anzeige (ohne leere).
    public var lines: [String] {
        var out = [[schemeLabel, statusLabel].filter { !$0.isEmpty }.joined(separator: " · ")]
        out.append(tr("Mandatsreferenz: {x1}", ["x1": reference]))
        if !ibanMasked.isEmpty { out.append(tr("Konto: {x1}", ["x1": ibanMasked])) }
        if !holder.isEmpty { out.append(tr("Kontoinhaber: {x1}", ["x1": holder])) }
        let signed = Zeit.plainDate(signedOn)
        if !signed.isEmpty { out.append(tr("Erteilt am {x1}", ["x1": signed])) }
        return out.filter { !$0.isEmpty }
    }
}

/// Lastschrift im Mitgliederbereich (`portal/<Zugang>/mandate/`); die App zeigt nur an.
public struct MandateState: Decodable, Equatable, Sendable {
    public var available: Bool
    public var clubName: String
    public var creditorId: String
    public var mandate: MyMandate?

    enum CodingKeys: String, CodingKey {
        case available, mandate
        case clubName = "club_name"
        case creditorId = "creditor_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName) ?? ""
        creditorId = try c.decodeIfPresent(String.self, forKey: .creditorId) ?? ""
        mandate = try c.decodeIfPresent(MyMandate.self, forKey: .mandate)
    }

    /// Abschnitt „Lastschrift“ zeigen: mit Mandat oder wenn der Verein Lastschriften anbietet.
    public var shown: Bool { mandate != nil || available }
}

/// Mitglied, für das die Firma zahlt (nur Name und Zeitraum).
public struct CompanyMember: Decodable, Equatable, Identifiable, Sendable {
    public var link: Int
    public var name: String
    public var since: String?
    public var until: String?
    public var paysVia: Bool
    public var id: Int { link }

    enum CodingKeys: String, CodingKey {
        case link, name, since, until
        case paysVia = "pays_via"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        link = try c.decode(Int.self, forKey: .link)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        since = try c.decodeIfPresent(String.self, forKey: .since)
        until = try c.decodeIfPresent(String.self, forKey: .until)
        paysVia = try c.decodeIfPresent(Bool.self, forKey: .paysVia) ?? false
    }

    /// Zeitraum und Beitrag in einer Zeile (wie im Browser).
    public var line: String {
        var parts: [String] = []
        let from = Zeit.plainDate(since), to = Zeit.plainDate(until)
        if !from.isEmpty { parts.append(tr("seit {date}", ["date": from])) }
        if !to.isEmpty { parts.append(tr("bis {date}", ["date": to])) }
        if paysVia { parts.append(tr("über die Firma")) }
        return parts.joined(separator: " · ")
    }
}

public struct CompanyEntry: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var members: [CompanyMember]

    enum CodingKeys: String, CodingKey { case id, name, members }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        members = try c.decodeIfPresent([CompanyMember].self, forKey: .members) ?? []
    }
}

/// `GET /api/portal/<Zugang>/company/`
public struct CompanyOverview: Decodable, Equatable, Sendable {
    public var canReport: Bool
    public var companies: [CompanyEntry]

    enum CodingKeys: String, CodingKey {
        case companies
        case canReport = "can_report"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canReport = try c.decodeIfPresent(Bool.self, forKey: .canReport) ?? false
        companies = try c.decodeIfPresent([CompanyEntry].self, forKey: .companies) ?? []
    }
}

extension Api {
    public func myMandate(accessId: Int) async throws -> MandateState {
        try await expect("GET", "/api/portal/\(accessId)/mandate/")
    }

    public func myCompanies(accessId: Int) async throws -> CompanyOverview {
        try await expect("GET", "/api/portal/\(accessId)/company/")
    }

    /// Neuen Mitarbeiter melden: Die Person bekommt per Mail den Link zum Online-Antrag.
    public func reportEmployee(accessId: Int, company: Int, firstName: String, lastName: String, email: String) async throws {
        let _: Ignored = try await expect("POST", "/api/portal/\(accessId)/company/\(company)/report/",
                                          json: ["first_name": firstName, "last_name": lastName, "email": email])
    }

    /// Rechnung (oder ihre Stornorechnung) als PDF, nur zum Ansehen.
    public func invoicePdf(accessId: Int, invoiceId: Int, cancellation: Bool = false) async throws -> Data {
        try await file("/api/portal/\(accessId)/invoices/\(invoiceId)/pdf/" + (cancellation ? "?storno=1" : ""))
    }

    /// Ausweis als Apple-Wallet-Pass (`.pkpass`); die App gibt ihn nur an Wallet weiter.
    public func walletPass(accessId: Int) async throws -> Data {
        try await file("/api/portal/\(accessId)/card/wallet/apple/")
    }
}
