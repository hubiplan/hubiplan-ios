import Foundation

/// Ein Termin, so wie er in den Gerätekalender geschrieben wird.
public struct CalendarEntry: Equatable, Sendable {
    public var key: String
    public var eventId: Int
    public var title: String
    public var start: Date
    /// Bei ganztägigen Terminen der letzte Tag (0 Uhr Ortszeit), sonst das Ende
    public var end: Date
    public var allDay: Bool
    public var location: String
    public var notes: String
    public var cancelled: Bool
    public var reminderMinutes: Int?

    /// Kurzform aller Werte: nur geänderte Termine werden neu geschrieben.
    public var fingerprint: String {
        let parts: [String] = [
            title, String(Int(start.timeIntervalSince1970)), String(Int(end.timeIntervalSince1970)), allDay ? "1" : "0",
            location, notes, cancelled ? "1" : "0", reminderMinutes.map(String.init) ?? "",
        ]
        // FNV-1a, 64 Bit: bleibt über App-Starts gleich (anders als `hashValue`)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in parts.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

extension Occurrence {
    /// Termin aus HUBIplan als Kalendereintrag; `nil`, wenn die Zeiten nicht lesbar sind.
    /// Ganztägig: HUBIplan liefert als Ende den letzten Tag; der Eintrag reicht vom ersten
    /// bis zum letzten Tag in der Zeitzone des Geräts.
    public func calendarEntry(unitTitle: String, reminderMinutes: Int?, timeZone: TimeZone = .current) -> CalendarEntry? {
        guard let start, let end else { return nil }
        var from = start
        var to = max(end, start)
        if allDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            from = calendar.startOfDay(for: start)
            to = max(calendar.startOfDay(for: end), from)
        }
        var prefix = ""
        if isCancelled {
            prefix = tr("Abgesagt: ")
        } else if myResponse == "yes" {
            prefix = "✓ "
        } else if myResponse == "no" {
            prefix = "✗ "
        }
        var lines: [String] = []
        if !owner.isEmpty { lines.append(owner) }
        if !note.isEmpty { lines.append(note) }
        if rsvpEnabled {
            switch myResponse {
            case "yes": lines.append(tr("Du hast zugesagt."))
            case "no": lines.append(tr("Du hast abgesagt."))
            default: lines.append(tr("Rückmeldung offen – Zu- oder Absage in der HUBIplan-App."))
            }
        }
        lines.append(tr("Aus HUBIplan ({unit})", ["unit": unitTitle]))
        return CalendarEntry(
            key: key,
            eventId: eventId,
            title: prefix + title,
            start: from,
            end: to,
            allDay: allDay,
            location: [location, address].filter { !$0.isEmpty }.joined(separator: ", "),
            notes: lines.joined(separator: "\n"),
            cancelled: isCancelled,
            // Abgesagte Termine und eigene Absagen ohne Erinnerung
            reminderMinutes: isCancelled || myResponse == "no" ? nil : reminderMinutes
        )
    }
}

/// Abgleich: was neu, geändert oder weg ist (vorhanden = Schlüssel → Fingerabdruck).
public struct SyncPlan: Equatable, Sendable {
    public var insert: [CalendarEntry]
    public var update: [CalendarEntry]
    public var delete: [String]

    public init(wanted: [CalendarEntry], existing: [String: String]) {
        let keys = Set(wanted.map(\.key))
        insert = wanted.filter { existing[$0.key] == nil }
        update = wanted.filter { entry in existing[entry.key].map { $0 != entry.fingerprint } ?? false }
        delete = existing.keys.filter { !keys.contains($0) }.sorted()
    }
}

/// Woran die App ihre Kalender und Einträge im Gerätekalender wiedererkennt.
public enum CalendarMark {
    /// Kennung des Kalenders einer Einheit auf einer Instanz.
    public static func name(server: String, accessId: Int) -> String { prefix(server: server) + String(accessId) }

    /// Anfang der Kennungen aller Kalender einer Instanz.
    public static func prefix(server: String) -> String {
        "hubiplan:" + (server.hasPrefix("https://") ? String(server.dropFirst(8)) : server) + ":"
    }

    /// Adresse am Kalendereintrag: führt zurück in die App und trägt Schlüssel und Fingerabdruck.
    public static func url(key: String, fingerprint: String) -> String {
        var parts = URLComponents()
        parts.scheme = "hubiplan"
        parts.host = "termin"
        parts.queryItems = [URLQueryItem(name: "k", value: key), URLQueryItem(name: "f", value: fingerprint)]
        return parts.string ?? "hubiplan://termin"
    }

    /// Schlüssel und Fingerabdruck aus der Adresse eines Eintrags; `nil` bei fremden Einträgen.
    public static func parse(_ url: String) -> (key: String, fingerprint: String)? {
        guard let parts = URLComponents(string: url), parts.scheme == "hubiplan", parts.host == "termin",
              let key = parts.queryItems?.first(where: { $0.name == "k" })?.value, !key.isEmpty
        else { return nil }
        return (key, parts.queryItems?.first(where: { $0.name == "f" })?.value ?? "")
    }

    /// Ist das ein Link auf einen Termin (und keiner zum Verbinden)?
    public static func isEventLink(_ url: String) -> Bool {
        guard let parts = URLComponents(string: url) else { return false }
        return parts.scheme == "hubiplan" && parts.host == "termin"
    }
}

/// Auswahl „Erinnerung“ in den Einstellungen (Minuten vor dem Termin; `nil` = keine).
public enum Erinnerung {
    public static let choices: [Int?] = [nil, 120, 24 * 60, 2 * 24 * 60, 7 * 24 * 60]

    public static func label(_ minutes: Int?) -> String {
        switch minutes {
        case nil: return tr("keine")
        case 120: return tr("2 Stunden vorher")
        case 24 * 60: return tr("1 Tag vorher")
        case 2 * 24 * 60: return tr("2 Tage vorher")
        case 7 * 24 * 60: return tr("1 Woche vorher")
        case let other?: return tr("{minutes} Minuten vorher", ["minutes": String(other)])
        }
    }
}
