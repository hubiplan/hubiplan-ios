import XCTest
@testable import HubiplanKern

final class AufgabenTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    func testAufgabenLesenUndAendern() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"items":[{"id":5,"title":"Zelt aufbauen","description":"Freitag ab 16 Uhr","status":"open","version":3,"due_label":"bis 27.11.2026","can_claim":true,"attachments":[{"id":1,"name":"Plan.pdf","available":true}]},{"id":6,"title":"Getränke bestellen","status":"done","can_complete":true,"neu":1}]}"#),
            FakeTransport.json(200, #"{"id":5,"title":"Zelt aufbauen","status":"open","version":4,"claimed":true,"claimed_by_me":true,"can_complete":true}"#),
            FakeTransport.json(200, #"{"id":5,"title":"Zelt aufbauen","status":"done","version":5,"claimed":true,"claimed_by_me":true,"can_complete":true}"#),
        ])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let todos = try await api.memberTodos(accessId: 3)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/todos/")
        XCTAssertEqual(todos.map(\.id), [5, 6])
        XCTAssertEqual(todos[0].dueText, "bis 27.11.2026")
        XCTAssertEqual(todos[0].attachments.first?.name, "Plan.pdf")
        XCTAssertTrue(todos[0].canClaim)
        XCTAssertFalse(todos[0].done)
        XCTAssertEqual(todos[1].dueText, "ohne Frist")
        XCTAssertEqual(todos[1].version, 1)
        XCTAssertTrue(todos[1].done)

        let claimed = try await api.claimTodo(accessId: 3, id: 5, version: 3, claim: true)
        XCTAssertEqual(net.seen[1].method, "PATCH")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/todos/5/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[1].body ?? Data()) as? [String: Any])
        XCTAssertEqual(sent["version"] as? Int, 3)
        XCTAssertEqual(sent["action"] as? String, "claim")
        XCTAssertTrue(claimed.claimedByMe)

        let done = try await api.completeTodo(accessId: 3, id: 5, version: 4, done: true)
        let second = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[2].body ?? Data()) as? [String: Any])
        XCTAssertEqual(second["status"] as? String, "done")
        XCTAssertEqual(second["version"] as? Int, 4)
        XCTAssertTrue(done.done)
    }

    func testLeereAufgabenliste() throws {
        let list = try JSONDecoder().decode(MemberTodoList.self, from: Data("{}".utf8))
        XCTAssertTrue(list.items.isEmpty)
    }

    private let overview = #"{"plans":[{"id":1,"title":"Schützenfest 2027","unit":"Schützenverein Musterstadt","event_title":"Schützenfest","signup":"self","max_shifts":2,"duties":[{"id":10,"name":"Theke","location":"Festzelt","min_age":18,"shifts":[{"id":100,"starts_at":"2027-08-28T18:00:00+02:00","ends_at":"2027-08-28T22:00:00+02:00","needed":4,"taken":2,"names":["Max M."]},{"id":101,"starts_at":"2027-08-29T18:00:00+02:00","ends_at":"2027-08-29T22:00:00+02:00","needed":2,"taken":2,"mine":7,"can_cancel":true},{"id":102,"starts_at":"2026-01-01T18:00:00+01:00","ends_at":"2026-01-01T22:00:00+01:00","needed":2,"taken":0,"past":true}]},{"id":11,"name":"Kasse","shifts":[{"id":103,"starts_at":"2026-01-01T18:00:00+01:00","ends_at":"2026-01-01T22:00:00+01:00","past":true}]}]},{"id":2,"title":"Aufbau","signup":"admin","duties":[{"id":12,"name":"Zelt","shifts":[{"id":104,"starts_at":"2027-08-27T16:00:00+02:00","ends_at":"2027-08-27T20:00:00+02:00","needed":6,"taken":1,"mine":8}]}]},{"id":3,"title":"Vorbei","duties":[]}],"mine":[{"id":7,"plan":"Schützenfest 2027","duty":"Theke","location":"Festzelt","starts_at":"2027-08-29T18:00:00+02:00","ends_at":"2027-08-29T22:00:00+02:00"},{"id":8,"plan":"Aufbau","duty":"Zelt","starts_at":"2027-08-27T16:00:00+02:00","ends_at":"2027-08-27T20:00:00+02:00"}]}"#

    func testHelferdienste() async throws {
        let net = FakeTransport([FakeTransport.json(200, overview), FakeTransport.json(200, "{}"), FakeTransport.json(200, "{}")])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let data = try await api.helpers(accessId: 3)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/helpers/")
        XCTAssertEqual(data.openPlans.map(\.id), [1, 2])
        let plan = data.plans[0]
        XCTAssertEqual(plan.info, "Schützenverein Musterstadt · Schützenfest")
        let theke = plan.duties[0]
        XCTAssertEqual(theke.line, "Theke · Festzelt · ab 18 Jahren")
        XCTAssertEqual(theke.open.map(\.id), [100, 101])
        XCTAssertEqual(theke.shifts[0].freeLabel, "2 von 4 frei")
        XCTAssertEqual(theke.shifts[1].freeLabel, "besetzt")
        XCTAssertTrue(plan.canSignup(theke.shifts[0]))
        // Schon dabei, vorbei oder nur über die Verwaltung: kein Eintragen
        XCTAssertFalse(plan.canSignup(theke.shifts[1]))
        XCTAssertFalse(plan.canSignup(theke.shifts[2]))
        XCTAssertFalse(data.plans[1].canSignup(data.plans[1].duties[0].shifts[0]))
        XCTAssertTrue(data.canCancel(7))
        XCTAssertFalse(data.canCancel(8))
        XCTAssertEqual(data.mine[0].title, "Theke · Schützenfest 2027")
        Texte.language = "en"
        XCTAssertEqual(theke.shifts[0].freeLabel, "2 of 4 free")
        XCTAssertEqual(theke.line, "Theke · Festzelt · aged 18 and over")

        try await api.signupShift(accessId: 3, shiftId: 100)
        XCTAssertEqual(net.seen[1].method, "POST")
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/helpers/shifts/100/signup/")
        try await api.cancelShift(accessId: 3, assignmentId: 7)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/3/helpers/assignments/7/cancel/")
    }

    func testModule() throws {
        func access(_ json: String) throws -> PortalAccess { try JSONDecoder().decode(PortalAccess.self, from: Data(json.utf8)) }
        let both = try access(#"{"id":1,"club_name":"Verein","modules":["todos","helpers"]}"#)
        XCTAssertTrue(both.hasTodos && both.hasHelpers)
        let none = try access(#"{"id":1,"club_name":"Verein","modules":["events"],"helpers_enabled":true}"#)
        XCTAssertFalse(none.hasTodos || none.hasHelpers)
        // Ältere Instanz ohne Modulliste: Helferdienste nach dem einzelnen Schalter, Aufgaben nicht
        let old = try access(#"{"id":1,"club_name":"Verein","helpers_enabled":true}"#)
        XCTAssertFalse(old.hasTodos)
        XCTAssertTrue(old.hasHelpers)
    }
}
