import EventKit
import Foundation
import HubiplanKern

/// Einstellungen zum Gerätekalender (gelten für alle Konten der App).
enum KalenderEinstellung {
    private static let onKey = "kalender_an"
    private static let reminderKey = "erinnerung_minuten"
    /// Vorgabe wie in der Android-App: einen Tag vorher
    static let defaultReminder = 24 * 60

    static var on: Bool {
        get { UserDefaults.standard.bool(forKey: onKey) }
        set { UserDefaults.standard.set(newValue, forKey: onKey) }
    }

    /// Minuten vor dem Termin; `nil` = keine Erinnerung (abgelegt als -1).
    static var reminder: Int? {
        get {
            guard let value = UserDefaults.standard.object(forKey: reminderKey) as? Int else { return defaultReminder }
            return value >= 0 ? value : nil
        }
        set { UserDefaults.standard.set(newValue ?? -1, forKey: reminderKey) }
    }
}

/// Das Gerät hat keinen Ort, an dem sich ein Kalender anlegen lässt.
struct KalenderFehler: Error {}

/// Kalender der App im Kalender des Geräts: je Einheit ein eigener Kalender. Einträge erkennt
/// die App an ihrer Adresse (`hubiplan://termin…`) wieder; andere Einträge fasst sie nicht an.
@MainActor
final class Geraetekalender {
    static let shared = Geraetekalender()

    private let store = EKEventStore()
    /// Kennung der Einheit (siehe `CalendarMark.name`) → Kennung des Kalenders im Gerät
    private static let idsKey = "kalender_kennungen"

    private var ids: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.idsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.idsKey) }
    }

    static var allowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Um Zugriff bitten (das System fragt nur beim ersten Mal).
    func request() async -> Bool {
        if Self.allowed { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    private func ensure(name: String, title: String) throws -> EKCalendar {
        let shown = "HUBIplan: " + title
        if let id = ids[name], let found = store.calendar(withIdentifier: id) {
            if found.title != shown {
                found.title = shown
                try store.saveCalendar(found, commit: true)
            }
            return found
        }
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
        else { throw KalenderFehler() }
        let new = EKCalendar(for: .event, eventStore: store)
        new.title = shown
        new.source = source
        try store.saveCalendar(new, commit: true)
        ids[name] = new.calendarIdentifier
        return new
    }

    /// Termine einer Einheit abgleichen: Neues anlegen, Geändertes ändern, Entfallenes löschen.
    func sync(name: String, title: String, wanted: [CalendarEntry]) throws {
        guard Self.allowed else { return }
        let calendar = try ensure(name: name, title: title)
        let now = Date()
        let from = now.addingTimeInterval(-366 * 86400)
        let to = now.addingTimeInterval(3 * 366 * 86400)
        var existing: [String: EKEvent] = [:]
        var prints: [String: String] = [:]
        for event in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [calendar])) {
            guard let mark = CalendarMark.parse(event.url?.absoluteString ?? "") else { continue }
            if existing[mark.key] != nil {
                // Doppelter Eintrag (z. B. nach einem abgebrochenen Abgleich)
                try store.remove(event, span: .thisEvent, commit: false)
                continue
            }
            existing[mark.key] = event
            prints[mark.key] = mark.fingerprint
        }
        let plan = SyncPlan(wanted: wanted, existing: prints)
        for entry in plan.insert {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            fill(event, entry)
            try store.save(event, span: .thisEvent, commit: false)
        }
        for entry in plan.update {
            guard let event = existing[entry.key] else { continue }
            fill(event, entry)
            try store.save(event, span: .thisEvent, commit: false)
        }
        for key in plan.delete {
            guard let event = existing[key] else { continue }
            try store.remove(event, span: .thisEvent, commit: false)
        }
        try store.commit()
    }

    private func fill(_ event: EKEvent, _ entry: CalendarEntry) {
        event.title = entry.title
        event.isAllDay = entry.allDay
        event.startDate = entry.start
        event.endDate = entry.end
        event.location = entry.location.isEmpty ? nil : entry.location
        event.notes = entry.notes
        event.url = URL(string: CalendarMark.url(key: entry.key, fingerprint: entry.fingerprint))
        event.availability = .busy
        event.alarms = entry.reminderMinutes.map { [EKAlarm(relativeOffset: TimeInterval(-60 * $0))] }
    }

    /// Kalender entfernen, die nicht mehr gebraucht werden: alle mit dem Anfang `prefix`
    /// (eine Instanz) außer `keep`; ohne `prefix` die Kalender aller Konten.
    func remove(prefix: String? = nil, keep: Set<String> = []) {
        guard Self.allowed else { return }
        var left = ids
        for (name, id) in ids where !keep.contains(name) && (prefix.map { name.hasPrefix($0) } ?? true) {
            if let calendar = store.calendar(withIdentifier: id) {
                try? store.removeCalendar(calendar, commit: true)
            }
            left[name] = nil
        }
        ids = left
    }
}
