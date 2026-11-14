import Foundation

/// Formate der Härtung H7, genau wie der Server sie prüft (`devices/devicekey.py` in HUBIplan):
/// öffentlicher Schlüssel als unkomprimierter P-256-Punkt (65 Byte), Unterschrift als DER,
/// alles base64url ohne `=`.
public enum SignedFormat {
    public static let timeHeader = "X-Hubiplan-Time"
    public static let signatureHeader = "X-Hubiplan-Signature"
    /// Format 2: Zufallskennung je Anfrage; der Server kündigt es mit `formatHeader` an.
    public static let nonceHeader = "X-Hubiplan-Nonce"
    public static let idempotencyHeader = "Idempotency-Key"
    public static let formatHeader = "X-Hubiplan-Signature-Format"

    /// 16 zufällige Byte, base64url (22 Zeichen).
    public static func newNonce() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Base64Url.encode(Data(bytes))
    }

    public static func renewMessage(deviceId: Int, challenge: String) -> Data {
        Data("hubiplan-renew\n\(deviceId)\n\(challenge)".utf8)
    }

    /// `path`: Pfad samt Abfrage wie gesendet (percent-kodiert). Mit `nonce` Format 2:
    /// zusätzlich Zufallskennung und `Idempotency-Key`.
    public static func adminMessage(
        method: String,
        path: String,
        timestamp: String,
        body: Data,
        nonce: String = "",
        idempotency: String = ""
    ) -> Data {
        let digest = Data(SHA256.hash(data: body)).hex
        if !nonce.isEmpty {
            return Data("hubiplan-admin-2\n\(method.uppercased())\n\(path)\n\(timestamp)\n\(nonce)\n\(idempotency)\n\(digest)".utf8)
        }
        return Data("hubiplan-admin\n\(method.uppercased())\n\(path)\n\(timestamp)\n\(digest)".utf8)
    }

    /// Öffentlicher Schlüssel, wie die App ihn als `device_key` meldet.
    public static func publicKey(_ key: P256.Signing.PublicKey) -> String {
        Base64Url.encode(key.x963Representation)
    }

    /// Unterschrift (ECDSA mit SHA-256, DER) über eine der Nachrichten oben.
    public static func sign(_ message: Data, with key: P256.Signing.PrivateKey) throws -> String {
        Base64Url.encode(try key.signature(for: message).derRepresentation)
    }
}
