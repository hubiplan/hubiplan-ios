import Foundation

// Verwaltung in der App (Schritt A8/B2 der Android-App): Einheiten mit Verwaltungsrechten,
// Freischalten mit Passwort und Zwei-Faktor-Code, Vorstandsschlüssel `hpa_…` mit eigenem
// Schlüsselpaar, offene Punkte und Mitglieder (nur lesen).

/// Einheit mit Verwaltungsrechten.
public struct AdminUnit: Decodable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var type: String
    public var permissions: [String]
    /// "u": Einheit mit Rollen dort · "d": Untereinheit mit Rollen nur dort (Zugführung)
    public var scope: String
    /// Rechte als Bereiche mit Stufen (Server ab November 2026)
    public var stufen: Bool
    /// Eingeschaltete Module (ältere Server: leer)
    public var modules: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, type, permissions, scope, stufen, modules
    }

    public init(id: Int, name: String, type: String = "", permissions: [String] = [], scope: String = "u", stufen: Bool = false, modules: [String] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.permissions = permissions
        self.scope = scope
        self.stufen = stufen
        self.modules = modules
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        scope = try c.decodeIfPresent(String.self, forKey: .scope) ?? "u"
        stufen = try c.decodeIfPresent(Bool.self, forKey: .stufen) ?? false
        modules = try c.decodeIfPresent([String].self, forKey: .modules) ?? []
    }

    public var key: String { "\(scope):\(id)" }
    public var isDepartment: Bool { scope == "d" }

    /// Bereich „Mitglieder“ zeigen: mindestens lesen.
    public var showsMembers: Bool {
        if !isDepartment || stufen { return permissions.contains { $0.hasPrefix("members.") } }
        return permissions.contains { $0.hasPrefix("dept.members.") }
    }

    /// Fotos freigeben oder ablehnen: „bearbeiten“ im Bereich Fotos (früher photos.manage).
    public var canEditPhotos: Bool {
        permissions.contains("photos.edit") || permissions.contains("photos.manage")
    }

    /// Ausweise am Einlass prüfen: wer in der Einheit Mitglieder sieht.
    public var canCheckCards: Bool { !isDepartment && showsMembers }

    /// Bereiche dieser Fassung. Untereinheiten haben keine gemeinsame Liste offener Punkte.
    public var sections: [AdminSection] {
        var list: [AdminSection] = []
        if !isDepartment { list.append(.tasks) }
        if showsTodos { list.append(.todos) }
        if showsMembers { list.append(.members) }
        if showsEvents { list.append(.events) }
        if showsFinance { list.append(.finance) }
        if showsBilling { list.append(.billing) }
        if !isDepartment, showsMembers { list.append(.occasions) }
        if showsCompetitions { list.append(.competitions) }
        if showsPartners { list.append(.partners) }
        if showsQualifications { list.append(.qualifications) }
        if showsObligations { list.append(.obligations) }
        return list
    }

    /// Stammdaten und Kontakt ändern: in der Einheit „Mitglieder bearbeiten“; in einer
    /// Untereinheit nur die Kontaktdaten (früher dept.members.edit).
    public var canEditMembers: Bool {
        permissions.contains("members.edit") || (isDepartment && permissions.contains("dept.members.edit"))
    }

    /// Mitgliedsart, Untereinheit, Austritt, Wiedereintritt: nur in der Einheit mit „Mitglieder bearbeiten“.
    public var canManageMembers: Bool { !isDepartment && permissions.contains("members.edit") }
}

public enum AdminSection: String, Sendable, CaseIterable {
    case tasks, todos, members, events, finance, billing, occasions, competitions, partners, qualifications, obligations
}

/// Untereinheit mit Rollen nur dort (z. B. Zugführung).
public struct AdminDepartment: Decodable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var permissions: [String]
    public var stufen: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, permissions, stufen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        permissions = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        stufen = try c.decodeIfPresent(Bool.self, forKey: .stufen) ?? false
    }

    public var asUnit: AdminUnit {
        AdminUnit(id: id, name: name, type: "department", permissions: permissions, scope: "d", stufen: stufen)
    }
}

public struct AdminOverview: Decodable, Equatable, Sendable {
    public var units: [AdminUnit]
    public var departments: [AdminDepartment]
    public var twoFactor: Bool
    public var unlocked: Bool
    public var until: String?

