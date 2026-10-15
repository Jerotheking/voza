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

    private let paths: AppPaths
    private let clock: Clock
    private let defaults: UserDefaults

    private var cacheFile: URL { paths.licenseCacheFile }

    private struct LicenseCache: Codable {
        let key: String
        let email: String?
        let lastVerified: Date
    }

    private struct VerifyResponse: Decodable {
        let success: Bool?
        let message: String?
        struct Purchase: Decodable {
            let email: String?
            let refunded: Bool?
            let disputed: Bool?
            let chargebacked: Bool?
        }
        let purchase: Purchase?

        /// A response is only acceptable when Gumroad says success AND the purchase
        /// has not been refunded/disputed/charged back (audit v2 §3.7).
        var purchaseUsable: Bool {
            guard success == true else { return false }
            let p = purchase
            return !(p?.refunded == true || p?.disputed == true || p?.chargebacked == true)
        }
    }

    /// Injected dependencies (plan-glm V01). Defaults reproduce the exact
    /// baseline production behavior; tests inject QA paths, a fixed clock and
    /// an isolated defaults suite. Internal (not private) so the QA suites can
    /// construct isolated instances; `shared` remains the production singleton.
    init(paths: AppPaths = .default,
                 clock: Clock = SystemClock(),
                 defaults: UserDefaults = .standard) {
        self.paths = paths
        self.clock = clock
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Call at app start. Restores cached license or computes trial state.
    func refreshIfNeeded() {
        if let cache = readCache() {
            state = .licensed(email: cache.email)
            if clock.now.timeIntervalSince(cache.lastVerified) > Self.reverifyInterval {
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
            // Activating a NEW installation counts a use; see verifyRequest.
            let response = try await Self.verifyRequest(key: key, purpose: .activation)
            if response.purchaseUsable {
                let cache = LicenseCache(key: key, email: response.purchase?.email, lastVerified: clock.now)
                writeCache(cache)
                state = .licensed(email: cache.email)
            } else {
                state = .invalid(message: response.message
                    ?? L.t("That key was not accepted", es: "Esa llave no fue aceptada"))
            }
        } catch is DecodingError {
            state = .invalid(message: L.t("That key was not accepted", es: "Esa llave no fue aceptada"))
        } catch {
            state = .invalid(message: L.t("Could not reach Gumroad (offline?)", es: "No se pudo conectar a Gumroad (¿sin internet?)"))
        }
    }

    // MARK: - Trial

    private func computeTrialState() {
        let startKey = "voza.trialStart"
        let maxWallKey = "voza.trialMaxWall"
        let uptimeKey = "voza.trialStartUptime"

        let now = clock.now
        let uptime = clock.uptimeSeconds

        let start: Date
        if let saved = defaults.object(forKey: startKey) as? Date {
            start = saved
        } else {
            start = now
            defaults.set(start, forKey: startKey)
            defaults.set(now, forKey: maxWallKey)
            defaults.set(uptime, forKey: uptimeKey)
        }

        // D063 (P1-2): prevent backward wall-clock rollback from extending trial days,
        // and cross-check against monotonic uptime when uptime has not reset across reboot.
        let previousMaxWall = (defaults.object(forKey: maxWallKey) as? Date) ?? start
        let effectiveNow = max(now, previousMaxWall)
        if effectiveNow > previousMaxWall {
            defaults.set(effectiveNow, forKey: maxWallKey)
        }

        let wallElapsed = max(0, effectiveNow.timeIntervalSince(start))
        var monotonicElapsed: TimeInterval = 0
        if let savedUptime = defaults.object(forKey: uptimeKey) as? TimeInterval,
           uptime >= savedUptime {
            monotonicElapsed = uptime - savedUptime
        } else {
            defaults.set(uptime, forKey: uptimeKey)
        }

        let elapsed = max(wallElapsed, monotonicElapsed)
        let daysLeft = Self.trialDays - Int(elapsed / 86_400)
        state = daysLeft > 0 ? .trial(daysLeft: daysLeft) : .trialOver
    }

    // MARK: - Network

    /// - Parameter purpose: activation increments the license's use counter (new
    ///   installation/seat); silent revalidation must NOT (Gumroad docs — audit v2 §3.7).
    private enum VerificationPurpose {
        case activation
        case revalidation
    }

    private static func verifyRequest(key: String, purpose: VerificationPurpose) async throws -> VerifyResponse {
        var components = URLComponents(string: "https://api.gumroad.com/v2/licenses/verify")!
        components.queryItems = [
            URLQueryItem(name: "product_permalink", value: Config.shared.gumroadPermalink),
            URLQueryItem(name: "license_key", value: key),
            URLQueryItem(name: "increment_uses_count", value: purpose == .activation ? "true" : "false"),
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
        if let decoded = try? JSONDecoder().decode(VerifyResponse.self, from: data) {
            return decoded
        }
        // D063 (P2-3): 4xx with non-JSON/HTML body means the key/request was rejected,
        // not that the user is offline.
        if (400..<500).contains(http.statusCode) {
            return VerifyResponse(success: false, message: nil, purchase: nil)
        }
        return try JSONDecoder().decode(VerifyResponse.self, from: data)
    }

    private func reverify(_ cache: LicenseCache) async {
        do {
            // Silent recheck: never bump the use counter.
            let response = try await Self.verifyRequest(key: cache.key, purpose: .revalidation)
            if response.purchaseUsable {
                writeCache(LicenseCache(key: cache.key, email: response.purchase?.email ?? cache.email, lastVerified: clock.now))
            } else {
                // Key revoked/refunded/disputed → clear and fall back to trial state.
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
