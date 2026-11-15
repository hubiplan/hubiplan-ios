import HubiplanKern
import SwiftUI

@main
struct HubiplanApp: App {
    @StateObject private var model = AppModel()

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
            .onOpenURL { url in model.offer(link: url.absoluteString) }
        }
    }
}
