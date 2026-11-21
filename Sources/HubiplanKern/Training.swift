import Foundation

// Training und Anwesenheit im Mitgliederbereich (`/api/portal/<Zugang>/training/`), Beschreibung
// in hubiplan/docs/app.md und docs/training.md. Verhalten wie in der Android-App (Ich › Training):
// Einchecken per QR-Code, eigene Anwesenheit, mit Schießsport das eigene Schießbuch mit Stand nach
// § 14 WaffG; wer Trainings leiten darf, hakt Anwesende ab und zeigt den QR-Code.
// Nichts davon wird auf dem Gerät gespeichert.

/// QR-Code der Übungsleitung:
/// `https://<Instanz>/mein-bereich/training/da/<Training>?v=<Verein>&c=<Code>`.
public struct TrainingLink: Equatable, Sendable {
    public var server: String
    public var sessionId: Int
    public var clubId: Int
    public var code: String

    public init(server: String, sessionId: Int, clubId: Int, code: String) {
        self.server = server
        self.sessionId = sessionId
        self.clubId = clubId
        self.code = code
    }

    public static func parse(_ text: String) -> TrainingLink? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let server = httpsOrigin(parts) else { return nil }
        let path = parts.percentEncodedPath
        let prefix = "/mein-bereich/training/da/"
        guard path.hasPrefix(prefix) else { return nil }
        var number = String(path.dropFirst(prefix.count))
        if number.hasSuffix("/") { number.removeLast() }
        guard (1...10).contains(number.count), number.allSatisfy({ ("0"..."9").contains($0) }),
              let session = Int(number), session > 0 else { return nil }
        let query = parts.queryItems ?? []
        guard let club = query.first(where: { $0.name == "v" })?.value.flatMap({ Int($0) }), club > 0,
              let code = query.first(where: { $0.name == "c" })?.value, MeetingLink.codeOk(code) else { return nil }
        return TrainingLink(server: server, sessionId: session, clubId: club, code: code)
    }

    /// Inhalt des QR-Codes wie im Browser, aus dem aktuellen Code der Übungsleitung.
    public static func build(server: String, code: TrainingCode) -> String {
        var base = server
        while base.hasSuffix("/") { base.removeLast() }
        let c = code.code.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? code.code
        return "\(base)/mein-bereich/training/da/\(code.session)?v=\(code.club)&c=\(c)"
    }

    /// Gescannten Text prüfen: eigene Instanz, eigener Verein, gültiger Code.
    public static func from(scan text: String, server: String, clubId: Int) -> (link: TrainingLink?, problem: String?) {
        guard let link = parse(text) else {
            return (nil, tr("Das ist kein QR-Code zum Einchecken ins Training."))
        }
        if link.server != server { return (nil, tr("Der QR-Code gehört zu einer anderen HUBIplan-Adresse.")) }
        if clubId != 0 && link.clubId != clubId {
            return (nil, tr("Der QR-Code gehört zu einem anderen Verein. Wähle unter „Ich“ oben links den passenden Zugang."))
        }
        return (link, nil)
    }
}

public struct TrainingAttendance: Decodable, Equatable, Identifiable, Sendable {
    public var session: Int
    public var date: String
    public var title: String
    public var kindLabel: String
    public var departmentName: String
    public var source: String
    public var id: Int { session }

    enum CodingKeys: String, CodingKey {
        case session, date, title, source
        case kindLabel = "kind_label"
        case departmentName = "department_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        session = try c.decode(Int.self, forKey: .session)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "hand"
    }
}

public struct TrainingSessionInfo: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var departmentName: String
    public var date: String
    public var startsAt: String?
    public var endsAt: String?
    public var title: String
    public var discipline: String
    public var checkinOpen: Bool
    public var count: Int
    /// Nur in der Liste zum Einchecken: schon eingecheckt
    public var present: Bool

    enum CodingKeys: String, CodingKey {
        case id, date, title, discipline, count, present
        case departmentName = "department_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case checkinOpen = "checkin_open"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        discipline = try c.decodeIfPresent(String.self, forKey: .discipline) ?? ""
        checkinOpen = try c.decodeIfPresent(Bool.self, forKey: .checkinOpen) ?? false
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        present = try c.decodeIfPresent(Bool.self, forKey: .present) ?? false
    }
}

