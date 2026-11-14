import Foundation

/// Fehler der Schnittstelle. `status` 0: keine Antwort (kein Netz, Zeitüberschreitung).
public struct ApiError: Error, Equatable {
    public let status: Int
    public let code: String
    public let message: String

    public init(status: Int, code: String = "", message: String = "") {
        self.status = status
        self.code = code
        self.message = message
    }

    /// `401 device_not_authenticated`: Gerät neu verbinden.
    public var mustReconnect: Bool { status == 401 && code == "device_not_authenticated" }
}

public struct HttpRequest: Equatable, Sendable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: Data?
}

public struct HttpResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Der Weg ins Netz. Die App nimmt URLSession (ohne Weiterleitungen, ohne Cookies),
/// die Tests einen Nachbau.
public protocol Transport: Sendable {
    func send(_ request: HttpRequest) async throws -> HttpResponse
}

/// Wo der Geräteschlüssel `hpd_…` liegt (App: Schlüsselbund) und wie er erneuert wird.
public protocol TokenStore: Sendable {
    func token() async -> String?
    /// Erneuert den Schlüssel `used` (H7); nil, wenn es gerade nicht geht.
    /// Mehrere gleichzeitige Aufrufe mit demselben alten Schlüssel erneuern nur einmal.
    func renew(used: String) async -> String?
}

/// Schnittstelle zu genau einer HUBIplan-Instanz. Die App spricht nur mit der Instanz des
/// Mitglieds, nie mit einem fremden Dienst.
public struct Api: Sendable {
    public static let platform = "ios"
    /// Höchste Größe einer JSON-Antwort.
    public static let maxJsonBytes = 4 * 1024 * 1024
    static let keyPaths: Set<String> = ["/api/app/v1/devices/current/renew/", "/api/app/v1/devices/current/key/"]

    public let server: String
    let transport: Transport
    let tokens: TokenStore?
    let language: String

    /// `server`: Ergebnis von `normalizeServer` (nur `https://Host[:Port]`).
    public init(server: String, transport: Transport, tokens: TokenStore? = nil, language: String = "de") {
        self.server = server
        self.transport = transport
        self.tokens = tokens
        self.language = language
    }

    // MARK: Anfragen

    static func errorFields(_ body: Data) -> (code: String, message: String) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return ("", "") }
        let code = object["code"] as? String ?? ""
        let message = object["detail"] as? String ?? ""
        return (code, message)
    }

    func raw(_ method: String, _ path: String, json: [String: Any]? = nil, retry: Bool = true) async throws -> HttpResponse {
        guard let url = serverLink(server: server, path: path) else {
            throw ApiError(status: 0, code: "address")
        }
        var headers = ["Accept": "application/json", "Accept-Language": language]
        let used = await tokens?.token()
        if let used { headers["Authorization"] = "Bearer " + used }
        var body: Data?
        if let json {
            body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            headers["Content-Type"] = "application/json"
        }
        let response: HttpResponse
        do {
            response = try await transport.send(HttpRequest(method: method, url: url, headers: headers, body: body))
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError(status: 0, code: "offline")
        }
        if response.body.count > Api.maxJsonBytes { throw ApiError(status: 0, code: "too_large") }
        // Erneuern und Nachmelden selbst nie erneut erneuern (das wäre eine Schleife).
        // Ohne Erneuerung nie 401 nach oben geben (das hieße „Gerät abgemeldet“).
        if response.status == 401, Api.errorFields(response.body).code == "device_renew",
           let used, let tokens, !Api.keyPaths.contains(path) {
            guard retry, await tokens.renew(used: used) != nil else {
                throw ApiError(status: 0, code: "renew_failed")
            }
            return try await raw(method, path, json: json, retry: false)
        }
        return response
    }

    func expect<T: Decodable>(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> T {
        let response = try await raw(method, path, json: json)
        guard (200...299).contains(response.status) else {
            let fields = Api.errorFields(response.body)
            throw ApiError(status: response.status, code: fields.code, message: fields.message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw ApiError(status: response.status, code: "format")
        }
    }

    // MARK: Endpunkte

    public func instance() async throws -> Instance {
        try await expect("GET", "/api/app/v1/instance/")
    }

    /// Verbinden mit dem Code aus dem QR-Code oder mit einem Anmeldelink.
    public func pair(
        code: String = "", loginLink: String = "", deviceName: String, appVersion: String, deviceKey: String = ""
    ) async throws -> Paired {
        try await expect("POST", "/api/app/v1/pair/", json: [
            "code": code,
            "login_link": loginLink,
            "name": deviceName,
            "platform": Api.platform,
            "app_version": appVersion,
            "device_key": deviceKey,
        ])
    }

    public func me() async throws -> Me {
        try await expect("GET", "/api/app/v1/me/")
    }

    /// Geräteschlüssel erneuern (H7): Aufgabe holen, unterschreiben, neuen Schlüssel bekommen.
    public func renew(deviceId: Int, key: P256.Signing.PrivateKey) async throws -> Renewed {
        let path = "/api/app/v1/devices/current/renew/"
        let challenge: RenewChallenge = try await expect("POST", path)
        let message = SignedFormat.renewMessage(deviceId: deviceId, challenge: challenge.challenge)
        return try await expect("POST", path, json: [
            "challenge": challenge.challenge,
            "signature": try SignedFormat.sign(message, with: key),
        ])
    }
}
