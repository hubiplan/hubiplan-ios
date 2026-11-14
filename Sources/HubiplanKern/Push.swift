import Foundation

/// Push über Apple: Die Instanz verschlüsselt (Web-Push, RFC 8291) und schickt an das
/// Push-Gateway des Herausgebers, das an Apple weiterreicht. Apple und das Gateway sehen nur
/// ein Wecksignal; entschlüsselt wird auf dem Gerät.
public enum ApplePush {
    public static let kind = "apns"
    /// Schlüssel im sicheren Speicher: Web-Push-Schlüssel des Geräts
    public static let keysKey = "pushKeys"

    /// Kennung der Instanz am Gateway: die ersten 16 Hex-Zeichen von SHA-256 über den rohen
    /// VAPID-Schlüssel. Nur Nachrichten dieser Instanz erreichen das Gerät.
    public static func keyId(vapidPublicKey: String) -> String? {
        guard let raw = Base64Url.decode(vapidPublicKey), raw.count == 65, raw.first == 0x04 else { return nil }
        return String(Data(SHA256.hash(data: raw)).hex.prefix(16))
    }

    /// Geräte-Token von Apple als Hex-Text.
    public static func tokenText(_ token: Data) -> String { token.hex }

    /// Der Weg `apns`, wenn die Instanz ihn anbietet.
    public static func way(_ instance: Instance) -> PushWay? {
        instance.push.first { $0.kind == kind && !$0.gateway.isEmpty && !$0.vapidPublicKey.isEmpty }
    }

    /// Endpunkt `<Gateway>/apns/<Geräte-Token>/<Kennung>`; nil, wenn Angaben nicht passen.
    public static func endpoint(way: PushWay, deviceToken: String) -> String? {
        guard way.kind == kind, let gateway = normalizeServer(way.gateway),
              let id = keyId(vapidPublicKey: way.vapidPublicKey),
              deviceToken.utf8.count >= 64, deviceToken.utf8.count <= 200,
              deviceToken.allSatisfy({ $0.isASCII && $0.isHexDigit && !$0.isUppercase })
        else { return nil }
        return "\(gateway)/apns/\(deviceToken)/\(id)"
    }

    /// Inhalt einer Apple-Nachricht entschlüsseln: Feld `b` (base64) ist der Web-Push.
    public static func open(b: String, keys: PushKeys) -> PushMessage? {
        guard let body = Data(base64Encoded: b), let plain = try? WebPushCrypto.decrypt(body, keys: keys) else {
            return nil
        }
        return try? JSONDecoder().decode(PushMessage.self, from: plain)
    }
}

extension Api {
    /// Push-Endpunkt dieses Geräts melden.
    public func setPush(kind: String, endpoint: String, keys: PushKeys) async throws {
        let _: Ignored = try await expect("PUT", "/api/app/v1/devices/current/push/", json: [
            "kind": kind, "endpoint": endpoint, "p256dh": keys.p256dh, "auth": keys.authB64,
        ])
    }

    /// Push abmelden (dann nur Abruf).
    public func clearPush() async throws {
        let _: Ignored = try await expect("DELETE", "/api/app/v1/devices/current/push/")
    }
}

extension DeviceSession {
    /// Web-Push-Schlüssel dieses Geräts; beim ersten Mal erzeugt.
    public func pushKeys() -> PushKeys {
        if let text = secret(ApplePush.keysKey), let keys = PushKeys.parse(text) { return keys }
        let keys = PushKeys.generate()
        setSecret(ApplePush.keysKey, keys.serialize())
        return keys
    }

    /// Geräte-Token von Apple bei der Instanz anmelden. `false`: Die Instanz bietet keinen
    /// Apple-Push an (dann bleibt es beim Abruf).
    public func registerPush(deviceToken: String) async throws -> Bool {
        let client = api()
        guard let way = ApplePush.way(try await client.instance()),
              let endpoint = ApplePush.endpoint(way: way, deviceToken: deviceToken)
        else { return false }
        try await client.setPush(kind: ApplePush.kind, endpoint: endpoint, keys: pushKeys())
        return true
    }
}
