import Foundation

/// Sicherer Speicher für die Geheimnisse eines Kontos (App: Schlüsselbund, Tests: im Speicher).
public protocol SecretStore: Sendable {
    func read(_ key: String) -> String?
    /// nil löscht den Eintrag.
    func write(_ key: String, _ value: String?)
}

/// Das verbundene Gerät eines Kontos: Geräteschlüssel `hpd_…`, Geräteschlüsselpaar (H7)
/// und die Erneuerung. Gleichzeitige Erneuerungen laufen nur einmal.
public actor DeviceSession: TokenStore {
    public static let tokenKey = "token"
    public static let deviceIdKey = "deviceId"
    public static let deviceKeyKey = "deviceKey"

    public let server: String
    private let store: SecretStore
    private let transport: Transport
    private let keys: DeviceKeyStore
    private var running: Task<String?, Never>?

    /// `keys`: Herkunft des Geräteschlüsselpaars (App: Secure Enclave, wenn vorhanden; APP-03).
    public init(server: String, store: SecretStore, transport: Transport, keys: DeviceKeyStore = SoftwareDeviceKeys()) {
        self.server = server
        self.store = store
        self.transport = transport
        self.keys = keys
    }

    /// Das gespeicherte Schlüsselpaar, mit Rückfall auf einen älteren Software-Schlüssel.
    func signer() -> DeviceKeySigner? {
        guard let stored = store.read(Self.deviceKeyKey) else { return nil }
        return keys.load(stored) ?? SoftwareDeviceKeys().load(stored)
    }

    /// Liegt der Geräteschlüssel noch in Software (vor APP-03 verbunden)? Dann wechselt er beim
    /// nächsten Verbinden in die Secure Enclave; die App weist darauf hin.
    public var usesSoftwareKey: Bool { signer().map { !$0.inHardware } ?? false }

    public var connected: Bool { store.read(Self.tokenKey) != nil }

    public func token() -> String? { store.read(Self.tokenKey) }

    /// Schnittstelle mit diesem Gerät.
    public nonisolated func api(language: String = Texte.language) -> Api {
        Api(server: server, transport: transport, tokens: self, language: language)
    }

    /// Verbinden mit dem Code aus dem QR-Code: erzeugt das Geräteschlüsselpaar, meldet den
    /// öffentlichen Teil mit und merkt sich Schlüssel und Gerät.
    public func connect(code: String, deviceName: String, appVersion: String) async throws -> Paired {
        let (signer, stored) = try keys.create()
        let paired = try await Api(server: server, transport: transport, language: Texte.language).pair(
            code: code, deviceName: deviceName, appVersion: appVersion,
            deviceKey: signer.publicKey
        )
        store.write(Self.deviceKeyKey, stored)
        store.write(Self.deviceIdKey, String(paired.device.id))
        store.write(Self.tokenKey, paired.token)
        return paired
    }

    func secret(_ key: String) -> String? { store.read(key) }
    func setSecret(_ key: String, _ value: String?) { store.write(key, value) }

    /// Alles vergessen (Verbindung trennen oder Gerät abgemeldet).
    public func forget() {
        store.write(ApplePush.keysKey, nil)
        store.write(Self.tokenKey, nil)
        store.write(Self.deviceIdKey, nil)
        store.write(Self.deviceKeyKey, nil)
    }

    public func renew(used: String) async -> String? {
        guard let current = store.read(Self.tokenKey) else { return nil }
        // Ein anderer Aufruf hat schon erneuert
        if current != used { return current }
        if let running { return await running.value }
        let task = Task { await self.renewNow() }
        running = task
        let result = await task.value
        running = nil
        return result
    }

    private func renewNow() async -> String? {
        guard let key = signer(), let idText = store.read(Self.deviceIdKey), let id = Int(idText)
        else { return nil }
        guard let renewed = try? await api().renew(deviceId: id, signer: key) else { return nil }
        store.write(Self.tokenKey, renewed.token)
        return renewed.token
    }
}

extension ApiError {
    /// Meldung für die Oberfläche, in der Sprache der App.
    public var text: String {
        if status == 0 {
            if code == "format" || code == "too_large" {
                return tr("Die Antwort der Instanz war nicht lesbar. Vielleicht ist die App zu alt.")
            }
            return tr("Keine Verbindung. Bitte prüfe das Netz und versuche es erneut.")
        }
        if mustReconnect { return tr("Dieses Gerät ist abgemeldet. Bitte neu verbinden.") }
        if code == "format" { return tr("Die Antwort der Instanz war nicht lesbar. Vielleicht ist die App zu alt.") }
        if !message.isEmpty { return message }
        return tr("Das hat nicht geklappt ({status}). Bitte später erneut versuchen.", ["status": status])
    }
}
