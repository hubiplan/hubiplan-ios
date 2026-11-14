import XCTest
@testable import HubiplanKern

final class VerwaltungAufgabenTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() {
        Texte.language = "de"
    }

    private func decode<T: Decodable>(_ text: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }

    private func verwaltung(_ net: FakeTransport, unit: AdminUnit = AdminUnit(id: 4, name: "Verein")) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: unit)
    }

    private func json(_ body: [String: Any]?) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: try XCTUnwrap(body), options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private let aufgabe = #"{"id":7,"title":"Festzelt bestellen","description":"Drei Angebote einholen","due_date":"2026-11-27","due_time":"18:00","timezone":"Europe/Berlin","status":"open","shared":true,"version":3,"can_edit":true,"can_complete":true,"local_note":"Angebot liegt vor","due_label":"bis 27.11.2026, 18:00 Uhr","highlight":true}"#

    func testRechteUndBereich() {
        XCTAssertFalse(AdminUnit(id: 1, name: "A", permissions: ["members.view"], stufen: true).showsTodos)
        XCTAssertEqual(AdminUnit(id: 1, name: "A", permissions: ["todos.view"], stufen: true).sections, [.tasks, .todos])
        XCTAssertEqual(AdminUnit(id: 1, name: "A", permissions: ["todos.edit", "members.view"], stufen: true).sections, [.tasks, .todos, .members, .occasions])
    }

    func testAufgabeLesen() throws {
        let todo: AdminTodo = try decode(aufgabe)
        XCTAssertFalse(todo.done)
        XCTAssertTrue(todo.mayComplete)
        XCTAssertTrue(todo.urgent)
        XCTAssertEqual(todo.dueText, "bis 27.11.2026, 18:00 Uhr")
        XCTAssertEqual(todo.sharedText, "Geteilt")
        XCTAssertEqual(todo.statusText, "Offen")
        XCTAssertEqual(todo.localNote, "Angebot liegt vor")

        let knapp: AdminTodo = try decode(#"{"id":8,"status":"done","can_edit":true,"per_unit":true}"#)
        XCTAssertTrue(knapp.done)
        XCTAssertFalse(knapp.mayComplete)
        XCTAssertEqual(knapp.dueText, "ohne Frist")
        XCTAssertEqual(knapp.sharedText, "Privat")
        XCTAssertEqual(knapp.statusText, "Erledigt")
        XCTAssertEqual(knapp.version, 1)
        XCTAssertEqual(knapp.timezone, "Europe/Berlin")
        let gesperrt: AdminTodo = try decode(#"{"id":9,"can_edit":true,"can_complete":false}"#)
        XCTAssertFalse(gesperrt.mayComplete)
        let nurLesen: AdminTodo = try decode(#"{"id":9,"can_complete":true}"#)
        XCTAssertFalse(nurLesen.mayComplete)
        XCTAssertEqual(AdminTodo.visible([todo, knapp], done: false).map(\.id), [7])
        XCTAssertEqual(AdminTodo.visible([todo, knapp], done: true).map(\.id), [8])
    }

    func testNeueAufgabeFristUndUhrzeit() throws {
        var draft = TodoDraft()
        XCTAssertNil(draft.body)
        draft.title = "  Kapelle buchen "
        XCTAssertEqual(try json(draft.body), #"{"description":"","due_date":null,"due_time":null,"timezone":"Europe/Berlin","title":"Kapelle buchen"}"#)
        draft.description = "Besetzung wie im letzten Jahr"
        draft.date = "27.11.2026"
        draft.time = "9:05"
        XCTAssertEqual(
            try json(draft.body),
            #"{"description":"Besetzung wie im letzten Jahr","due_date":"2026-11-27","due_time":"09:05","timezone":"Europe/Berlin","title":"Kapelle buchen"}"#
        )
        draft.time = ""
        XCTAssertEqual(draft.body?["due_date"] as? String, "2026-11-27")
        XCTAssertTrue(draft.body?["due_time"] is NSNull)
        // Uhrzeit braucht ein Datum
        draft.date = ""
        draft.time = "18:00"
        XCTAssertFalse(draft.dueValid)
        XCTAssertNil(draft.body)
        draft.date = "31.02.2026"
        XCTAssertNil(draft.body)
        draft.date = "27.11.2026"
        draft.time = "25:00"
        XCTAssertNil(draft.body)
        draft.time = ""
        XCTAssertTrue(draft.dueValid)
        draft.title = String(repeating: "a", count: 201)
        XCTAssertNil(draft.body)
        draft.title = String(repeating: "a", count: 200)
        XCTAssertNotNil(draft.body)
    }

    func testAufgabenLadenAnlegenErledigenUndZuruecknehmen() async throws {
        let erledigt = aufgabe.replacingOccurrences(of: #""status":"open""#, with: #""status":"done""#).replacingOccurrences(of: #""version":3"#, with: #""version":4"#)
        let net = FakeTransport([
            FakeTransport.json(200, #"{"items":[\#(aufgabe),{"id":8,"title":"Alt","status":"done"}]}"#),
            FakeTransport.json(200, aufgabe),
            .success(HttpResponse(status: 201, body: Data(aufgabe.utf8), headers: ["X-Change-Set": "cs-1", "X-Change-Undoable": "1"])),
            .success(HttpResponse(status: 200, body: Data(erledigt.utf8), headers: ["X-Change-Set": "cs-2", "X-Change-Undoable": "1", "X-Change-Task": "7"])),
            FakeTransport.json(200, "{}"),
            FakeTransport.json(200, "{}"),
            FakeTransport.json(409, #"{"detail":"Die Aufgabe wurde inzwischen geändert."}"#),
        ])
        let client = verwaltung(net)
        let list = try await client.todos()
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/todos/")
        XCTAssertEqual(list.map(\.id), [7, 8])
        let one = try await client.todo(7)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/4/todos/7/")
        XCTAssertEqual(one.version, 3)

        var draft = TodoDraft()
        draft.title = "Festzelt bestellen"
        let created = try await client.createTodo(try XCTUnwrap(draft.body))
        XCTAssertEqual(net.seen[2].method, "POST")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/4/todos/")
        XCTAssertEqual(created.todo.id, 7)
        XCTAssertEqual(created.change.changeSet, "cs-1")
        XCTAssertNil(created.change.task)

        let done = try await client.completeTodo(7, version: 3, done: true)
        XCTAssertEqual(net.seen[3].method, "PATCH")
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/app/v1/admin/u/4/todos/7/")
        XCTAssertEqual(String(decoding: try XCTUnwrap(net.seen[3].body), as: UTF8.self), #"{"status":"done","version":3}"#)
        XCTAssertTrue(done.todo.done)
        XCTAssertEqual(done.change.task, 7)

        // Aufgaben haben ihren eigenen Rückweg
        try await client.undo("cs-2", task: done.change.task)
        XCTAssertEqual(net.seen[4].url, "https://verein.example.de/api/app/v1/admin/u/4/todos/7/changes/cs-2/undo/")
        try await client.undo("cs-1", task: created.change.task)
        XCTAssertEqual(net.seen[5].url, "https://verein.example.de/api/app/v1/admin/u/4/changes/cs-1/undo/")

        do {
            _ = try await client.completeTodo(7, version: 3, done: false)
            XCTFail("409 erwartet")
        } catch let failure as ApiError {
            XCTAssertEqual(failure.status, 409)
            XCTAssertEqual(failure.message, "Die Aufgabe wurde inzwischen geändert.")
        }
        XCTAssertEqual(String(decoding: try XCTUnwrap(net.seen[6].body), as: UTF8.self), #"{"status":"open","version":3}"#)
    }
}
