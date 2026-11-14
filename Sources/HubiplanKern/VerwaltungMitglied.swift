import Foundation

// Vorgänge an einem Mitglied: Mitgliedsart wechseln, Untereinheit wechseln, Austritt,
// Wiedereintritt, „zahlt Beitrag selbst“. Wie in der Android-App zeigt die App vor dem
// Ausführen, was passiert (Vorschau vom Server), und führt erst nach Bestätigung aus.

/// Wert mit Beschriftung zur Auswahl (z. B. Austrittsgrund).
public struct MemberChoice: Decodable, Equatable, Sendable, Identifiable {
    public var value: String
    public var label: String

    public var id: String { value }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct MemberTypeItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isArchived = "is_archived"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

public struct DepartmentItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var displayName: String
    public var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case displayName = "display_name"
        case isActive = "is_active"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    public var label: String { displayName.isEmpty ? name : displayName }
}

/// Was eine Änderung bewirkt, bevor sie ausgeführt wird.
public struct MemberPreview: Decodable, Equatable, Sendable {
    public var title: String
    public var consequences: [String]

    enum CodingKeys: String, CodingKey { case title, consequences }

    public init(title: String, consequences: [String]) {
        self.title = title
        self.consequences = consequences
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        consequences = try c.decodeIfPresent([String].self, forKey: .consequences) ?? []
    }

    /// Überschrift des Bestätigungsblatts und Text der Meldung danach.
    public var heading: String { title.isEmpty ? tr("Änderung bestätigen") : title }
    public var doneText: String { title.isEmpty ? tr("Gespeichert") : title }
}

/// Ein Vorgang an einem Mitglied; Daten als `JJJJ-MM-TT`.
public enum MemberProcess: Equatable, Sendable {
    case changeType(type: Int, from: String)
    case move(department: Int, from: String)
    case exit(date: String, reason: String, note: String)
    case feeSelf(Bool)
    /// `typeName` nur für den Bestätigungstext
    case reentry(type: Int, typeName: String, from: String)

    /// Angaben für die Vorschau des Servers; nil: Der Server kennt für diesen Vorgang keine
    /// Vorschau, die App nennt die Folgen selbst (`localPreview`).
    var previewBody: [String: Any]? {
        switch self {
        case let .changeType(type, from): return ["action": "change_type", "member_type": type, "valid_from": from]
        case let .move(department, from): return ["action": "move", "department": department, "valid_from": from]
        case let .exit(date, reason, _): return ["action": "exit", "exit_date": date, "exit_reason": reason]
        case let .feeSelf(value): return ["action": "fee_self", "pays_fee_self": value]
        case .reentry: return nil
        }
    }

    var localPreview: MemberPreview? {
        guard case let .reentry(_, typeName, from) = self else { return nil }
        return MemberPreview(title: tr("Wiedereintritt"), consequences: [
            tr("Ab {datum} wieder Mitglied als {name}.", ["datum": Zeit.plainDate(from), "name": typeName]),
            tr("Frühere Zeiten und Nummern bleiben erhalten."),
        ])
    }

    /// Methode, Pfad hinter `members/<id>/` und Inhalt der Änderung.
    var request: (method: String, path: String, body: [String: Any]) {
        switch self {
        case let .changeType(type, from): return ("POST", "change-type/", ["member_type": type, "valid_from": from])
        case let .move(department, from): return ("POST", "move/", ["department": department, "valid_from": from])
        case let .exit(date, reason, note):
            return ("POST", "exit/", ["exit_date": date, "exit_reason": reason, "note": String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))])
        case let .feeSelf(value): return ("PATCH", "", ["pays_fee_self": value])
        case let .reentry(type, _, from): return ("POST", "reentry/", ["entry_date": from, "member_type": type])
        }
    }
}

extension MemberDetail {
    /// Mitgliedsarten, in die gewechselt werden kann (ohne die laufende).
    public func otherTypes(_ types: [MemberTypeItem]) -> [MemberTypeItem] {
        types.filter { $0.id != currentType }
    }

    /// Untereinheiten, in die gewechselt werden kann (ohne die heute laufenden).
    public func otherDepartments(_ all: [DepartmentItem], today: String) -> [DepartmentItem] {
        let current = Set(currentDepartments(today: today).map(\.department))
        return all.filter { !current.contains($0.id) }
    }
}

extension AdminClient {
    /// Mitgliedsarten der Einheit, ohne archivierte.
    public func memberTypes() async throws -> [MemberTypeItem] {
        let list: [MemberTypeItem] = try await api.expect("GET", base + "member-types/")
        return list.filter { !$0.isArchived }
    }

    /// Aktive Untereinheiten der Einheit.
    public func departments() async throws -> [DepartmentItem] {
        let list: [DepartmentItem] = try await api.expect("GET", base + "departments/")
        return list.filter(\.isActive)
    }

    /// Was der Vorgang bewirkt; ändert nichts.
    public func preview(member id: Int, _ process: MemberProcess) async throws -> MemberPreview {
        if let local = process.localPreview { return local }
        return try await api.expect("POST", base + "members/\(id)/preview/", json: process.previewBody ?? [:])
    }

    /// Vorgang ausführen; die Antwort ist die neue Akte.
    public func apply(member id: Int, _ process: MemberProcess) async throws -> (member: MemberDetail, change: AdminChange) {
        let request = process.request
        return try await memberChange(request.method, "members/\(id)/" + request.path, request.body)
    }
}
