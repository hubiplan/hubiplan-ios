import Foundation

/// Punkt der Tagesordnung.
public struct AgendaPoint: Decodable, Equatable, Sendable {
    public var position: Int
    public var title: String
    public var description: String
    /// 0 = Punkt, 1 = Unterpunkt
    public var level: Int
    /// Angezeigte Nummer, z. B. „8“ oder „8.1“; ältere Stände liefern sie nicht
    public var number: String

    enum CodingKeys: String, CodingKey { case position, title, description, level, number }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 0
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
    }

    public var shownNumber: String { number.isEmpty ? String(position) : number }
    public var line: String { "\(shownNumber). \(title)" }
}

/// Eigener Antrag zu einer Versammlung.
public struct OwnMotion: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var text: String
    public var status: String
    public var reply: String

    enum CodingKeys: String, CodingKey { case id, title, text, status, reply }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        reply = try c.decodeIfPresent(String.self, forKey: .reply) ?? ""
    }

    /// Zurückziehen geht nur, solange der Vorstand noch nicht entschieden hat.
    public var withdrawable: Bool { status == "submitted" }

    /// Stand in Worten (wie im Browser).
    public var statusText: String {
        switch status {
        case "submitted": return tr("eingereicht")
        case "accepted": return tr("in die Tagesordnung aufgenommen")
        case "rejected": return tr("nicht aufgenommen")
        case "withdrawn": return tr("zurückgezogen")
        default: return status
        }
    }
}

/// Bevorstehende Versammlung mit Tagesordnung und eigenen Anträgen.
public struct UpcomingMeeting: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var kindName: String
    public var unit: String
    public var startsAt: String?
    public var location: String
    public var address: String
    /// Letzter Zeitpunkt für Anträge; `nil`, wenn die Art keine Anträge vorsieht
    public var motionUntil: String?
    /// Anmeldung im Saal läuft (Ansicht „Versammlung läuft“)
    public var checkinOpen: Bool
    /// Teilnahme und Abstimmung aus der Ferne erlaubt (hybride Versammlung)
    public var remote: Bool
    public var motions: [OwnMotion]
    public var agenda: [AgendaPoint]

    enum CodingKeys: String, CodingKey {
        case id, title, unit, location, address, motions, agenda, remote
        case kindName = "kind_name"
        case startsAt = "starts_at"
        case motionUntil = "motion_until"
        case checkinOpen = "checkin_open"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindName = try c.decodeIfPresent(String.self, forKey: .kindName) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        motionUntil = try c.decodeIfPresent(String.self, forKey: .motionUntil)
        checkinOpen = try c.decodeIfPresent(Bool.self, forKey: .checkinOpen) ?? false
        remote = try c.decodeIfPresent(Bool.self, forKey: .remote) ?? false
        motions = try c.decodeIfPresent([OwnMotion].self, forKey: .motions) ?? []
        agenda = try c.decodeIfPresent([AgendaPoint].self, forKey: .agenda) ?? []
    }

    public var start: Date? { startsAt.flatMap(Zeit.parse) }

    /// Läuft die Frist für Anträge noch?
    public func motionsOpen(now: Date = Date()) -> Bool {
        guard let until = motionUntil.flatMap(Zeit.parse) else { return false }
        return until > now
    }

    /// Art und Einheit unter dem Titel (ohne Wiederholung des Titels).
    public var kindLine: String {
        [kindName, unit].filter { !$0.isEmpty && $0 != title }.joined(separator: " · ")
    }

    public var sortedAgenda: [AgendaPoint] { agenda.sorted { $0.position < $1.position } }
}

/// Vergangene Versammlung mit freigegebenem Protokoll.
public struct PastMeeting: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var kindName: String
    public var unit: String
    public var startsAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, unit
        case kindName = "kind_name"
        case startsAt = "starts_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindName = try c.decodeIfPresent(String.self, forKey: .kindName) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
    }

    public var start: Date? { startsAt.flatMap(Zeit.parse) }
}

public struct MyMeetings: Decodable, Equatable, Sendable {
    public var upcoming: [UpcomingMeeting]
    public var minutes: [PastMeeting]

    enum CodingKeys: String, CodingKey { case upcoming, minutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upcoming = try c.decodeIfPresent([UpcomingMeeting].self, forKey: .upcoming) ?? []
        minutes = try c.decodeIfPresent([PastMeeting].self, forKey: .minutes) ?? []
    }

    public var isEmpty: Bool { upcoming.isEmpty && minutes.isEmpty }
}

