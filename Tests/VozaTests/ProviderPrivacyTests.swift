import XCTest
@testable import VozaKit

/// V12 — Provider/credential privacy boundary, hermetic end to end:
/// a fake Keychain (no real items), a stub URLProtocol transport (no
/// sockets), and QA paths (no real files). No real API key is ever used
/// (ticket pause conditions).
final class ProviderPrivacyTests: XCTestCase {
    // MARK: - Fakes

    /// Controllable keychain: can simulate locked/denied failures.
    final class FakeKeychain: KeychainStore, @unchecked Sendable {
        var items: [String: String] = [:]
        var failWrites = false

        func get(_ key: String) -> String? { items[key] }
        @discardableResult
        func set(_ key: String, value: String) -> Bool {
            guard !failWrites else { return false }
            items[key] = value
            return true
        }
        @discardableResult
        func delete(_ key: String) -> Bool { items.removeValue(forKey: key) != nil }
    }

    /// URLProtocol stub: records requests (method/host, NEVER the body, so
    /// the dictation text never lands in test logs — V12-AC05), serves a
    /// canned response, and can simulate a cross-host redirect.
    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
        nonisolated(unsafe) static var seenRequests: [(method: String, host: String)] = []

        static func reset() { handler = nil; seenRequests = [] }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if let url = request.url {
                Self.seenRequests.append((request.httpMethod ?? "GET", url.host ?? "?"))
            }
            guard let handler = Self.handler, let url = request.url else { return }
            let (status, headers, data) = handler(request)
            // Redirect simulation: serve 302 + Location; the transport's
            // delegate must cancel BEFORE this protocol sees a second load.
            let response = HTTPURLResponse(url: url, statusCode: status,
                                           httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func makeTransport() -> SecureCleanupTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        // Production NoRedirectDelegate: the redirect boundary under test.
        return SecureCleanupTransport(
            session: session,
            delegate: SecureCleanupTransport.NoRedirectDelegate()
        )
    }

