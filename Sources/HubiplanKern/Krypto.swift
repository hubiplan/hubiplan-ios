import Foundation

#if canImport(CryptoKit)
@_exported import CryptoKit
#else
@_exported import Crypto
#endif

/// base64url ohne `=`, wie HUBIplan es überall in der App-Schnittstelle verwendet.
public enum Base64Url {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ text: String) -> Data? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.hasSuffix("=") { s.removeLast() }
        if s.count % 4 == 1 { return nil }
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
