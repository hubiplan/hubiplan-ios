import Foundation

// Vorstandsaufgaben in der Verwaltung, wie in der Android-App (`AdminVorstand.kt`) und im
// Browser: Beitrittsanträge entscheiden, Belegungsanfragen freigeben, Versammlung leiten
// (hubiplan docs/app.md, „Vorstandsaufgaben“). Pfade unter `/api/app/v1/admin/<u|d>/<Einheit>/`.

private extension KeyedDecodingContainer {
    /// Wert oder Vorgabe, wenn das Feld fehlt, null ist oder einen anderen Typ hat.
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: Rechte

extension AdminUnit {
    /// Bereich „Beitrittsanträge“: Verein mit Mitgliederverwaltung, Recht Mitglieder lesen.
    public var showsApplications: Bool {
        !isDepartment && modules.contains("members") && permissions.contains { $0.hasPrefix("members.") }
    }

    /// Bereich „Belegung freigeben“: Modul Belegung und Recht zum Freigeben.
    public var showsBookings: Bool { modules.contains("bookings") && permissions.contains("bookings.edit") }

    /// Bereich „Versammlung leiten“: Modul Versammlungen und Recht zum Bearbeiten.
    public var showsMeetings: Bool { modules.contains("meetings") && permissions.contains("meetings.edit") }

    /// Anwesenheit und Einlass brauchen zusätzlich das Recht, Mitglieder zu lesen.
    public var canMeetingAttendance: Bool {
        permissions.contains { $0.hasPrefix("members.") || $0.hasPrefix("dept.members.") }
    }
}

// MARK: Beitrittsanträge

public let openApplicationStates: Set<String> = ["unsigned", "open", "query"]

public struct ApplicationRow: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var number: String
    public var status: String
    public var statusLabel: String
    public var name: String
    public var memberType: String
    public var unit: String
    public var minor: Bool
    public var createdAt: String?
    public var approvalsMet: Bool?
    public var disputed: Bool
    public var missing: [String]

    enum CodingKeys: String, CodingKey {
        case id, number, status, name, unit, minor, disputed, missing
        case statusLabel = "status_label"
        case memberType = "member_type"
        case createdAt = "created_at"
        case approvalsMet = "approvals_met"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = c.value(.number, "")
        status = c.value(.status, "")
        statusLabel = c.value(.statusLabel, "")
        name = c.value(.name, "")
        memberType = c.value(.memberType, "")
        unit = c.value(.unit, "")
        minor = c.value(.minor, false)
        createdAt = c.value(.createdAt, nil as String?)
        approvalsMet = c.value(.approvalsMet, nil as Bool?)
        disputed = c.value(.disputed, false)
        missing = c.value(.missing, [String]())
    }

    public var isOpen: Bool { openApplicationStates.contains(status) }

    /// Stand, Mitgliedsart und was noch fehlt in einer Zeile (wie Android `applicationLine`).
    public var line: String {
        var parts: [String] = []
        if !statusLabel.isEmpty { parts.append(statusLabel) }
        if !memberType.isEmpty { parts.append(memberType) }
        if !unit.isEmpty { parts.append(unit) }
        if minor { parts.append(tr("minderjährig")) }
        if disputed {
            parts.append(tr("Ablehnung liegt vor"))
        } else if status == "open", approvalsMet == false, !missing.isEmpty {
            parts.append(tr("es fehlt: {missing}", ["missing": missing.joined(separator: ", ")]))
        } else if status == "open", approvalsMet == true {
            parts.append(tr("bereit zur Aufnahme"))
        }
        return parts.joined(separator: " · ")
    }
}

public struct ApplicationList: Decodable, Equatable, Sendable {
    public var results: [ApplicationRow]
    public var ruleText: String
    public var mayApprove: Bool
    public var counts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case results, counts
        case ruleText = "rule_text"
        case mayApprove = "may_approve"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = try c.decodeIfPresent([ApplicationRow].self, forKey: .results) ?? []
        ruleText = c.value(.ruleText, "")
        mayApprove = c.value(.mayApprove, false)
        counts = c.value(.counts, [String: Int]())
    }
}

public struct ApplicationApproval: Decodable, Equatable, Sendable {
    public var userName: String
    public var roles: String
    public var decision: String
    public var note: String

