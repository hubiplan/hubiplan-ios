import Foundation

public struct PushDecryptError: Error, Equatable {
    public let message: String
}

/// Schlüssel dieses Geräts für Web-Push (RFC 8291): P-256-Schlüsselpaar und 16 Byte „auth“.
/// Der öffentliche Teil und auth gehen an HUBIplan, der private bleibt auf dem Gerät
/// (im Schlüsselbund, in der gemeinsamen Gruppe von App und Mitteilungserweiterung).
public struct PushKeys: Sendable {
    public let privateKey: P256.KeyAgreement.PrivateKey
    public let auth: Data

    public init(privateKey: P256.KeyAgreement.PrivateKey, auth: Data) {
        self.privateKey = privateKey
        self.auth = auth
    }

    /// 0x04 ‖ x ‖ y, 65 Byte.
    public var publicBytes: Data { privateKey.publicKey.x963Representation }
    public var p256dh: String { Base64Url.encode(publicBytes) }
    public var authB64: String { Base64Url.encode(auth) }

    public static func generate() -> PushKeys {
        var generator = SystemRandomNumberGenerator()
        let auth = Data((0..<16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        return PushKeys(privateKey: P256.KeyAgreement.PrivateKey(), auth: auth)
    }

    /// Zum Speichern: privater Schlüssel (32 Byte, roh) und auth, je base64url.
    public func serialize() -> String {
        Base64Url.encode(privateKey.rawRepresentation) + "." + authB64
    }

    public static func parse(_ text: String) -> PushKeys? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let raw = Base64Url.decode(String(parts[0])),
              let auth = Base64Url.decode(String(parts[1])), auth.count == 16,
              let key = try? P256.KeyAgreement.PrivateKey(rawRepresentation: raw)
        else { return nil }
        return PushKeys(privateKey: key, auth: auth)
    }
}

/// Entschlüsseln nach RFC 8291 (Inhaltskodierung aes128gcm, RFC 8188), ein Datensatz.
public enum WebPushCrypto {
    /// Höchste Größe einer Push-Nachricht (RFC 8030 verlangt mindestens 4096 Byte).
    public static let maxBody = 8192

    /// Jeder Fehler (auch ungültige Punkte, Längen oder Schlüssel) endet als `PushDecryptError`.
    public static func decrypt(_ body: Data, keys: PushKeys) throws -> Data {
        do {
            return try decryptChecked(Data(body), keys: keys)
        } catch let error as PushDecryptError {
            throw error
        } catch {
            throw PushDecryptError(message: "Ungültige Nachricht")
        }
    }

    private static func hmac(_ key: Data, _ data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    private static func decryptChecked(_ body: Data, keys: PushKeys) throws -> Data {
        if body.count < 21 + 65 + 17 { throw PushDecryptError(message: "Nachricht zu kurz") }
        if body.count > maxBody { throw PushDecryptError(message: "Nachricht zu groß") }
        let bytes = [UInt8](body)
        let salt = Data(bytes[0..<16])
        let recordSize = bytes[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let idLength = Int(bytes[20])
        if idLength != 65 || recordSize < 18 { throw PushDecryptError(message: "Unbekanntes Format") }
        let senderRaw = Data(bytes[21..<(21 + 65)])
        let ciphertext = Data(bytes[(21 + 65)...])
        if UInt32(ciphertext.count) > recordSize {
            throw PushDecryptError(message: "Mehrere Datensätze werden nicht unterstützt")
        }
        if senderRaw.first != 0x04 { throw PushDecryptError(message: "Ungültiger Schlüssel") }

        let sender = try P256.KeyAgreement.PublicKey(x963Representation: senderRaw)
        let shared = try keys.privateKey.sharedSecretFromKeyAgreement(with: sender)
            .withUnsafeBytes { Data($0) }

        let prkKey = hmac(keys.auth, shared)
        let ikm = hmac(prkKey, Data("WebPush: info\u{0}".utf8) + keys.publicBytes + senderRaw + Data([1]))
        let prk = hmac(salt, ikm)
        let cek = hmac(prk, Data("Content-Encoding: aes128gcm\u{0}".utf8) + Data([1])).prefix(16)
        let nonce = hmac(prk, Data("Content-Encoding: nonce\u{0}".utf8) + Data([1])).prefix(12)

        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext.dropLast(16),
                tag: ciphertext.suffix(16)
            )
            plain = try AES.GCM.open(box, using: SymmetricKey(data: cek))
        } catch {
            throw PushDecryptError(message: "Entschlüsseln fehlgeschlagen")
        }
        // Auffüllung entfernen: Ende ist das letzte Byte ungleich 0, es muss 2 sein (letzter Datensatz)
        let out = [UInt8](plain)
        var end = out.count - 1
        while end >= 0 && out[end] == 0 { end -= 1 }
        if end < 0 || out[end] != 2 { throw PushDecryptError(message: "Ungültige Auffüllung") }
        return Data(out[0..<end])
    }
}

/// Inhalt einer Push-Nachricht von HUBIplan (nach dem Entschlüsseln).
public struct PushMessage: Decodable, Equatable, Sendable {
    public var v: Int
    public var type: String
    public var access: Int?
    public var id: Int?
    public var kind: String
    public var title: String
    public var text: String
    public var from: String
    public var todo: Int?
    public var org: Int?
    public var department: Int?
    /// Termin: Rundschreiben dazu (bei "circular") bzw. Einladung/Erinnerung (bei "event")
    public var event: Int?
    public var rsvp: Bool
    public var maybe: Bool

    enum CodingKeys: String, CodingKey {
        case v, type = "t", access, id, kind, title, text, from, todo, org, department, event, rsvp, maybe
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = try c.decodeIfPresent(Int.self, forKey: .v) ?? 1
        type = try c.decode(String.self, forKey: .type)
        access = try c.decodeIfPresent(Int.self, forKey: .access)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        todo = try c.decodeIfPresent(Int.self, forKey: .todo)
        org = try c.decodeIfPresent(Int.self, forKey: .org)
        department = try c.decodeIfPresent(Int.self, forKey: .department)
        event = try c.decodeIfPresent(Int.self, forKey: .event)
        rsvp = try c.decodeIfPresent(Bool.self, forKey: .rsvp) ?? false
        maybe = try c.decodeIfPresent(Bool.self, forKey: .maybe) ?? false
    }

    public static func parse(_ text: String) -> PushMessage? {
        try? JSONDecoder().decode(PushMessage.self, from: Data(text.utf8))
    }
}
