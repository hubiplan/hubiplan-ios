import Foundation
import HubiplanKern
import Security

/// Geheimnisse eines Kontos im Schlüsselbund: nur auf diesem Gerät, nicht in Sicherungen
/// auf andere Geräte, lesbar nach dem ersten Entsperren (für Abgleich im Hintergrund).
struct KeychainStore: SecretStore {
    let service: String

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: String, _ value: String?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let value else { return }
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Netz der App: nur HTTPS zur Instanz, ohne Cookies, ohne Zwischenspeicher und ohne
/// Weiterleitungen (eine Weiterleitung könnte den Geräteschlüssel an eine fremde Adresse tragen).
final class UrlSessionTransport: NSObject, Transport, URLSessionTaskDelegate, @unchecked Sendable {
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url), url.scheme == "https" else {
            throw ApiError(status: 0, code: "address")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ApiError(status: 0, code: "offline") }
        return HttpResponse(status: http.statusCode, body: data)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Das verbundene Konto (ohne Geheimnisse; die liegen im Schlüsselbund).
struct Account: Codable, Equatable {
    var server: String
    var display: String
    var email: String

    private static let key = "konto"

    static func load() -> Account? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func save(_ account: Account?) {
        if let account, let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
