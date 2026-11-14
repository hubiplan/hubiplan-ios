import Foundation

// Verwaltung in der App, nur zum Nachschlagen (wie in der Android-App): Geschäftspartner mit
// Ansprechpartnern, Qualifikationen, die bald ablaufen, und der Fristenkalender.
// Gepflegt wird alles im Browser.

extension AdminUnit {
    /// Bereich „Geschäftspartner“: nur in der Einheit selbst. Ältere Server melden das Recht nicht.
    public var showsPartners: Bool {
        !isDepartment && (permissions.contains("partners.view") || permissions.contains("partners.edit"))
    }

    /// Bereich „Qualifikationen“: Modul an, Mitglieder lesen, nur in der Einheit selbst.
    public var showsQualifications: Bool {
        !isDepartment && modules.contains("qualifications") && permissions.contains { $0.hasPrefix("members.") }
    }

    /// Bereich „Fristen“: Modul an und Recht zum Lesen, nur in der Einheit selbst.
    public var showsObligations: Bool {
        !isDepartment && modules.contains("obligations")
            && (permissions.contains("obligations.view") || permissions.contains("obligations.edit"))
    }
}

// MARK: Geschäftspartner

public struct PartnerDetails: Decodable, Equatable, Sendable {
    public var street = ""
    public var postcode = ""
    public var city = ""
    public var country = ""
    public var email = ""
    public var phone = ""
    public var website = ""

