import HubiplanKern
import SwiftUI

@main
struct HubiplanApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        // Früh zuständig sein: Zusage/Absage aus einer Mitteilung kann die App erst starten
        Hinweise.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if model.account == nil {
                    VerbindenView()
                } else {
                    HauptView()
                }
            }
            .environmentObject(model)
            .task { Hinweise.shared.attach(model) }
            .onOpenURL { url in
                if url.isFileURL {
                    model.open(calendarFile: url)
                } else {
                    model.offer(link: url.absoluteString)
                }
            }
            // Nicht vorn: Inhalt verdecken, auch vor der Anmeldung und über allen Blättern
            .onChange(of: phase) { _, now in SichtschutzFenster.shared.aktualisieren(aktiv: now == .active) }
        }
    }
}
