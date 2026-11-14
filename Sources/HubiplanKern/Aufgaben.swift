import Foundation

/// Anhang einer Aufgabe; die App nennt ihn nur, geöffnet wird im Browser.
public struct MemberTodoFile: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var available: Bool

    enum CodingKeys: String, CodingKey { case id, name, available }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        available = try c.decodeIfPresent(Bool.self, forKey: .available) ?? false
    }
}

/// Aufgabe im Mitgliederbereich: für das Mitglied freigegeben oder als Angebot der Einheit.
public struct MemberTodo: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var description: String
    /// "open" oder "done"
    public var status: String
    public var version: Int
    public var dueLabel: String
    public var canComplete: Bool
    public var canClaim: Bool
    public var claimedByMe: Bool
    public var claimed: Bool
    public var attachments: [MemberTodoFile]

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, version, claimed, attachments
        case dueLabel = "due_label"
        case canComplete = "can_complete"
        case canClaim = "can_claim"
        case claimedByMe = "claimed_by_me"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        dueLabel = try c.decodeIfPresent(String.self, forKey: .dueLabel) ?? ""
        canComplete = try c.decodeIfPresent(Bool.self, forKey: .canComplete) ?? false
        canClaim = try c.decodeIfPresent(Bool.self, forKey: .canClaim) ?? false
        claimedByMe = try c.decodeIfPresent(Bool.self, forKey: .claimedByMe) ?? false
        claimed = try c.decodeIfPresent(Bool.self, forKey: .claimed) ?? false
        attachments = try c.decodeIfPresent([MemberTodoFile].self, forKey: .attachments) ?? []
    }

    public var done: Bool { status == "done" }

    /// Zeile unter dem Titel: Frist oder „ohne Frist“.
    public var dueText: String { dueLabel.isEmpty ? tr("ohne Frist") : dueLabel }
}

struct MemberTodoList: Decodable {
    var items: [MemberTodo]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([MemberTodo].self, forKey: .items) ?? []
    }
}

/// Schicht eines Dienstes im Dienstplan.
public struct HelperShift: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var startsAt: String
    public var endsAt: String
    public var needed: Int
    public var taken: Int
    public var note: String
    public var names: [String]
    /// Eigene Eintragung in dieser Schicht (Kennung zum Absagen)
    public var mine: Int?
    public var canCancel: Bool
    public var past: Bool

    enum CodingKeys: String, CodingKey {
        case id, needed, taken, note, names, mine, past
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case canCancel = "can_cancel"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
        needed = try c.decodeIfPresent(Int.self, forKey: .needed) ?? 0
        taken = try c.decodeIfPresent(Int.self, forKey: .taken) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
        mine = try c.decodeIfPresent(Int.self, forKey: .mine)
        canCancel = try c.decodeIfPresent(Bool.self, forKey: .canCancel) ?? false
        past = try c.decodeIfPresent(Bool.self, forKey: .past) ?? false
    }

    public var free: Int { max(needed - taken, 0) }

    /// Belegung: „2 von 4 frei“ oder „besetzt“.
    public var freeLabel: String {
        free > 0 ? tr("{free} von {needed} frei", ["free": free, "needed": needed]) : tr("besetzt")
    }
}

public struct HelperDuty: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var description: String
    public var location: String
    public var minAge: Int?
    public var shifts: [HelperShift]

    enum CodingKeys: String, CodingKey {
        case id, name, description, location, shifts
        case minAge = "min_age"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        minAge = try c.decodeIfPresent(Int.self, forKey: .minAge)
        shifts = try c.decodeIfPresent([HelperShift].self, forKey: .shifts) ?? []
    }

    /// Kopfzeile mit Ort und Mindestalter.
    public var line: String {
        var parts = [name]
        if !location.isEmpty { parts.append(location) }
        if let minAge, minAge > 0 { parts.append(tr("ab {age} Jahren", ["age": minAge])) }
        return parts.joined(separator: " · ")
    }

    /// Schichten, die noch nicht vorbei sind.
    public var open: [HelperShift] { shifts.filter { !$0.past } }
}

