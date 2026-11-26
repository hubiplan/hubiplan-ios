import HubiplanKern
import SwiftUI

/// Vorstand oder Zugführung: Kurzmitteilung an alle Mitglieder einer Einheit (wie Android).
/// Erst „Weiter“ zählt die Empfänger, gesendet wird nach der Rückfrage.
struct SendenView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let senders: Senders
    let done: (String) -> Void
    @State private var senderKey: String?
    @State private var subject = ""
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var preview: [String: Int]?
    @State private var leave = false

    private var sender: Sender? {
        senders.senders.first { $0.key == senderKey } ?? senders.senders.first
    }

    private var ready: Bool {
        sender != nil
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var changed: Bool { !subject.isEmpty || !text.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { MeldungText(error, .fehler) }
                }
                if !model.adminOpen {
                    Section { MeldungText(tr("Zum Senden muss die Verwaltung entsperrt sein. Bitte zuerst unter „Verwaltung“ entsperren."), .warnung) }
                }
                Section {
                    if senders.senders.count > 1 {
                        Picker(tr("An"), selection: Binding(get: { sender?.key ?? "" }, set: { senderKey = $0 })) {
                            ForEach(senders.senders) { Text($0.label).tag($0.key) }
                        }
                    } else if let sender {
                        LabeledContent(tr("An"), value: sender.label)
                    }
                } footer: {
                    Text(tr("Geht an alle Mitglieder dieser Einheit: per App, sonst per E-Mail."))
                }
                Section(tr("Betreff")) {
                    TextField(tr("Betreff"), text: $subject)
                        .weiterFeld()
                        .onChange(of: subject) { _, new in if new.count > 200 { subject = String(new.prefix(200)) } }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .accessibilityLabel(tr("Text"))
                        .onChange(of: text) { _, new in
                            if new.count > senders.maxBody { text = String(new.prefix(senders.maxBody)) }
                        }
                } header: {
                    Text(tr("Text"))
                } footer: {
                    Text(tr("{length} von {maxBody} Zeichen", ["length": text.count, "maxBody": senders.maxBody]))
                }
            }
            .tastaturFuehrung()
            .disabled(busy)
            .navigationTitle(tr("Kurzmitteilung senden"))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(changed)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Abbrechen")) { if changed { leave = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        Laedt()
                    } else {
                        Button(tr("Weiter")) { Task { await call(confirm: false) } }
                            .disabled(!ready)
                    }
                }
            }
            .alert(
                tr("Kurzmitteilung senden?"),
                isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })
            ) {
                Button(tr("Jetzt senden")) { Task { await call(confirm: true) } }
                    .disabled(Empfaenger.total(preview ?? [:]) == 0)
                Button(tr("Abbrechen"), role: .cancel) { preview = nil }
            } message: {
                Text(tr("„{x1}“ {x2}. Gesendete Mitteilungen lassen sich nicht zurückholen.", [
                    "x1": subject.trimmingCharacters(in: .whitespacesAndNewlines),
                    "x2": Empfaenger.summary(preview ?? [:]),
                ]))
            }
            .confirmationDialog(tr("Entwurf verwerfen?"), isPresented: $leave, titleVisibility: .visible) {
                Button(tr("Verwerfen"), role: .destructive) { dismiss() }
                Button(tr("Weiter bearbeiten"), role: .cancel) {}
            }
        }
    }

    private func call(confirm: Bool) async {
        guard let sender, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        let result = await model.sendShort(
            sender,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: text.trimmingCharacters(in: .whitespacesAndNewlines),
            confirm: confirm
        )
        switch result {
        case .success(let answer):
            if confirm {
                preview = nil
                done(tr("Kurzmitteilung an {name} ist unterwegs.", ["name": sender.name]))
                dismiss()
            } else {
                preview = answer.counts
            }
        case .failure(let failure):
            preview = nil
            error = failure.text
        case nil:
            dismiss()
        }
    }
}
