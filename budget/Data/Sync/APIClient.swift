import Foundation
import OSLog

enum APIError: LocalizedError {
    case http(Int, String)
    case notAuthenticated
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(_, let message): return message
        case .notAuthenticated:     return NSLocalizedString("Session expirée. Reconnecte-toi.", comment: "")
        case .invalidResponse:      return NSLocalizedString("Réponse serveur invalide.", comment: "")
        }
    }
}

final class APIClient: Sendable {
    static let shared = APIClient()

    static let accessTokenKey = "auth.accessToken"
    static let refreshTokenKey = "auth.refreshToken"

    private init() {}

    private struct ErrorEnvelope: Decodable {
        let success: Bool
        let error: String?
    }

    static let sessionInvalidatedNotification = Notification.Name("BudgetSessionInvalidated")

    private static let sensitiveKeys = [
        "access_token", "refresh_token", "identity_token", "id_token", "password", "token"
    ]

    private static let scrubRegexes: [(key: String, regex: NSRegularExpression)] = {
        sensitiveKeys.compactMap { key in
            let pattern = "\"\(key)\"\\s*:\\s*\"[^\"]*\""
            guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (key, r)
        }
    }()

    private static func scrubSensitive(_ raw: String) -> String {
        var s = raw
        for (key, regex) in scrubRegexes {
            s = regex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s),
                withTemplate: "\"\(key)\":\"<scrubbed>\""
            )
        }
        return s
    }

    // MARK: — Requête générique

    func send<T: Decodable>(
        _ type: T.Type,
        method: String,
        path: String,
        query: [String: String] = [:],
        body: (any Encodable)? = nil,
        authenticated: Bool = true,
        // Device-bound session model. App Attest assertion proves the request comes from the
        // genuine attested device; verifying it costs a Secure Enclave signature per call. We
        // require it on mutations (POST/PUT/PATCH/DELETE), where replay/forgery matters, and skip
        // it on reads (GET), which are frequent and low-risk — mirrors the backend's per-route
        // requiresAssertion. Default derives from the HTTP method; pass an explicit value to
        // override (pre-session auth endpoints and logout send false despite being POST).
        assertion: Bool? = nil
    ) async throws -> T {
        let useAssertion = assertion ?? (method.uppercased() != "GET")
        let data = try await sendRaw(
            method: method, path: path, query: query, body: body,
            authenticated: authenticated, assertion: useAssertion, allowRefresh: true
        )
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func sendRaw(
        method: String,
        path: String,
        query: [String: String],
        body: (any Encodable)?,
        authenticated: Bool,
        assertion: Bool,
        allowRefresh: Bool
    ) async throws -> Data {
        var components = URLComponents(
            url: APIConfig.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var bodyData: Data?
        if let body {
            bodyData = try JSONEncoder().encode(body)
            request.httpBody = bodyData
        }

        let started = Date()
        AppLogger.sync.debug("→ \(method, privacy: .public) \(components.url?.absoluteString ?? path, privacy: .public)")
        if let bodyData, bodyData.count < 2048, let s = String(data: bodyData, encoding: .utf8) {
            AppLogger.sync.debug("  body: \(Self.scrubSensitive(s), privacy: .private)")
        }

        let rawQuery = components.percentEncodedQuery ?? ""
        if assertion {
            let headers = try await AppAttestClient.shared.assertionHeaders(
                method: method, path: path, query: rawQuery, body: bodyData
            )
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        } else {
            try await AppAttestClient.shared.ensureAttested()
            if let keyId = AppAttestClient.shared.keyId {
                request.setValue(keyId, forHTTPHeaderField: "X-Key-Id")
            }
        }

        var usedAccessToken: String?
        if authenticated {
            guard let token = KeychainStore.get(Self.accessTokenKey) else {
                throw APIError.notAuthenticated
            }
            usedAccessToken = token
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            AppLogger.sync.error("✗ \(method, privacy: .public) \(path, privacy: .public) → \(error.localizedDescription, privacy: .public) (\(elapsed)ms)")
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        let preview: String
        if data.count < 2048, let s = String(data: data, encoding: .utf8) {
            preview = Self.scrubSensitive(s)
        } else {
            preview = "\(data.count) bytes"
        }
        AppLogger.sync.debug("← \(http.statusCode, privacy: .public) \(method, privacy: .public) \(path, privacy: .public) (\(elapsed)ms) \(preview, privacy: .private)")

        if http.statusCode == 401, authenticated, allowRefresh {
            do {
                // Single-flight: concurrent 401s collapse into one refresh. The refresh token
                // is single-use/rotating server-side, so parallel refreshes would revoke each
                // other and force a spurious logout. Callers that lost the race just retry with
                // the freshly stored token.
                try await TokenRefreshCoordinator.shared.refreshIfNeeded(staleAccessToken: usedAccessToken) {
                    try await self.refreshTokens()
                }
            } catch {
                await invalidateSession()
                throw APIError.notAuthenticated
            }
            return try await sendRaw(
                method: method, path: path, query: query, body: body,
                authenticated: authenticated, assertion: assertion, allowRefresh: false
            )
        }

        if http.statusCode == 401, authenticated, !allowRefresh {
            // 401 even after a fresh refresh — refresh token is revoked or expired. End the session.
            await invalidateSession()
            throw APIError.notAuthenticated
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error
                ?? String(format: NSLocalizedString("Erreur serveur (%d).", comment: ""), http.statusCode)
            throw APIError.http(http.statusCode, message)
        }

        return data
    }

    // MARK: — Tokens

    struct TokenPair: Decodable {
        let accessToken: String
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    func storeTokens(access: String, refresh: String) {
        KeychainStore.set(access, for: Self.accessTokenKey)
        KeychainStore.set(refresh, for: Self.refreshTokenKey)
    }

    func clearTokens() {
        KeychainStore.delete(Self.accessTokenKey)
        KeychainStore.delete(Self.refreshTokenKey)
    }

    private func invalidateSession() async {
        // Only clear auth tokens. The App Attest key is independent of session validity —
        // resetting it here forces a needless key rotation, which restarts the Secure Enclave
        // counter and breaks assertions until the server-side counter catches up. Stale keyId
        // recovery is already handled in AppAttestClient on DCError.invalidInput.
        clearTokens()
        await MainActor.run {
            NotificationCenter.default.post(name: Self.sessionInvalidatedNotification, object: nil)
        }
    }

    var hasTokens: Bool {
        KeychainStore.get(Self.accessTokenKey) != nil
    }

    private func refreshTokens() async throws {
        guard let refreshToken = KeychainStore.get(Self.refreshTokenKey) else {
            throw APIError.notAuthenticated
        }

        struct RefreshResponse: Decodable {
            let success: Bool
            let accessToken: String?
            let refreshToken: String?

            enum CodingKeys: String, CodingKey {
                case success
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
            }
        }

        do {
            let response: RefreshResponse = try await send(
                RefreshResponse.self,
                method: "POST",
                path: "/budget/auth/refresh",
                body: ["refresh_token": refreshToken],
                authenticated: false,
                assertion: true
            )
            guard response.success, let access = response.accessToken, let refresh = response.refreshToken else {
                clearTokens()
                throw APIError.notAuthenticated
            }
            storeTokens(access: access, refresh: refresh)
        } catch {
            clearTokens()
            throw APIError.notAuthenticated
        }
    }
}

/// Collapses concurrent token refreshes into a single network call.
///
/// The backend rotates refresh tokens single-use (the old one is revoked the moment it's
/// consumed). Without this gate, several requests hitting 401 at once would each fire a
/// refresh with the same stale refresh token — the first wins, the rest get
/// "Invalid or expired refresh token" and trigger a spurious logout.
actor TokenRefreshCoordinator {
    static let shared = TokenRefreshCoordinator()

    private var inFlight: Task<Void, Error>?

    private init() {}

    /// - Parameter staleAccessToken: the access token that produced the 401. If the stored
    ///   token already differs, another caller has refreshed — we skip and let the caller retry.
    func refreshIfNeeded(
        staleAccessToken: String?,
        perform: @Sendable @escaping () async throws -> Void
    ) async throws {
        if let current = KeychainStore.get(APIClient.accessTokenKey), current != staleAccessToken {
            return
        }
        if let task = inFlight {
            try await task.value
            return
        }
        let task = Task { try await perform() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}
