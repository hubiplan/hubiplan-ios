import Foundation

/// Anmeldung mit E-Mail und Passwort in der App (UX-Audit 16.11., IOS-06), wie in der
/// Android-App: allauth (Client „app“) liefert eine kurze Sitzung, mit der die App einmal ein
/// Gerät anlegt. Passwort und Sitzung behält die App nicht.
public enum LoginStep: Equatable, Sendable {
    /// Angemeldet: mit dieser Sitzung das Gerät anlegen
    case done(sessionToken: String)
    /// Zweiter Faktor nötig: Code aus der Authenticator-App oder Wiederherstellungscode
    case needsCode(sessionToken: String)
}

/// Welche Pflichtangaben beim Anmelden fehlen (in dieser Reihenfolge bekommt das erste Feld den Fokus).
public enum LoginField: Equatable, Sendable {
    case server, email, password
}

public enum Anmeldung {
    /// Höchstlänge des Codes (TOTP 6 Ziffern, Wiederherstellungscodes länger)
    public static let maxCode = 64

    public static func missing(server: String, email: String, password: String) -> [LoginField] {
        var out: [LoginField] = []
        if normalizeServer(server) == nil { out.append(.server) }
        if email.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.email) }
        if password.isEmpty { out.append(.password) }
        return out
    }

    /// Seite „Passwort vergessen“ der Instanz
    public static func passwordReset(server: String) -> URL? {
        normalizeServer(server).flatMap { serverLink(server: $0, path: "/passwort-vergessen") }.flatMap(URL.init(string:))
    }

    /// Antwort von allauth auswerten (wie `parseAuthStep` in der Android-App).
    public static func step(status: Int, body: Data, previous: String?) throws -> LoginStep {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw ApiError(status: status == 200 ? 0 : status, code: status == 200 ? "format" : "", message: "")
        }
        let session = ((root["meta"] as? [String: Any])?["session_token"] as? String) ?? previous
        let flows = ((root["data"] as? [String: Any])?["flows"] as? [[String: Any]]) ?? []
        let pendingCode = flows.contains { ($0["id"] as? String) == "mfa_authenticate" && ($0["is_pending"] as? Bool) == true }
        if status == 200, let session { return .done(sessionToken: session) }
        if status == 401, pendingCode, let session { return .needsCode(sessionToken: session) }
        let message = ((root["errors"] as? [[String: Any]])?.first?["message"] as? String)
            ?? tr("Anmeldung fehlgeschlagen. Bitte E-Mail und Passwort prüfen.")
        throw ApiError(status: status == 401 ? 400 : status, code: "login", message: message)
    }
}

extension Api {
    /// Anmeldung mit Passwort über allauth (Client „app“).
    public func login(email: String, password: String) async throws -> LoginStep {
        let response = try await raw("POST", "/_allauth/app/v1/auth/login", json: [
            "email": email.trimmingCharacters(in: .whitespaces), "password": password,
        ])
        return try Anmeldung.step(status: response.status, body: response.body, previous: nil)
    }

    /// Zweiter Faktor zur Sitzung aus `login`.
    public func secondFactor(sessionToken: String, code: String) async throws -> LoginStep {
        let clean = String(code.filter { !$0.isWhitespace }.prefix(Anmeldung.maxCode))
        let response = try await raw(
            "POST", "/_allauth/app/v1/auth/2fa/authenticate", json: ["code": clean],
            extra: ["X-Session-Token": sessionToken]
        )
        return try Anmeldung.step(status: response.status, body: response.body, previous: sessionToken)
    }

    /// Gerät nach der Anmeldung mit Passwort anlegen.
    public func createDevice(sessionToken: String, deviceName: String, appVersion: String, deviceKey: String) async throws -> Paired {
        let response = try await checked("POST", "/api/app/v1/devices/", json: [
            "name": deviceName,
            "platform": Api.platform,
            "app_version": appVersion,
            "device_key": deviceKey,
        ], extra: ["X-Session-Token": sessionToken])
        do {
            return try JSONDecoder().decode(Paired.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }
}

extension DeviceSession {
    /// Mit E-Mail und Passwort anmelden. Ist ein zweiter Faktor nötig, kommt `.needsCode` zurück
    /// und die App fragt den Code ab (`connect(sessionToken:code:…)`).
    public func login(email: String, password: String, appVersion: String) async throws -> LoginStep {
        let plain = Api(server: server, transport: transport, language: Texte.language)
        try await plain.instance().check(build: Int(appVersion.trimmingCharacters(in: .whitespaces)))
        return try await plain.login(email: email, password: password)
    }

    /// Gerät mit der Sitzung aus der Anmeldung anlegen; `code`: zweiter Faktor, falls verlangt.
    public func connect(sessionToken: String, code: String? = nil, deviceName: String, appVersion: String) async throws -> Paired {
        let plain = Api(server: server, transport: transport, language: Texte.language)
        var session = sessionToken
        if let code {
            switch try await plain.secondFactor(sessionToken: sessionToken, code: code) {
            case .done(let token): session = token
            case .needsCode:
                throw ApiError(status: 400, code: "login", message: tr("Der Code stimmt nicht. Bitte erneut versuchen."))
            }
        }
        let (signer, stored) = try keys.create()
        let paired = try await plain.createDevice(
            sessionToken: session, deviceName: deviceName, appVersion: appVersion, deviceKey: signer.publicKey
        )
        store.write(Self.deviceKeyKey, stored)
        store.write(Self.deviceIdKey, String(paired.device.id))
        store.write(Self.tokenKey, paired.token)
        return paired
    }
}
