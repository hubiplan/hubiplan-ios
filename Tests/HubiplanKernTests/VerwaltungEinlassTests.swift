import XCTest
@testable import HubiplanKern

/// Einlass bei Terminen mit Anmeldung (HUBIplan A6/A7), gleiche Fälle wie Android `EinlassTest`;
/// alle Daten erfunden.
final class VerwaltungEinlassTests: XCTestCase {
    private let server = "https://verein.example.de"

    override func setUp() {
        Texte.language = "de"
    }

    private let antwort = #"""
    {"event_id":5,"title":"Sommerfest","can_edit":true,"can_cash":true,"count":3,"checked_in":1,
     "participants":[
      {"id":1,"name":"Anna Muster","price_name":"Erwachsene","registration_id":3,"number":"A2099-0001",
       "contact":"Anna Muster","paid_state":"paid","invoice_id":9,"invoice_number":"2099-0042","outstanding":"0.00",
       "checked_in_at":"2099-07-03T14:05:00+02:00","checked_in_via":"Eingang Nord","minor":false,
       "bookings":[{"name":"Mittagessen","redeemed_at":null}]},
      {"id":2,"name":"Kim Muster","price_name":"Kinder","registration_id":3,"number":"A2099-0001",
       "contact":"Anna Muster","paid_state":"open","invoice_id":10,"invoice_number":"2099-0043","outstanding":"15.00",
       "checked_in_at":null,"minor":true},
      {"id":3,"name":"Gerd Gast","price_name":"Gäste","registration_id":4,"number":"A2099-0002",
       "contact":"Gerd Gast","paid_state":"free","invoice_id":null,"invoice_number":"","outstanding":"0.00",
       "checked_in_at":null,"minor":false,"neu":"wird ignoriert"}]}
    """#

    private func liste() throws -> CheckInList {
        try JSONDecoder().decode(CheckInList.self, from: Data(antwort.utf8))
    }

    private func verwaltung(_ net: FakeTransport) -> AdminClient {
        AdminClient(api: Api(server: server, transport: net, tokens: FakeTokens("hpd_a")).verwaltung(AdminAccess(token: "hpa_erfunden", key: nil)), unit: AdminUnit(id: 4, name: "Verein"))
    }

    func testListeLesen() throws {
        let l = try liste()
        XCTAssertEqual(l.participants.count, 3)
        XCTAssertTrue(l.canCash)
        let anna = l.participants[0]
        XCTAssertTrue(anna.checkedIn)
        XCTAssertEqual(anna.checkedInVia, "Eingang Nord")
        XCTAssertNil(anna.bookings[0].redeemedAt)
        XCTAssertFalse(anna.owes)
        XCTAssertTrue(l.participants[1].owes)
        // Kostenlos: keine Rechnung, nichts zu kassieren
        XCTAssertFalse(l.participants[2].owes)
        XCTAssertEqual(l.stand, "1 von 3 eingelassen")
        XCTAssertEqual(l.participants[2].detail, "A2099-0002 · Gäste · kostenlos")
    }

    func testSucheNachNameNummerUndAnmeldendem() throws {
        let l = try liste()
        XCTAssertEqual(l.filtered("muster").map(\.id), [1, 2])
        XCTAssertEqual(l.filtered("0002").map(\.id), [3])
        XCTAssertEqual(l.filtered(" anna ").map(\.id), [1, 2])
        XCTAssertEqual(l.filtered("").count, 3)
    }

    func testOhneNetzWartenSchritteUndHebenSichAuf() throws {
        var q = PendingCheckIn.queue([], PendingCheckIn(participant: 2, undo: false))
        q = PendingCheckIn.queue(q, PendingCheckIn(participant: 3, undo: false))
        XCTAssertEqual(q.map(\.participant), [2, 3])
        // Einlassen und gleich wieder zurücknehmen: nichts nachzureichen
        q = PendingCheckIn.queue(q, PendingCheckIn(participant: 2, undo: true))
        XCTAssertEqual(q.map(\.participant), [3])
        let l = try liste().with(pending: q, now: "2099-07-03T15:00:00+02:00")
        XCTAssertEqual(l.checkedIn, 2)
        XCTAssertEqual(l.participants[2].checkedInAt, "2099-07-03T15:00:00+02:00")
    }

    func testErgebnisGutOderAuffaellig() throws {
        let ok = try JSONDecoder().decode(CheckInResult.self, from: Data(#"{"result":"ok","message":"Eingelassen.","participant":null}"#.utf8))
        let schon = try JSONDecoder().decode(CheckInResult.self, from: Data(#"{"result":"already","message":"Schon eingelassen."}"#.utf8))
        XCTAssertTrue(ok.good)
        XCTAssertFalse(schon.good)
    }

    func testKarteScannenUndPersonEinlassen() async throws {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"result":"ok","message":"Eingelassen.","participant":{"id":2,"name":"Kim Muster","checked_in_at":"2099-07-03T14:10:00+02:00"}}"#),
            FakeTransport.json(200, #"{"result":"undone","message":"Einlass zurückgenommen.","participant":null}"#),
        ])
        let client = verwaltung(net)
        let r = try await client.checkIn(5, code: " T1:abc\n")
        XCTAssertEqual(r.participant?.id, 2)
        _ = try await client.checkIn(5, participant: 2, undo: true)
        XCTAssertEqual(net.seen[0].method, "POST")
        XCTAssertEqual(net.seen[0].url, "https://verein.example.de/api/app/v1/admin/u/4/events/5/registration/checkin/")
        let first = try JSONSerialization.jsonObject(with: net.seen[0].body ?? Data()) as? [String: Any]
        XCTAssertEqual(first?["code"] as? String, "T1:abc")
        let second = try JSONSerialization.jsonObject(with: net.seen[1].body ?? Data()) as? [String: Any]
        XCTAssertEqual(second?["participant"] as? Int, 2)
        XCTAssertEqual(second?["undo"] as? Bool, true)
    }
}