public struct ShootingEntry: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var date: String
    public var discipline: String
    public var weaponClassLabel: String
    public var caliber: String
    public var permitRequired: Bool
    public var competition: Bool
    public var place: String
    public var external: Bool
    public var status: String
    public var statusLabel: String

    enum CodingKeys: String, CodingKey {
        case id, date, discipline, caliber, competition, place, external, status
        case weaponClassLabel = "weapon_class_label"
        case permitRequired = "permit_required"
        case statusLabel = "status_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        discipline = try c.decodeIfPresent(String.self, forKey: .discipline) ?? ""
        weaponClassLabel = try c.decodeIfPresent(String.self, forKey: .weaponClassLabel) ?? ""
        caliber = try c.decodeIfPresent(String.self, forKey: .caliber) ?? ""
        permitRequired = try c.decodeIfPresent(Bool.self, forKey: .permitRequired) ?? true
        competition = try c.decodeIfPresent(Bool.self, forKey: .competition) ?? false
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        external = try c.decodeIfPresent(Bool.self, forKey: .external) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "confirmed"
        statusLabel = try c.decodeIfPresent(String.self, forKey: .statusLabel) ?? ""
    }

    /// Nur gemeldete, noch nicht bestätigte Einträge kann das Mitglied zurückziehen.
    public var canWithdraw: Bool { status == "reported" }

    /// Kurzzeile unter dem Eintrag, wie in Android und im Browser.
    public var details: String {
        [
            weaponClassLabel,
            caliber,
            place,
            competition ? tr("Wettkampf") : "",
            external ? tr("anderer Verein") : "",
            permitRequired ? "" : tr("erlaubnisfrei"),
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public struct ShootingAcquisition: Decodable, Equatable, Sendable {
    public var ok = false
    public var member12Months = false
    public var byMonths = false
    public var count = 0
    public var needed = 18
    public var longestGapDays = 0
    public var gapOk = true
    public var external = 0
    public var internalCount = 0
    public var mostlyOwnClub = true

    enum CodingKeys: String, CodingKey {
        case ok, count, needed, external
        case member12Months = "member_12_months"
        case byMonths = "by_months"
        case longestGapDays = "longest_gap_days"
        case gapOk = "gap_ok"
        case internalCount = "internal"
        case mostlyOwnClub = "mostly_own_club"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        member12Months = try c.decodeIfPresent(Bool.self, forKey: .member12Months) ?? false
        byMonths = try c.decodeIfPresent(Bool.self, forKey: .byMonths) ?? false
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
        needed = try c.decodeIfPresent(Int.self, forKey: .needed) ?? 18
        longestGapDays = try c.decodeIfPresent(Int.self, forKey: .longestGapDays) ?? 0
        gapOk = try c.decodeIfPresent(Bool.self, forKey: .gapOk) ?? true
        external = try c.decodeIfPresent(Int.self, forKey: .external) ?? 0
        internalCount = try c.decodeIfPresent(Int.self, forKey: .internalCount) ?? 0
        mostlyOwnClub = try c.decodeIfPresent(Bool.self, forKey: .mostlyOwnClub) ?? true
    }
}

public struct ShootingPossession: Decodable, Equatable, Sendable {
    public var label: String
    public var ok: Bool
    public var byQuarters: Bool
    public var bySix: Bool

    enum CodingKeys: String, CodingKey {
        case label, ok
        case byQuarters = "by_quarters"
        case bySix = "by_six"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        byQuarters = try c.decodeIfPresent(Bool.self, forKey: .byQuarters) ?? false
        bySix = try c.decodeIfPresent(Bool.self, forKey: .bySix) ?? false
    }
}

public struct ShootingEvaluation: Decodable, Equatable, Sendable {
    public var acquisition: ShootingAcquisition
    public var possession: [ShootingPossession]
    public var pending: Int

    enum CodingKeys: String, CodingKey { case acquisition, possession, pending }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        acquisition = try c.decodeIfPresent(ShootingAcquisition.self, forKey: .acquisition) ?? ShootingAcquisition()
        possession = try c.decodeIfPresent([ShootingPossession].self, forKey: .possession) ?? []
        pending = try c.decodeIfPresent(Int.self, forKey: .pending) ?? 0
    }

    /// Stand nach § 14 WaffG in Zeilen, wie in Android (`evaluationLines`).
    public var lines: [String] {
        let a = acquisition
        var out: [String] = []
        out.append(tr("Erwerb (Abs. 3): letzte 12 Monate") + ": " + okText(a.ok))
        out.append(a.member12Months ? tr("Seit mindestens zwölf Monaten Mitglied.") : tr("Noch keine zwölf Monate Mitglied."))
        out.append(tr("In jedem Monat geschossen: {state}.", ["state": okText(a.byMonths)]))
        out.append(tr("Termine insgesamt: {n} von {needed}.", ["n": a.count, "needed": a.needed]))
        if !a.gapOk {
            out.append(tr(
                "Längere Pause: {days} Tage ohne Schießtermin. Der BSSB erlaubt höchstens vier Monate ohne Begründung.",
                ["days": a.longestGapDays]
            ))
        }
        if !a.mostlyOwnClub {
            out.append(tr(
                "Mehr Termine in anderen Vereinen ({external}) als im eigenen ({internal}).",
                ["external": a.external, "internal": a.internalCount]
            ))
        }
        for p in possession {
            out.append(tr("Besitz (Abs. 4), {label}: letzte 24 Monate", ["label": p.label]) + ": " + okText(p.ok))
            out.append(tr("Jedes Quartal: {q}. Sechsmal je zwölf Monate: {six}.", ["q": okText(p.byQuarters), "six": okText(p.bySix)]))
        }
        if pending > 0 {
            out.append(tr("{n} gemeldete Termine warten auf die Bestätigung des Vereins.", ["n": pending]))
        }
        return out
    }
}

public func okText(_ ok: Bool) -> String { ok ? tr("erfüllt") : tr("nicht erfüllt") }

public struct OwnShootingLog: Decodable, Equatable, Sendable {
    public var entries: [ShootingEntry]
    public var evaluation: ShootingEvaluation?

    enum CodingKeys: String, CodingKey { case entries, evaluation }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([ShootingEntry].self, forKey: .entries) ?? []
        evaluation = try c.decodeIfPresent(ShootingEvaluation.self, forKey: .evaluation)
    }
}

