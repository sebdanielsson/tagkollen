import Foundation
import TrafikverketKit

/// Resolves the Trafikverket API key: a user-entered key in the Keychain wins over the key
/// baked into the bundle at build time (`TRV_API_KEY` from `Config/Secrets.xcconfig`).
@MainActor
@Observable
final class APIKeyStore: APIKeyProvider {
    enum Source: Equatable {
        case none
        case bundled
        case userProvided
    }

    private(set) var key: String?
    private(set) var source: Source = .none

    private static let account = "trafikverket-api-key"

    let registrationURL: URL

    init(bundle: Bundle = .main) {
        registrationURL = (bundle.object(forInfoDictionaryKey: "TRVAPIKeyRegistrationURL") as? String)
            .flatMap(URL.init(string:)) ?? URL(string: "https://data.trafikverket.se")!
        reload(bundle: bundle)
    }

    private func reload(bundle: Bundle) {
        if let stored = Keychain.string(for: Self.account)?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            key = stored
            source = .userProvided
            return
        }
        let bundled = (bundle.object(forInfoDictionaryKey: "TRVAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !bundled.isEmpty, !bundled.hasPrefix("$(") {
            key = bundled
            source = .bundled
        } else {
            key = nil
            source = .none
        }
    }

    var hasKey: Bool {
        !(key ?? "").isEmpty
    }

    /// Persists a user-provided key. Passing nil or an empty string reverts to the bundled key.
    func setUserKey(_ newKey: String?) {
        let trimmed = newKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed, for: Self.account)
        reload(bundle: .main)
    }

    nonisolated func apiKey() async -> String? {
        await MainActor.run { key }
    }
}
