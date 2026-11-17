import Foundation
import XCTest

/// Datenschutz-Manifest der App (Gesamtaudit 15.11., APP-12): gültige Property-Liste, kein
/// Tracking, Gründe für die genutzten Required-Reason-APIs. Ob Xcode es beim Archivieren
/// übernimmt, prüft nur ein Lauf auf macOS.
final class DatenschutzManifestTests: XCTestCase {
    private func manifest() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/HUBIplan/PrivacyInfo.xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    func testKeinTrackingUndGruende() throws {
        let m = try manifest()
        XCTAssertEqual(m["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((m["NSPrivacyTrackingDomains"] as? [String])?.count, 0)
        let apis = try XCTUnwrap(m["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var reasons: [String: [String]] = [:]
        for api in apis {
            reasons[api["NSPrivacyAccessedAPIType"] as? String ?? ""] =
                api["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        }
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
        let collected = try XCTUnwrap(m["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertFalse(collected.isEmpty)
        for item in collected {
            XCTAssertEqual(item["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
        }
    }
}