public struct TrainingTarget: Decodable, Equatable, Hashable, Sendable {
    public var department: Int?
    public var name: String

    enum CodingKeys: String, CodingKey { case department, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        department = try c.decodeIfPresent(Int.self, forKey: .department)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

public struct MemberTraining: Decodable, Equatable, Sendable {
    public var attendance: [TrainingAttendance]
    public var countYear: Int
    public var count12: Int
    public var checkin: [TrainingSessionInfo]
    public var shootingEnabled: Bool
    /// Wo dieses Konto Trainings leiten darf
    public var targets: [TrainingTarget]
    public var shooting: OwnShootingLog?

    enum CodingKeys: String, CodingKey {
        case attendance, checkin, targets, shooting
        case countYear = "count_year"
        case count12 = "count_12"
        case shootingEnabled = "shooting_enabled"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attendance = try c.decodeIfPresent([TrainingAttendance].self, forKey: .attendance) ?? []
        countYear = try c.decodeIfPresent(Int.self, forKey: .countYear) ?? 0
        count12 = try c.decodeIfPresent(Int.self, forKey: .count12) ?? 0
        checkin = try c.decodeIfPresent([TrainingSessionInfo].self, forKey: .checkin) ?? []
        shootingEnabled = try c.decodeIfPresent(Bool.self, forKey: .shootingEnabled) ?? false
        targets = try c.decodeIfPresent([TrainingTarget].self, forKey: .targets) ?? []
        shooting = try c.decodeIfPresent(OwnShootingLog.self, forKey: .shooting)
    }

