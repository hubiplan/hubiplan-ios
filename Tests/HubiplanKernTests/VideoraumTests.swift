import XCTest
@testable import HubiplanKern

/// Videoraum (Nextcloud Talk) am Termin; gleiche Fälle wie `VideoraumTest` in der Android-App.
final class VideoraumTests: XCTestCase {
    func testTerminTraegtLinkUndPasswort() throws {
        let json = #"""
        {"id":7,"title":"Vorstandssitzung","starts_at":"2099-03-05T19:30:00+01:00","ends_at":"2099-03-05T21:30:00+01:00",
         "video":{"url":"https://cloud.example.org/call/abc123","password":"Xy-7kq+P2mZt9wRa","created_at":"2099-03-01T10:00:00+01:00"}}
        """#
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(json.utf8))
        XCTAssertEqual(event.video?.url, "https://cloud.example.org/call/abc123")
        XCTAssertEqual(event.video?.password, "Xy-7kq+P2mZt9wRa")
        XCTAssertEqual(event.video?.openable, true)
        let occ = try JSONDecoder().decode(Occurrence.self, from: Data(#"""
        {"key":"7","event_id":7,"title":"Vorstandssitzung","starts_at":"2099-03-05T19:30:00+01:00","ends_at":"2099-03-05T21:30:00+01:00","video":{"url":"https://cloud.example.org/call/abc123","password":""}}
        """#.utf8))
        XCTAssertEqual(occ.video?.password, "")
    }

    func testOhneVideoraumOderAlterServer() throws {
        let event = try JSONDecoder().decode(EventDetail.self, from: Data(#"""
        {"id":8,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00","video":null}
        """#.utf8))
        XCTAssertNil(event.video)
        let alt = try JSONDecoder().decode(Occurrence.self, from: Data(#"""
        {"key":"8","event_id":8,"title":"Sommerfest","starts_at":"2099-06-13T14:00:00+02:00","ends_at":"2099-06-13T18:00:00+02:00"}
        """#.utf8))
        XCTAssertNil(alt.video)
    }

    func testNurHttpsWirdGeoeffnet() {
        XCTAssertFalse(VideoRoom(url: "http://cloud.example.org/call/x").openable)
        XCTAssertFalse(VideoRoom(url: "javascript:alert(1)").openable)
        XCTAssertFalse(VideoRoom().openable)
    }

    func testTexteAufEnglisch() {
        Texte.language = "en"
        defer { Texte.language = "de" }
        XCTAssertEqual(tr("Videoraum öffnen"), "Open video room")
        XCTAssertEqual(tr("Passwort: {password}", ["password": "x"]), "Password: x")
    }
}