    enum CodingKeys: String, CodingKey {
        case roles, decision, note
        case userName = "user_name"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userName = c.value(.userName, "")
        roles = c.value(.roles, "")
        decision = c.value(.decision, "")
        note = c.value(.note, "")
    }
}

public struct ApplicationMatch: Decodable, Equatable, Sendable {
    public var name: String
    public var birthDate: String?
    public var here: Bool
    public var former: Bool
    public var activeElsewhere: String

    enum CodingKeys: String, CodingKey {
        case name, here, former
        case birthDate = "birth_date"
        case activeElsewhere = "active_elsewhere"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.value(.name, "")
        birthDate = c.value(.birthDate, nil as String?)
        here = c.value(.here, false)
        former = c.value(.former, false)
        activeElsewhere = c.value(.activeElsewhere, "")
    }
}

public struct ApplicationDetail: Decodable, Equatable, Sendable {
    public var id: Int
    public var number: String
    public var status: String
    public var statusLabel: String
    public var name: String
    public var memberType: String
    public var approvalsMet: Bool?
    public var disputed: Bool
    public var missing: [String]
    public var summary: [String]
    public var approvals: [ApplicationApproval]
    public var matches: [ApplicationMatch]
    public var ruleText: String
    public var entryDate: String?
    public var mayApprove: Bool
    public var mayDecide: Bool
    public var ownDecision: String?
    public var decisionNote: String

    enum CodingKeys: String, CodingKey {
        case id, number, status, name, disputed, missing, summary, approvals, matches
        case statusLabel = "status_label"
        case memberType = "member_type"
        case approvalsMet = "approvals_met"
        case ruleText = "rule_text"
        case entryDate = "entry_date"
        case mayApprove = "may_approve"
        case mayDecide = "may_decide"
        case ownDecision = "own_decision"
        case decisionNote = "decision_note"
    }

    struct Matches: Decodable {
        var persons: [ApplicationMatch]?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = c.value(.number, "")
        status = c.value(.status, "")
        statusLabel = c.value(.statusLabel, "")
        name = c.value(.name, "")
        memberType = c.value(.memberType, "")
        approvalsMet = c.value(.approvalsMet, nil as Bool?)
        disputed = c.value(.disputed, false)
        missing = c.value(.missing, [String]())
        summary = c.value(.summary, [String]())
        approvals = (try? c.decodeIfPresent([ApplicationApproval].self, forKey: .approvals)) ?? []
        matches = ((try? c.decodeIfPresent(Matches.self, forKey: .matches)) ?? nil)?.persons ?? []
        ruleText = c.value(.ruleText, "")
        entryDate = c.value(.entryDate, nil as String?)
        mayApprove = c.value(.mayApprove, false)
        mayDecide = c.value(.mayDecide, false)
        ownDecision = c.value(.ownDecision, nil as String?)
        decisionNote = c.value(.decisionNote, "")
    }

    public var isOpen: Bool { openApplicationStates.contains(status) }
    /// Aufnehmen: eingegangen, alle Zustimmungen da, niemand hat abgelehnt.
    public var canAccept: Bool { mayDecide && status == "open" && approvalsMet != false && !disputed }
    public var canApprove: Bool { mayApprove && isOpen && ownDecision == nil }
}

// MARK: Belegung freigeben

public struct BookingRequest: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var itemTitle: String
    public var title: String
    public var note: String
    public var startsAt: String
    public var endsAt: String
    public var allDay: Bool
    public var repeats: Bool
    public var memberName: String
    public var bookedBy: String
    public var contactName: String
    public var version: Int

    enum CodingKeys: String, CodingKey {
        case id, title, note, repeat, version, contact
        case itemTitle = "item_title"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case allDay = "all_day"
        case memberName = "member_name"
        case bookedBy = "booked_by"
    }

    struct Contact: Decodable {
        var name: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        itemTitle = c.value(.itemTitle, "")
        title = c.value(.title, "")
        note = c.value(.note, "")
        startsAt = c.value(.startsAt, "")
        endsAt = c.value(.endsAt, "")
        allDay = c.value(.allDay, false)
        repeats = !c.value(.repeat, "").isEmpty
        memberName = c.value(.memberName, "")
        bookedBy = c.value(.bookedBy, "")
        contactName = ((try? c.decodeIfPresent(Contact.self, forKey: .contact)) ?? nil)?.name ?? ""
        version = c.value(.version, 1)
    }

    /// Wer angefragt hat: Mitglied, sonst Konto, sonst Kontakt (Gast).
    public var requester: String {
        if !memberName.isEmpty { return memberName }
        if !bookedBy.isEmpty { return bookedBy }
        return contactName
    }
}

