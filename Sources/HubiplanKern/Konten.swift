import Foundation

/// Ein verbundenes Konto (ohne Geheimnisse; die liegen im sicheren Speicher unter `id`).
public struct AccountEntry: Codable, Equatable, Identifiable, Sendable {
    /// Kennung für Schlüsselbund und Ablage; leer beim Konto aus der Zeit vor mehreren Konten
    public var id: String
    public var server: String
    public var display: String
    public var email: String

    public init(id: String, server: String, display: String, email: String) {
        self.id = id
        self.server = server
        self.display = display
        self.email = email
    }

    enum CodingKeys: String, CodingKey { case id, server, display, email }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        server = try c.decode(String.self, forKey: .server)
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
    }

    /// Adresse ohne `https://` für die Anzeige.
    public var host: String { server.hasPrefix("https://") ? String(server.dropFirst(8)) : server }

    /// Dasselbe Konto auf derselben Instanz (E-Mail ohne Groß-/Kleinschreibung).
    public func same(server: String, email: String) -> Bool {
        self.server == server && self.email.lowercased() == email.lowercased()
    }
}

/// Die Konten der App und welches gerade gezeigt wird.
public struct AccountList: Codable, Equatable, Sendable {
    public static let limit = 8

    public private(set) var accounts: [AccountEntry]
    public private(set) var activeId: String?

    public init(accounts: [AccountEntry] = [], activeId: String? = nil) {
        self.accounts = accounts
        self.activeId = accounts.contains { $0.id == activeId } ? activeId : accounts.first?.id
    }

    enum CodingKeys: String, CodingKey { case accounts, activeId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            accounts: try c.decodeIfPresent([AccountEntry].self, forKey: .accounts) ?? [],
            activeId: try c.decodeIfPresent(String.self, forKey: .activeId)
        )
    }

    public var active: AccountEntry? { accounts.first { $0.id == activeId } }
    public var full: Bool { accounts.count >= Self.limit }

    /// Kennung, die noch kein Konto trägt.
    public func freeId(_ make: () -> String = { UUID().uuidString.lowercased() }) -> String {
        var id = make()
        while id.isEmpty || accounts.contains(where: { $0.id == id }) { id = UUID().uuidString.lowercased() }
        return id
    }

    /// Neues Konto aufnehmen und zeigen. Gibt ein Konto zurück, das dadurch ersetzt wurde
    /// (dieselbe Instanz und E-Mail noch einmal verbunden); dessen Geheimnisse sind zu löschen.
    @discardableResult
    public mutating func add(_ entry: AccountEntry) -> AccountEntry? {
        let replaced = accounts.first { $0.id != entry.id && $0.same(server: entry.server, email: entry.email) }
        accounts.removeAll { $0.id == entry.id || $0.id == replaced?.id }
        accounts.append(entry)
        activeId = entry.id
        return replaced
    }

    /// Anderes Konto zeigen; `false`, wenn es das Konto nicht gibt.
    @discardableResult
    public mutating func select(_ id: String) -> Bool {
        guard accounts.contains(where: { $0.id == id }) else { return false }
        activeId = id
        return true
    }

    /// Konto entfernen; war es das gezeigte, kommt das erste verbliebene nach vorn.
    public mutating func remove(_ id: String) {
        accounts.removeAll { $0.id == id }
        if activeId == id { activeId = accounts.first?.id }
    }

    /// Name und E-Mail nach einer Antwort der Instanz auffrischen.
    public mutating func update(_ id: String, display: String, email: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[index].display = display
        accounts[index].email = email
    }

    /// Bezeichnung in der Kontenliste: Name, bei gleichem Namen mit Adresse der Instanz.
    public func label(_ entry: AccountEntry) -> String {
        let name = entry.display.isEmpty ? entry.email : entry.display
        return accounts.filter { ($0.display.isEmpty ? $0.email : $0.display) == name }.count > 1
            ? "\(name) (\(entry.host))" : name
    }

    /// Übernahme aus der Zeit mit nur einem Konto (`{"server":…,"display":…,"email":…}`).
    public static func migrate(single data: Data) -> AccountList? {
        guard let old = try? JSONDecoder().decode(AccountEntry.self, from: data) else { return nil }
        return AccountList(accounts: [old], activeId: old.id)
    }
}
