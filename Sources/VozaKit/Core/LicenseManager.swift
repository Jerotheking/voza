import Foundation

/// Gumroad license verification for the pre-built (notarized) Voza binary.
///
/// Design: the MIT source keeps working regardless — the license funds
/// development. Verified licenses are cached offline at
/// `~/.config/voza/license.json` and re-verified at most every 7 days.
/// A network failure never deactivates a cached license (offline grace);
/// only a definitive Gumroad "invalid" response does. Without a license the
/// app runs on an unfussy 14-day trial that nags politely and keeps working.
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    static let trialDays = 14
    static let reverifyInterval: TimeInterval = 7 * 86_400

    enum State: Equatable {
        case unlicensed
        case trial(daysLeft: Int)
        case trialOver
        case licensed(email: String?)
        case invalid(message: String)
    }

    @Published private(set) var state: State = .unlicensed

    private var cacheFile: URL {
        URL(fileURLWithPath: Config.appSupportDirectory + "/license.json")
    }

    private struct LicenseCache: Codable {
        let key: String
        let email: String?
        let lastVerified: Date
    }

    private struct VerifyResponse: Decodable {
        let success: Bool?
        let message: String?
        struct Purchase: Decodable { let email: String? }
        let purchase: Purchase?
    }

    private init() {}

    // MARK: - Public API

    /// Call at app start. Restores cached license or computes trial state.
    func refreshIfNeeded() {
        if let cache = readCache() {
            state = .licensed(email: cache.email)
            if Date().timeIntervalSince(cache.lastVerified) > Self.reverifyInterval {
                Task { [weak self] in await self?.reverify(cache) }
            }
            return
        }
        computeTrialState()
    }

    /// Verifies a license key against Gumroad and caches it on success.
    func activate(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            state = .invalid(message: L.t("Enter a license key", es: "Escribe tu llave de licencia"))
            return
        }
        do {
            let response = try await Self.verifyRequest(key: key)
            if response.success == true {
                let cache = LicenseCache(key: key, email: response.purchase?.email, lastVerified: Date())
                writeCache(cache)
                state = .licensed(email: cache.email)
            } else {
                state = .invalid(message: response.message
                    ?? L.t("That key was not accepted", es: "Esa llave no fue aceptada"))
            }
        } catch {
            state = .invalid(message: L.t("Could not reach Gumroad (offline?)", es: "No se pudo conectar a Gumroad (¿sin internet?)"))
        }
    }

    // MARK: - Trial

    private func computeTrialState() {
        let defaults = UserDefaults.standard
        let key = "voza.trialStart"
        let start: Date
        if let saved = defaults.object(forKey: key) as? Date {
            start = saved
        } else {
            start = Date()
            defaults.set(start, forKey: key)
        }
        let daysLeft = Self.trialDays - Int(Date().timeIntervalSince(start) / 86_400)
        state = daysLeft > 0 ? .trial(daysLeft: daysLeft) : .trialOver
    }

    // MARK: - Network

    private static func verifyRequest(key: String) async throws -> VerifyResponse {
        var components = URLComponents(string: "https://api.gumroad.com/v2/licenses/verify")!
        components.queryItems = [
            URLQueryItem(name: "product_permalink", value: Config.shared.gumroadPermalink),
            URLQueryItem(name: "license_key", value: key),
            URLQueryItem(name: "increment_uses_count", value: "true"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.httpMethod = "POST"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // 404 = unknown key → decode success:false. 5xx/other → throw for grace handling.
        if http.statusCode >= 500 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(VerifyResponse.self, from: data)
    }

    private func reverify(_ cache: LicenseCache) async {
        do {
            let response = try await Self.verifyRequest(key: cache.key)
            if response.success == true {
                writeCache(LicenseCache(key: cache.key, email: response.purchase?.email ?? cache.email, lastVerified: Date()))
            } else {
                // Key revoked/refunded → clear and fall back to trial state.
                clearCache()
                computeTrialState()
            }
        } catch {
            // Network failure → offline grace, keep the cached license.
        }
    }

    // MARK: - Cache I/O

    private func readCache() -> LicenseCache? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? JSONDecoder().decode(LicenseCache.self, from: data)
    }

    private func writeCache(_ cache: LicenseCache) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFile, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheFile.path)
        }
    }

    private func clearCache() {
        try? FileManager.default.removeItem(at: cacheFile)
    }
}
