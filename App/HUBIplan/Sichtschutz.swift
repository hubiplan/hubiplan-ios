import HubiplanKern
import SwiftUI
import UIKit
import WebKit

/// Sichtschutz in der App-Übersicht (Gesamtaudit 19.11.2026, S-09): Ein eigenes Fenster über
/// allem, auch über Blättern und Vollbildansichten, solange die App nicht vorn liegt.
@MainActor
final class SichtschutzFenster {
    static let shared = SichtschutzFenster()
    private var fenster: UIWindow?

    func aktualisieren(aktiv: Bool) {
        if !Demo.active, Sichtschutz.verdecken(aktiv: aktiv, erlaubt: Sichtschutz.erlaubt()) {
            zeigen()
        } else {
            verbergen()
        }
    }

    private func zeigen() {
        guard fenster == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.rootViewController = UIHostingController(rootView: SichtschutzBild())
        window.isHidden = false
        fenster = window
    }

    private func verbergen() {
        fenster?.isHidden = true
        fenster = nil
    }

    /// Nach dem Abmelden: Speicher der eingebetteten Webansicht (Standmodus) löschen.
    static func loescheWebDaten(_ was: Sichtschutz.WebDaten) async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        switch was {
        case .nichts:
            return
        case .alles:
            await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        case .instanz(let host):
            let records = await store.dataRecords(ofTypes: types)
            let own = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }
            await store.removeData(ofTypes: types, for: own)
        }
    }
}

private struct SichtschutzBild: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            Image(systemName: "lock.fill").font(.hubi(.largeTitle)).foregroundStyle(Color.secondary)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
