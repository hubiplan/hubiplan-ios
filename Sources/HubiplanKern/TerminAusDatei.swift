import Foundation

/// Ein Termin aus einer geteilten Kalenderdatei (.ics), etwa aus Outlook, Thunderbird oder dem
/// Kalender (hubiplan konzepte/termine-aus-dem-mailprogramm.md, W4). Die App füllt damit nur
/// „Neuer Termin“ vor; angelegt wird erst nach dem Prüfen. Wie `IcsLeser` der Android-App.
public struct IcsTermin: Equatable, Sendable {
    public var title: String
    /// Tag als `JJJJ-MM-TT` in der Zeitzone des Telefons
    public var day: String
    /// Beginn und Ende als `HH:MM`; ganztägig: leer. Ende leer, wenn unbekannt oder an einem anderen Tag.
    public var start: String
    public var end: String
    public var allDay: Bool
    public var location: String
    public var description: String
    public var videoUrl: String
    /// Serien legt die App nicht an: Hinweis zeigen, nur der erste Termin wird übernommen.
    public var repeats: Bool

    /// Der Tag als Datum (Mittag in `timeZone`, damit Datumsauswahlen nicht verrutschen).
    public func dayDate(timeZone: TimeZone = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Vorlage für „Neuer Termin“.
    public var draft: EventDraft {
        var d = EventDraft()
        d.title = title
        d.day = day
        d.start = start.isEmpty ? d.start : start
        d.end = end
        d.allDay = allDay
        d.location = location
        d.description = description
        d.videoUrl = videoUrl
        return d
    }
}

public enum IcsLeser {
    /// Größer ist keine einzelne Einladung.
    public static let maxBytes = 1_000_000

    private static let videoPattern =
        "https://[^\\s<>\"'\\\\]*?(?:/call/[A-Za-z0-9]+|/meet/[^\\s<>\"'\\\\]+|teams\\.microsoft\\.com/"
        + "[^\\s<>\"'\\\\]+|teams\\.live\\.com/[^\\s<>\"'\\\\]+|zoom\\.us/[jw]/[^\\s<>\"'\\\\]+|meet\\.jit\\.si/"
        + "[^\\s<>\"'\\\\]+|meet\\.google\\.com/[^\\s<>\"'\\\\]+|/b/[a-z0-9-]{3,}|/rooms/[^\\s<>\"'\\\\]+/join)"

    /// Windows-Zeitzonen aus Outlook, die in Vereinen vorkommen.
    private static let windowsZones = [
        "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest",
        "Romance Standard Time": "Europe/Paris",
        "Central European Standard Time": "Europe/Warsaw",
        "GMT Standard Time": "Europe/London",
        "UTC": "UTC",
    ]

    private struct Zeile {
        let name: String
        let params: [String: String]
        let value: String
    }

    /// Den ersten Termin der Datei lesen; nil, wenn sie keinen brauchbaren Termin enthält
    /// (auch bei einer Absage, METHOD:CANCEL).
    public static func lesen(_ text: String, timeZone: TimeZone = .current) -> IcsTermin? {
        let lines = entfalten(text)
        if lines.contains(where: { $0.name == "METHOD" && $0.value.uppercased() == "CANCEL" }) { return nil }
        guard let begin = lines.firstIndex(where: { $0.name == "BEGIN" && $0.value.uppercased() == "VEVENT" }) else { return nil }
        var event: [Zeile] = []
        var depth = 0
        for line in lines[(begin + 1)...] {
            if line.name == "BEGIN" { depth += 1 }
            if line.name == "END" {
                if depth == 0 { break }
                depth -= 1
                continue
            }
            if depth == 0 { event.append(line) }
        }
        func first(_ name: String) -> Zeile? { event.first { $0.name == name } }
        if first("STATUS")?.value.uppercased() == "CANCELLED" { return nil }
        guard let startLine = first("DTSTART") else { return nil }
        let allDay = startLine.params["VALUE"]?.uppercased() == "DATE" || startLine.value.trimmingCharacters(in: .whitespaces).count == 8
        guard let from = zeit(startLine, timeZone) else { return nil }
        var to = first("DTEND").flatMap { zeit($0, timeZone) }
        if to == nil, let duration = first("DURATION").flatMap({ dauer($0.value) }) {
            to = from.addingTimeInterval(duration)
        }
        let title = wert(first("SUMMARY")?.value)
        guard !title.isEmpty else { return nil }
        let location = wert(first("LOCATION")?.value)
        let description = wert(first("DESCRIPTION")?.value)
        let conference = event.filter { $0.name == "CONFERENCE" }
            .map { $0.value.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("https://") && $0.count <= 500 }
        let video = conference ?? videoLink(location) ?? videoLink(description) ?? ""

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = Self.format(from, "yyyy-MM-dd", timeZone)
        var end = ""
        if !allDay, let to, to > from, calendar.isDate(to, inSameDayAs: from) {
            end = Self.format(to, "HH:mm", timeZone)
        }
        return IcsTermin(
            title: String(title.prefix(200)),
            day: day,
            start: allDay ? "" : Self.format(from, "HH:mm", timeZone),
            end: end,
            allDay: allDay,
            location: String(location.prefix(200)),
            description: description,
            videoUrl: video,
            repeats: event.contains { $0.name == "RRULE" || $0.name == "RDATE" }
        )
    }