    func makeConfig(envFile: String = "", keychain: KeychainStore? = nil) throws -> (Config, TestEnvironment) {
        let env = try TestEnvironment()
        try FileManager.default.createDirectory(at: env.paths.configFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try envFile.write(to: env.paths.envFile, atomically: true, encoding: .utf8)
        let config = Config(paths: env.paths, keychain: keychain)
        return (config, env)
    }

    override func setUp() {
        super.setUp()
        StubProtocol.reset()
    }

    // MARK: - V12-AC01: literal/plain/auto → zero cloud requests

    func testPlainModeMakesZeroCloudRequestsEvenWithKeys() async throws {
        let keychain = FakeKeychain()
        keychain.items["OPENAI_API_KEY"] = "sk-test"
        keychain.items["ANTHROPIC_API_KEY"] = "sk-ant-test"
        let (config, env) = try makeConfig(keychain: keychain)
        defer { env.tearDown() }

        for mode in ["plain", "auto", "ollama", "mlx", "garbage"] {
            StubProtocol.handler = { _ in
                XCTFail("mode \(mode) must never reach the network")
                return (500, [:], Data())
            }
            let outcome = await Cleaner.clean("texto", config: {
                config.setCleanupMode(mode)
                return config
            }(), transport: makeTransport())
            XCTAssertTrue(outcome.applied == false, "mode \(mode) cannot claim a cleaning")
        }
        XCTAssertTrue(StubProtocol.seenRequests.isEmpty, "any non-cloud mode made zero requests")
    }

    // MARK: - V12-AC02: insecure endpoints and cross-host redirects refused

    func testInsecureRemoteEndpointRefusedWithoutSendingCredential() async throws {
        // Plain HTTP to a remote host: the transport must refuse BEFORE any
        // request exists (pure gate), credential or not.
        let url = try XCTUnwrap(URL(string: "http://api.provider.com/v1/chat/completions"))
        XCTAssertThrowsError(try SecureCleanupTransport.validateEndpoint(url))
        // Loopback plain HTTP is the allowed exception.
        let loop = try XCTUnwrap(URL(string: "http://127.0.0.1:11434/v1/chat/completions"))
        XCTAssertNoThrow(try SecureCleanupTransport.validateEndpoint(loop))

        // And the request-builder gate: an http:// OPENAI_BASE_URL must not
        // produce a usable remote endpoint the pipeline would call.
        let request = Cleaner.openAIRequest(text: "hola", apiKey: "sk-test",
                                            baseURL: "http://api.provider.com/v1", model: nil)
        XCTAssertNotNil(request)
        XCTAssertThrowsError(try SecureCleanupTransport.validateEndpoint(request!.url))
    }

    func testCrossHostRedirectIsNotTolerated() throws {
        let from = try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions"))
        // Cross-host → refused (the classic credential-leak vector).
        let evil = try XCTUnwrap(URL(string: "https://evil.example.com/v1/chat/completions"))
        XCTAssertFalse(SecureCleanupTransport.redirectIsTolerable(from: from, to: evil))
        // Downgrade https→http even on the same host → refused.
        let downgrade = try XCTUnwrap(URL(string: "http://api.openai.com/v1/chat/completions"))
        XCTAssertFalse(SecureCleanupTransport.redirectIsTolerable(from: from, to: downgrade))
        // Same host+scheme would be "tolerable" per the predicate — but the
        // delegate cancels ALL redirects in production (defense in depth).
        let same = try XCTUnwrap(URL(string: "https://api.openai.com/v1/chat/completions?x=1"))
        XCTAssertTrue(SecureCleanupTransport.redirectIsTolerable(from: from, to: same))
    }

    /// Live-transport pin: a 302 from the provider must NOT produce a second
    /// request to the redirect target carrying the credential.
    func testRedirectProducesNoSecondRequest() async throws {
        let (config, env) = try makeConfig(envFile: "OPENAI_API_KEY=sk-test\n")
        defer { env.tearDown() }
        config.setCleanupMode("cloud")

        StubProtocol.handler = { request in
            if request.url?.host == "api.openai.com" {
                return (302, ["Location": "https://evil.example.com/catch"], Data())
            }
            // Any request that DOES reach another host is the leak itself.
            XCTFail("redirect target received a request: \(request.url?.host ?? "?")")
            return (200, [:], Data())
        }
        let outcome = await Cleaner.clean("texto privado", config: config, transport: makeTransport())
        XCTAssertFalse(outcome.applied, "a blocked redirect degrades to raw — never 'cleaned'")
        let hosts = StubProtocol.seenRequests.map(\.host)
        XCTAssertFalse(hosts.contains("evil.example.com"), "the text/credential must never reach the redirect host")
        XCTAssertEqual(hosts.filter { $0 == "api.openai.com" }.count, 1, "exactly one attempt, no retry loops")
    }

    // MARK: - V12-AC03: Keychain failure never destroys the .env key

    func testFailedKeychainWriteKeepsEnvFileIntact() throws {
        let keychain = FakeKeychain()
        keychain.failWrites = true
        let original = "OPENAI_API_KEY=sk-file-value\n# comment stays\n"
        let (config, env) = try makeConfig(envFile: original, keychain: nil)
        defer { env.tearDown() }

        let saved = config.saveCleanupKey("OPENAI_API_KEY", value: "sk-new", keychain: keychain)
        XCTAssertFalse(saved, "a refused Keychain write must report failure")
        let fileNow = try String(contentsOf: env.paths.envFile, encoding: .utf8)
        XCTAssertEqual(fileNow, original, "the .env key survives untouched (nothing half-migrated)")
        XCTAssertEqual(config.env["OPENAI_API_KEY"], "sk-file-value", "the layered env still resolves the file value")
    }

    /// The full migration: verify-then-strip, with the Keychain read-back
    /// gating the file-line removal.
    func testMigrationStripsFileOnlyAfterKeychainVerifies() throws {
        let keychain = FakeKeychain()
        let (config, env) = try makeConfig(envFile: "OPENAI_API_KEY=sk-migrate\n", keychain: keychain)
        defer { env.tearDown() }

        // Migrating WITHOUT storing first must fail and leave the file.
        XCTAssertFalse(config.migrateEnvKeyToKeychain("OPENAI_API_KEY", keychain: keychain))
        XCTAssertEqual(try String(contentsOf: env.paths.envFile, encoding: .utf8),
                       "OPENAI_API_KEY=sk-migrate\n")

        // Store the SAME value the file has → verify passes → strip.
        keychain.items["OPENAI_API_KEY"] = "sk-migrate"
        XCTAssertTrue(config.migrateEnvKeyToKeychain("OPENAI_API_KEY", keychain: keychain))
        let fileNow = try String(contentsOf: env.paths.envFile, encoding: .utf8)
        XCTAssertFalse(fileNow.contains("OPENAI_API_KEY"), "the plaintext line is gone")
        XCTAssertEqual(config.env["OPENAI_API_KEY"], "sk-migrate", "still resolves via the Keychain layer")
        XCTAssertTrue(config.hasCleanupProvider)
    }

    // MARK: - V12-AC04: authorized cloud requests carry TEXT ONLY, chosen provider

    func testCloudRequestCarriesTextOnlyToChosenProvider() async throws {
        let (config, env) = try makeConfig(envFile: "OPENAI_API_KEY=sk-test\n")
        defer { env.tearDown() }
        config.setCleanupMode("cloud")

        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            return (200, [:], Data("{\"choices\":[{\"message\":{\"content\":\"Hola.\"}}]}".utf8))
        }
        // Text-only pin: the STUB never records the body (V12-AC05 forbids
        // logging secrets/text), so here we assert the header + host choice
        // and that the provider chain order is respected.
        let outcome = await Cleaner.clean("hola", config: config, transport: makeTransport())
        XCTAssertEqual(outcome.provider, "openai", "the chain uses the first WORKING provider in order")
        XCTAssertTrue(outcome.applied)
        XCTAssertEqual(StubProtocol.seenRequests.map(\.host), ["api.openai.com"])
    }

