import XCTest
@testable import HubiplanKern

/// Versammlungen V7: QR-Code der Leitung, Stand und Abstimmen. Erfundene Daten.
final class VersammlungLiveTests: XCTestCase {
    private let code = "59123456-0123456789abcdef"
    private var url: String { "https://verein.example.de/mein-bereich/versammlungen/da/12?v=7&c=\(code)" }

    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    func testQrCodeDerLeitung() {
        XCTAssertEqual(MeetingLink.parse(url), MeetingLink(server: "https://verein.example.de", meetingId: 12, clubId: 7, code: code))
        XCTAssertEqual(MeetingLink.parse("  " + url.replacingOccurrences(of: "/12?", with: "/12/?") + "\n")?.meetingId, 12)
    }

    func testFremdeCodesAblehnen() {
        XCTAssertNil(MeetingLink.parse(url.replacingOccurrences(of: "https:", with: "http:")))
        XCTAssertNil(MeetingLink.parse("https://verein.example.de/mein-bereich/versammlungen/da/12?v=7"))
        XCTAssertNil(MeetingLink.parse("https://verein.example.de/mein-bereich/versammlungen/da/x?v=7&c=\(code)"))
        XCTAssertNil(MeetingLink.parse("https://verein.example.de/stand/zugang/abc?v=7&c=\(code)"))
        XCTAssertNil(MeetingLink.parse("https://verein.example.de/mein-bereich/versammlungen/da/12?v=7&c=falsch"))
        XCTAssertNil(MeetingLink.parse("https://verein.example.de/mein-bereich/versammlungen/da/12?v=0&c=\(code)"))
        XCTAssertNil(MeetingLink.parse("https://verein.example.de/mein-bereich/versammlungen/da/12/34?v=7&c=\(code)"))
        XCTAssertNil(MeetingLink.parse("WIFI:S:netz;T:WPA;P:geheim;;"))
    }

    func testNurEigeneInstanzUndEigenerVerein() {
        let ok = LiveTarget.from(scan: url, server: "https://verein.example.de", clubId: 7)
        XCTAssertEqual(ok.target, LiveTarget(meetingId: 12, code: code))
        XCTAssertNil(ok.problem)
        let other = LiveTarget.from(scan: url, server: "https://andere.example.de", clubId: 7)
        XCTAssertNil(other.target)
        XCTAssertEqual(other.problem, "Der QR-Code gehört zu einer anderen HUBIplan-Adresse.")
        XCTAssertNil(LiveTarget.from(scan: url, server: "https://verein.example.de", clubId: 8).target)
        // Ältere Serverstände ohne club_id: nur die Instanz zählt
        XCTAssertEqual(LiveTarget.from(scan: url, server: "https://verein.example.de", clubId: 0).target?.meetingId, 12)
        XCTAssertNotNil(LiveTarget.from(scan: "Hallo", server: "https://verein.example.de", clubId: 7).problem)
    }

    private let stand = #"{"id":12,"title":"Jahreshauptversammlung","kind_name":"JHV","unit":"Schützenverein Musterstadt","location":"Vereinsheim","checkin_open":true,"remote":true,"voter":true,"is_organization":false,"status":"","mode":"","votes":0,"polls":[{"id":4,"agenda_position":7,"question":"Entlastung","secret":true,"status":"open","options":[{"id":1,"role":"yes","label":"Ja"},{"id":2,"role":"no","label":"Nein"}],"result":null,"votes":[{"attendance":3,"name":"Erika Beispiel","how":"own","done":false},{"attendance":5,"name":"Max Muster","how":"proxy","done":false},{"attendance":4,"name":"Max Muster","how":"proxy","done":true}],"neu":"egal"},{"id":5,"agenda_position":8,"agenda_number":"8.1","question":"Wahl","candidate":"Erika Beispiel","office":"Kassiererin","status":"closed","options":[],"result":[{"id":1,"label":"Ja","votes":12},{"id":2,"label":"Nein","votes":1}]}]}"#

