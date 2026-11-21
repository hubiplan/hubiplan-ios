import XCTest
@testable import HubiplanKern

/// Vorstandsaufgaben (Beitrittsanträge, Belegung freigeben, Versammlung leiten), gleiche Fälle wie
/// Android `AdminVorstandTest`; alle Daten erfunden.
final class VerwaltungVorstandTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() {
        Texte.language = "de"
    }

    private func verwaltung(_ net: FakeTransport, unit: AdminUnit = AdminUnit(id: 7, name: "Verein")) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: unit)
    }

    private func body(_ net: FakeTransport, _ index: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: net.seen[index].body ?? Data())) as? [String: Any] ?? [:]
    }

    func testBereicheNachModulUndRecht() {
        let verein = AdminUnit(id: 1, name: "Verein", permissions: ["members.view", "bookings.edit", "meetings.edit"], modules: ["members", "bookings", "meetings"])
        XCTAssertTrue(verein.showsApplications)
        XCTAssertTrue(verein.showsBookings)
        XCTAssertTrue(verein.showsMeetings)
        XCTAssertTrue(verein.canMeetingAttendance)
        XCTAssertTrue(verein.sections.contains(.applications))
        XCTAssertTrue(verein.sections.contains(.bookings))
        XCTAssertTrue(verein.sections.contains(.meetings))
        // Ohne Modul kein Bereich, auch mit Recht
        let ohneModul = AdminUnit(id: 1, name: "Verein", permissions: ["bookings.edit", "meetings.edit"])
        XCTAssertFalse(ohneModul.showsBookings)
        XCTAssertFalse(ohneModul.showsMeetings)
        XCTAssertFalse(ohneModul.canMeetingAttendance)
    }

    func testOffenePunkteFuehrenZuAntragUndBelegung() throws {
        let tasks = try JSONDecoder().decode(AdminTasks.self, from: Data(#"""
        {"items":[{"kind":"application","kind_label":"Beitrittsantrag","title":"Erika Muster","ref":3},
                  {"kind":"booking","kind_label":"Belegung","title":"Saal","ref":11}]}
        """#.utf8))
        XCTAssertEqual(tasks.items[0].target, .application(3))
        XCTAssertEqual(tasks.items[1].target, .bookings)
    }

    func testBeitrittsantraegeLesenUndEntscheiden() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"results":[{"id":3,"status":"open","name":"Muster, Erika","approvals_met":false,"missing":["Vorstand"]}],"may_approve":true,"counts":{"open":1}}"#),
            FakeTransport.json(200, #"{"id":3,"status":"open","approvals_met":true,"may_decide":true,"may_approve":true,"own_decision":null,"summary":["Name: Erika Muster"],"entry_date":"2026-12-01"}"#),
            FakeTransport.json(200, #"{"id":3,"status":"open","own_decision":"approve","may_approve":true}"#),
            FakeTransport.json(200, #"{"id":3,"status":"accepted"}"#),
        ])
        let client = verwaltung(net)
        let list = try await client.applications()
        XCTAssertEqual(list.results.first?.name, "Muster, Erika")
        XCTAssertTrue(list.results[0].isOpen)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/7/admission/?status=offen")

        let d = try await client.application(3)
        XCTAssertTrue(d.canAccept && d.canApprove)

        let approved = try await client.approveApplication(3, approve: true, note: " passt ")
        XCTAssertFalse(approved.canApprove)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/7/admission/3/approve/")
        XCTAssertEqual(body(net, 2)["decision"] as? String, "approve")
        XCTAssertEqual(body(net, 2)["note"] as? String, "passt")

        let accepted = try await client.acceptApplication(3, entryDate: "2026-12-01", note: "", welcome: true)
        XCTAssertEqual(accepted.status, "accepted")
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/app/v1/admin/u/7/admission/3/accept/")
        XCTAssertEqual(body(net, 3)["entry_date"] as? String, "2026-12-01")
        XCTAssertEqual(body(net, 3)["welcome"] as? Bool, true)
    }

    func testAblehnungEinesAnderenVerhindertAufnahme() throws {
        let d = try JSONDecoder().decode(ApplicationDetail.self, from: Data(#"{"id":1,"status":"open","disputed":true,"approvals_met":true,"may_decide":true}"#.utf8))
        XCTAssertFalse(d.canAccept)
    }

    func testBelegungFreigebenMitVersion() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"occurrences":[],"requests":[{"id":11,"item_title":"Saal","title":"Geburtstag","version":2,"member_name":"Anna Beispiel","starts_at":"2026-12-05T18:00:00+01:00","ends_at":"2026-12-05T23:00:00+01:00"}]}"#),
            FakeTransport.json(200, #"{"id":11,"status":"confirmed","version":3}"#),
            FakeTransport.json(409, #"{"detail":"Die Buchung wurde inzwischen geändert."}"#),
        ])
        let client = verwaltung(net)
        let list = try await client.bookingRequests(today: "2026-11-21")
        XCTAssertEqual(list.first?.requester, "Anna Beispiel")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/7/bookings/?start=2026-11-21")
        _ = try await client.decideBooking(11, version: 2, confirm: true)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/7/bookings/11/decision/")
        XCTAssertEqual(body(net, 1)["action"] as? String, "confirm")
        XCTAssertEqual(body(net, 1)["version"] as? Int, 2)
        do {
            _ = try await client.decideBooking(11, version: 2, confirm: false)
            XCTFail("409 erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.status, 409)
        }
    }

    func testVersammlungLeiten() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"[{"id":5,"title":"Jahreshauptversammlung","status":"invited","agenda":[{"id":9,"type":"resolution","title":"Entlastung"}]}]"#),
            FakeTransport.json(200, #"{"voters":10,"present":1,"editable":true,"rows":[{"id":1,"membership":20,"name":"Anna Beispiel","voter":true,"status":"present"}]}"#),
            FakeTransport.json(200, #"{"rows":[]}"#),
            FakeTransport.json(200, #"{"meeting":5,"organization":7,"checkin_open":true,"live":true,"code":"123-0123456789abcdef","refresh_in":12,"polls":[]}"#),
            FakeTransport.json(201, #"{"meeting":5,"polls":[{"id":2,"status":"draft"}]}"#),
            FakeTransport.json(200, #"{"meeting":5,"polls":[{"id":2,"status":"open"}]}"#),
        ])
        let dept = verwaltung(net, unit: AdminUnit(id: 4, name: "1. Zug", scope: "d"))
        let client = verwaltung(net)
        let m = try await dept.meetings()
        XCTAssertTrue(m[0].isLive && m[0].agenda[0].votable)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/d/4/meetings/")

        let att = try await client.setAttendance(meeting: 5, membership: 20, name: nil, status: "present")
        XCTAssertTrue(att.rows[0].present)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/app/v1/admin/u/7/meetings/5/attendance/")
        XCTAssertEqual(body(net, 1)["membership"] as? Int, 20)

        _ = try await client.removeAttendance(meeting: 5, entry: 1)
        XCTAssertEqual(net.seen[2].method, "DELETE")
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/app/v1/admin/u/7/meetings/5/attendance/1/")

        let live = try await client.setCheckin(meeting: 5, open: true)
        XCTAssertEqual(body(net, 3)["open"] as? Bool, true)
        let link = try XCTUnwrap(live.checkinLink(server: "https://verein.example.org/"))
        XCTAssertEqual(link, "https://verein.example.org/mein-bereich/versammlungen/da/5?v=7&c=123-0123456789abcdef")
        // Die Mitglieder-App versteht genau diesen Link
        let parsed = try XCTUnwrap(MeetingLink.parse(link))
        XCTAssertEqual(parsed.meetingId, 5)
        XCTAssertEqual(parsed.clubId, 7)
        XCTAssertEqual(parsed.code, "123-0123456789abcdef")
        let closed = try JSONDecoder().decode(LeadLive.self, from: Data(#"{"meeting":5,"organization":7,"checkin_open":false,"code":"x"}"#.utf8))
        XCTAssertNil(closed.checkinLink(server: "https://verein.example.org"))

        _ = try await client.createPoll(meeting: 5, agendaItem: 9, question: "Entlastung?", secret: true, candidates: [" ", "Anna"])
        XCTAssertEqual(net.seen[4].url, "https://verein.example.de/api/app/v1/admin/u/7/meetings/5/polls/")
        XCTAssertEqual(body(net, 4)["agenda_item"] as? Int, 9)
        XCTAssertEqual((body(net, 4)["candidates"] as? [Any])?.count, 1)

        let opened = try await client.pollAction(meeting: 5, poll: 2, action: "open")
        XCTAssertEqual(opened.polls.first?.status, "open")
        XCTAssertEqual(net.seen[5].url, "https://verein.example.de/api/app/v1/admin/u/7/meetings/5/polls/2/")
    }
}