struct BookingRequests: Decodable {
    var requests: [BookingRequest]

    enum CodingKeys: String, CodingKey { case requests }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decodeIfPresent([BookingRequest].self, forKey: .requests) ?? []
    }
}

// MARK: Versammlung leiten

public let liveMeetingStates: Set<String> = ["draft", "invited", "held"]

public struct LeadAgendaItem: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var number: String
    public var title: String
    public var type: String

    enum CodingKeys: String, CodingKey { case id, number, title, type }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        number = c.value(.number, "")
        title = c.value(.title, "")
        type = c.value(.type, "")
    }

    /// Abgestimmt wird nur bei Beschlüssen und Wahlen.
    public var votable: Bool { type == "resolution" || type == "election" }
    public var label: String { number.isEmpty ? title : "\(number) \(title)" }
}

public struct LeadMeeting: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var startsAt: String
    public var location: String
    public var status: String
    public var onlineVoting: Bool
    public var agenda: [LeadAgendaItem]

    enum CodingKeys: String, CodingKey {
        case id, title, location, status, agenda
        case startsAt = "starts_at"
        case onlineVoting = "online_voting"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = c.value(.title, "")
        startsAt = c.value(.startsAt, "")
        location = c.value(.location, "")
        status = c.value(.status, "")
        onlineVoting = c.value(.onlineVoting, false)
        agenda = (try? c.decodeIfPresent([LeadAgendaItem].self, forKey: .agenda)) ?? []
    }

    /// Leiten lässt sich, was noch nicht abgeschlossen ist.
    public var isLive: Bool { liveMeetingStates.contains(status) }

    public static func statusLabel(_ status: String) -> String {
        switch status {
        case "draft": return tr("in Vorbereitung")
        case "invited": return tr("eingeladen")
        case "held": return tr("gehalten")
        case "minutes": return tr("Protokoll in Arbeit")
        case "done": return tr("abgeschlossen")
        case "cancelled": return tr("abgesagt")
        default: return status
        }
    }
}

public struct AttendanceRow: Decodable, Equatable, Sendable {
    public var id: Int?
    public var membership: Int?
    public var name: String
    public var voter: Bool
    public var status: String
    public var mode: String

    enum CodingKeys: String, CodingKey { case id, membership, name, voter, status, mode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, nil as Int?)
        membership = c.value(.membership, nil as Int?)
        name = c.value(.name, "")
        voter = c.value(.voter, false)
        status = c.value(.status, "")
        mode = c.value(.mode, "")
    }

    public var present: Bool { status == "present" || status == "delegate" }
    public var key: String { "\(membership ?? 0)-\(id ?? 0)-\(name)" }

    /// Gast, Art der Anwesenheit (wie Android `attendanceLabel`).
    public var label: String {
        var parts: [String] = []
        if !voter { parts.append(tr("Gast")) }
        switch status {
        case "present":
            switch mode {
            case "app": parts.append(tr("per App angemeldet"))
            case "online": parts.append(tr("online dabei"))
            default: parts.append(tr("anwesend"))
            }
        case "delegate": parts.append(tr("durch Vertreter"))
        case "represented": parts.append(tr("vertreten"))
        case "excused": parts.append(tr("entschuldigt"))
        case "left": parts.append(tr("gegangen"))
        default: break
        }
        return parts.joined(separator: " · ")
    }
}

public struct AttendanceList: Decodable, Equatable, Sendable {
    public var voters: Int
    public var present: Int
    public var represented: Int
    public var guests: Int
    public var editable: Bool
    public var rows: [AttendanceRow]

    enum CodingKeys: String, CodingKey { case voters, present, represented, guests, editable, rows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voters = c.value(.voters, 0)
        present = c.value(.present, 0)
        represented = c.value(.represented, 0)
        guests = c.value(.guests, 0)
        editable = c.value(.editable, false)
        rows = (try? c.decodeIfPresent([AttendanceRow].self, forKey: .rows)) ?? []
    }
}

