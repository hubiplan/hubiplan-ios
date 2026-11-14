import Foundation
import HubiplanKern
import LocalAuthentication
import Security

/// Tresor für den Vorstandsschlüssel eines Kontos: ein Eintrag im Schlüsselbund, den iOS nur
/// nach Face ID, Touch ID oder Gerätecode herausgibt. Ohne Gerätecode gibt es keinen Tresor
/// und damit keine Verwaltung. Der Eintrag bleibt auf diesem Gerät (keine Sicherung, kein Abgleich).
struct VerwaltungTresor: Sendable {
    enum Ergebnis: Sendable {
        case offen(String)
        /// Abgebrochen oder nicht erkannt: Eintrag bleibt, erneut versuchen
        case abgebrochen
        /// Eintrag fehlt oder ist unbrauchbar: neu freischalten
        case weg
    }

    let service: String
    private static let account = "verwaltung"

    init(account id: String) {
        service = Konten.secrets(id).service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    /// Hat das Gerät einen Code (Voraussetzung für den Tresor)?
    static var deviceLock: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Ablegen; false, wenn das Gerät keinen Code hat.
    func save(_ value: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil
        ) else { return false }
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessControl as String] = control
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    /// Liegt ein Schlüssel im Tresor? Fragt nicht nach Face ID oder Code.
    var filled: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var q = query
        q[kSecUseAuthenticationContext as String] = context
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Herausgeben nach Face ID, Touch ID oder Gerätecode; `reason` steht in der Abfrage.
    func open(reason: String) async -> Ergebnis {
        let tresor = self
        return await Task.detached { () -> Ergebnis in
            let context = LAContext()
            context.localizedReason = reason
            var q = tresor.query
            q[kSecUseAuthenticationContext as String] = context
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &out)
            if status == errSecSuccess, let data = out as? Data, let text = String(data: data, encoding: .utf8) {
                return .offen(text)
            }
            if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
                return .abgebrochen
            }
            return .weg
        }.value
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
