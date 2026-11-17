import Foundation

/// Quarantäne für Buchungs- und Quittungsentwürfe (Gesamtaudit 15.11., APP-04), wie Android
/// (`LocalAccountData.retire`/`adopt`): Meldet der Server das Gerät ab (z. B. Passwort im
/// Browser geändert), werden unversandte Entwürfe nicht gelöscht, sondern verschlüsselt
/// beiseitegelegt. Gebunden an Instanz und Konto (E-Mail): Verbindet sich dasselbe Konto auf
/// derselben Instanz wieder, kommen sie zurück; ein anderes Konto bekommt nichts. Nach
/// `finalDays` werden sie gelöscht.
public enum DraftQuarantine {
    /// Wie Android `STALE_DAYS`: danach fragt die App, ob die Vorgänge gelöscht werden dürfen,
    /// und bietet einen Export an (Fachfrage FQ24)
    public static let staleDays = 90
    /// Wie Android `FINAL_DAYS`: spätestens dann löscht die App auch ohne Zustimmung
    public static let finalDays = 120
    static let ownerName = "konto.json"

    public struct Owner: Codable, Equatable, Sendable {
        public var server: String
        public var email: String
        public var since: Date
    }

    /// Kennung der Quarantäne für Instanz und Konto (Ordner- und Schlüsselbundname).
    public static func id(server: String, email: String) -> String {
        let text = server.lowercased() + "\n" + email.lowercased()
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// Entwürfe aus `box` (abgemeldetes Konto) in die Quarantäne `target` legen, verschlüsselt
    /// mit deren eigenem Schlüssel. Gibt die Zahl der verschobenen Dateien zurück.
    @discardableResult
    public static func retire(_ box: DraftBox, into target: DraftBox, owner: Owner, files: DraftFiles) -> Int {
        let moved = box.move(to: target)
        if moved > 0 || !target.files.names().filter({ $0 != ownerName }).isEmpty {
            if let data = try? JSONEncoder().encode(owner) { _ = files.write(ownerName, data) }
        }
        return moved
    }

    /// Wem gehört die Quarantäne `files`?
    public static func owner(_ files: DraftFiles) -> Owner? {
        guard let data = files.read(ownerName) else { return nil }
        return try? JSONDecoder().decode(Owner.self, from: data)
    }

    /// Nach erneutem Verbinden: Entwürfe zurückholen, wenn Instanz und Konto passen.
    @discardableResult
    public static func adopt(_ quarantine: DraftBox, into box: DraftBox, server: String, email: String) -> Int {
        guard let who = owner(quarantine.files), !who.email.isEmpty,
              who.server.lowercased() == server.lowercased(), who.email.lowercased() == email.lowercased()
        else { return 0 }
        let moved = quarantine.move(to: box)
        if quarantine.files.names().allSatisfy({ $0 == ownerName }) { quarantine.clear() }
        return moved
    }

    private static let day: Double = 24 * 3600

    private static func entries(_ files: DraftFiles) -> [String] {
        files.names().filter { $0 != ownerName && !$0.hasSuffix(".tmp") }
    }

    private static func older(_ files: DraftFiles, than days: Int, now: Date) -> Bool {
        guard let who = owner(files) else { return true }
        return now.timeIntervalSince(who.since) > Double(days) * day
    }

    /// Vorgänge in Quarantänen, die älter als `staleDays` sind (für die Rückfrage).
    public static func staleCount(_ boxes: [DraftBox], now: Date = Date()) -> Int {
        boxes.filter { older($0.files, than: staleDays, now: now) }.map { entries($0.files).count }.reduce(0, +)
    }

    /// Wann die ältesten Vorgänge der Rückfrage endgültig gelöscht werden (nil: keine alten).
    public static func finalDeletion(_ boxes: [DraftBox], now: Date = Date()) -> Date? {
        boxes.filter { older($0.files, than: staleDays, now: now) }
            .compactMap { owner($0.files)?.since }
            .min()
            .map { $0.addingTimeInterval(Double(finalDays) * day) }
    }

    /// Alte Vorgänge (älter als `staleDays`) entschlüsselt als JSON, um sie vor dem Löschen zu
    /// teilen oder zu sichern (Fachfrage FQ24); Aufbau wie Android `exportStale`. nil, wenn sich
    /// nichts öffnen ließ. Zweites Ergebnis: Zahl der Vorgänge.
    public static func exportStale(_ boxes: [DraftBox], now: Date = Date()) -> (Data, Int)? {
        var items: [[String: Any]] = []
        for box in boxes where older(box.files, than: staleDays, now: now) {
            let who = owner(box.files)
            guard let key = box.key(create: false) else { continue }
            for name in entries(box.files) {
                guard let sealed = box.files.read(name), let sealedBox = try? AES.GCM.SealedBox(combined: sealed),
                      let plain = try? AES.GCM.open(sealedBox, using: key)
                else { continue }
                let content: Any = (try? JSONSerialization.jsonObject(with: plain)) ?? String(decoding: plain, as: UTF8.self)
                items.append([
                    "art": name.hasSuffix(DraftBox.receiptEnding) ? "quittungen" : "entwuerfe",
                    "server": who?.server ?? "",
                    "konto": who?.email ?? "",
                    "inhalt": content,
                ])
            }
        }
        guard !items.isEmpty else { return nil }
        let doc: [String: Any] = [
            "hinweis": tr("Nicht gesendete Vorgänge aus HUBIplan. Enthält Namen und Beträge; nach der Übergabe an den Verein bitte löschen."),
            "exportiert": ISO8601DateFormatter().string(from: now),
            "vorgaenge": items,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return (data, items.count)
    }

    /// Abgelaufen (älter als `finalDays`)?
    public static func expired(_ files: DraftFiles, now: Date = Date()) -> Bool {
        guard let who = owner(files) else { return true }
        return now.timeIntervalSince(who.since) > Double(finalDays) * 24 * 3600
    }
}

extension DraftBox {
    /// Alle Entwürfe und Quittungen in `target` umschlüsseln; erst nach erfolgreichem Schreiben
    /// wird die Quelle gelöscht. Unlesbare Dateien bleiben liegen.
    func move(to target: DraftBox) -> Int {
        guard let source = key(create: false) else { return 0 }
        var moved = 0
        for name in files.names() where name.hasSuffix(DraftBox.ending) || name.hasSuffix(DraftBox.receiptEnding) {
            guard let sealed = files.read(name), let box = try? AES.GCM.SealedBox(combined: sealed),
                  let plain = try? AES.GCM.open(box, using: source),
                  let key = target.key(create: true),
                  let again = try? AES.GCM.seal(plain, using: key).combined,
                  target.files.write(name, again)
            else { continue }
            files.delete(name)
            moved += 1
        }
        return moved
    }
}
