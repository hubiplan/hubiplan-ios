import Foundation

/// Anhang eines Rundschreibens.
public struct CircularFile: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var size: Int

    enum CodingKeys: String, CodingKey { case id, name, size }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0
    }
}

/// Mitteilung des Vereins (Rundschreiben).
public struct CircularItem: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var subject: String
    public var sender: String
    public var kindLabel: String
    public var sentAt: String?
    public var body: String?
    public var attachments: [CircularFile]
    /// Versandweg: app, mail, letter, portal
    public var channel: String

    enum CodingKeys: String, CodingKey {
        case id, subject, sender, body, attachments, channel
        case kindLabel = "kind_label"
        case sentAt = "sent_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        subject = try c.decode(String.self, forKey: .subject)
        sender = try c.decodeIfPresent(String.self, forKey: .sender) ?? ""
        kindLabel = try c.decodeIfPresent(String.self, forKey: .kindLabel) ?? ""
        sentAt = try c.decodeIfPresent(String.self, forKey: .sentAt)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        attachments = try c.decodeIfPresent([CircularFile].self, forKey: .attachments) ?? []
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
    }

    public var sent: Date? { sentAt.flatMap(Zeit.parse) }
}

/// Absatz oder Liste im Text einer Mitteilung: `kind` ist "p", "ul" oder "ol".
public struct CircularBlock: Equatable, Sendable {
    public var kind: String
    public var lines: [String]
}

/// Stück einer Zeile mit Auszeichnung.
public struct CircularSpan: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    /// Nur https, http und mailto
    public var link: String?
}

/// Text der Mitteilungen: derselbe begrenzte Umfang wie im Web und in der Android-App
/// (Absätze, Listen, **fett**, *kursiv*, [Text](Adresse)); HTML bleibt lesbarer Text.
public enum CircularText {
    private static let bullet = try! NSRegularExpression(pattern: #"^\s*[-•]\s+(.*)$"#)
    private static let number = try! NSRegularExpression(pattern: #"^\s*\d+[.)]\s+(.*)$"#)
    private static let token = try! NSRegularExpression(
        pattern: #"\[([^\]\n]+)\]\(((?:https?://|mailto:)[^)\s]+)\)|\*\*(.+?)\*\*|\*(?!\s)(.+?)\*"#
    )

    private static func capture(_ regex: NSRegularExpression, _ line: String) -> String? {
        guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }

    public static func blocks(_ text: String) -> [CircularBlock] {
        var result: [CircularBlock] = []
        var open = false
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            while let last = line.last, last.isWhitespace { line.removeLast() }
            if line.isEmpty {
                open = false
                continue
            }
            let item = capture(bullet, line)
            let ordered = item == nil ? capture(number, line) : nil
            let kind = item != nil ? "ul" : ordered != nil ? "ol" : "p"
            let content = item ?? ordered ?? line
            if open, result.last?.kind == kind {
                result[result.count - 1].lines.append(content)
            } else {
                result.append(CircularBlock(kind: kind, lines: [content]))
            }
            open = true
        }
        return result
    }

    public static func inline(_ text: String) -> [CircularSpan] {
        var out: [CircularSpan] = []
        add(text, bold: false, italic: false, depth: 0, into: &out)
        return out
    }

    private static func add(_ source: String, bold: Bool, italic: Bool, depth: Int, into out: inout [CircularSpan]) {
        func plain(_ s: Substring) {
            if !s.isEmpty { out.append(CircularSpan(text: String(s), bold: bold, italic: italic)) }
        }
        if depth > 8 {
            plain(source[...])
            return
        }
        var end = source.startIndex
        for match in token.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let whole = Range(match.range, in: source) else { continue }
            plain(source[end..<whole.lowerBound])
            func group(_ n: Int) -> String? { Range(match.range(at: n), in: source).map { String(source[$0]) } }
            if let label = group(1), let target = group(2) {
                out.append(CircularSpan(text: label, bold: bold, italic: italic, link: target))
            } else if let strong = group(3) {
                add(strong, bold: true, italic: italic, depth: depth + 1, into: &out)
            } else if let soft = group(4) {
                add(soft, bold: bold, italic: true, depth: depth + 1, into: &out)
            }
            end = whole.upperBound
        }
        plain(source[end...])
    }

    /// Adresse der Mitteilung im Mitgliederbereich (für Anhänge); ohne Sitzungsdaten.
    public static func webUrl(server: String, access: Int, circular: Int) -> String? {
        guard access > 0, circular > 0, let origin = normalizeServer(server) else { return nil }
        return "\(origin)/mein-bereich/rundschreiben?zugang=\(access)&schreiben=\(circular)"
    }
}

extension Api {
    /// Mitteilungen des Zugangs, neueste zuerst.
    public func circulars(accessId: Int) async throws -> [CircularItem] {
        try await expect("GET", "/api/portal/\(accessId)/circulars/")
    }
}
