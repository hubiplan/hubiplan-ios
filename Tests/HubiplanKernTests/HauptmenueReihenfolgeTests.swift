import XCTest
@testable import HubiplanKern

/// Verwaltungsbereiche in der Reihenfolge der Gruppen des Hauptmenüs im Browser, wie Android
/// (HauptmenueReihenfolgeTest).
final class HauptmenueReihenfolgeTests: XCTestCase {
    func testBereicheFolgenDenMenuegruppen() {
        let unit = AdminUnit(
            id: 1,
            name: "Verein",
            permissions: [
                "todos.view", "members.view", "events.view", "finance.view", "billing.view",
                "competitions.results", "partners.view", "obligations.view",
            ],
            stufen: true,
            modules: ["competitions", "qualifications", "obligations"]
        )
        XCTAssertEqual(unit.sections, [
            .tasks,
            .events, .todos, .obligations,
            .members, .occasions, .qualifications,
            .competitions,
            .finance, .billing, .partners,
        ])
    }

    func testUntereinheitTermineZuerst() {
        let zug = AdminUnit(id: 4, name: "Zug", permissions: ["todos.view", "members.view", "events.view"], scope: "d", stufen: true)
        XCTAssertEqual(zug.sections, [.events, .todos, .members])
    }
}
