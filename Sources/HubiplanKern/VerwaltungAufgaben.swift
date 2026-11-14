import Foundation

// Verwaltung in der App: „Aufgaben verteilen“ wie in der Android-App. Aufgaben der Einheit
// ansehen, erledigen oder wieder öffnen und eine neue (zunächst private) Aufgabe anlegen.
// Teilen, Anhänge und Serien bleiben im Browser.

extension AdminUnit {
    /// Bereich „Aufgaben verteilen“ zeigen: mindestens lesen.
    public var showsTodos: Bool { permissions.contains("todos.view") || permissions.contains("todos.edit") }
}

public struct AdminTodo: Decodable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var description: String
    public var dueDate: String?
    public var dueTime: String?
    public var timezone: String
    /// "open" oder "done"
    public var status: String
    public var shared: Bool
    /// Fassung für das Erledigen: der Server lehnt veraltete ab
    public var version: Int
    public var canEdit: Bool
    public var canComplete: Bool?
    /// Je Einheit einzeln zu erledigen (nur im Browser)
    public var perUnit: Bool
    public var localNote: String
    public var dueLabel: String
    public var highlight: Bool
    public var overdue: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description, timezone, status, shared, version, highlight, overdue
        case dueDate = "due_date"
        case dueTime = "due_time"
        case canEdit = "can_edit"
        case canComplete = "can_complete"
        case perUnit = "per_unit"
        case localNote = "local_note"
        case dueLabel = "due_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        dueTime = try c.decodeIfPresent(String.self, forKey: .dueTime)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? "Europe/Berlin"
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        shared = try c.decodeIfPresent(Bool.self, forKey: .shared) ?? false
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        canEdit = try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        canComplete = try c.decodeIfPresent(Bool.self, forKey: .canComplete)
        perUnit = try c.decodeIfPresent(Bool.self, forKey: .perUnit) ?? false
        localNote = try c.decodeIfPresent(String.self, forKey: .localNote) ?? ""
        dueLabel = try c.decodeIfPresent(String.self, forKey: .dueLabel) ?? ""
        highlight = try c.decodeIfPresent(Bool.self, forKey: .highlight) ?? false
        overdue = try c.decodeIfPresent(Bool.self, forKey: .overdue) ?? false
    }

    public var done: Bool { status == "done" }
    /// Erledigen oder wieder öffnen geht in der App.
    public var mayComplete: Bool { canEdit && canComplete != false && !perUnit }
    /// Frist hervorheben (bald fällig oder überfällig).
    public var urgent: Bool { highlight || overdue }
    public var dueText: String { dueLabel.isEmpty ? tr("ohne Frist") : dueLabel }
    public var sharedText: String { shared ? tr("Geteilt") : tr("Privat") }
    public var statusText: String { done ? tr("Erledigt") : tr("Offen") }

    /// Aufgaben einer Ansicht: erledigte oder offene.
    public static func visible(_ list: [AdminTodo], done: Bool) -> [AdminTodo] { list.filter { $0.done == done } }
}

struct AdminTodoList: Decodable {
    var items: [AdminTodo]

    enum CodingKeys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([AdminTodo].self, forKey: .items) ?? []
    }
}

/// Neue Aufgabe: Eingaben, bis sie angelegt ist.
public struct TodoDraft: Equatable, Sendable {
    public var title = ""
    public var description = ""
    /// `TT.MM.JJJJ` oder `JJJJ-MM-TT`; leer: ohne Frist
    public var date = ""
    /// `HH:MM`; leer: ohne Uhrzeit. Eine Uhrzeit braucht ein Datum.
    public var time = ""

    public static let timezone = "Europe/Berlin"

    public init() {}

    /// Frist und Uhrzeit passen zusammen (leer ist erlaubt).
    public var dueValid: Bool { due != nil }

    private var due: (date: String?, time: String?)? {
        var day: String?
        if !date.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = MasterData.parseDate(date) else { return nil }
            day = parsed
        }
        var at: String?
        if !time.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let parsed = EventTime.parseTime(time), day != nil else { return nil }
            at = String(format: "%02d:%02d", parsed.hour, parsed.minute)
        }
        return (day, at)
    }

    /// Inhalt der Anfrage; nil, solange der Titel fehlt oder zu lang ist oder die Frist nicht passt.
    public var body: [String: Any]? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, description.count <= 50000, let due = self.due else { return nil }
        return [
            "title": name, "description": description,
            "due_date": due.date.map { $0 as Any } ?? NSNull(), "due_time": due.time.map { $0 as Any } ?? NSNull(),
            "timezone": Self.timezone,
        ]
    }
}

extension AdminClient {
    /// Aufgaben der Einheit, offene und erledigte.
    public func todos() async throws -> [AdminTodo] {
        let list: AdminTodoList = try await api.expect("GET", base + "todos/")
        return list.items
    }

    public func todo(_ id: Int) async throws -> AdminTodo {
        try await api.expect("GET", base + "todos/\(id)/")
    }

    /// Neue Aufgabe (zunächst privat); Inhalt aus `TodoDraft.body`.
    public func createTodo(_ body: [String: Any]) async throws -> (todo: AdminTodo, change: AdminChange) {
        let response = try await api.raw("POST", base + "todos/", json: body)
        let todo: AdminTodo = try decoded(response)
        return (todo, AdminChange(response))
    }

    /// Erledigen oder wieder öffnen; `version` aus der zuletzt geladenen Aufgabe.
    public func completeTodo(_ id: Int, version: Int, done: Bool) async throws -> (todo: AdminTodo, change: AdminChange) {
        let response = try await api.raw("PATCH", base + "todos/\(id)/", json: ["version": version, "status": done ? "done" : "open"])
        let todo: AdminTodo = try decoded(response)
        return (todo, AdminChange(response))
    }
}
