import HubiplanKern
import SwiftUI

@main
struct HubiplanApp: App {
    @StateObject private var model = AppModel()

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
            .onOpenURL { url in model.offer(link: url.absoluteString) }
        }
    }
}
