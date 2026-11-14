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
        if showsMembers { list.append(.members) }
        return list
    }
}

public enum AdminSection: String, Sendable, CaseIterable {
    case tasks, members
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
        return nil
    }
}

public enum AdminTarget: Equatable, Sendable {
    case changeRequests
    case member(Int)
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
    public var name: String
    public var validFrom: String
    public var validUntil: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name = "department_name"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        validFrom = try c.decodeIfPresent(String.self, forKey: .validFrom) ?? ""
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
    }
}

/// Mitgliedsakte, soweit die App sie in dieser Fassung zeigt (nur lesen).
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
    public var entryDate: String
    /// Freigegebenes Foto und ein neues, das auf Freigabe wartet (Pfade wie im Browser)
    public var photo: String?
    public var pendingPhoto: String?
    var suffix: String

    enum CodingKeys: String, CodingKey {
        case id, kind, title, status, contact, departments, periods, organization, photo
        case lastName = "last_name"
        case firstName = "first_name"
        case birthDate = "birth_date"
        case clubNumber = "club_number"
        case currentType = "current_type"
    }

    private struct TypeName: Decodable {
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
        typeName = try c.decodeIfPresent(TypeName.self, forKey: .currentType)?.member_type_name ?? ""
        contact = try c.decodeIfPresent(Contact.self, forKey: .contact)
        departments = try c.decodeIfPresent([MemberDepartment].self, forKey: .departments) ?? []
        let periods = try c.decodeIfPresent([Period].self, forKey: .periods) ?? []
        // Erster Eintritt: frühester Zeitraum
        entryDate = periods.compactMap(\.entry_date).filter { !$0.isEmpty }.min() ?? ""
        suffix = try c.decodeIfPresent(Organization.self, forKey: .organization)?.name_suffix ?? ""
        let photos = try? c.decodeIfPresent(Photos.self, forKey: .photo)
        photo = photos?.approved?.url.flatMap { $0.isEmpty ? nil : $0 }
        pendingPhoto = photos?.pending?.url.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var isOrganization: Bool { kind == "organization" }
    public var isFormer: Bool { status == "former" }

    public var name: String {
        if isOrganization { return organizationName(lastName, suffix) }
        return [title, firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Heute laufende Zugehörigkeiten (Untereinheiten); `today` als `JJJJ-MM-TT`.
    public func currentDepartments(today: String) -> [MemberDepartment] {
        departments.filter { $0.validFrom <= today && ($0.validUntil.map { $0 >= today } ?? true) }
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
    public func members(search: String, page: Int = 1, status: String = "aktiv") async throws -> MemberPage {
        let q = queryValue(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await api.expect("GET", base + "members/?suche=\(q)&status=\(queryValue(status))&page=\(max(1, page))&page_size=50")
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
    public func undo(_ changeSet: String) async throws {
        guard !changeSet.isEmpty, changeSet.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw ApiError(status: 0, code: "format")
        }
        _ = try await change("POST", "changes/\(changeSet)/undo/", [:])
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

    private func change(_ method: String, _ path: String, _ json: [String: Any]) async throws -> AdminChange {
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

    init(_ response: HttpResponse) {
        let undoable = response.header("X-Change-Undoable") == "1"
        changeSet = undoable ? response.header("X-Change-Set").flatMap { $0.isEmpty ? nil : $0 } : nil
        label = response.header("X-Change-Label").flatMap { $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding } ?? ""
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
