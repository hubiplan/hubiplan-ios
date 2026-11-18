import XCTest
@testable import HubiplanKern

/// Gleicher Fall wie Android (UxAudit1116cTest.absageFristBeimEintragen, AND-22).
final class HelferFristTests: XCTestCase {
    func testAbsageFristBeimEintragen() throws {
        let json = #"{"id":9,"title":"Sommerfest","cancel_days":3,"duties":[{"id":2,"name":"Ausschank","shifts":[{"id":1,"starts_at":"2026-12-05T10:00:00+01:00","ends_at":"2026-12-05T14:00:00+01:00","needed":2}]}]}"#
        let plan = try JSONDecoder().decode(HelperPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.cancelDays, 3)
        let shift = try XCTUnwrap(plan.duties.first?.shifts.first)
        XCTAssertTrue(plan.cancellableAfterSignup(shift, now: try XCTUnwrap(Zeit.parse("2026-12-01T08:00:00Z"))))
        XCTAssertFalse(plan.cancellableAfterSignup(shift, now: try XCTUnwrap(Zeit.parse("2026-12-03T08:00:00Z"))))
        var broken = shift
        broken.startsAt = "kaputt"
        XCTAssertFalse(plan.cancellableAfterSignup(broken))
    }
}
