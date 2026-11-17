import Foundation

/// Unterschreibt mit dem Geräteschlüsselpaar (Härtung H7).
public protocol DeviceKeySigner: Sendable {
    /// Öffentlicher Teil, wie die App ihn als `device_key` meldet.
    var publicKey: String { get }
    /// Unterschrift (ECDSA P-256 mit SHA-256, DER, base64url).
    func sign(_ message: Data) throws -> String
    /// Liegt der private Teil in Hardware (Secure Enclave)?
    var inHardware: Bool { get }
}

/// Woher das Geräteschlüsselpaar kommt (Gesamtaudit 15.11., APP-03). Die App nutzt die Secure
/// Enclave, wenn das Gerät eine hat; der Kern und die Tests den Software-Schlüssel.
public protocol DeviceKeyStore: Sendable {
    /// Neues Schlüsselpaar; `stored` legt die App im Schlüsselbund ab.
    func create() throws -> (signer: DeviceKeySigner, stored: String)
    /// Gespeichertes Schlüsselpaar laden; nil, wenn es sich nicht (mehr) laden lässt.
    func load(_ stored: String) -> DeviceKeySigner?
}

/// Software-Schlüssel (CryptoKit/swift-crypto); so verbundene Geräte bleiben gültig.
public struct SoftwareDeviceKeys: DeviceKeyStore {
    public init() {}

    public func create() throws -> (signer: DeviceKeySigner, stored: String) {
        let key = P256.Signing.PrivateKey()
        return (SoftwareSigner(key: key), Base64Url.encode(key.rawRepresentation))
    }

    public func load(_ stored: String) -> DeviceKeySigner? {
        guard let raw = Base64Url.decode(stored), let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) else {
            return nil
        }
        return SoftwareSigner(key: key)
    }
}

struct SoftwareSigner: DeviceKeySigner {
    let key: P256.Signing.PrivateKey
    var publicKey: String { SignedFormat.publicKey(key.publicKey) }
    var inHardware: Bool { false }
    func sign(_ message: Data) throws -> String { try SignedFormat.sign(message, with: key) }
}