    func testStandMitVollmachtLesen() throws {
        let state = try JSONDecoder().decode(MeetingLive.self, from: Data(stand.utf8))
        XCTAssertTrue(state.canJoinRemote)
        XCTAssertTrue(state.canCheckin)
        XCTAssertFalse(state.present)
        XCTAssertEqual(state.subline, "JHV · Schützenverein Musterstadt · Vereinsheim")
        XCTAssertEqual(state.statusText, "Du bist noch nicht angemeldet.")
        let poll = state.polls[0]
        XCTAssertTrue(poll.running)
        XCTAssertEqual(poll.openVotes.map(\.attendance), [3, 5])
        XCTAssertEqual(poll.openVotes.map(\.label), ["Deine Stimme", "Vollmacht von Max Muster"])
        XCTAssertEqual(poll.heading, "7. Entlastung")
        XCTAssertEqual(poll.details, "geheime Abstimmung")
        XCTAssertEqual(state.polls[1].heading, "8.1. Wahl")
        XCTAssertEqual(state.polls[1].details, "Erika Beispiel · Kassiererin · offene Abstimmung")
        XCTAssertEqual(state.polls[1].result?.map(\.votes), [12, 1])
    }

    /// IOS-03: Eine beim Nachfragen eröffnete Abstimmung wird angesagt, nur einmal und nur mit offener Stimme.
    func testNeueAbstimmungAnsagen() throws {
        let jetzt = try JSONDecoder().decode(MeetingLive.self, from: Data(stand.utf8))
        var vorher = jetzt
        vorher.polls[0].status = "closed"
        XCTAssertEqual(neueAbstimmungAnsage(vorher: vorher, jetzt: jetzt), "Abstimmung eröffnet: 7. Entlastung")
        XCTAssertNil(neueAbstimmungAnsage(vorher: jetzt, jetzt: jetzt))
        XCTAssertNil(neueAbstimmungAnsage(vorher: nil, jetzt: jetzt))
        var abgestimmt = jetzt
        abgestimmt.polls[0].votes = []
        XCTAssertNil(neueAbstimmungAnsage(vorher: vorher, jetzt: abgestimmt))
    }

    func testStandTexte() throws {
        var state = try JSONDecoder().decode(MeetingLive.self, from: Data(stand.utf8))
        state.status = "present"
        state.votes = 2
        XCTAssertFalse(state.canJoinRemote)
        XCTAssertFalse(state.canCheckin)
        XCTAssertEqual(state.statusText, "Du bist als anwesend eingetragen. Du hast 2 Stimmen (mit Vollmachten).")
        state.mode = "online"
        state.votes = 1
        XCTAssertEqual(state.statusText, "Du nimmst aus der Ferne teil.")
        state.status = "left"
        XCTAssertEqual(state.statusText, "Du hast dich abgemeldet.")
        state.status = ""
        state.isOrganization = true
        XCTAssertFalse(state.canCheckin)
        XCTAssertFalse(state.canJoinRemote)
        Texte.language = "en"
        XCTAssertEqual(state.polls[0].openVotes[1].label, "Proxy from Max Muster")
    }

    func testAnmeldenGehenAbstimmen() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, stand),
            FakeTransport.json(200, stand),
            FakeTransport.json(200, stand),
            FakeTransport.json(200, stand),
            FakeTransport.json(200, stand),
        ])
        let api = Api(server: "https://verein.example.de", transport: net, tokens: FakeTokens("hpd_a"))
        _ = try await api.meetingLive(accessId: 3, meetingId: 12)
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/portal/3/meetings/12/live/")
        XCTAssertEqual(net.seen[0].method, "GET")

        _ = try await api.meetingCheckin(accessId: 3, meetingId: 12, code: code)
        XCTAssertEqual(net.seen[1].url, "https://verein.example.de/api/portal/3/meetings/12/live/checkin/")
        let checkin = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[1].body ?? Data()) as? [String: Any])
        XCTAssertEqual(checkin as? [String: String], ["code": code])

        _ = try await api.meetingCheckin(accessId: 3, meetingId: 12, code: nil, remote: true)
        let remote = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[2].body ?? Data()) as? [String: Any])
        XCTAssertEqual(remote["remote"] as? Bool, true)
        XCTAssertEqual(remote.count, 1)

        _ = try await api.meetingLeave(accessId: 3, meetingId: 12)
        XCTAssertEqual(net.seen[3].url, "https://verein.example.de/api/portal/3/meetings/12/live/leave/")
        XCTAssertEqual(net.seen[3].method, "POST")

        _ = try await api.meetingVote(accessId: 3, meetingId: 12, pollId: 4, votes: [5: 2, 3: 1])
        XCTAssertEqual(net.seen[4].url, "https://verein.example.de/api/portal/3/meetings/12/polls/4/vote/")
        let vote = try XCTUnwrap(JSONSerialization.jsonObject(with: net.seen[4].body ?? Data()) as? [String: Any])
        let list = try XCTUnwrap(vote["votes"] as? [[String: Int]])
        XCTAssertEqual(list, [["attendance": 3, "option": 1], ["attendance": 5, "option": 2]])
    }
}
