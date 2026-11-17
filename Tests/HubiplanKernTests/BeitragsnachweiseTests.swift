import XCTest
@testable import HubiplanKern

/// Beitragsnachweise unter „Ich“, gleiche Fälle wie `BeitragsnachweiseTest` in Android.
/// Alle Daten erfunden.
final class BeitragsnachweiseTests: XCTestCase {
    override func setUp() { Texte.language = "de" }
    override func tearDown() { Texte.language = "de" }

    private let text = #"""
    {"states":[
      {"discount":3,"discount_name":"Studierende","kinds":["Immatrikulationsbescheinigung"],
       "year":2099,"year_label":"2099","due":"2099-02-28","final":"2099-03-14","state":"open",
       "applies":true,"proof":null,"unknown_field":1},
      {"discount":3,"discount_name":"Studierende","kinds":[],"year":2098,"year_label":"2098",
       "due":"2098-02-28","final":"2098-02-28","state":"accepted","applies":true,
       "proof":{"id":7,"status":"accepted","valid_until":"2099-03-31","received_on":"2098-01-20"}}
    ],
    "proofs":[{"id":7,"discount_name":"Studierende","year":2098,"year_label":"2098","status":"accepted",
               "received_on":"2098-01-20","valid_until":"2099-03-31","file_name":"","note":""}]}
    """#

    func testLiestStandUndNachweise() throws {
        let o = try JSONDecoder().decode(FeeProofOverview.self, from: Data(text.utf8))
        let open = o.states[0]
        XCTAssertTrue(open.canSubmit && open.needsMe)
        XCTAssertEqual(open.kinds, ["Immatrikulationsbescheinigung"])
        XCTAssertEqual(open.sentence, "Bitte bis 28.02.2099 einreichen (spätestens 14.03.2099).")
        let done = o.states[1]
        XCTAssertFalse(done.canSubmit)
        XCTAssertEqual(done.sentence, "Anerkannt, gültig bis 31.03.2099.")
        XCTAssertEqual(done.label, "Nachweis anerkannt")
        XCTAssertEqual(o.proofs.count, 1)
    }

    func testIchZeigtNachweiseNurMitErmaessigung() throws {
        let on = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV","fee_proofs_enabled":true,"fee_proofs_due":1}"#.utf8))
        XCTAssertTrue(on.hasFeeProofs)
        XCTAssertEqual(on.feeProofsDue, 1)
        let off = try JSONDecoder().decode(PortalAccess.self, from: Data(#"{"id":5,"club_name":"SV"}"#.utf8))
        XCTAssertFalse(off.hasFeeProofs)
        XCTAssertEqual(feeProofSummary(due: 1), "1 Nachweis fehlt")
        XCTAssertEqual(feeProofSummary(due: 0), "Nachweis für den ermäßigten Beitrag")
    }

    func testFelderZumEinreichen() {
        let fields = Dictionary(feeProofFields(discount: 3, year: 2099, kind: "", note: "WS").map { ($0.name, $0.value) }, uniquingKeysWith: { $1 })
        XCTAssertEqual(fields, ["discount": "3", "year": "2099", "kind": "", "note": "WS"])
    }
}
