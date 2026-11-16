import CoreImage.CIFilterBuiltins
import HubiplanKern
import SwiftUI
import UIKit

/// Ausweise auf dem Gerät: Dateien im App-Bereich, vom System verschlüsselt, nicht in
/// Sicherungen. Beim Trennen der Verbindung gelöscht.
struct FileCardStore: CardStore {
    /// Kennung des Kontos; jedes Konto hat seinen eigenen Ordner
    let account: String

    private var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(account.isEmpty ? "ausweise" : "ausweise-\(account)", isDirectory: true)
    }

    private func file(_ accessId: Int) -> URL { dir.appendingPathComponent("ausweis-\(accessId).bin") }

    func load(accessId: Int) -> StoredCard? {
        guard let data = try? Data(contentsOf: file(accessId)) else { return nil }
        return StoredCard.decode(data)
    }

    func save(accessId: Int, card: StoredCard) {
        guard let data = card.encoded() else { return }
        var folder = dir
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        try? data.write(to: file(accessId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(accessId: Int) { try? FileManager.default.removeItem(at: file(accessId)) }

    func clear() { try? FileManager.default.removeItem(at: dir) }
}

/// QR-Code als scharfes Bild (ohne Glättung vergrößern).
func qrImage(_ text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let image = CIContext().createCGImage(output, from: output.extent)
    else { return nil }
    return UIImage(cgImage: image)
}

private func farbe(_ hex: String?, sonst: Color) -> Color {
    guard let rgb = Farbe.rgb(hex) else { return sonst }
    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
}

/// Reiter „Ich“: eigener Mitgliedsausweis wie die gedruckte Karte, mit QR-Code zur Prüfung,
/// darunter die eigenen Daten und Rechnungen.
/// Die App zeigt ihn auch ohne Netz; die Prüfseite zeigt immer den aktuellen Stand.
struct AusweisView: View {
    @EnvironmentObject private var model: AppModel
    @State private var big = false
    @State private var onTop = true
    /// Vorführmodus: für das Bildschirmfoto gleich in Versammlungen oder Dokumente
    @State private var showMeetings = Demo.active && ["versammlungen", "live"].contains(Demo.section)
    @State private var showDocuments = Demo.active && Demo.section == "dokumente"
    @State private var showResults = Demo.active && Demo.section == "ergebnisse"
    @State private var showBookings = Demo.active && Demo.section == "belegung"
    @State private var showAbsences = Demo.active && Demo.section == "abwesenheiten"
    @State private var showAccount = Demo.active && Demo.tab == "konto"
    @State private var showAdmin = Demo.active && ["verwaltung", "freischalten", "offen", "meldungen", "mitglieder", "mitglied", "stammdaten", "austritt", "folgen", "akte", "ehrung", "zusatzfelder", "bank", "aufnahme", "dubletten", "anlaesse", "ausweispruefung", "vtermine", "vtermin", "neuertermin", "kasse", "buchung", "neuebuchung", "quittung", "entwuerfe", "vrechnungen", "vrechnung", "vaufgaben", "vaufgabe", "neueaufgabe", "partner", "qualifikationen", "fristen", "frist", "wettbewerbe", "standcode"].contains(Demo.section)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch CardAnzeige.from(stored: model.card, offline: model.cardOffline) {
                    case .loading:
                        Text(tr("Ausweis wird geladen …")).foregroundStyle(.secondary)
                    case .offlineEmpty:
                        Text(tr("Ohne Netz ist noch kein Ausweis gespeichert. Er erscheint, sobald die App einmal online war."))
                            .foregroundStyle(.secondary)
                    case .revoked:
                        Text(tr("Dein Ausweis ist gesperrt. Bitte wende dich an den Vorstand.")).foregroundStyle(.red)
                    case .none:
                        Text(tr("Für dich gibt es zurzeit keinen gültigen Ausweis, z. B. weil die Mitgliedschaft noch nicht begonnen hat oder beendet ist."))
                            .foregroundStyle(.secondary)
                    case let .card(stored, note):
                        Button { big = true } label: { AusweisKarte(stored: stored) }
                            .buttonStyle(.plain)
                            .accessibilityHint(tr("QR-Code groß zeigen"))
                        if note {
                            Text(tr(
                                "Ohne Netz angezeigt, Stand {stand}. Wer den QR-Code prüft, sieht immer den aktuellen Stand.",
                                ["stand": stored.savedAt.formatted(.dateTime.day().month().year().hour().minute().locale(Texte.locale))]
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(tr("Der QR-Code führt zur Prüfseite deines Vereins. Sie zeigt immer den aktuellen Stand."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button(tr("QR-Code groß zeigen")) { big = true }
                            .buttonStyle(.bordered)
                        if !note, stored.card.wallet?.apple == true {
                            WalletKnopf()
                        }
                    }
                    if let profile = model.profile {
                        MeineDaten(profile: profile)
                        if let cancellation = profile.cancellation, cancellation.shown {
                            KuendigungAbschnitt(info: cancellation)
                        }
                    }
                    if let invoices = model.invoices {
                        MeineRechnungen(list: invoices).id("rechnungen")
                    }
                    if let mandate = model.mandate {
                        MeinMandat(state: mandate)
                    }
                    if let meetings = model.meetings {
                        IchVerweis(title: tr("Versammlungen"), detail: versammlungenKurz(meetings)) { VersammlungenView() }
                    }
                    if let surveys = model.surveys {
                        IchVerweis(title: tr("Umfragen"), detail: surveys.summary) { UmfragenView() }
                    }
                    if let expenses = model.expenses {
                        IchVerweis(title: tr("Auslagen"), detail: expenses.summary) { AuslagenView() }
                    }
                    if let access = model.access, access.hasResults || access.hasEntries {
                        IchVerweis(
                            title: tr("Wettbewerbe"),
                            detail: access.hasEntries ? tr("Meldungen, Plätze, Werte und Titel") : tr("Meine Ergebnisse und Ranglisten")
                        ) { ErgebnisseView() }
                    }
                    if let access = model.access, access.hasAbsences {
                        IchVerweis(title: tr("Abwesenheiten"), detail: tr("Wann du nicht mitspielen kannst")) { AbwesenheitenView() }
                    }
                    if let access = model.access, access.hasBookings {
                        IchVerweis(title: tr("Belegung"), detail: tr("Schützenhaus, Stand oder Material anfragen")) { BelegungView() }
                    }
                    if let access = model.access, access.company {
                        IchVerweis(title: tr("Mitarbeiter"), detail: tr("Für wen die Firma zahlt")) { MitarbeiterView() }
                    }
                    if let documents = model.documents {
                        IchVerweis(title: tr("Dokumente"), detail: trn("1 Dokument", "{n} Dokumente", documents.count)) { DokumenteView() }
                    }
                    if let units = model.adminOverview?.allUnits, !units.isEmpty {
                        IchVerweis(title: tr("Verwaltung"), detail: units.map(\.name).joined(separator: ", ")) { VerwaltungView() }
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding()
            }
            .onChange(of: model.invoices) {
                // Vorführmodus: für das Bildschirmfoto gleich zu den Rechnungen
                if Demo.active && Demo.section == "rechnungen" { proxy.scrollTo("rechnungen", anchor: .bottom) }
            }
            }
            .navigationTitle(tr("Ich"))
            .navigationDestination(isPresented: $showMeetings) { VersammlungenView() }
            .navigationDestination(isPresented: $showDocuments) { DokumenteView() }
            .navigationDestination(isPresented: $showResults) { ErgebnisseView() }
            .navigationDestination(isPresented: $showBookings) { BelegungView() }
            .navigationDestination(isPresented: $showAbsences) { AbwesenheitenView() }
            .navigationDestination(isPresented: $showAccount) { KontoView() }
            .navigationDestination(isPresented: $showAdmin) { VerwaltungView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAccount = true
                    } label: {
                        Label(tr("Mein Konto"), systemImage: "person.crop.circle")
                    }
                }
            }
            .refreshable { await model.refreshIch() }
            .task(id: model.accessId) { await model.refreshIch() }
            // Rechnungen als PDF; nur solange diese Ansicht oben liegt (die anderen haben ihre eigene)
            .onAppear { onTop = true }
            .onDisappear { onTop = false }
            .quickLookPreview(onTop ? $model.preview : .constant(nil))
            .fullScreenCover(isPresented: $big) {
                if let stored = model.card, let url = stored.card.url, let display = stored.card.display {
                    GrosserQrCode(url: url, name: display.name, club: display.club) { big = false }
                }
            }
        }
    }
}

struct AusweisKarte: View {
    let stored: StoredCard

    @ViewBuilder
    private func zeile(_ label: String, _ value: String) -> some View {
        if !label.isEmpty && !value.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(Color(white: 0.33))
                Text(value).font(.footnote)
            }
        }
    }

    var body: some View {
        if let display = stored.card.display {
            let primary = farbe(display.theme?.primary, sonst: Color(red: 14 / 255, green: 124 / 255, blue: 102 / 255))
            let onPrimary = farbe(display.theme?.onPrimary, sonst: .white)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    if let data = stored.logo, let logo = UIImage(data: data) {
                        Image(uiImage: logo).resizable().scaledToFit().frame(width: 36, height: 36)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(display.club).font(.subheadline.bold())
                        Text(tr("Mitgliedsausweis")).font(.caption2)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(onPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(primary)
                HStack(alignment: .top, spacing: 12) {
                    if let data = stored.photo, let photo = UIImage(data: data) {
                        if display.isOrganization {
                            // Logo der Organisation: ganz zeigen, nicht beschneiden
                            Image(uiImage: photo).resizable().scaledToFit()
                                .frame(width: 88, height: 66)
                                .accessibilityLabel(tr("Logo"))
                        } else {
                            Image(uiImage: photo).resizable().scaledToFill()
                                .frame(width: 72, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .accessibilityLabel(tr("Foto"))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(display.firstLine).font(.subheadline)
                        Text(display.lastName).font(.headline)
                        zeile(display.departmentLabel, display.departments.joined(separator: ", "))
                        zeile(tr("Mitgliedsnummer"), display.clubNumber)
                        zeile(tr("Mitgliedsart"), display.memberType ?? "")
                        Text(display.statusLabel)
                            .font(.caption.bold())
                            .foregroundStyle(display.status == "active"
                                ? Color(red: 27 / 255, green: 94 / 255, blue: 32 / 255)
                                : Color(red: 183 / 255, green: 28 / 255, blue: 28 / 255))
                    }
                    Spacer(minLength: 0)
                    if let qr = qrImage(stored.card.url ?? "") {
                        Image(uiImage: qr).interpolation(.none).resizable()
                            .frame(width: 96, height: 96)
                            .accessibilityLabel(tr("QR-Code zur Prüfung"))
                    }
                }
                .padding(12)
            }
            // Wie die gedruckte Karte immer hell, auch im Dunkelmodus
            .foregroundStyle(.black)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }
}

/// Vorzeigen: QR-Code bildschirmfüllend auf Weiß, Bildschirm so hell wie möglich.
struct GrosserQrCode: View {
    let url: String
    let name: String
    let club: String
    let close: () -> Void
    @State private var before: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(club).font(.headline)
            Text(name).font(.title2.bold())
            if let qr = qrImage(url) {
                Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                    .frame(maxWidth: 420)
                    .accessibilityLabel(tr("QR-Code zur Prüfung"))
            }
            Button(tr("Schließen"), action: close)
                .buttonStyle(.borderedProminent)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.black)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            before = screen?.brightness
            screen?.brightness = 1
        }
        .onDisappear {
            if let before { screen?.brightness = before }
        }
    }
}

/// Abschnitt mit Überschrift auf einer Karte.
struct IchAbschnitt<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
    }
}

