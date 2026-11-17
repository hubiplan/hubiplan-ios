import CryptoKit
import Foundation
import HubiplanKern
import LocalAuthentication
import Security

/// Geräteschlüsselpaar in der Secure Enclave (Gesamtaudit 15.11., APP-03), wie Android im
/// Keystore: Der private Teil verlässt den Chip nie und lässt sich nicht exportieren; im
/// Schlüsselbund liegt nur der verschlüsselte Verweis (`dataRepresentation`), nutzbar nur auf
/// diesem Gerät. Ohne Secure Enclave (Simulator) bleibt es beim Software-Schlüssel.
/// Nur auf macOS/iOS prüfbar.
struct EnclaveDeviceKeys: DeviceKeyStore {
    static let prefix = "se1:"

    var hardwareAvailable: Bool { SecureEnclave.isAvailable }

    func create() throws -> (signer: DeviceKeySigner, stored: String) {
        guard SecureEnclave.isAvailable else { return try SoftwareDeviceKeys().create() }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            // Wie der übrige Schlüsselbund (Speicher.swift): Auch bei gesperrtem Gerät nach dem
            // ersten Entsperren nutzbar, etwa wenn ein Wecksignal das Erneuern auslöst.
            // Nur auf einem Gerät prüfbar.
            kCFAllocatorDefault, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error
        ) else {
            return try SoftwareDeviceKeys().create()
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        return (EnclaveSigner(key: key), Self.prefix + key.dataRepresentation.base64EncodedString())
    }

    func load(_ stored: String) -> DeviceKeySigner? {
        guard stored.hasPrefix(Self.prefix) else { return SoftwareDeviceKeys().load(stored) }
        guard let data = Data(base64Encoded: String(stored.dropFirst(Self.prefix.count))),
              let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        else { return nil }
        return EnclaveSigner(key: key)
    }
}

struct EnclaveSigner: DeviceKeySigner {
    let key: SecureEnclave.P256.Signing.PrivateKey
    var publicKey: String { Base64Url.encode(key.publicKey.x963Representation) }
    var inHardware: Bool { true }
    func sign(_ message: Data) throws -> String {
        Base64Url.encode(try key.signature(for: message).derRepresentation)
    }
}