public struct LeadPollResult: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var label: String
    public var votes: Int

    enum CodingKeys: String, CodingKey { case id, label, votes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = c.value(.label, "")
        votes = c.value(.votes, 0)
    }
}

public struct LeadPoll: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var agendaNumber: String
    public var agendaTitle: String
    public var question: String
    public var office: String
    public var candidate: String
    public var secret: Bool
    public var status: String
    public var cast: Int
    public var entitled: Int
    public var result: [LeadPollResult]?
    public var resolution: Int?

    enum CodingKeys: String, CodingKey {
        case id, question, office, candidate, secret, status, cast, entitled, result, resolution
        case agendaNumber = "agenda_number"
        case agendaTitle = "agenda_title"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        agendaNumber = c.value(.agendaNumber, "")
        agendaTitle = c.value(.agendaTitle, "")
        question = c.value(.question, "")
        office = c.value(.office, "")
        candidate = c.value(.candidate, "")
        secret = c.value(.secret, false)
        status = c.value(.status, "")
        cast = c.value(.cast, 0)
        entitled = c.value(.entitled, 0)
        result = (try? c.decodeIfPresent([LeadPollResult].self, forKey: .result)) ?? nil
        resolution = c.value(.resolution, nil as Int?)
    }

    public static func statusLabel(_ status: String) -> String {
        switch status {
        case "draft": return tr("vorbereitet")
        case "open": return tr("läuft")
        case "closed": return tr("beendet")
        default: return status
        }
    }
}

public struct LeadLive: Decodable, Equatable, Sendable {
    public var meeting: Int
    public var organization: Int
    public var remoteAllowed: Bool
    public var checkinOpen: Bool
    public var remote: Bool
    public var live: Bool
    public var onlineVoting: Bool
    public var presentApp: Int
    public var presentOnline: Int
    public var entitled: Int
    public var polls: [LeadPoll]
    /// Nur bei offener Anmeldung: wechselnder Code und Sekunden bis zum Wechsel
    public var code: String?
    public var refreshIn: Int

    enum CodingKeys: String, CodingKey {
        case meeting, organization, remote, live, entitled, polls, code
        case remoteAllowed = "remote_allowed"
        case checkinOpen = "checkin_open"
        case onlineVoting = "online_voting"
        case presentApp = "present_app"
        case presentOnline = "present_online"
        case refreshIn = "refresh_in"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meeting = c.value(.meeting, 0)
        organization = c.value(.organization, 0)
        remoteAllowed = c.value(.remoteAllowed, false)
        checkinOpen = c.value(.checkinOpen, false)
        remote = c.value(.remote, false)
        live = c.value(.live, false)
        onlineVoting = c.value(.onlineVoting, false)
        presentApp = c.value(.presentApp, 0)
        presentOnline = c.value(.presentOnline, 0)
        entitled = c.value(.entitled, 0)
        polls = (try? c.decodeIfPresent([LeadPoll].self, forKey: .polls)) ?? []
        code = c.value(.code, nil as String?)
        refreshIn = c.value(.refreshIn, 30)
    }

    /// Inhalt des QR-Codes zum Anmelden, wie im Browser und in der Android-App:
    /// `https://<Instanz>/mein-bereich/versammlungen/da/<Versammlung>?v=<Verein>&c=<Code>` (liest `MeetingLink`).
    public func checkinLink(server: String) -> String? {
        guard checkinOpen, let code, !code.isEmpty, let origin = normalizeServer(server) else { return nil }
        var parts = URLComponents()
        parts.queryItems = [URLQueryItem(name: "v", value: String(organization)), URLQueryItem(name: "c", value: code)]
        return origin + "/mein-bereich/versammlungen/da/\(meeting)?" + (parts.percentEncodedQuery ?? "")
    }
}

// MARK: Schnittstelle

extension AdminClient {
    public func applications() async throws -> ApplicationList {
        try await api.expect("GET", base + "admission/?status=offen")
    }

    public func application(_ id: Int) async throws -> ApplicationDetail {
        try await api.expect("GET", base + "admission/\(id)/")
    }