/// Zeile, die zu einem eigenen Bildschirm führt (Versammlungen, Dokumente).
struct IchVerweis<Ziel: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let ziel: () -> Ziel

    var body: some View {
        NavigationLink {
            ziel()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.primary)
                    if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(Color.secondary) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }
}

struct MeineDaten: View {
    let profile: Profile

    @ViewBuilder
    private func zeile(_ label: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value)
            }
        }
    }

    var body: some View {
        IchAbschnitt(title: tr("Meine Daten")) {
            Text(profile.name).font(.body.weight(.semibold))
            zeile(tr("Mitgliedsnummer"), profile.clubNumber)
            zeile(tr("Mitgliedsart"), profile.memberType ?? "")
            if !profile.isOrganization {
                zeile(tr("Geburtsdatum"), Zeit.plainDate(profile.birthDate))
            }
            zeile(tr("Mitglied seit"), Zeit.plainDate(profile.entryDate))
            if let contact = profile.contact {
                zeile(tr("Anschrift"), contact.addressLines.joined(separator: "\n"))
                zeile(tr("E-Mail"), contact.email)
                zeile(tr("Telefon"), contact.phone)
            }
            Text(tr("Stimmt etwas nicht? Ändern kannst du deine Daten im Mitgliederbereich im Browser."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct MeineRechnungen: View {
    @EnvironmentObject private var model: AppModel
    let list: MyInvoices

    var body: some View {
        IchAbschnitt(title: tr("Rechnungen")) {
            if list.invoices.isEmpty && list.collective.isEmpty {
                Text(tr("Keine Rechnungen")).foregroundStyle(.secondary)
            }
            if let sum = list.openSum {
                Text(tr("Offen insgesamt: {betrag}", ["betrag": sum])).font(.body.weight(.semibold))
            }
            if model.previewBusy {
                Text(tr("Datei wird geladen …")).font(.footnote).foregroundStyle(.secondary)
            } else if let message = model.error {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            ForEach(list.sorted) { invoice in
                VStack(alignment: .leading, spacing: 2) {
                    Text(invoice.subject.isEmpty ? invoice.number : invoice.subject)
                    Text(invoice.headline).font(.footnote).foregroundStyle(.secondary)
                    HStack {
                        Text(invoice.stateText)
                            .font(.footnote.weight(invoice.open ? .semibold : .regular))
                            .foregroundStyle(invoice.overdue ? Color.red : invoice.open ? Color.orange : Color.secondary)
                        Spacer(minLength: 8)
                        Text(Geld.format(invoice.total)).font(.footnote)
                    }
                    HStack(spacing: 12) {
                        Button(tr("PDF ansehen")) { Task { await model.openInvoice(invoice) } }
                            .buttonStyle(.bordered)
                        if invoice.hasCancellationPdf {
                            Button(tr("Stornorechnung")) { Task { await model.openInvoice(invoice, cancellation: true) } }
                                .buttonStyle(.borderless)
                        }
                    }
                    .font(.footnote)
                    .disabled(model.previewBusy)
                }
                .padding(.vertical, 4)
            }
            if !list.collective.isEmpty {
                Text(tr("Über eine Sammelrechnung")).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(tr("Diese Beiträge zahlt deine Einheit gesammelt; die Rechnung bekommt sie."))
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(list.collective) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title)
                        Text(line.line).font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !list.invoices.isEmpty {
                Text(tr("Rechnungen öffnet die App nur online und speichert sie nicht."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