    enum CodingKeys: String, CodingKey {
        case units, departments, unlocked, until
        case twoFactor = "two_factor"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = try c.decodeIfPresent([AdminUnit].self, forKey: .units) ?? []
        departments = try c.decodeIfPresent([AdminDepartment].self, forKey: .departments) ?? []
        twoFactor = try c.decodeIfPresent(Bool.self, forKey: .twoFactor) ?? false
        unlocked = try c.decodeIfPresent(Bool.self, forKey: .unlocked) ?? false
        until = try c.decodeIfPresent(String.self, forKey: .until)
    }

    /// Einheiten und Untereinheiten (Zugführung) zusammen, für die Auswahl.
    public var allUnits: [AdminUnit] { units + departments.map(\.asUnit) }
}

public struct AdminUnlock: Decodable, Equatable, Sendable {
    public var token: String
    public var until: String?
    public var signed: Bool

    enum CodingKeys: String, CodingKey {
        case token, until, signed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        until = try c.decodeIfPresent(String.self, forKey: .until)
        signed = try c.decodeIfPresent(Bool.self, forKey: .signed) ?? false
    }
}

/// Offener Punkt (Änderungsmeldung, Foto, Wechsel, Termin mit Rückmeldungen …).
public struct AdminTask: Decodable, Equatable, Sendable {
    public var kind: String
    public var kindLabel: String
    public var title: String
    public var detail: String
    public var createdAt: String?
    /// Änderungsmeldung, Aufgabe oder Termin, auf den der Punkt zeigt
    public var ref: Int?
    /// Mitglied, um das es geht (z. B. bei einem neuen Foto)
    public var membership: Int?

    enum CodingKeys: String, CodingKey {
        case kind, title, detail, ref, membership
        case kindLabel = "kind_label"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        ref = try? c.decodeIfPresent(Int.self, forKey: .ref)
        membership = try? c.decodeIfPresent(Int.self, forKey: .membership)
    }

    /// Wohin der Punkt in der App führt; nil: nur im Browser.
    public var target: AdminTarget? {
        if kind == "change_request" { return .changeRequests }
        if kind == "photo", let membership { return .member(membership) }
        if kind == "event", let ref { return .event(ref) }
        return nil
    }
}

public enum AdminTarget: Equatable, Sendable {
    case changeRequests
    case member(Int)
    case event(Int)
}

struct AdminTasks: Decodable {
    var items: [AdminTask]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([AdminTask].self, forKey: .items) ?? []
    }
}

/// Name einer Organisation mit Zusatz, wie im Browser („Musterbau GmbH – Niederlassung“).
public func organizationName(_ name: String, _ suffix: String) -> String {
    suffix.trimmingCharacters(in: .whitespaces).isEmpty ? name : "\(name) – \(suffix)"
}

/// Zeile der Mitgliederliste.
public struct MemberRow: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    /// "person" oder "organization" (ältere Stände: fehlt)
    public var kind: String
    public var lastName: String
    public var firstName: String
    public var nameSuffix: String
    public var memberType: String?
    public var status: String
    public var departments: [String]
    public var city: String

    enum CodingKeys: String, CodingKey {
        case id, kind, status, departments, city
        case lastName = "last_name"
        case firstName = "first_name"
        case nameSuffix = "name_suffix"
        case memberType = "member_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "person"
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        nameSuffix = try c.decodeIfPresent(String.self, forKey: .nameSuffix) ?? ""
        memberType = try c.decodeIfPresent(String.self, forKey: .memberType)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        departments = try c.decodeIfPresent([String].self, forKey: .departments) ?? []
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
    }

    public var isOrganization: Bool { kind == "organization" }

    /// „Nachname, Vorname“, Organisationen mit ihrem ganzen Namen.
    public var listName: String {
        isOrganization ? organizationName(lastName, nameSuffix) : "\(lastName), \(firstName)"
    }

    /// Zweite Zeile: Mitgliedsart, Untereinheiten, Ort (was da ist).
    public var listDetail: String {
        ([memberType ?? ""] + departments + [city]).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct MemberPage: Decodable, Equatable, Sendable {
    public var count: Int
    public var next: String?
    public var results: [MemberRow]

    enum CodingKeys: String, CodingKey { case count, next, results }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        next = try c.decodeIfPresent(String.self, forKey: .next)
        results = try c.decodeIfPresent([MemberRow].self, forKey: .results) ?? []
    }

    public var hasMore: Bool { next != nil }
}