public struct DocVersion: Decodable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var size: Int
    public var contentType: String
    public var url: String

    enum CodingKeys: String, CodingKey {
        case id, name, size, url
        case contentType = "content_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

public struct MyDocument: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var date: String?
    public var note: String
    public var current: DocVersion?

    enum CodingKeys: String, CodingKey { case id, title, date, note, current }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        current = try c.decodeIfPresent(DocVersion.self, forKey: .current)
    }

    public var shownTitle: String { title.isEmpty ? (current?.name ?? "") : title }
    /// Datum und Hinweis unter dem Titel.
    public var line: String { [Zeit.plainDate(date), note].filter { !$0.isEmpty }.joined(separator: " · ") }
}

public struct DocFolder: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var department: String?
    public var documents: [MyDocument]

    enum CodingKeys: String, CodingKey { case id, name, department, documents }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        department = try c.decodeIfPresent(String.self, forKey: .department)
        documents = try c.decodeIfPresent([MyDocument].self, forKey: .documents) ?? []
    }

    public var heading: String { [name, department ?? ""].filter { !$0.isEmpty }.joined(separator: " · ") }
    /// Dokumente mit einer Fassung, die sich öffnen lässt.
    public var shown: [MyDocument] { documents.filter { $0.current != nil } }
}

public struct MyDocuments: Decodable, Equatable, Sendable {
    public var folders: [DocFolder]

    enum CodingKeys: String, CodingKey { case folders }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([DocFolder].self, forKey: .folders) ?? []
    }

    public var shown: [DocFolder] { folders.filter { !$0.shown.isEmpty } }
    public var count: Int { folders.reduce(0) { $0 + $1.shown.count } }
}

/// Dateien aus dem Mitgliederbereich nur zum Ansehen: Die App legt sie kurz ab und löscht sie
/// beim nächsten Öffnen, beim Start und beim Trennen. Gespeichert wird nichts.
public enum Ansicht {
    /// Höchste Größe einer Datei zum Ansehen.
    public static let maxBytes = 25 * 1024 * 1024

    /// Dateiname nur aus erlaubten Zeichen; der Rest wird zu „-“.
    public static func safeName(_ name: String, fallback: String = "datei.pdf") -> String {
        let last = name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        var cleaned = String(last.map { allowed.contains($0) ? $0 : "-" })
        while let first = cleaned.first, first == "." || first == "-" { cleaned.removeFirst() }
        while let end = cleaned.last, end == "." || end == "-" { cleaned.removeLast() }
        cleaned = String(cleaned.prefix(80))
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Nur Pfade des eigenen Mitgliederbereichs laden (der Link kommt vom Server, wird aber
    /// nicht blind übernommen): `/api/portal/<Zugang>/documents/versions/<Nr>/`.
    public static func documentPathOk(accessId: Int, path: String) -> Bool {
        let prefix = "/api/portal/\(accessId)/documents/versions/"
        guard path.hasPrefix(prefix), path.hasSuffix("/") else { return false }
        let number = path.dropFirst(prefix.count).dropLast()
        return !number.isEmpty && number.count <= 18 && number.allSatisfy { ("0"..."9").contains($0) }
    }
}

extension PortalAccess {
    public var hasMeetings: Bool { has(module: "meetings", fallback: meetingsEnabled) }
    public var hasDocs: Bool { has(module: "docs", fallback: docsEnabled) }
}

extension Api {
    public func myMeetings(accessId: Int) async throws -> MyMeetings {
        try await expect("GET", "/api/portal/\(accessId)/meetings/")
    }

    /// Antrag einreichen; die Antwort sind die eigenen Anträge zu dieser Versammlung.
    public func submitMotion(accessId: Int, meetingId: Int, title: String, text: String) async throws -> [OwnMotion] {
        try await expect("POST", "/api/portal/\(accessId)/meetings/\(meetingId)/motions/", json: ["title": title, "text": text])
    }

    public func withdrawMotion(accessId: Int, motionId: Int) async throws {
        let _: Ignored = try await expect("POST", "/api/portal/\(accessId)/meetings/motions/\(motionId)/withdraw/", json: [:])
    }

    public func myDocuments(accessId: Int) async throws -> MyDocuments {
        try await expect("GET", "/api/portal/\(accessId)/documents/")
    }

    /// Datei zum Ansehen (kein JSON, bis `Ansicht.maxBytes`).
    func file(_ path: String) async throws -> Data {
        let response = try await raw("GET", path, accept: false, limit: Ansicht.maxBytes)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
        return response.body
    }

    /// Freigegebenes Protokoll einer Versammlung als PDF.
    public func minutesPdf(accessId: Int, meetingId: Int) async throws -> Data {
        try await file("/api/portal/\(accessId)/meetings/\(meetingId)/minutes/")
    }

    /// Aktuelle Fassung eines Dokuments; nur Pfade des eigenen Mitgliederbereichs.
    public func documentFile(accessId: Int, path: String) async throws -> Data {
        guard Ansicht.documentPathOk(accessId: accessId, path: path) else { throw ApiError(status: 0, code: "format") }
        return try await file(path)
    }
}
