import Foundation

// Ohne Netz lesen (UX-Audit 16.11., IOS-24, wie Android AND-07) und ungelesene Mitteilungen
// (IOS-22, wie Android AND-15). Abgelegt werden nur Termine und Mitteilungen des Mitglieds,
// verschlüsselt mit einem Schlüssel aus dem Schlüsselbund des Kontos; beim Abmelden wird alles
// gelöscht. Verwaltungsdaten kommen hier nie hinein.

/// Letzter geladener Stand eines Zugangs.
public struct OfflineSnapshot: Sendable {
    public var events: [Occurrence]
    public var circulars: [CircularItem]
    public var savedAt: Date
}

/// Welche Mitteilungen auf diesem Gerät neu sind.
public enum Gelesen {
    /// Höchstens so viele Nummern merken; ältere Mitteilungen fallen ohnehin aus der Liste.
    public static let max = 500

    /// Ungelesene Nummern aus `ids` und die danach zu merkende Menge. Beim ersten Mal
    /// (`known == nil`) gilt alles Vorhandene als gelesen, damit nach dem Verbinden nicht die
    /// ganze Liste „neu“ ist.
    public static func unread(known: Set<Int>?, ids: [Int]) -> (unread: Set<Int>, remember: Set<Int>) {
        guard let known else { return ([], Set(ids)) }
        return (Set(ids.filter { !known.contains($0) }), known)
    }

    /// Die neuesten Nummern behalten.
    public static func trimmed(_ ids: Set<Int>) -> [Int] {
        Array(ids.sorted(by: >).prefix(max))
    }
}

/// Ablage für den Offline-Stand und die gelesenen Mitteilungen eines Kontos.
public struct OfflineBox: Sendable {
    static let keyName = "offlineschluessel"
    let files: DraftFiles
    let secrets: SecretStore

    public init(files: DraftFiles, secrets: SecretStore) {
        self.files = files
        self.secrets = secrets
    }

    private struct Stored: Decodable {
        var saved: String
        var events: EventList
        var circulars: [CircularItem]
    }

    func key(create: Bool) -> SymmetricKey? {
        if let stored = secrets.read(OfflineBox.keyName), let data = Base64Url.decode(stored), data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let fresh = SymmetricKey(size: .bits256)
        let text = fresh.withUnsafeBytes { Base64Url.encode(Data($0)) }
        secrets.write(OfflineBox.keyName, text)
        return secrets.read(OfflineBox.keyName) == text ? fresh : nil
    }

    private func seal(_ plain: Data, _ name: String) {
        guard let key = key(create: true), let sealed = try? AES.GCM.seal(plain, using: key).combined else { return }
        _ = files.write(name, sealed)
    }

    private func unseal(_ name: String) -> Data? {
        guard let key = key(create: false), let sealed = files.read(name),
              let box = try? AES.GCM.SealedBox(combined: sealed)
        else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    /// Antworten des Servers unverändert ablegen (`eventsJson` ist die Terminliste mit `items`).
    public func save(accessId: Int, eventsJson: Data, circularsJson: Data, at date: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var plain = Data("{\"saved\":\"\(formatter.string(from: date))\",\"events\":".utf8)
        plain.append(eventsJson)
        plain.append(Data(",\"circulars\":".utf8))
        plain.append(circularsJson)
        plain.append(Data("}".utf8))
        // Nur ablegen, was sich wieder lesen lässt
        guard (try? JSONDecoder().decode(Stored.self, from: plain)) != nil else { return }
        seal(plain, "stand-\(accessId).bin")
    }

    public func load(accessId: Int) -> OfflineSnapshot? {
        guard let plain = unseal("stand-\(accessId).bin"),
              let stored = try? JSONDecoder().decode(Stored.self, from: plain),
              let saved = Zeit.parse(stored.saved)
        else { return nil }
        return OfflineSnapshot(events: stored.events.items, circulars: stored.circulars, savedAt: saved)
    }

    /// Zuletzt gespeicherter Stand irgendeines Zugangs (Kaltstart ohne Netz, Zugang noch unbekannt).
    public func latest() -> (id: Int, snapshot: OfflineSnapshot)? {
        let candidates = files.names().reversed().compactMap { name -> Int? in
            guard name.hasPrefix("stand-"), name.hasSuffix(".bin") else { return nil }
            return Int(name.dropFirst(6).dropLast(4))
        }
        var best: (id: Int, snapshot: OfflineSnapshot)?
        for id in candidates {
            guard let snapshot = load(accessId: id) else { continue }
            if best == nil || snapshot.savedAt > best!.snapshot.savedAt { best = (id, snapshot) }
        }
        return best
    }

    /// Gelesene Mitteilungen; nil, solange für diesen Zugang noch nichts gemerkt ist.
    public func read(accessId: Int) -> Set<Int>? {
        guard let plain = unseal("gelesen-\(accessId).bin"),
              let ids = try? JSONDecoder().decode([Int].self, from: plain)
        else { return nil }
        return Set(ids)
    }

    public func remember(accessId: Int, read ids: Set<Int>) {
        guard let plain = try? JSONEncoder().encode(Gelesen.trimmed(ids)) else { return }
        seal(plain, "gelesen-\(accessId).bin")
    }

    /// Ungelesene Mitteilungen aus `ids`; beim ersten Mal wird alles als gelesen gemerkt.
    public func unread(accessId: Int, ids: [Int]) -> Set<Int> {
        let known = read(accessId: accessId)
        let result = Gelesen.unread(known: known, ids: ids)
        if known == nil { remember(accessId: accessId, read: result.remember) }
        return result.unread
    }

    public func markRead(accessId: Int, id: Int) {
        let known = read(accessId: accessId) ?? []
        if !known.contains(id) { remember(accessId: accessId, read: known.union([id])) }
    }

    /// Alles dieses Kontos löschen (beim Abmelden).
    public func clear() {
        for name in files.names() { files.delete(name) }
        secrets.write(OfflineBox.keyName, nil)
    }
}

extension Api {
    /// Termine wie `events`, dazu die unveränderte Antwort für den Offline-Stand.
    public func eventsWithJson(accessId: Int, from: String, to: String) async throws -> ([Occurrence], Data) {
        let response = try await checked("GET", "/api/portal/\(accessId)/events/?from=\(from)&to=\(to)")
        guard let list = try? JSONDecoder().decode(EventList.self, from: response.body) else {
            throw ApiError(status: response.status, code: "format")
        }
        return (list.items, response.body)
    }

    /// Mitteilungen wie `circulars`, dazu die unveränderte Antwort für den Offline-Stand.
    public func circularsWithJson(accessId: Int) async throws -> ([CircularItem], Data) {
        let response = try await checked("GET", "/api/portal/\(accessId)/circulars/")
        guard let items = try? JSONDecoder().decode([CircularItem].self, from: response.body) else {
            throw ApiError(status: response.status, code: "format")
        }
        return (items, response.body)
    }

    /// Anhang einer Mitteilung zum Ansehen in der App (IOS-22, wie Android AND-15).
    public func circularAttachment(accessId: Int, circularId: Int, attachmentId: Int) async throws -> Data {
        try await file("/api/portal/\(accessId)/circulars/\(circularId)/attachments/\(attachmentId)/")
    }
}
