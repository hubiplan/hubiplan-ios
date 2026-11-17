import Foundation
import XCTest
@testable import HubiplanKern

/// Produkt und Mindestversion je Plattform (Gesamtaudit 15.11., APP-11). Gleiche Fälle wie in
/// hubiplan-android (MindestversionTest).
final class MindestversionTests: XCTestCase {
    private func instanz(_ text: String) throws -> Instance {
        try JSONDecoder().decode(Instance.self, from: Data(text.utf8))
    }

    func testIosWertJePlattform() throws {
        let i = try instanz(#"{"product":"HUBIplan","api_version":1,"min_app_version":3,"min_app_versions":{"android":7,"ios":2}}"#)
        XCTAssertEqual(i.minIosBuild, 2)
        XCTAssertNoThrow(try i.check(build: 2))
        XCTAssertThrowsError(try i.check(build: 1)) { error in
            XCTAssertEqual((error as? ApiError)?.code, "app_too_old")
        }
    }

    func testAeltereInstanzOhneListeVerlangtNichts() throws {
        // Der alte Wert gilt für Android (versionCode), nicht für iOS
        let i = try instanz(#"{"product":"HUBIplan","api_version":1,"min_app_version":9}"#)
        XCTAssertNoThrow(try i.check(build: 1))
    }

    func testFremdesProdukt() throws {
        let i = try instanz(#"{"product":"Etwas anderes","api_version":1}"#)
        XCTAssertThrowsError(try i.check(build: 99)) { error in
            XCTAssertEqual((error as? ApiError)?.code, "not_hubiplan")
        }
    }

    func testZuAlteAppVerbindetNicht() async {
        let net = FakeTransport([
            FakeTransport.json(200, #"{"product":"HUBIplan","api_version":1,"min_app_versions":{"ios":5}}"#),
        ])
        let store = MemoryStore()
        let session = DeviceSession(server: "https://verein.example.de", store: store, transport: net)
        do {
            _ = try await session.connect(code: "abc", deviceName: "iPhone", appVersion: "4")
            XCTFail("Fehler erwartet")
        } catch let error as ApiError {
            XCTAssertEqual(error.code, "app_too_old")
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(net.seen.count, 1)  // nur die Selbstauskunft, der Code bleibt unberührt
        XCTAssertNil(store.read(DeviceSession.tokenKey))
    }
}