    /// Kurzstand neben „Training“, wie in Android (`trainingSummary`).
    public var summary: String {
        checkin.contains(where: { !$0.present })
            ? tr("Einchecken ist offen")
            : tr("Dieses Jahr {n}-mal da", ["n": countYear])
    }
}

/// Schießtermin melden (Mitglied)
public struct ShootingDraft: Equatable, Sendable {
    public var date: String
    public var discipline: String
    public var weaponClass = "short"
    public var caliber = ""
    public var permitRequired = true
    public var competition = false
    public var place = ""
    public var external = true

    public init(date: String, discipline: String) {
        self.date = date
        self.discipline = discipline
    }

    public var json: [String: Any] {
        [
            "date": date,
            "discipline": discipline.trimmingCharacters(in: .whitespacesAndNewlines),
            "weapon_class": weaponClass,
            "caliber": caliber.trimmingCharacters(in: .whitespacesAndNewlines),
            "permit_required": permitRequired,
            "competition": competition,
            "place": place.trimmingCharacters(in: .whitespacesAndNewlines),
            "external": external,
            "note": "",
        ]
    }
}

// MARK: Übungsleitung

public struct ManageTrainings: Decodable, Equatable, Sendable {
    public var sessions: [TrainingSessionInfo]
    public var targets: [TrainingTarget]

    enum CodingKeys: String, CodingKey { case sessions, targets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try c.decodeIfPresent([TrainingSessionInfo].self, forKey: .sessions) ?? []
        targets = try c.decodeIfPresent([TrainingTarget].self, forKey: .targets) ?? []
    }
}

public struct TrainingRow: Decodable, Equatable, Identifiable, Sendable {
    public var membership: Int
    public var name: String
    public var present: Bool
    public var source: String?
    public var id: Int { membership }

    enum CodingKeys: String, CodingKey { case membership, name, present, source }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        membership = try c.decode(Int.self, forKey: .membership)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        present = try c.decodeIfPresent(Bool.self, forKey: .present) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

public struct TrainingDetail: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var departmentName: String
    public var date: String
    public var startsAt: String?
    public var endsAt: String?
    public var title: String
    public var kindLabel: String
    public var location: String
    public var discipline: String
    public var checkinOpen: Bool
    public var checkinPossible: Bool
    public var attendance: [TrainingRow]

    enum CodingKeys: String, CodingKey {
        case id, date, title, location, discipline, attendance
        case departmentName = "department_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case kindLabel = "kind_label"
        case checkinOpen = "checkin_open"
        case checkinPossible = "checkin_possible"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        discipline = try c.decodeIfPresent(String.self, forKey: .discipline) ?? ""
        checkinOpen = try c.decodeIfPresent(Bool.self, forKey: .checkinOpen) ?? false
        checkinPossible = try c.decodeIfPresent(Bool.self, forKey: .checkinPossible) ?? false
        attendance = try c.decodeIfPresent([TrainingRow].self, forKey: .attendance) ?? []
    }

    public var presentCount: Int { attendance.filter(\.present).count }
}

public struct TrainingCode: Decodable, Equatable, Sendable {
    public var code: String
    public var refreshIn: Int
    public var session: Int
    public var club: Int
    public var count: Int

    enum CodingKeys: String, CodingKey {
        case code, session, club, count
        case refreshIn = "refresh_in"
    }

