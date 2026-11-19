import HubiplanKern
import UserNotifications

/// Mitteilungen auf dem Gerät: „Rückmeldung fehlt“ mit Zusage und Absage (wie Android).
/// Die App plant sie beim Abgleich vor; Push-Mitteilungen kommen erst mit dem Apple-Konto.
@MainActor
final class Hinweise: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Hinweise()
    static let kategorie = "rueckmeldung"
    private static let schalter = "hinweis_rueckmeldung"

    /// Für Antworten aus der Mitteilung; gesetzt, sobald die App läuft
    weak var model: AppModel?
    /// Antwort, die kam, bevor das Modell bereit war
    private var offen: (account: String, access: Int, event: Int, status: String)?

    /// Einstellung „Hinweis, wenn eine Rückmeldung fehlt“ (Vorgabe an).
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: schalter) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: schalter) }
    }

    /// Beim Start: Zuständig für Mitteilungen der App und Knöpfe Zusage/Absage.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let yes = UNNotificationAction(identifier: "yes", title: tr("Zusage"), options: [.authenticationRequired])
        let no = UNNotificationAction(identifier: "no", title: tr("Absage"), options: [.authenticationRequired])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.kategorie, actions: [yes, no], intentIdentifiers: [], options: []),
        ])
    }

    func attach(_ model: AppModel) {
        self.model = model
        if let waiting = offen {
            offen = nil
            Task { await model.respondFromHint(account: waiting.account, accessId: waiting.access, eventId: waiting.event, status: waiting.status) }
        }
    }

    /// Zustand der Erlaubnis, ohne zu fragen (UX-Audit 16.11., IOS-16).
    enum Erlaubnis { case erlaubt, verweigert, offen }

    static func erlaubnis() async -> Erlaubnis {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .erlaubt
        case .denied: return .verweigert
        default: return .offen
        }
    }

    /// Erlaubnis für Mitteilungen erfragen (einmal; danach entscheidet die Einstellung des Geräts).
    /// Nur, wenn die Person es selbst will: Schalter in „Mein Konto“ oder „Erinnern lassen“ bei den Terminen.
    static func erlauben() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Hinweise eines Kontos neu planen: alte des Kontos weg, aktuelle dazu.
    static func plan(_ hints: [RsvpHint], account: String, unit: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = RueckmeldeHinweis.prefix(account: account)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        // Nie ungefragt die Systemabfrage zeigen (IOS-16): planen nur mit Erlaubnis
        guard on, !hints.isEmpty, await erlaubnis() == .erlaubt else { return }
        for hint in hints {
            let content = UNMutableNotificationContent()
            content.title = tr("Rückmeldung fehlt: {title}", ["title": hint.title])
            content.body = tr("{x1} · {unit}. Anmeldeschluss ist bald.", [
                "x1": terminZeit(hint.startsAt, hint.endsAt, allDay: hint.allDay), "unit": unit,
            ])
            content.categoryIdentifier = kategorie
            content.sound = .default
            content.userInfo = ["account": account, "access": hint.accessId, "event": hint.eventId]
            let wait = max(5, hint.fireAt.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: hint.id, content: content, trigger: trigger))
        }
    }

    /// Alle Hinweise eines Kontos entfernen (Trennen, Schalter aus).
    static func clear(account: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = RueckmeldeHinweis.prefix(account: account)
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let shown = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: shown)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        guard action == "yes" || action == "no",
              let account = info["account"] as? String, let access = info["access"] as? Int, let event = info["event"] as? Int
        else { return }
        await MainActor.run {
            if let model = self.model {
                Task { await model.respondFromHint(account: account, accessId: access, eventId: event, status: action) }
            } else {
                self.offen = (account, access, event, action)
            }
        }
    }
}
