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
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return HttpResponse(status: http.statusCode, body: data, headers: headers)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Die verbundenen Konten (ohne Geheimnisse; die liegen je Konto im Schlüsselbund).
enum Konten {
    private static let key = "konten"
    /// Ablage aus der Zeit mit nur einem Konto
    private static let oldKey = "konto"

    static func load() -> AccountList {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: key), let list = try? JSONDecoder().decode(AccountList.self, from: data) {
            return list
        }
        if let data = defaults.data(forKey: oldKey), let list = AccountList.migrate(single: data) {
            save(list)
            defaults.removeObject(forKey: oldKey)
            return list
        }
        return AccountList()
    }

    static func save(_ list: AccountList) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Schlüsselbund eines Kontos; das Konto aus der Zeit vor mehreren Konten behält seinen Platz.
    static func secrets(_ id: String) -> KeychainStore {
        KeychainStore(service: id.isEmpty ? "de.hubiplan.app.konto" : "de.hubiplan.app.konto.\(id)")
    }
}

/// Ordner eines Kontos für verschlüsselte Buchungsentwürfe: im App-Speicher, ohne Sicherung,
/// nur bei entsperrtem iPhone lesbar. Den Inhalt verschlüsselt `DraftBox` zusätzlich selbst.
final class EntwurfsOrdner: DraftFiles, @unchecked Sendable {
    private let dir: URL

    init(account: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let safe = account.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        dir = base.appendingPathComponent("entwuerfe", isDirectory: true)
            .appendingPathComponent(safe.isEmpty ? "konto" : "konto-\(safe)", isDirectory: true)
    }

    func names() -> [String] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        var dated: [(name: String, date: Date)] = []
        for file in files {
            let date: Date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            dated.append((name: file.lastPathComponent, date: date))
        }
        dated.sort { (a: (name: String, date: Date), b: (name: String, date: Date)) -> Bool in
            if a.date == b.date { return a.name < b.name }
            return a.date < b.date
        }
        return dated.map { $0.name }
    }

    func read(_ name: String) -> Data? {
        try? Data(contentsOf: dir.appendingPathComponent(name))
    }

    func write(_ name: String, _ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var folder = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}