    public init(code: String, refreshIn: Int, session: Int, club: Int, count: Int = 0) {
        self.code = code
        self.refreshIn = refreshIn
        self.session = session
        self.club = club
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        refreshIn = try c.decodeIfPresent(Int.self, forKey: .refreshIn) ?? 30
        session = try c.decode(Int.self, forKey: .session)
        club = try c.decode(Int.self, forKey: .club)
        count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

/// „19:00–21:00“ bzw. „19:00“ oder leer
public func trainingTime(_ startsAt: String?, _ endsAt: String?) -> String {
    guard let start = startsAt, !start.isEmpty else { return "" }
    guard let end = endsAt, !end.isEmpty else { return start }
    return "\(start)–\(end)"
}

extension PortalAccess {
    /// „Training“ unter „Ich“ (Ansprechpartner von Organisationen nicht)
    public var hasTraining: Bool { trainingEnabled && !isContact }

    /// Kurzstand neben „Training“, bevor die Seite geladen ist.
    public var trainingHint: String {
        if trainingCheckin > 0 { return tr("Einchecken ist offen") }
        return shootingLogEnabled ? tr("Anwesenheit und Schießbuch") : tr("Deine Anwesenheit bei Übungsabenden")
    }
}

extension Api {
    public func memberTraining(accessId: Int) async throws -> MemberTraining {
        try await expect("GET", "/api/portal/\(accessId)/training/")
    }

    /// Einchecken mit dem Code aus dem QR-Code der Übungsleitung.
    public func trainingCheckin(accessId: Int, sessionId: Int, code: String) async throws -> MemberTraining {
        try await portalSend("POST", "/api/portal/\(accessId)/training/\(sessionId)/checkin/", json: ["code": code])
    }

    /// Schießtermin melden; `key` verhindert Doppelte nach einem Abbruch.
    public func reportShooting(accessId: Int, draft: ShootingDraft, key: String) async throws -> MemberTraining {
        try await portalSend("POST", "/api/portal/\(accessId)/training/shooting/", json: draft.json, key: key)
    }

    /// Gemeldeten, noch nicht bestätigten Schießtermin zurückziehen.
    public func withdrawShooting(accessId: Int, entryId: Int) async throws -> MemberTraining {
        try await portalSend("DELETE", "/api/portal/\(accessId)/training/shooting/\(entryId)/")
    }

    public func manageTrainings(accessId: Int) async throws -> ManageTrainings {
        try await expect("GET", "/api/portal/\(accessId)/training/manage/")
    }

    public func manageTraining(accessId: Int, sessionId: Int) async throws -> TrainingDetail {
        try await expect("GET", "/api/portal/\(accessId)/training/manage/\(sessionId)/")
    }

    /// Training anlegen (Verein oder Untereinheit); `key` verhindert Doppelte.
    public func createTraining(accessId: Int, department: Int?, date: String, title: String, kind: String, key: String) async throws -> TrainingDetail {
        var body: [String: Any] = ["date": date, "title": title, "kind": kind]
        body["department"] = department.map { $0 as Any } ?? NSNull()
        return try await portalSend("POST", "/api/portal/\(accessId)/training/manage/", json: body, key: key)
    }

    public func setTrainingPresent(accessId: Int, sessionId: Int, membership: Int, present: Bool) async throws -> TrainingDetail {
        try await portalSend("POST", "/api/portal/\(accessId)/training/manage/\(sessionId)/attendance/",
                             json: ["membership": membership, "present": present])
    }

    public func trainingCode(accessId: Int, sessionId: Int) async throws -> TrainingCode {
        try await expect("GET", "/api/portal/\(accessId)/training/manage/\(sessionId)/checkin/")
    }

    public func openTrainingCheckin(accessId: Int, sessionId: Int, open: Bool) async throws -> TrainingDetail {
        try await portalSend("POST", "/api/portal/\(accessId)/training/manage/\(sessionId)/checkin/", json: ["open": open])
    }
}
