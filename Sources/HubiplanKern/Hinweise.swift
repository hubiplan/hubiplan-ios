import Foundation

/// Hinweis „Rückmeldung fehlt“ wie in der Android-App: etwa einen Tag (30 Stunden) vor dem
/// Anmeldeschluss, wenn noch keine Zu- oder Absage da ist. Auf dem iPhone plant die App ihn
/// beim Abgleich als Mitteilung auf dem Gerät vor; der Server erfährt davon nichts.
public struct RsvpHint: Equatable, Sendable {
    /// Kennung der Mitteilung: Konto, Zugang und Termin
    public var id: String
    public var fireAt: Date
    public var accessId: Int
    public var eventId: Int
    public var title: String
    public var startsAt: String
    public var endsAt: String
    public var allDay: Bool
}

public enum RueckmeldeHinweis {
    /// So lange vor dem Anmeldeschluss kommt der Hinweis.
    public static let lead: TimeInterval = 30 * 60 * 60
    /// Höchstens so viele vorgeplante Hinweise je Konto (iOS erlaubt 64 insgesamt).
    public static let limit = 20
    /// Gemeinsamer Anfang aller Kennungen eines Kontos.
    public static func prefix(account: String) -> String { "rsvp-\(account.isEmpty ? "-" : account)-" }

    /// Hinweise für die Termine eines Zugangs, nach Zeitpunkt sortiert. Schon fällige kommen
    /// sofort (in fünf Sekunden), abgelaufene Fristen gar nicht.
    public static func plan(_ events: [Occurrence], accessId: Int, account: String, now: Date = Date()) -> [RsvpHint] {
        var hints: [RsvpHint] = []
        for event in events where event.responseMissing {
            guard let deadline = event.rsvpDeadline.flatMap(Zeit.parse), deadline > now else { continue }
            let fire = max(now.addingTimeInterval(5), deadline.addingTimeInterval(-lead))
            hints.append(RsvpHint(
                id: prefix(account: account) + "\(accessId)-\(event.key)",
                fireAt: fire, accessId: accessId, eventId: event.eventId, title: event.title,
                startsAt: event.startsAt, endsAt: event.endsAt, allDay: event.allDay
            ))
        }
        return Array(hints.sorted { $0.fireAt < $1.fireAt }.prefix(limit))
    }
}