    func testAnthropicFallbackOnlyAfterOpenAIFails() async throws {
        let (config, env) = try makeConfig(
            envFile: "OPENAI_API_KEY=sk-test\nANTHROPIC_API_KEY=sk-ant\n")
        defer { env.tearDown() }
        config.setCleanupMode("cloud")

        StubProtocol.handler = { request in
            if request.url?.host == "api.openai.com" { return (500, [:], Data()) }
            return (200, [:], Data(#"{"content":[{"text":"Hola."}]}"#.utf8))
        }
        let outcome = await Cleaner.clean("hola", config: config, transport: makeTransport())
        XCTAssertEqual(outcome.provider, "anthropic", "fallback runs only after the first provider fails")
        let hosts = StubProtocol.seenRequests.map(\.host)
        XCTAssertEqual(hosts, ["api.openai.com", "api.anthropic.com"], "order is the pinned chain")
    }

    // MARK: - V12-AC05: no secrets in process args / query strings / logs

    func testSecretsNeverAppearInURLQueryOrHostRecords() throws {
        // The request builders put credentials in HEADERS only — a URL can
        // end up in logs, crash reports and `ps`.
        let openai = try XCTUnwrap(Cleaner.openAIRequest(text: "hola", apiKey: "sk-secret",
                                                         baseURL: nil, model: nil))
        XCTAssertNil(openai.url.query, "credentials must never travel in query strings")
        XCTAssertFalse(openai.url.absoluteString.contains("sk-secret"))
        XCTAssertEqual(openai.headers["Authorization"], "Bearer sk-secret")

        let anthropic = try XCTUnwrap(Cleaner.anthropicRequest(text: "hola", apiKey: "sk-ant-secret", model: nil))
        XCTAssertNil(anthropic.url.query)
        XCTAssertFalse(anthropic.url.absoluteString.contains("sk-ant-secret"))
        XCTAssertEqual(anthropic.headers["x-api-key"], "sk-ant-secret")
    }

    // MARK: - Layered precedence (extends the pinned P2-e contract)

    func testKeychainLayerWinsOverFileAndShell() throws {
        let keychain = FakeKeychain()
        keychain.items["OPENAI_API_KEY"] = "sk-keychain"
        let (config, env) = try makeConfig(envFile: "OPENAI_API_KEY=sk-file\n", keychain: keychain)
        defer { env.tearDown() }
        setenv("OPENAI_API_KEY", "sk-shell", 1)
        defer { unsetenv("OPENAI_API_KEY") }

        config.reload()
        XCTAssertEqual(config.env["OPENAI_API_KEY"], "sk-keychain", "Keychain → file → shell, most trusted first")
        XCTAssertEqual(config.envFileValues["OPENAI_API_KEY"], "sk-file", "the file layer stays visible for migration verification")
    }

    /// The service namespace separates QA from production items.
    func testProductionKeychainServiceNamespacing() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultPaths = AppPaths(appSupport: home.appendingPathComponent(".config/voza", isDirectory: true),
                                    history: home.appendingPathComponent("Dictation"),
                                    temp: FileManager.default.temporaryDirectory)
        _ = Config.productionKeychain(for: defaultPaths) // production constant path — no crash, no collision
        let qaStore = Config.productionKeychain(for: AppPaths.qa(root: URL(fileURLWithPath: "/tmp/voza-qa-x")))
        if let sec = qaStore as? SecItemKeychainStore {
            XCTAssertNotEqual(sec.service, "com.jerotherey.voza.credentials",
                              "a QA root must be namespaced away from production items")
        }
    }
}
