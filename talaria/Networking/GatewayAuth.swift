import Foundation

enum GatewayAuthError: LocalizedError {
    case notConfigured
    case badCredentials
    case http(Int, String)
    case noProvider

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Server, username and password are required."
        case .badCredentials: return "The dashboard rejected the username or password."
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .noProvider: return "The dashboard has no username/password sign-in enabled."
        }
    }
}

/// Dashboard session handling. Password login sets the dashboard's session cookies (12h access,
/// 30-day rotating refresh, rotated silently by the server); a single-use ticket authenticates
/// each WebSocket upgrade. Cookies live in the shared cookie jar, credentials in the Keychain.
struct GatewayAuth {
    let baseURL: URL
    let username: String
    let password: String

    private var session: URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }

    struct Status {
        let version: String?
        let authRequired: Bool
        let providers: [String]
    }

    func status() async throws -> Status {
        let (data, _) = try await session.data(for: request("GET", "/api/status"))
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return Status(version: obj["version"] as? String,
                      authRequired: obj["auth_required"] as? Bool ?? false,
                      providers: obj["auth_providers"] as? [String] ?? [])
    }

    /// Sign in with the stored credentials. The dashboard answers 401 for bad credentials,
    /// 404 when no password provider exists, 429 when rate limited.
    func login() async throws {
        guard !username.isEmpty, !password.isEmpty else { throw GatewayAuthError.notConfigured }
        var req = request("POST", "/auth/password-login")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "basic", "username": username, "password": password, "next": ""])
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return
        case 401: throw GatewayAuthError.badCredentials
        case 404: throw GatewayAuthError.noProvider
        default: throw GatewayAuthError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Mint a 30-second single-use WebSocket ticket, signing in first if the session is gone.
    func wsTicket() async throws -> String {
        if let t = try await mintTicket() { return t }
        try await login()
        guard let t = try await mintTicket() else { throw GatewayAuthError.badCredentials }
        return t
    }

    private func mintTicket() async throws -> String? {
        var req = request("POST", "/api/auth/ws-ticket")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { return nil }
        guard (200..<300).contains(code) else { throw GatewayAuthError.http(code, String(data: data, encoding: .utf8) ?? "") }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return obj?["ticket"] as? String
    }

    /// Ends the dashboard session and drops its cookies. Caller clears the Keychain.
    func logout() async {
        var req = request("POST", "/auth/logout")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        _ = try? await session.data(for: req)
        clearCookies()
    }

    func clearCookies() {
        let jar = HTTPCookieStorage.shared
        for c in jar.cookies(for: baseURL) ?? [] { jar.deleteCookie(c) }
    }

    func webSocketURL(ticket: String) -> URL {
        var comps = URLComponents(url: baseURL.appendingPathComponent("/api/ws"), resolvingAgainstBaseURL: false)!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        return comps.url!
    }

    private func request(_ method: String, _ path: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }
}