public struct HelperPlan: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var unit: String
    public var eventTitle: String
    /// "self": Mitglieder tragen sich selbst ein; sonst teilt nur die Verwaltung ein
    public var signup: String
    public var maxShifts: Int?
    public var note: String
    public var duties: [HelperDuty]

    enum CodingKeys: String, CodingKey {
        case id, title, unit, signup, note, duties
        case eventTitle = "event_title"
        case maxShifts = "max_shifts"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        eventTitle = try c.decodeIfPresent(String.self, forKey: .eventTitle) ?? ""
        signup = try c.decodeIfPresent(String.self, forKey: .signup) ?? "self"
        maxShifts = try c.decodeIfPresent(Int.self, forKey: .maxShifts)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        duties = try c.decodeIfPresent([HelperDuty].self, forKey: .duties) ?? []
    }

    /// Eintragen ist möglich: Plan zum Selbsteintragen, Schicht nicht vorbei, frei, nicht schon dabei.
    public func canSignup(_ shift: HelperShift) -> Bool {
        signup == "self" && !shift.past && shift.mine == nil && shift.free > 0
    }

    /// Einheit und Veranstaltung unter dem Titel.
    public var info: String { [unit, eventTitle].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// Eigener Dienst („Meine Dienste“).
public struct MyShift: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var plan: String
    public var duty: String
    public var location: String
    public var startsAt: String
    public var endsAt: String

    enum CodingKeys: String, CodingKey {
        case id, plan, duty, location
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        plan = try c.decodeIfPresent(String.self, forKey: .plan) ?? ""
        duty = try c.decodeIfPresent(String.self, forKey: .duty) ?? ""
        location = try c.decodeIfPresent(String.self, forKey: .location) ?? ""
        startsAt = try c.decode(String.self, forKey: .startsAt)
        endsAt = try c.decode(String.self, forKey: .endsAt)
    }

    public var title: String { [duty, plan].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// Helferdienste im Mitgliederbereich (`/api/portal/<Zugang>/helpers/`).
public struct HelperOverview: Decodable, Equatable, Sendable {
    public var plans: [HelperPlan]
    public var mine: [MyShift]

    enum CodingKeys: String, CodingKey { case plans, mine }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plans = try c.decodeIfPresent([HelperPlan].self, forKey: .plans) ?? []
        mine = try c.decodeIfPresent([MyShift].self, forKey: .mine) ?? []
    }

    /// Darf das Mitglied diesen eigenen Dienst noch selbst absagen (Frist des Plans)?
    public func canCancel(_ assignment: Int) -> Bool {
        plans.contains { plan in
            plan.duties.contains { duty in duty.shifts.contains { $0.mine == assignment && $0.canCancel } }
        }
    }

    /// Pläne, in denen noch eine Schicht bevorsteht.
    public var openPlans: [HelperPlan] { plans.filter { plan in plan.duties.contains { !$0.open.isEmpty } } }
}

extension PortalAccess {
    /// Aufgaben und Helferdienste des Mitgliederbereichs (Reiter „Aufgaben“).
    public var hasTodos: Bool { has(module: "todos") }
    public var hasHelpers: Bool { has(module: "helpers", fallback: helpersEnabled) }
}

extension Api {
    public func memberTodos(accessId: Int) async throws -> [MemberTodo] {
        let list: MemberTodoList = try await expect("GET", "/api/portal/\(accessId)/todos/")
        return list.items
    }

    /// Erledigen oder wieder öffnen; `version` schützt vor dem Überschreiben fremder Änderungen.
    public func completeTodo(accessId: Int, id: Int, version: Int, done: Bool) async throws -> MemberTodo {
        try await expect(
            "PATCH", "/api/portal/\(accessId)/todos/\(id)/",
            json: ["version": version, "status": done ? "done" : "open"]
        )
    }

    /// Angebot übernehmen oder die Übernahme wieder freigeben.
    public func claimTodo(accessId: Int, id: Int, version: Int, claim: Bool) async throws -> MemberTodo {
        try await expect(
            "PATCH", "/api/portal/\(accessId)/todos/\(id)/",
            json: ["version": version, "action": claim ? "claim" : "release"]
        )
    }

    public func helpers(accessId: Int) async throws -> HelperOverview {
        try await expect("GET", "/api/portal/\(accessId)/helpers/")
    }

    public func signupShift(accessId: Int, shiftId: Int) async throws {
        let _: Ignored = try await expect("POST", "/api/portal/\(accessId)/helpers/shifts/\(shiftId)/signup/", json: [:])
    }

    public func cancelShift(accessId: Int, assignmentId: Int) async throws {
        let _: Ignored = try await expect("POST", "/api/portal/\(accessId)/helpers/assignments/\(assignmentId)/cancel/", json: [:])
    }
}
