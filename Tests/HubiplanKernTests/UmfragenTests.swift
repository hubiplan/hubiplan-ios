import XCTest
@testable import HubiplanKern

/// Umfragen unter „Ich“ (HUBIplan Umfragen, Stufe U2), gleiche Fälle wie `UmfragenTest` in Android.
/// Alle Daten erfunden.
final class UmfragenTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let list = #"""
    {"surveys":[
      {"id":5,"title":"Ausflug 2099","description":"","unit":"","event":null,"status":"open",
       "closes_at":"2099-05-01T18:00:00Z","names":"open","results_mode":"after_answer","anonymous":false,
       "answered":false,"can_answer":true,"can_change":false,"mine":null,"results":null,"follow_event":null,
       "questions":[
         {"id":1,"kind":"single","text":"Wie fährst du mit?","required":true,"max_choices":null,"allow_maybe":false,
          "options":[{"id":11,"label":"Bus","starts_at":null,"ends_at":null,"all_day":false,"capacity":50},
                     {"id":12,"label":"eigenes Auto","starts_at":null,"ends_at":null,"all_day":false,"capacity":null}]},
         {"id":2,"kind":"dates","text":"Wann passt es?","required":true,"max_choices":null,"allow_maybe":true,
          "options":[{"id":21,"label":"","starts_at":"2099-06-13T16:00:00Z","ends_at":null,"all_day":false,"capacity":null},
                     {"id":22,"label":"","starts_at":"2099-06-20T16:00:00Z","ends_at":null,"all_day":false,"capacity":null}]},
         {"id":3,"kind":"quantity","text":"Essen","required":false,"max_choices":null,"allow_maybe":false,"max_total":2,
          "options":[{"id":31,"label":"Schnitzel"},{"id":32,"label":"vegetarisch"}]},
         {"id":4,"kind":"text","text":"Anmerkungen","required":false,"options":[]}]},
      {"id":6,"title":"Grillabend","status":"closed","anonymous":true,"answered":true,"can_answer":false,
       "questions":[],"results":{"participants":2,"hidden":true,"questions":[]},
       "follow_event":{"id":40,"title":"Grillabend","starts_at":"2099-06-13T16:00:00Z","ends_at":"2099-06-13T20:00:00Z",
         "all_day":false,"rsvp_enabled":true,"said_yes":true,"response":null}}]}
    """#

    func testAntwortLesen() throws {
        let data = try JSONDecoder().decode(SurveyList.self, from: Data(list.utf8))
        XCTAssertEqual(data.surveys.count, 2)
        let s = data.surveys[0]
        XCTAssertTrue(s.waiting)
        XCTAssertEqual(s.questions[2].quantityLimit, 2)
        XCTAssertEqual(data.waitingCount, 1)
        var closed = data.surveys[1]
        XCTAssertFalse(closed.isOpen)
        XCTAssertTrue(closed.canFollow)
        XCTAssertTrue(closed.results?.hidden ?? false)
        closed.followEvent?.response = "yes"
        XCTAssertFalse(closed.canFollow)
    }

    func testFormularUndNutzlast() async throws {
        let s = try JSONDecoder().decode(SurveyList.self, from: Data(list.utf8)).surveys[0]
        var draft = s.initialDraft()
        // Terminfindung startet mit „Nein“ für jeden Vorschlag
        XCTAssertEqual(draft[2]?.dates, ["21": "no", "22": "no"])
        XCTAssertFalse(s.ready(draft))
        draft[1]?.options = [11]
        XCTAssertTrue(s.ready(draft))
        draft[2]?.dates = ["21": "yes", "22": "maybe"]
        draft[3]?.quantities = ["31": 2, "32": 1]
        XCTAssertFalse(s.ready(draft), "mehr als erlaubt")
        draft[3]?.quantities = ["31": 2, "32": 0]
        XCTAssertTrue(s.ready(draft))
        XCTAssertFalse(s.questions[3].filled(SurveyAnswerRow(question: 4, text: "  ")))

        let answered = #"{"id":5,"title":"Ausflug 2099","status":"open","answered":true,"can_answer":true,"can_change":true,"questions":[]}"#
        let net = FakeTransport([FakeTransport.json(200, answered), FakeTransport.json(200, answered), FakeTransport.json(200, answered)])
        let api = Api(server: server, transport: net, tokens: FakeTokens("hpd_a"))
        let back = try await api.answerSurvey(accessId: 3, surveyId: 5, payload: s.answerPayload(draft))
        XCTAssertTrue(back.canChange)
        XCTAssertEqual(net.seen[0].method, "POST")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/surveys/5/answer/")
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(net.seen[0].body)) as? [String: Any])
        let rows = try XCTUnwrap(sent["answers"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0]["question"] as? Int, 1)
        XCTAssertEqual(rows[0]["options"] as? [Int], [11])
        XCTAssertEqual(rows[1]["dates"] as? [String: String], ["21": "yes", "22": "maybe"])
        XCTAssertEqual(rows[2]["quantities"] as? [String: Int], ["31": 2])

        _ = try await api.withdrawSurvey(accessId: 3, surveyId: 5)
        XCTAssertEqual(net.seen[1].method, "DELETE")
        _ = try await api.followSurvey(accessId: 3, surveyId: 5)
        XCTAssertEqual(net.seen[2].url, "https://verein.example.de/api/portal/3/surveys/5/follow/")
    }

    func testIchZeigtUmfragen() throws {
        func access(_ json: String) throws -> PortalAccess { try JSONDecoder().decode(PortalAccess.self, from: Data(json.utf8)) }
        XCTAssertTrue(try access(#"{"id":5,"club_name":"Musterstadt","modules":["surveys"],"surveys_open":2}"#).hasSurveys)
        XCTAssertEqual(try access(#"{"id":5,"club_name":"Musterstadt","surveys_open":2}"#).surveysOpen, 2)
        XCTAssertFalse(try access(#"{"id":5,"club_name":"Musterstadt","modules":[]}"#).hasSurveys)
        // Ältere Stände ohne Modulliste: Schalter
        XCTAssertTrue(try access(#"{"id":5,"club_name":"Musterstadt","surveys_enabled":true}"#).hasSurveys)
        let data = try JSONDecoder().decode(SurveyList.self, from: Data(list.utf8))
        XCTAssertEqual(data.summary, "1 wartet auf dich")
        XCTAssertEqual(SurveyList().summary, "Keine offenen Umfragen")
        XCTAssertEqual(surveyValueLabel("abstain"), "Enthaltung")
        Texte.language = "en"
        XCTAssertEqual(data.summary, "1 waiting for you")
    }
}
