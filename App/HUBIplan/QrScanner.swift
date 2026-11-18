import AVFoundation
import HubiplanKern
import SwiftUI
import VisionKit

/// QR-Code „App verbinden“ mit der Kamera lesen. Der Inhalt wird nur an die App gegeben;
/// verbunden wird erst nach der Rückfrage mit der Adresse der Instanz.
struct QrScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    /// Kamera vorhanden und erlaubt (im Simulator nicht).
    @MainActor static var available: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case let .barcode(code) = item, let text = code.payloadStringValue {
                    done = true
                    found(text)
                    return
                }
            }
        }
    }
}

/// Kamera verweigert: sagen, warum der Scan fehlt, und in die Einstellungen führen
/// (UX-Audit 16.11., wie Android AND-17). Ohne Kamera am Gerät (Simulator) nur der Satz.
struct KameraHinweis: View {
    var alternative: String?
    @Environment(\.openURL) private var openURL

    private var denied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    var body: some View {
        if denied {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Ohne Kamera lässt sich der QR-Code nicht scannen. Erlaube die Kamera in den Einstellungen.")
                    + (alternative.map { " " + $0 } ?? ""))
                    .foregroundStyle(Color.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Button(tr("Einstellungen öffnen")) { openURL(url) }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            Text(tr("Die Kamera ist auf diesem Gerät nicht verfügbar oder nicht erlaubt."))
                .foregroundStyle(Color.secondary)
        }
    }
}
