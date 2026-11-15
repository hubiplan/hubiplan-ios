import Foundation

/// Vorgabe der Leitung: nächstes Stück für alle Geräte derselben Mappe (wie Android, Noten N6).
public struct LiveCue: Decodable, Equatable, Sendable {
    public var seq: Int64
    public var arrangement: Int
    public var number: String
    public var title: String
    public var sender: String

    enum CodingKeys: String, CodingKey { case seq, arrangement, number, title, sender }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int64.self, forKey: .seq)
        arrangement = try c.decode(Int.self, forKey: .arrangement)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        sender = try c.decodeIfPresent(String.self, forKey: .sender) ?? ""
    }

    /// „Dirigent: Nr. 27 · Alte Kameraden“
    public var headline: String {
        let piece = [number.isEmpty ? "" : tr("Nr. {number}", ["number": number]), title].filter { !$0.isEmpty }.joined(separator: " · ")
        return tr("{sender}: {piece}", ["sender": sender.isEmpty ? tr("Leitung") : sender, "piece": piece])
    }
}

public struct LiveState: Decodable, Equatable, Sendable {
    public var cue: LiveCue?
    public var canSend: Bool
    public var pollSeconds: Int

    enum CodingKeys: String, CodingKey {
        case cue
        case canSend = "can_send"
        case pollSeconds = "poll_seconds"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cue = try c.decodeIfPresent(LiveCue.self, forKey: .cue)
        canSend = try c.decodeIfPresent(Bool.self, forKey: .canSend) ?? false
        pollSeconds = try c.decodeIfPresent(Int.self, forKey: .pollSeconds) ?? 2
    }

    /// Pause bis zur nächsten Nachfrage, 2 bis 30 Sekunden.
    public var pause: Int { min(30, max(2, pollSeconds)) }
}

struct LiveSent: Decodable {
    var cue: LiveCue?
}

public enum NotenLive {
    /// Nur die bekannten Ziele in den Pfad lassen.
    public static func targetOk(_ target: String) -> Bool {
        let parts = target.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, ["folder", "performance", "rehearsal"].contains(String(parts[0])) else { return false }
        return (1...12).contains(parts[1].count) && parts[1].allSatisfy { ("0"..."9").contains($0) }
    }

    /// Ist das eine neue Vorgabe? Beim Öffnen (`lastSeq` nil) gilt eine alte nicht, eigene auch nicht.
    public static func isNew(_ cue: LiveCue?, lastSeq: Int64?, ownSeq: Int64) -> Bool {
        guard let cue, let lastSeq else { return false }
        return cue.seq > lastSeq && cue.seq != ownSeq
    }

    /// Wo liegt das vorgegebene Stück? Erst in der offenen Mappe, dann in den anderen.
    /// Liefert Mappe und Stelle in `playable`, sonst nil.
    public static func place(of arrangement: Int, current: Mappe, all: [Mappe]) -> (mappe: Mappe, piece: Int)? {
        if let here = current.playable.firstIndex(where: { $0.arrangement == arrangement }) { return (current, here) }
        for other in all where other.key != current.key {
            if let index = other.playable.firstIndex(where: { $0.arrangement == arrangement }) { return (other, index) }
        }
        return nil
    }
}

extension Api {
    /// Live-Vorgabe der Leitung für eine Mappe oder einen Termin (`target` z. B. "folder-3").
    public func live(accessId: Int, target: String) async throws -> LiveState {
        guard NotenLive.targetOk(target) else { throw ApiError(status: 0, code: "format") }
        return try await expect("GET", "/api/portal/\(accessId)/music/live/\(target)/")
    }

    /// Stück an alle senden; die Antwort ist die eigene Vorgabe.
    public func sendLive(accessId: Int, target: String, arrangement: Int, number: String) async throws -> LiveCue? {
        guard NotenLive.targetOk(target) else { throw ApiError(status: 0, code: "format") }
        let sent: LiveSent = try await expect("POST", "/api/portal/\(accessId)/music/live/\(target)/",
                                              json: ["arrangement": arrangement, "number": number])
        return sent.cue
    }
}