public struct MemberDepartment: Decodable, Equatable, Sendable {
    public var id: Int
    /// Kennung der Untereinheit (fehlt bei älteren Ständen: 0)
    public var department: Int
    public var name: String
    public var validFrom: String
    public var validUntil: String?

    enum CodingKeys: String, CodingKey {
        case id, department
        case name = "department_name"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        department = try c.decodeIfPresent(Int.self, forKey: .department) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        validFrom = try c.decodeIfPresent(String.self, forKey: .validFrom) ?? ""
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
    }
}

/// Mitgliedsakte, soweit die App sie zeigt.
public struct MemberDetail: Decodable, Equatable, Sendable {
    public var id: Int
    public var kind: String
    public var lastName: String
    public var firstName: String
    public var title: String
    public var birthDate: String?
    public var clubNumber: String
    public var status: String
    public var typeName: String
    public var contact: Contact?
    public var departments: [MemberDepartment]
    /// Untereinheiten nur als Namen (Antwort für die Zugführung)
    public var departmentNames: [String]
    public var gender: String
    public var entryDate: String
    /// Freigegebenes Foto und ein neues, das auf Freigabe wartet (Pfade wie im Browser)
    public var photo: String?
    public var pendingPhoto: String?
    /// Laufende Mitgliedsart (Kennung), nil in Untereinheiten und bei Ehemaligen
    public var currentType: Int?
    public var paysFeeSelf: Bool
    /// Austrittsgründe zur Auswahl, wie der Server sie nennt
    public var exitReasons: [MemberChoice]
    var suffix: String
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, status, contact, departments, periods, organization, photo, gender
        case memberType = "member_type"
        case entryDate = "entry_date"
        case displayName = "display_name"
        case lastName = "last_name"
        case firstName = "first_name"
        case birthDate = "birth_date"
        case clubNumber = "club_number"
        case currentType = "current_type"
        case paysFeeSelf = "pays_fee_self"
        case exitReasons = "exit_reasons"
    }

    private struct TypeName: Decodable {
        var member_type: Int?
        var member_type_name: String?
    }

    private struct Period: Decodable {
        var entry_date: String?
    }

    private struct Organization: Decodable {
        var name_suffix: String?
    }

    private struct Photos: Decodable {
        struct Version: Decodable {
            var url: String?
        }

        var approved: Version?
        var pending: Version?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "person"
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
        clubNumber = try c.decodeIfPresent(String.self, forKey: .clubNumber) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? ""
        // Einheit: laufende Mitgliedsart als Objekt; Untereinheit (Zugführung): nur der Name
        let type = try c.decodeIfPresent(TypeName.self, forKey: .currentType)
        currentType = type?.member_type
        typeName = type?.member_type_name ?? (try? c.decodeIfPresent(String.self, forKey: .memberType)) ?? ""
        paysFeeSelf = (try? c.decodeIfPresent(Bool.self, forKey: .paysFeeSelf)) ?? true
        exitReasons = (try? c.decodeIfPresent([MemberChoice].self, forKey: .exitReasons)) ?? []
        contact = try c.decodeIfPresent(Contact.self, forKey: .contact)
        if let full = try? c.decodeIfPresent([MemberDepartment].self, forKey: .departments) {
            departments = full
            departmentNames = []
        } else {
            departments = []
            departmentNames = (try? c.decodeIfPresent([String].self, forKey: .departments)) ?? []
        }
        let periods = try c.decodeIfPresent([Period].self, forKey: .periods) ?? []
        // Erster Eintritt: frühester Zeitraum
        entryDate = periods.compactMap(\.entry_date).filter { !$0.isEmpty }.min()
            ?? (try? c.decodeIfPresent(String.self, forKey: .entryDate)) ?? ""
        suffix = try c.decodeIfPresent(Organization.self, forKey: .organization)?.name_suffix ?? ""
        displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
        let photos = try? c.decodeIfPresent(Photos.self, forKey: .photo)
        photo = photos?.approved?.url.flatMap { $0.isEmpty ? nil : $0 }
        pendingPhoto = photos?.pending?.url.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var isOrganization: Bool { kind == "organization" }
    public var isFormer: Bool { status == "former" }

    public var name: String {
        if isOrganization { return displayName.isEmpty ? organizationName(lastName, suffix) : displayName }
        return [title, firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Heute laufende Zugehörigkeiten (Untereinheiten); `today` als `JJJJ-MM-TT`.
    public func currentDepartments(today: String) -> [MemberDepartment] {
        departments.filter { $0.validFrom <= today && ($0.validUntil.map { $0 >= today } ?? true) }
    }

    /// Namen der heute laufenden Untereinheiten, für die Anzeige.
    public func departmentLabels(today: String) -> [String] {
        (departmentNames + currentDepartments(today: today).map(\.name)).filter { !$0.isEmpty }
    }
}

// MARK: Vorstandsschlüssel

/// Vorstandsschlüssel `hpa_…` mit seinem Schlüsselpaar. Liegt in der App nur im Schlüsselbund
/// hinter Face ID, Touch ID oder Gerätecode und im Arbeitsspeicher höchstens fünf Minuten.
public struct AdminAccess: Sendable {
    public let token: String
    /// Privater Teil des Schlüsselpaars in Rohform; nil: Freischaltung ohne Schlüsselpaar
    /// (ältere Instanz), Anfragen ohne Unterschrift
    let keyRaw: Data?
    let now: @Sendable () -> Date
    let nonce: @Sendable () -> String

    public init(
        token: String,
        key: P256.Signing.PrivateKey?,
        now: @escaping @Sendable () -> Date = { Date() },
        nonce: @escaping @Sendable () -> String = { SignedFormat.newNonce() }
    ) {
        self.token = token
        self.keyRaw = key?.rawRepresentation
        self.now = now
        self.nonce = nonce
    }

    public var key: P256.Signing.PrivateKey? {
        keyRaw.flatMap { try? P256.Signing.PrivateKey(rawRepresentation: $0) }
    }

    /// Zum Ablegen im Schlüsselbund: `Schlüssel` oder `Schlüssel Schlüsselpaar`.
    public var stored: String {
        guard let keyRaw else { return token }
        return token + " " + Base64Url.encode(keyRaw)
    }

    public init?(stored: String) {
        let parts = stored.split(separator: " ").map(String.init)
        guard let first = parts.first, first.hasPrefix("hpa_"), parts.count <= 2 else { return nil }
        var key: P256.Signing.PrivateKey?
        if parts.count == 2 {
            guard let raw = Base64Url.decode(parts[1]), let parsed = try? P256.Signing.PrivateKey(rawRepresentation: raw) else {
                return nil
            }
            key = parsed
        }
        self.init(token: first, key: key)
    }

    /// Kopfzeilen der Unterschrift (H7). `path`: Pfad samt Abfrage, wie er gesendet wird.
    func sign(_ headers: inout [String: String], server: String, method: String, path: String, body: Data) throws {
        guard let key else { return }
        let time = String(Int(now().timeIntervalSince1970))
        let nonce = SignedFormat.servers.knows(server) ? self.nonce() : ""
        let message = SignedFormat.adminMessage(
            method: method, path: path, timestamp: time, body: body, nonce: nonce,
            idempotency: headers[SignedFormat.idempotencyHeader] ?? ""
        )
        headers[SignedFormat.timeHeader] = time
        headers[SignedFormat.signatureHeader] = try SignedFormat.sign(message, with: key)
        if !nonce.isEmpty { headers[SignedFormat.nonceHeader] = nonce }
    }
}

/// Wann die Verwaltung sich von selbst sperrt (wie in der Android-App).
public enum AdminPause {
    /// Sekunden ohne Bedienung, nach denen neu entsperrt werden muss
    public static let idle = 300.0
    /// Sekunden im Hintergrund, nach denen gesperrt ist
    public static let background = 60.0

    public static func locked(sinceUse: Double) -> Bool { sinceUse > idle }
    public static func lockedAfterBackground(_ seconds: Double) -> Bool { seconds > background }
}

/// Zeichen, die in einem Abfragewert unverändert bleiben dürfen (alles andere percent-kodiert).
func queryValue(_ text: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
}

extension Api {
    /// Geräteschlüssel neben dem Vorstandsschlüssel (Härtung H3).
    public static let deviceHeader = "X-Hubiplan-Device"

    /// Einheiten mit Verwaltungsrechten; keine Daten.
    public func adminOverview() async throws -> AdminOverview {
        try await expect("GET", "/api/app/v1/admin/")
    }

    /// Mit Passwort und Zwei-Faktor-Code freischalten; liefert den Vorstandsschlüssel.
    /// `adminKey`: öffentlicher Teil des neuen Vorstands-Schlüsselpaars.
    public func unlockAdmin(password: String, code: String, adminKey: String) async throws -> AdminUnlock {
        try await expect("POST", "/api/app/v1/admin/unlock/", json: [
            "password": password, "code": code, "admin_key": adminKey,
        ])
    }

    /// Verwaltung auf diesem Gerät sperren (das Gerät bleibt angemeldet).
    public func lockAdmin() async throws {
        let _: Ignored = try await expect("DELETE", "/api/app/v1/admin/unlock/")
    }

    /// Dieselbe Instanz mit dem Vorstandsschlüssel; nur für Pfade der Verwaltung.
    public func verwaltung(_ access: AdminAccess) -> Api {
        var copy = self
        copy.admin = access
        return copy
    }
}

/// Verwaltung einer Einheit mit dem Vorstandsschlüssel. Pfade wie im Browser, nur unter
/// `/api/app/v1/admin/u|d/<Einheit>/`.
public struct AdminClient: Sendable {
    let api: Api
    public let unit: AdminUnit

    /// `api`: Ergebnis von `Api.verwaltung`.
    public init(api: Api, unit: AdminUnit) {
        self.api = api
        self.unit = unit
    }

    var base: String { "/api/app/v1/admin/\(unit.isDepartment ? "d" : "u")/\(unit.id)/" }

    /// Offene Punkte wie auf der Startseite; Untereinheiten haben keine.
    public func tasks() async throws -> [AdminTask] {
        if unit.isDepartment { return [] }
        let list: AdminTasks = try await api.expect("GET", base + "tasks/")
        return list.items
    }

    /// `status`: "aktiv", "ehemalig" oder "alle" (Filter wie im Browser).
    /// Untereinheiten kennen den Filter nicht (dort nur die aktuellen Mitglieder).
    public func members(search: String, page: Int = 1, status: String = "aktiv") async throws -> MemberPage {
        let q = queryValue(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let filter = unit.isDepartment ? "" : "&status=\(queryValue(status))"
        return try await api.expect("GET", base + "members/?suche=\(q)\(filter)&page=\(max(1, page))&page_size=50")
    }

    /// Stammdaten und Kontakt ändern (nur geänderte Felder, siehe `MasterData.changes`).
    public func update(member id: Int, values: [String: String]) async throws -> (member: MemberDetail, change: AdminChange) {
        try await memberChange("PATCH", "members/\(id)/", values)
    }

    /// Änderung an einem Mitglied; die Antwort ist die neue Akte.
    func memberChange(_ method: String, _ path: String, _ json: [String: Any]) async throws -> (member: MemberDetail, change: AdminChange) {
        let response = try await api.raw(method, base + path, json: json)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
        guard let member = try? JSONDecoder().decode(MemberDetail.self, from: response.body) else {
            throw ApiError(status: response.status, code: "format")
        }
        return (member, AdminChange(response))
    }

    /// Geburtstage von `from` bis `to` (`JJJJ-MM-TT`), nur in der Einheit.
    public func birthdays(from: String, to: String) async throws -> [BirthdayRow] {
        let rows: Rows<BirthdayRow> = try await api.expect("GET", base + "birthdays/?von=\(queryValue(from))&bis=\(queryValue(to))")
        return rows.results
    }

    /// Jubiläen von `from` bis `to` (`JJJJ-MM-TT`), nur in der Einheit.
    public func jubilees(from: String, to: String) async throws -> [JubileeRow] {
        let rows: Rows<JubileeRow> = try await api.expect("GET", base + "jubilees/?von=\(queryValue(from))&bis=\(queryValue(to))")
        return rows.results
    }

    public func member(_ id: Int) async throws -> MemberDetail {
        try await api.expect("GET", base + "members/\(id)/")
    }

    /// Offene Änderungsmeldungen der Mitglieder.
    public func changeRequests() async throws -> [AdminChangeRequest] {
        try await api.expect("GET", base + "change-requests/")
    }

    /// Änderungsmeldung entscheiden. 409: seit der Meldung im Verein geändert (`overwrite`).
    public func decide(_ id: Int, accept: Bool, overwrite: Bool = false) async throws -> AdminChange {
        try await change("POST", "change-requests/\(id)/decide/", ["accept": accept, "response": "", "overwrite": overwrite])
    }

    /// Neues Foto eines Mitglieds freigeben oder ablehnen.
    public func decidePhoto(member id: Int, approve: Bool) async throws -> AdminChange {
        try await change("POST", "members/\(id)/photo/approve/", ["decision": approve ? "approve" : "reject"])
    }

    /// Änderung zurücknehmen (Kennung aus `AdminChange.changeSet`).
    /// `task`: Aufgabe, zu der die Änderung gehört (`AdminChange.task`); sie hat ihren eigenen Rückweg.
    public func undo(_ changeSet: String, task: Int? = nil) async throws {
        guard !changeSet.isEmpty, changeSet.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw ApiError(status: 0, code: "format")
        }
        let prefix = task.map { "todos/\($0)/" } ?? ""
        _ = try await change("POST", "\(prefix)changes/\(changeSet)/undo/", [:])
    }

    /// Ausweis am Einlass prüfen; `code`: Inhalt des QR-Codes.
    public func checkCard(code: String) async throws -> CardCheck {
        try await api.expect("POST", base + "cards/check/", json: ["code": code])
    }

    /// Bildpfad aus einer Antwort (`/api/orgs/<Einheit>/…`) auf den Verwaltungspfad umstellen;
    /// nil, wenn der Pfad nicht zu dieser Einheit gehört.
    public func imagePath(_ path: String) -> String? {
        let prefix = "/api/orgs/\(unit.id)/"
        if path.hasPrefix(prefix) { return base + String(path.dropFirst(prefix.count)) }
        return path.hasPrefix(base) ? path : nil
    }

    /// Foto aus der Akte; nil, wenn es nicht zu laden ist.
    public func image(_ path: String) async -> Data? {
        guard let target = imagePath(path) else { return nil }
        return await api.image(target)
    }

    func change(_ method: String, _ path: String, _ json: [String: Any]?) async throws -> AdminChange {
        let response = try await api.raw(method, base + path, json: json)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
        return AdminChange(response)
    }
}

/// Ergebnis einer Änderung: Paket für „Rückgängig“, soweit der Server es anbietet.
public struct AdminChange: Equatable, Sendable {
    public var changeSet: String?
    public var label: String
    /// Aufgabe, zu der die Änderung gehört (Kopfzeile `X-Change-Task`); nur für „Rückgängig“
    public var task: Int?

    init(_ response: HttpResponse) {
        let undoable = response.header("X-Change-Undoable") == "1"
        changeSet = undoable ? response.header("X-Change-Set").flatMap { $0.isEmpty ? nil : $0 } : nil
        label = response.header("X-Change-Label").flatMap { $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding } ?? ""
        task = changeSet == nil ? nil : response.header("X-Change-Task").flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// Änderungsmeldung eines Mitglieds (eigene Daten im Mitgliederbereich geändert).
public struct AdminChangeRequest: Decodable, Equatable, Sendable, Identifiable {
    public struct Line: Equatable, Sendable {
        public var key: String
        public var old: String
        public var new: String

        /// „Telefon: alt → neu“, leere Werte als „–“.
        public var text: String { "\(ChangeField.label(key)): \(ChangeField.display(key, old)) → \(ChangeField.display(key, new))" }
    }

    public var id: Int
    public var memberId: Int
    public var memberName: String
    public var message: String
    public var createdAt: String?
    public var lines: [Line]

    enum CodingKeys: String, CodingKey {
        case id, data, previous, message
        case memberId = "member_id"
        case memberName = "member_name"
        case createdAt = "created_at"
    }

    /// Wert einer Meldung: Text, Zahl, Wahrheitswert oder nichts.
    private struct Wert: Decodable {
        var text: String

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                text = ""
            } else if let value = try? c.decode(String.self) {
                text = value
            } else if let value = try? c.decode(Int.self) {
                text = String(value)
            } else if let value = try? c.decode(Double.self) {
                text = String(value)
            } else if let value = try? c.decode(Bool.self) {
                text = value ? "true" : "false"
            } else {
                text = ""
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        memberId = try c.decode(Int.self, forKey: .memberId)
        memberName = try c.decodeIfPresent(String.self, forKey: .memberName) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        let data = try c.decodeIfPresent([String: Wert].self, forKey: .data) ?? [:]
        let previous = (try? c.decodeIfPresent([String: Wert].self, forKey: .previous)) ?? [:]
        // Feste Reihenfolge: bekannte Felder wie im Formular, unbekannte danach nach Namen
        lines = data.keys.sorted { ChangeField.rank($0) < ChangeField.rank($1) }.map {
            Line(key: $0, old: previous[$0]?.text ?? "", new: data[$0]?.text ?? "")
        }
    }
}

/// Felder der Stammdaten, wie Mitglieder sie melden.
public enum ChangeField {
    static let order = [
        "title", "first_name", "last_name", "birth_date", "gender", "club_number",
        "email", "phone", "street", "postal_code", "city", "country",
    ]

    static func rank(_ key: String) -> String {
        if let index = order.firstIndex(of: key) { return String(format: "0%02d", index) }
        return "1" + key
    }

    public static func label(_ key: String) -> String {
        switch key {
        case "first_name": return tr("Vorname")
        case "last_name": return tr("Nachname")
        case "birth_date": return tr("Geburtsdatum")
        case "gender": return tr("Geschlecht")
        case "title": return tr("Titel")
        case "club_number": return tr("Mitgliedsnummer")
        case "email": return tr("E-Mail")
        case "phone": return tr("Telefon")
        case "street": return tr("Straße")
        case "postal_code": return tr("PLZ")
        case "city": return tr("Ort")
        case "country": return tr("Land")
        default: return key
        }
    }

    public static func display(_ key: String, _ value: String) -> String {
        if value.trimmingCharacters(in: .whitespaces).isEmpty { return "–" }
        if key == "birth_date" {
            let date = Zeit.plainDate(value)
            return date.isEmpty ? value : date
        }
        if key == "gender" {
            switch value {
            case "männlich": return tr("männlich")
            case "weiblich": return tr("weiblich")
            case "divers": return tr("divers")
            default: return value
            }
        }
        return value
    }
}

/// Ergebnis der Ausweisprüfung am Einlass.
public struct CardCheck: Decodable, Equatable, Sendable {
    public var kind: String
    public var status: String
    public var statusLabel: String
    public var firstName: String
    public var lastName: String
    public var memberType: String
    public var club: String
    public var departments: [String]
    public var photoUrl: String?
    public var membership: Int?

    enum CodingKeys: String, CodingKey {
        case kind, status, club, departments, membership
        case statusLabel = "status_label"
        case firstName = "first_name"
        case lastName = "last_name"
        case memberType = "member_type"
        case photoUrl = "photo_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "person"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        memberType = try c.decodeIfPresent(String.self, forKey: .memberType) ?? ""
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? ""
        departments = try c.decodeIfPresent([String].self, forKey: .departments) ?? []
        photoUrl = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        membership = try c.decodeIfPresent(Int.self, forKey: .membership)
    }

    public var valid: Bool { status == "active" }
    public var isOrganization: Bool { kind == "organization" }
    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
    public var detail: String { [memberType, club].filter { !$0.isEmpty }.joined(separator: " · ") }
}

struct Rows<Row: Decodable>: Decodable {
    var results: [Row]

    enum CodingKeys: String, CodingKey { case results }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([Row].self, forKey: .results) ?? []
    }
}

public struct BirthdayRow: Decodable, Equatable, Sendable {
    public var memberId: Int
    public var firstName: String
    public var lastName: String
    public var date: String
    public var age: Int

    enum CodingKeys: String, CodingKey {
        case date, age
        case memberId = "member_id"
        case firstName = "first_name"
        case lastName = "last_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try c.decode(Int.self, forKey: .memberId)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 0
    }

    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

public struct JubileeRow: Decodable, Equatable, Sendable {
    public var memberId: Int
    public var firstName: String
    public var lastName: String
    public var years: Int
    public var date: String
    /// Kurzname der Einheit, in der das Jubiläum zählt (z. B. Dachverband); leer: der Verein
    public var organization: String

    enum CodingKeys: String, CodingKey {
        case years, date
        case memberId = "member_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case organization = "organization_short"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try c.decode(Int.self, forKey: .memberId)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        years = try c.decodeIfPresent(Int.self, forKey: .years) ?? 0
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        organization = try c.decodeIfPresent(String.self, forKey: .organization) ?? ""
    }

    public var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// Dialog „Stammdaten und Kontakt“: Felder, Ausgangswerte und was davon zu senden ist.
public enum MasterData {
    static let personOnly: Set<String> = ["first_name", "birth_date", "gender", "title"]
    static let contact = ["phone", "email", "street", "postal_code", "city"]

    /// Felder des Dialogs. Organisationen ohne Vorname, Geburtsdatum, Geschlecht und Titel;
    /// in einer Untereinheit (Zugführung) nur die Kontaktdaten.
    public static func keys(organization: Bool, department: Bool) -> [String] {
        if department { return contact }
        let all = ["title", "first_name", "last_name", "birth_date", "gender", "club_number", "email", "phone", "street", "postal_code", "city", "country"]
        return all.filter { !(organization && personOnly.contains($0)) }
    }

    /// Ausgangswerte; das Geburtsdatum als `TT.MM.JJJJ`.
    public static func values(_ member: MemberDetail, department: Bool) -> [String: String] {
        let all: [String: String] = [
            "title": member.title, "first_name": member.firstName, "last_name": member.lastName,
            "birth_date": Zeit.plainDate(member.birthDate), "gender": member.gender, "club_number": member.clubNumber,
            "email": member.contact?.email ?? "", "phone": member.contact?.phone ?? "",
            "street": member.contact?.street ?? "", "postal_code": member.contact?.postalCode ?? "",
            "city": member.contact?.city ?? "", "country": member.contact?.country ?? "",
        ]
        let wanted = Set(keys(organization: member.isOrganization, department: department))
        return all.filter { wanted.contains($0.key) }
    }

    /// `TT.MM.JJJJ` (auch einstellig) oder `JJJJ-MM-TT` → `JJJJ-MM-TT`; nil, wenn es kein Datum ist.
    public static func parseDate(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        var parts = t.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3 {
            parts.reverse()
        } else {
            parts = t.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        }
        guard parts.count == 3, parts[0].count == 4, (1...2).contains(parts[1].count), (1...2).contains(parts[2].count),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), year >= 1
        else { return nil }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        guard (1...days).contains(day) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Geänderte Felder für die Anfrage: Text am Rand gekürzt, Geburtsdatum als `JJJJ-MM-TT`.
    /// Ein geleertes Geburtsdatum geht als "" mit (freiwillig, der Server entfernt es).
    /// nil, wenn das Datum ungültig ist.
    public static func changes(before: [String: String], after: [String: String]) -> [String: String]? {
        var out: [String: String] = [:]
        for (key, raw) in after {
            let value = raw.trimmingCharacters(in: .whitespaces)
            let old = (before[key] ?? "").trimmingCharacters(in: .whitespaces)
            if key == "birth_date" {
                if value.isEmpty {
                    if !old.isEmpty { out[key] = "" }
                    continue
                }
                guard let iso = parseDate(value) else { return nil }
                if iso != (parseDate(old) ?? old) { out[key] = iso }
            } else if value != old {
                out[key] = value
            }
        }
        return out
    }

    public static func label(_ key: String, organization: Bool) -> String {
        if key == "birth_date" { return tr("Geburtsdatum (freiwillig, TT.MM.JJJJ)") }
        if organization, key == "last_name" { return tr("Name der Organisation") }
        return ChangeField.label(key)
    }

    /// Zeitraum für Geburtstage und Jubiläen: heute bis in `days` Tagen.
    public static func upcoming(today: Date, days: Int, calendar: Calendar = .current) -> (from: String, to: String) {
        let end = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return (Zeit.day(today, timeZone: calendar.timeZone), Zeit.day(end, timeZone: calendar.timeZone))
    }
}