    /// Videolink (Nextcloud Talk, Jitsi, Teams, Zoom, Meet, BigBlueButton) im Text.
    public static func videoLink(_ text: String) -> String? {
        guard let range = text.range(of: videoPattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var link = String(text[range])
        while let last = link.last, ".,;)".contains(last) { link.removeLast() }
        return link.count <= 500 ? link : nil
    }

    private static func entfalten(_ text: String) -> [Zeile] {
        let raw = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var joined: [String] = []
        for line in raw {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !joined.isEmpty {
                joined[joined.count - 1] += String(line.dropFirst())
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                joined.append(line)
            }
        }
        return joined.compactMap(zeile)
    }

    /// „NAME;PARAM=WERT;…:Wert“; Doppelpunkte in Anführungszeichen gehören zum Parameter.
    private static func zeile(_ line: String) -> Zeile? {
        var quoted = false
        var colon: String.Index?
        for index in line.indices {
            let c = line[index]
            if c == "\"" { quoted.toggle() }
            if c == ":", !quoted { colon = index; break }
        }
        guard let colon, colon > line.startIndex else { return nil }
        let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        var params: [String: String] = [:]
        for p in head.dropFirst() {
            guard let eq = p.firstIndex(of: "="), eq > p.startIndex else { continue }
            params[p[..<eq].uppercased()] = p[p.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Zeile(name: head[0].uppercased(), params: params, value: String(line[line.index(after: colon)...]))
    }

    private static func wert(_ value: String?) -> String {
        guard let value else { return "" }
        var out = ""
        var escaped = false
        for c in value {
            if escaped {
                out.append(c == "n" || c == "N" ? "\n" : c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parser(_ pattern: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = pattern
        return f
    }

    private static func format(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        parser(pattern, zone).string(from: date)
    }

    /// Zeitpunkt; ganztägig: 0:00 des Tags in der Zone des Telefons.
    private static func zeit(_ line: Zeile, _ zone: TimeZone) -> Date? {
        let v = line.value.trimmingCharacters(in: .whitespaces)
        if v.count == 8 { return parser("yyyyMMdd", zone).date(from: v) }
        if v.uppercased().hasSuffix("Z") {
            return parser("yyyyMMdd'T'HHmmss", TimeZone(identifier: "UTC")!).date(from: String(v.dropLast()))
        }
        let source = line.params["TZID"].flatMap(zoneOf) ?? zone
        return parser("yyyyMMdd'T'HHmmss", source).date(from: v)
    }

    private static func zoneOf(_ tzid: String) -> TimeZone? {
        var name = tzid.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("/") { name.removeFirst() }
        if let mapped = windowsZones[name] { return TimeZone(identifier: mapped) }
        if let zone = TimeZone(identifier: name) { return zone }
        // Manche Programme schreiben „/freeassociation.sourceforge.net/Europe/Berlin“
        if let range = name.range(of: "[A-Za-z]+/[A-Za-z_]+$", options: .regularExpression) {
            return TimeZone(identifier: String(name[range]))
        }
        return nil
    }

    /// RFC-5545-Dauer wie „PT1H30M“ oder „P1D“ in Sekunden.
    private static func dauer(_ value: String) -> TimeInterval? {
        let v = value.trimmingCharacters(in: .whitespaces).uppercased()
        guard v.hasPrefix("P") || v.hasPrefix("+P") else { return nil }
        var seconds = 0.0
        var number = ""
        var inTime = false
        for c in v.drop(while: { $0 == "+" }).dropFirst() {
            if c.isNumber { number.append(c); continue }
            if c == "T" { inTime = true; continue }
            guard let n = Double(number) else { return nil }
            number = ""
            switch (c, inTime) {
            case ("W", false): seconds += n * 604_800
            case ("D", false): seconds += n * 86_400
            case ("H", true): seconds += n * 3_600
            case ("M", true): seconds += n * 60
            case ("S", true): seconds += n
            default: return nil
            }
        }
        return number.isEmpty ? seconds : nil
    }
}