    /// Zustimmen oder nicht zustimmen als Zustimmende (Regel des Formulars).
    public func approveApplication(_ id: Int, approve: Bool, note: String) async throws -> ApplicationDetail {
        try await api.expect("POST", base + "admission/\(id)/approve/", json: [
            "decision": approve ? "approve" : "reject",
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
    }

    /// Aufnehmen; `entryDate` als `JJJJ-MM-TT`, nil: Vorgabe des Servers.
    public func acceptApplication(_ id: Int, entryDate: String?, note: String, welcome: Bool) async throws -> ApplicationDetail {
        var body: [String: Any] = ["note": note.trimmingCharacters(in: .whitespacesAndNewlines), "welcome": welcome]
        if let entryDate, !entryDate.isEmpty { body["entry_date"] = entryDate }
        return try await api.expect("POST", base + "admission/\(id)/accept/", json: body)
    }

    public func rejectApplication(_ id: Int, note: String, sendMail: Bool) async throws -> ApplicationDetail {
        try await api.expect("POST", base + "admission/\(id)/reject/", json: [
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines), "send_mail": sendMail,
        ])
    }

    public func askApplication(_ id: Int, text: String) async throws -> ApplicationDetail {
        try await api.expect("POST", base + "admission/\(id)/ask/", json: ["text": text.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    /// Offene Belegungsanfragen, die diese Person freigeben darf.
    public func bookingRequests(today: String) async throws -> [BookingRequest] {
        let list: BookingRequests = try await api.expect("GET", base + "bookings/?start=\(queryValue(today))")
        return list.requests
    }

    /// `confirm` oder `reject`; 409, wenn die Anfrage inzwischen geändert wurde.
    public func decideBooking(_ id: Int, version: Int, confirm: Bool) async throws -> BookingRequest {
        try await api.expect("POST", base + "bookings/\(id)/decision/", json: [
            "action": confirm ? "confirm" : "reject", "version": version,
        ])
    }

    public func meetings() async throws -> [LeadMeeting] {
        try await api.expect("GET", base + "meetings/")
    }

    public func meeting(_ id: Int) async throws -> LeadMeeting {
        try await api.expect("GET", base + "meetings/\(id)/")
    }

    public func attendance(meeting: Int) async throws -> AttendanceList {
        try await api.expect("GET", base + "meetings/\(meeting)/attendance/")
    }

    /// Mitglied (`membership`) oder Gast (`name`) eintragen.
    public func setAttendance(meeting: Int, membership: Int?, name: String?, status: String) async throws -> AttendanceList {
        var body: [String: Any] = ["status": status]
        if let membership { body["membership"] = membership }
        if let name { body["name"] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return try await api.expect("POST", base + "meetings/\(meeting)/attendance/", json: body)
    }

    public func removeAttendance(meeting: Int, entry: Int) async throws -> AttendanceList {
        try await api.expect("DELETE", base + "meetings/\(meeting)/attendance/\(entry)/")
    }

    public func meetingLive(_ meeting: Int) async throws -> LeadLive {
        try await api.expect("GET", base + "meetings/\(meeting)/live/")
    }

    /// Anmeldung per App öffnen oder schließen; `remote`: Teilnahme aus der Ferne.
    public func setCheckin(meeting: Int, open: Bool, remote: Bool? = nil) async throws -> LeadLive {
        var body: [String: Any] = ["open": open]
        if let remote { body["remote"] = remote }
        return try await api.expect("POST", base + "meetings/\(meeting)/live/", json: body)
    }

    public func createPoll(meeting: Int, agendaItem: Int, question: String, secret: Bool, office: String = "", candidates: [String] = []) async throws -> LeadLive {
        let names = candidates.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return try await api.expect("POST", base + "meetings/\(meeting)/polls/", json: [
            "agenda_item": agendaItem,
            "question": question.trimmingCharacters(in: .whitespacesAndNewlines),
            "secret": secret,
            "office": office.trimmingCharacters(in: .whitespacesAndNewlines),
            "candidates": names.map { ["name": $0] },
        ])
    }

    /// `open` (starten), `close` (beenden) oder `apply` (als Beschluss übernehmen).
    public func pollAction(meeting: Int, poll: Int, action: String) async throws -> LeadLive {
        guard ["open", "close", "apply"].contains(action) else { throw ApiError(status: 0, code: "format") }
        return try await api.expect("POST", base + "meetings/\(meeting)/polls/\(poll)/", json: ["action": action])
    }

    public func deletePoll(meeting: Int, poll: Int) async throws -> LeadLive {
        try await api.expect("DELETE", base + "meetings/\(meeting)/polls/\(poll)/")
    }
}
