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

        public init(server: String, email: String, since: Date) {
            self.server = server
            self.email = email
            self.since = since
        }
    }

    /// Kennung der Quarantäne für Instanz und Konto (Ordner- und Schlüsselbundname).
    public static func id(server: String, email: String) -> String {
        let text = server.lowercased() + "\n" + email.lowercased()
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    /// Entwürfe aus `box` (abgemeldetes Konto) in die Quarantäne `target` legen, verschlüsselt
    /// mit deren eigenem Schlüssel. Gibt die Zahl der verschobenen Dateien zurück.
    ///
    /// `konto.json` wird zuerst geschrieben: Endet die App mitten im Verschieben, liegt nie eine
    /// Quarantäne ohne Eigentümer da. Liegt für dasselbe Konto schon eine, bleibt deren älteres
    /// `since`, damit ältere Vorgänge nicht über `finalDays` hinaus verlängert werden.
    @discardableResult
    public static func retire(_ box: DraftBox, into target: DraftBox, owner: Owner) -> Int {
        let files = target.files
        var owner = owner
        if let earlier = self.owner(files) {
            if same(earlier, owner) { owner.since = min(owner.since, earlier.since) }
        } else if !entries(target.files).isEmpty, let changed = files.lastChange() {
            // Schon Vorgänge ohne lesbaren Eigentümer da: deren Alter nicht zurücksetzen
            owner.since = min(owner.since, changed)
        }
        if let data = try? JSONEncoder().encode(owner) { _ = files.write(ownerName, data) }
        let moved = box.move(to: target)
        if moved == 0 && entries(target.files).isEmpty { files.delete(ownerName) }
        return moved
    }

    private static func same(_ a: Owner, _ b: Owner) -> Bool {
        a.server.lowercased() == b.server.lowercased() && a.email.lowercased() == b.email.lowercased()
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

    /// Seit wann die Quarantäne besteht: aus `konto.json`, sonst (fehlt oder unlesbar, z. B.
    /// nach einem Absturz) die letzte Änderung des Ordners, wie Android (`since`). nil: unbekannt,
    /// dann gilt sie nie als alt und wird nicht gelöscht.
    private static func since(_ files: DraftFiles) -> Date? {
        owner(files)?.since ?? files.lastChange()
    }

    private static func older(_ files: DraftFiles, than days: Int, now: Date) -> Bool {
        guard let since = since(files) else { return false }
        return now.timeIntervalSince(since) > Double(days) * day
    }

    /// Vorgänge in Quarantänen, die älter als `staleDays` sind (für die Rückfrage).
    public static func staleCount(_ boxes: [DraftBox], now: Date = Date()) -> Int {
        boxes.filter { older($0.files, than: staleDays, now: now) }.map { entries($0.files).count }.reduce(0, +)
    }

    /// Wann die ältesten Vorgänge der Rückfrage endgültig gelöscht werden (nil: keine alten).
    public static func finalDeletion(_ boxes: [DraftBox], now: Date = Date()) -> Date? {
        boxes.filter { older($0.files, than: staleDays, now: now) }
            .compactMap { since($0.files) }
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

    /// Abgelaufen (älter als `finalDays`)? Ohne lesbares `konto.json` zählt die letzte Änderung
    /// des Ordners; eine Quarantäne ohne Eigentümer wird also nie sofort gelöscht.
    public static func expired(_ files: DraftFiles, now: Date = Date()) -> Bool {
        older(files, than: finalDays, now: now)
    }

    /// Wie `expired(_:now:)` für die Quarantäne `box` (die App sieht deren Ablage nicht).
    public static func expired(_ box: DraftBox, now: Date = Date()) -> Bool {
        expired(box.files, now: now)
    }

    // MARK: Exportdatei

    /// Ordner für die Exportdatei im temporären Verzeichnis (wie Android `cacheDir/export`).
    public static func exportFolder(in temporary: URL) -> URL {
        temporary.appendingPathComponent("export", isDirectory: true)
    }

    /// Ort der Exportdatei; der Ordner wird bei Bedarf angelegt.
    public static func exportURL(in temporary: URL, fileManager: FileManager = .default) -> URL {
        let folder = exportFolder(in: temporary)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(exportName)
    }

    static let exportName = "hubiplan-belege.json"

    /// Entschlüsselte Exportdateien löschen: wenn das Teilen geschlossen wird und beim nächsten
    /// Start (wie Android `sweep`). Auch die Datei früherer Fassungen direkt im temporären
    /// Verzeichnis. Die Vorgänge in der Quarantäne bleiben.
    public static func clearExports(in temporary: URL, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: exportFolder(in: temporary))
        try? fileManager.removeItem(at: temporary.appendingPathComponent(exportName))
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
