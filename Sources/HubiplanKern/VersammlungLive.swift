import Foundation

/// Anmelden per App und Online-Abstimmung in Versammlungen (HUBIplan V7, `docs/versammlungen.md`).
///
/// Die Leitung zeigt einen QR-Code mit
/// `https://<Instanz>/mein-bereich/versammlungen/da/<Versammlung>?v=<Verein>&c=<Code>`.
/// Der Code wechselt alle 30 Sekunden; die App schickt ihn sofort nach dem Scannen.
public struct MeetingLink: Equatable, Sendable {
    public var server: String
    public var meetingId: Int
    public var clubId: Int
    public var code: String

    public init(server: String, meetingId: Int, clubId: Int, code: String) {
        self.server = server
        self.meetingId = meetingId
        self.clubId = clubId
        self.code = code
    }

    public static func parse(_ text: String) -> MeetingLink? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let server = httpsOrigin(parts) else { return nil }
        let path = parts.percentEncodedPath
        let prefix = "/mein-bereich/versammlungen/da/"
        guard path.hasPrefix(prefix) else { return nil }
        var number = String(path.dropFirst(prefix.count))
        if number.hasSuffix("/") { number.removeLast() }
        guard (1...10).contains(number.count), number.allSatisfy({ ("0"..."9").contains($0) }),
              let meeting = Int(number), meeting > 0 else { return nil }
        let query = parts.queryItems ?? []
        guard let club = query.first(where: { $0.name == "v" })?.value.flatMap({ Int($0) }), club > 0,
              let code = query.first(where: { $0.name == "c" })?.value, codeOk(code) else { return nil }
        return MeetingLink(server: server, meetingId: meeting, clubId: club, code: code)
    }

    /// `<1–12 Ziffern>-<16 Hexzeichen>`
    static func codeOk(_ code: String) -> Bool {
        let halves = code.split(separator: "-", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return false }
        let digits = halves[0], hex = halves[1]
        return (1...12).contains(digits.count) && digits.allSatisfy { ("0"..."9").contains($0) }
            && hex.count == 16 && hex.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}

/// Ziel der Live-Ansicht: Versammlung und, nach dem Scan, der Code vom Bildschirm.
public struct LiveTarget: Equatable, Hashable, Identifiable, Sendable {
    public var meetingId: Int
    public var code: String?
    public var id: Int { meetingId }

    public init(meetingId: Int, code: String? = nil) {
        self.meetingId = meetingId
        self.code = code
    }

    /// Gescannten Text prüfen: eigene Instanz, eigener Verein, gültiger Code.
    /// Liefert das Ziel oder einen Fehlertext.
    public static func from(scan text: String, server: String, clubId: Int) -> (target: LiveTarget?, problem: String?) {
        guard let link = MeetingLink.parse(text) else {
            return (nil, tr("Das ist kein QR-Code zum Anmelden in einer Versammlung."))
        }
        if link.server != server { return (nil, tr("Der QR-Code gehört zu einer anderen HUBIplan-Adresse.")) }
        if clubId != 0 && link.clubId != clubId {
            return (nil, tr("Der QR-Code gehört zu einem anderen Verein. Wähle unter „Ich“ oben links den passenden Zugang."))
        }
        return (LiveTarget(meetingId: link.meetingId, code: link.code), nil)
    }
}

public struct PollOption: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var role: String
    public var label: String

    enum CodingKeys: String, CodingKey { case id, role, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

public struct PollResult: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var label: String
    public var votes: Int

    enum CodingKeys: String, CodingKey { case id, label, votes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        votes = try c.decodeIfPresent(Int.self, forKey: .votes) ?? 0
    }
}

/// Eine Stimme, die das Mitglied abgeben darf: eigene, Vollmacht oder für eine Organisation.
public struct PollVote: Decodable, Equatable, Identifiable, Sendable {
    public var attendance: Int
    public var name: String
    public var how: String
    public var done: Bool
    public var id: Int { attendance }

    enum CodingKeys: String, CodingKey { case attendance, name, how, done }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        attendance = try c.decode(Int.self, forKey: .attendance)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        how = try c.decodeIfPresent(String.self, forKey: .how) ?? "own"
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }

    public var label: String {
        switch how {
        case "own": return tr("Deine Stimme")
        case "proxy": return tr("Vollmacht von {name}", ["name": name])
        default: return tr("Für {name}", ["name": name])
        }
    }
}