    enum CodingKeys: String, CodingKey { case street, postcode, city, country, email, phone, website }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        street = try c.decodeIfPresent(String.self, forKey: .street) ?? ""
        postcode = try c.decodeIfPresent(String.self, forKey: .postcode) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        website = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
    }

    /// Straße und „PLZ Ort“ in einer Zeile; leer, wenn nichts eingetragen ist.
    public var address: String {
        [street, "\(postcode) \(city)"].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

public struct PartnerContact: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var lastName: String
    public var firstName: String
    public var function: String
    public var email: String
    public var phone: String
    public var isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case id, function, email, phone
        case lastName = "last_name"
        case firstName = "first_name"
        case isPrimary = "is_primary"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        function = try c.decodeIfPresent(String.self, forKey: .function) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        isPrimary = try c.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }

    public var fullName: String {
        [firstName, lastName].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Funktion und „Hauptansprechpartner“; leer, wenn beides fehlt.
    public var info: String {
        [function.trimmingCharacters(in: .whitespaces), isPrimary ? tr("Hauptansprechpartner") : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct PartnerItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var roles: [String]
    public var number: String
    public var details: PartnerDetails
    public var notes: String
    public var contacts: [PartnerContact]

    enum CodingKeys: String, CodingKey { case id, name, roles, number, details, notes, contacts }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        roles = try c.decodeIfPresent([String].self, forKey: .roles) ?? []
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        details = try c.decodeIfPresent(PartnerDetails.self, forKey: .details) ?? PartnerDetails()
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        contacts = try c.decodeIfPresent([PartnerContact].self, forKey: .contacts) ?? []
    }

    /// Bezeichnung einer Rolle wie im Browser; unbekannte bleiben, wie sie sind.
    public static func roleLabel(_ role: String) -> String {
        switch role {
        case "supplier": return tr("Lieferant")
        case "service": return tr("Dienstleister")
        case "customer": return tr("Kunde/Auftraggeber")
        case "sponsor": return tr("Sponsor")
        case "donor": return tr("Spender")
        case "venue": return tr("Vermieter/Veranstaltungsort")
        case "artist": return tr("Künstler/Musiker")
        case "authority": return tr("Behörde")
        case "press": return tr("Presse")
        case "insurance": return tr("Versicherung")
        case "bank": return tr("Bank")
        default: return role
        }
    }

    public var roleText: String { roles.map(Self.roleLabel).joined(separator: ", ") }

    /// Zeile in der Liste: Rollen, Ort, erster Ansprechpartner.
    public var listDetail: String {
        [roleText, details.city.trimmingCharacters(in: .whitespaces), contacts.first?.fullName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Zeile auf der Seite des Partners: Nummer und Rollen.
    public var headline: String {
        [number.trimmingCharacters(in: .whitespaces), roleText].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: Qualifikationen

public struct QualificationRow: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var member: Int
    public var firstName: String
    public var lastName: String
    public var kindName: String
    public var validUntil: String?
    /// "expired", "expiring" oder gültig
    public var status: String

    enum CodingKeys: String, CodingKey {
        case id, member, status
        case firstName = "first_name"
        case lastName = "last_name"
        case kindName = "kind_name"
        case validUntil = "valid_until"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        member = try c.decodeIfPresent(Int.self, forKey: .member) ?? 0
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        kindName = try c.decodeIfPresent(String.self, forKey: .kindName) ?? ""
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    }

    public var name: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    public var statusText: String {
        switch status {
        case "expired": return tr("abgelaufen")
        case "expiring": return tr("läuft bald ab")
        default: return tr("gültig")
        }
    }

    /// Abgelaufen oder bald abgelaufen: hervorheben.
    public var urgent: Bool { status == "expired" || status == "expiring" }

    public var untilText: String {
        let day = Zeit.plainDate(validUntil)
        return day.isEmpty ? tr("unbefristet") : tr("bis {datum}", ["datum": day])
    }

    /// Zeile unter dem Namen: Art, Stand, Gültigkeit.
    public var detail: String {
        [kindName, statusText, untilText].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: Fristen

public struct ObligationDone: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var doneOn: String
    public var note: String
    public var doneBy: String

    enum CodingKeys: String, CodingKey {
        case id, note
        case doneOn = "done_on"
        case doneBy = "done_by"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        doneOn = try c.decodeIfPresent(String.self, forKey: .doneOn) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        doneBy = try c.decodeIfPresent(String.self, forKey: .doneBy) ?? ""
    }

    /// „erledigt am 03.03.2026 · Erika Musterfrau · Notiz“
    public var line: String {
        [tr("erledigt am {datum}", ["datum": Zeit.plainDate(doneOn)]), doneBy, note]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct ObligationItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var note: String
    public var dueDate: String?
    /// "overdue", "soon", "planned", "election", "done", "inactive"
    public var status: String
    public var roleName: String
    public var intervalMonths: Int?
    public var history: [ObligationDone]

    enum CodingKeys: String, CodingKey {
        case id, title, note, status, history
        case dueDate = "due_date"
        case roleName = "role_name"
        case intervalMonths = "interval_months"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        roleName = try c.decodeIfPresent(String.self, forKey: .roleName) ?? ""
        intervalMonths = try c.decodeIfPresent(Int.self, forKey: .intervalMonths)
        history = try c.decodeIfPresent([ObligationDone].self, forKey: .history) ?? []
    }

    public var statusText: String {
        switch status {
        case "overdue": return tr("überfällig")
        case "soon": return tr("bald fällig")
        case "planned": return tr("geplant")
        case "election": return tr("nach jeder Vorstandswahl")
        case "done": return tr("erledigt")
        case "inactive": return tr("abgeschaltet")
        default: return status
        }
    }

    public var urgent: Bool { status == "overdue" || status == "soon" }

    /// Stand, Frist und zuständige Rolle in einer Zeile.
    public var line: String {
        let day = Zeit.plainDate(dueDate)
        return [statusText, day.isEmpty ? "" : tr("Frist {datum}", ["datum": day]), roleName.trimmingCharacters(in: .whitespaces)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// „wiederholt sich alle 12 Monate“; nil ohne Wiederholung.
    public var repeatText: String? {
        intervalMonths.map { trn("wiederholt sich jeden Monat", "wiederholt sich alle {n} Monate", $0) }
    }

    /// Überfällige und bald fällige zuerst, dann nach Frist und Titel.
    public static func sorted(_ items: [ObligationItem]) -> [ObligationItem] {
        let rank = ["overdue": 0, "soon": 1, "planned": 2, "election": 3, "done": 4, "inactive": 5]
        func key(_ item: ObligationItem) -> (Int, String, String) {
            (rank[item.status] ?? 6, item.dueDate ?? "9999", item.title.lowercased())
        }
        return items.sorted { key($0) < key($1) }
    }
}

struct ObligationList: Decodable {
    var items: [ObligationItem]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([ObligationItem].self, forKey: .items) ?? []
    }
}

extension AdminClient {
    /// Geschäftspartner mit Ansprechpartnern; `search`: Name, Ort oder Ansprechpartner.
    public func partners(search: String) async throws -> [PartnerItem] {
        let q = queryValue(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let list: Listed<PartnerItem> = try await api.expect("GET", base + "billing/partners/?suche=\(q)")
        return list.rows
    }

    /// Nachweise der Mitglieder; `soonOnly`: nur die, die bald ablaufen oder abgelaufen sind.
    public func qualifications(soonOnly: Bool) async throws -> [QualificationRow] {
        let list: Listed<QualificationRow> = try await api.expect("GET", base + (soonOnly ? "qualifications/?stand=bald" : "qualifications/"))
        return list.rows
    }

    /// Pflichten des Fristenkalenders, überfällige zuerst.
    public func obligations() async throws -> [ObligationItem] {
        let list: ObligationList = try await api.expect("GET", base + "obligations/")
        return ObligationItem.sorted(list.items)
    }
}
