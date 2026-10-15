import Foundation

/// V12 — Hardened HTTP transport for cloud cleanup requests. Boundary rules
/// (ticket V12, audit F16 / AC02):
///
/// - HTTPS only. Plain HTTP is refused UNLESS the host is an explicit
///   loopback (127.0.0.1, ::1, localhost) — local proxies are the one
///   legitimate plain-text endpoint.
/// - Redirects are NEVER followed. URLSession auto-follows redirects by
///   default (up to ~20 hops) and RE-ATTACHES headers — which would hand
///   the Authorization / x-api-key header, and the dictation text, to
///   whatever host the redirect points at. `NoRedirectDelegate` cancels
///   the navigation before a second request can exist.
/// - Only provider endpoints chosen by the session snapshot are contacted —
///   the caller passes the fully-built request; this layer adds no hosts.
struct SecureCleanupTransport {
    enum TransportError: Error, Equatable {
        case insecureEndpoint(String)
        case redirectBlocked(from: String, to: String)
    }

    /// Cancels redirects BEFORE URLSession re-sends headers: the task simply
    /// fails and no second request is ever created. This is the production
    /// guarantee; `redirectIsTolerable` below is its pure, testable form.
    final class NoRedirectDelegate: NSObject, URLSessionDataDelegate {
        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)   // cancel: no redirect request is ever sent
        }
    }

    let session: URLSession

    /// Default production transport: ephemeral session (no cookie jar shared
    /// with the user's browser session) + bounded resource timeout + the no-redirect delegate.
    init() {
        let delegate = NoRedirectDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        transportDelegate = delegate
    }

    /// Test seam: inject a session whose protocol/delegate the test owns.
    init(session: URLSession) {
        self.session = session
    }

    /// Test seam with the production no-redirect delegate semantics.
    init(session: URLSession, delegate: NoRedirectDelegate) {
        self.session = session
        self.transportDelegate = delegate
    }

    /// Kept from the delegate-bearing init so the redirect guarantee stays
    /// explicit at construction sites.
    private var transportDelegate: NoRedirectDelegate?

    /// Pure predicate: is this host allowed to receive credentials/text over
    /// plain HTTP? Only explicit loopback names/addresses qualify.
    static func isLoopbackHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h == "[::1]"
    }

    /// Pure predicate: scheme/host gate for the INITIAL request.
    static func validateEndpoint(_ url: URL) throws {
        guard url.host != nil else { throw TransportError.insecureEndpoint(url.absoluteString) }
        switch url.scheme?.lowercased() {
        case "https":
            return
        case "http":
            guard isLoopbackHost(url.host!) else { throw TransportError.insecureEndpoint(url.absoluteString) }
        default:
            throw TransportError.insecureEndpoint(url.absoluteString)
        }
    }

    /// Pure form of the delegate's decision: the ONLY redirect this design
    /// would tolerate stays on the same host AND scheme (and passes the
    /// endpoint gate). The delegate cancels everything regardless — this
    /// predicate exists so tests pin the boundary decision (V12-AC02)
    /// without sockets.
    static func redirectIsTolerable(from: URL, to: URL) -> Bool {
        guard (try? Self.validateEndpoint(to)) != nil else { return false }
        return from.host?.lowercased() == to.host?.lowercased()
            && from.scheme?.lowercased() == to.scheme?.lowercased()
    }

    /// Sends the request with the boundary rules enforced. Failures surface
    /// as thrown errors; the provider chain treats them like any provider
    /// failure and degrades to the raw transcript (never leaks, never
    /// retries the text on another host).
    func send(_ request: URLRequest, body: Data) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw TransportError.insecureEndpoint("(nil URL)") }
        try Self.validateEndpoint(url)

        var req = request
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