public struct Poll: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var agendaPosition: Int
    public var agendaNumber: String
    public var question: String
    public var office: String
    public var candidate: String
    public var secret: Bool
    public var status: String
    public var options: [PollOption]
    public var result: [PollResult]?
    public var votes: [PollVote]

    enum CodingKeys: String, CodingKey {
        case id, kind, question, office, candidate, secret, status, options, result, votes
        case agendaPosition = "agenda_position"
        case agendaNumber = "agenda_number"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        agendaPosition = try c.decodeIfPresent(Int.self, forKey: .agendaPosition) ?? 0
        agendaNumber = try c.decodeIfPresent(String.self, forKey: .agendaNumber) ?? ""
        question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        office = try c.decodeIfPresent(String.self, forKey: .office) ?? ""
        candidate = try c.decodeIfPresent(String.self, forKey: .candidate) ?? ""
        secret = try c.decodeIfPresent(Bool.self, forKey: .secret) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        options = try c.decodeIfPresent([PollOption].self, forKey: .options) ?? []
        result = try c.decodeIfPresent([PollResult].self, forKey: .result)
        votes = try c.decodeIfPresent([PollVote].self, forKey: .votes) ?? []
    }

    public var running: Bool { status == "open" }
    public var openVotes: [PollVote] { votes.filter { !$0.done } }
    public var heading: String { "\(agendaNumber.isEmpty ? String(agendaPosition) : agendaNumber). \(question)" }
    /// Kandidat, Amt und Art der Abstimmung.
    public var details: String {
        [candidate, office, secret ? tr("geheime Abstimmung") : tr("offene Abstimmung")]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Stand einer laufenden Versammlung für das Mitglied.
/// Ansage für VoiceOver, wenn beim Nachfragen eine Abstimmung eröffnet wurde (UX-Audit 16.11.,
/// IOS-03): nur für neu laufende Abstimmungen mit offener eigener Stimme. nil: nichts ansagen.
public func neueAbstimmungAnsage(vorher: MeetingLive?, jetzt: MeetingLive) -> String? {
    guard let vorher else { return nil }
    let alt = Set(vorher.polls.filter(\.running).map(\.id))
    let neu = jetzt.polls.filter { $0.running && !alt.contains($0.id) && !$0.openVotes.isEmpty }
    guard let erste = neu.first else { return nil }
    return tr("Abstimmung eröffnet: {question}", ["question": erste.heading])
}

public struct MeetingLive: Decodable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var kindName: String
    public var unit: String
    public var location: String
    public var checkinOpen: Bool
    public var remote: Bool
    public var voter: Bool
    public var isOrganization: Bool
    public var status: String
    public var mode: String
    public var votes: Int
    public var polls: [Poll]

    enum CodingKeys: String, CodingKey {
        case id, title, unit, location, remote, voter, status, mode, votes, polls
        case kindName = "kind_name"
        case checkinOpen = "checkin_open"
        case isOrganization = "is_organization"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        kindName = try c.decodeIfPresent(String.self, forKey: .kindName) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        checkinOpen = try c.decodeIfPresent(Bool.self, forKey: .checkinOpen) ?? false
        remote = try c.decodeIfPresent(Bool.self, forKey: .remote) ?? false
        voter = try c.decodeIfPresent(Bool.self, forKey: .voter) ?? false
        isOrganization = try c.decodeIfPresent(Bool.self, forKey: .isOrganization) ?? false
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
        votes = try c.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        polls = try c.decodeIfPresent([Poll].self, forKey: .polls) ?? []
    }

    public var present: Bool { status == "present" }
    /// „Online teilnehmen“ geht nur für Stimmberechtigte, wenn die Leitung es erlaubt.
    public var canJoinRemote: Bool { !present && !isOrganization && remote && voter }
    /// „QR-Code scannen: Ich bin da“
    public var canCheckin: Bool { !present && !isOrganization && checkinOpen }

    /// Art, Einheit und Ort unter dem Titel.
    public var subline: String {
        [kindName, unit, location].filter { !$0.isEmpty && $0 != title }.joined(separator: " · ")
    }

    /// Stand in Worten, mit Stimmen aus Vollmachten.
    public var statusText: String {
        let base: String
        if present && mode == "online" {
            base = tr("Du nimmst aus der Ferne teil.")
        } else if present {
            base = tr("Du bist als anwesend eingetragen.")
        } else if status == "left" {
            base = tr("Du hast dich abgemeldet.")
        } else {
            base = tr("Du bist noch nicht angemeldet.")
        }
        guard present, votes > 1 else { return base }
        return base + " " + tr("Du hast {n} Stimmen (mit Vollmachten).", ["n": String(votes)])
    }
}

extension Api {
    public func meetingLive(accessId: Int, meetingId: Int) async throws -> MeetingLive {
        try await expect("GET", "/api/portal/\(accessId)/meetings/\(meetingId)/live/")
    }

    /// „Ich bin da“ mit dem Code aus dem QR-Code oder aus der Ferne (`remote`).
    public func meetingCheckin(accessId: Int, meetingId: Int, code: String?, remote: Bool = false) async throws -> MeetingLive {
        let body: [String: Any] = remote ? ["remote": true] : ["code": code ?? ""]
        return try await expect("POST", "/api/portal/\(accessId)/meetings/\(meetingId)/live/checkin/", json: body)
    }

    public func meetingLeave(accessId: Int, meetingId: Int) async throws -> MeetingLive {
        try await expect("POST", "/api/portal/\(accessId)/meetings/\(meetingId)/live/leave/", json: [:])
    }

    /// Stimmen abgeben: je Stimme (Anwesenheitseintrag) die gewählte Antwort.
    public func meetingVote(accessId: Int, meetingId: Int, pollId: Int, votes: [Int: Int]) async throws -> MeetingLive {
        let list: [[String: Any]] = votes.keys.sorted().map { ["attendance": $0, "option": votes[$0]!] }
        return try await expect("POST", "/api/portal/\(accessId)/meetings/\(meetingId)/polls/\(pollId)/vote/", json: ["votes": list])
    }
}
