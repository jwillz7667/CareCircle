import Foundation
import OSLog

// MARK: - APIClient

/// Actor-isolated HTTP client for the CareCircle Railway backend.
///
/// Owns the cached access/refresh token pair (durably backed by the
/// Keychain) and serializes refresh attempts so concurrent requests
/// share a single `/v1/auth/refresh` round-trip. Callers don't need to
/// reason about token freshness — `send` proactively refreshes a stale
/// access token before the request and retries once on a 401 reply.
actor APIClient {
    let tokenStore: BackendTokenStore

    private let configuration: BackendConfiguration
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var inFlightRefresh: Task<BackendTokens, Error>?

    init(
        configuration: BackendConfiguration,
        keychain: KeychainStore = KeychainStore(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIClient.isoFractionalFormatter.string(from: date))
        }
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = APIClient.isoFractionalFormatter.date(from: raw) {
                return date
            }
            if let date = APIClient.isoPlainFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO-8601 date: \(raw)"
            )
        }
        self.decoder = decoder
        tokenStore = BackendTokenStore(keychain: keychain, encoder: encoder, decoder: decoder)
    }

    // MARK: Request entry points

    func send<Response: Decodable & Sendable>(
        method: HTTPMethod,
        path: String,
        body: some Encodable & Sendable,
        authenticated: Bool = true
    ) async throws(APIError)
        -> Response
    {
        let payload = try encodeBody(body)
        let (data, _) = try await performRequest(
            method: method,
            path: path,
            body: payload,
            authenticated: authenticated,
            retryOnUnauthorized: true
        )
        return try decodeResponse(data)
    }

    func send<Response: Decodable & Sendable>(
        method: HTTPMethod,
        path: String,
        authenticated: Bool = true
    ) async throws(APIError)
        -> Response
    {
        let (data, _) = try await performRequest(
            method: method,
            path: path,
            body: nil,
            authenticated: authenticated,
            retryOnUnauthorized: true
        )
        return try decodeResponse(data)
    }

    func sendNoResponse(
        method: HTTPMethod,
        path: String,
        body: some Encodable & Sendable,
        authenticated: Bool = true
    ) async throws(APIError) {
        let payload = try encodeBody(body)
        _ = try await performRequest(
            method: method,
            path: path,
            body: payload,
            authenticated: authenticated,
            retryOnUnauthorized: true
        )
    }

    func sendNoResponse(
        method: HTTPMethod,
        path: String,
        authenticated: Bool = true
    ) async throws(APIError) {
        _ = try await performRequest(
            method: method,
            path: path,
            body: nil,
            authenticated: authenticated,
            retryOnUnauthorized: true
        )
    }

    /// Returns a guaranteed-fresh access token. Used by callers that
    /// can't piggy-back on the request pipeline — currently the
    /// realtime WebSocket, which needs to embed the token in the
    /// connect URL because URLSessionWebSocketTask has no per-request
    /// Authorization header hook before the upgrade.
    func freshAccessToken() async throws(APIError) -> String {
        let tokens = try await ensureFreshAccessToken()
        return tokens.accessToken
    }

    /// Returns the raw response bytes without JSON decoding. Used by the
    /// data-export flow, which downloads a binary ZIP rather than JSON.
    func sendForData(
        method: HTTPMethod,
        path: String,
        authenticated: Bool = true
    ) async throws(APIError)
        -> Data
    {
        let (data, _) = try await performRequest(
            method: method,
            path: path,
            body: nil,
            authenticated: authenticated,
            retryOnUnauthorized: true
        )
        return data
    }

    /// Sends a pre-encoded JSON body. Used by `SyncEngine` so it can
    /// assemble heterogeneous operation payloads with
    /// `JSONSerialization` without having to model every payload type at
    /// the encoder level.
    func sendRawJSON<Response: Decodable & Sendable>(
        method: HTTPMethod,
        path: String,
        body: Data,
        authenticated: Bool = true
    ) async throws(APIError)
        -> Response
    {
        let (data, _) = try await performRequest(
            method: method,
            path: path,
            body: body,
            authenticated: authenticated,
            retryOnUnauthorized: true
        )
        return try decodeResponse(data)
    }

    // MARK: Internal plumbing

    private func encodeBody(_ body: some Encodable) throws(APIError) -> Data {
        do {
            return try encoder.encode(body)
        } catch {
            throw .decoding(error)
        }
    }

    private func decodeResponse<Response: Decodable>(_ data: Data) throws(APIError) -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .decoding(error)
        }
    }

    private func performRequest(
        method: HTTPMethod,
        path: String,
        body: Data?,
        authenticated: Bool,
        retryOnUnauthorized: Bool
    ) async throws(APIError)
        -> (Data, HTTPURLResponse)
    {
        let request = try await buildRequest(
            method: method,
            path: path,
            body: body,
            authenticated: authenticated
        )
        let (data, httpResponse) = try await executeRequest(request)

        if httpResponse.statusCode == 401, authenticated, retryOnUnauthorized {
            do {
                _ = try await forceRefresh()
            } catch {
                await tokenStore.clearTokens()
                throw .refreshFailed
            }
            return try await performRequest(
                method: method,
                path: path,
                body: body,
                authenticated: authenticated,
                retryOnUnauthorized: false
            )
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            AppLogger.backend.notice(
                "HTTP \(httpResponse.statusCode, privacy: .public) on \(path, privacy: .public)"
            )
            throw .http(status: httpResponse.statusCode, body: bodyString)
        }

        return (data, httpResponse)
    }

    private func buildRequest(
        method: HTTPMethod,
        path: String,
        body: Data?,
        authenticated: Bool
    ) async throws(APIError)
        -> URLRequest
    {
        let url = configuration.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated {
            let tokens = try await ensureFreshAccessToken()
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func executeRequest(
        _ request: URLRequest
    ) async throws(APIError)
        -> (Data, HTTPURLResponse)
    {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.transport(URLError(.badServerResponse))
            }
            return (data, httpResponse)
        } catch let urlError as URLError {
            throw .transport(urlError)
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw .transport(URLError(.unknown))
        }
    }

    private func ensureFreshAccessToken() async throws(APIError) -> BackendTokens {
        guard let tokens = await tokenStore.currentTokens() else {
            throw .notAuthenticated
        }
        guard tokens.isAccessTokenStale else {
            return tokens
        }
        guard !tokens.isRefreshTokenExpired else {
            await tokenStore.clearTokens()
            throw .refreshFailed
        }
        do {
            return try await refresh(using: tokens.refreshToken)
        } catch let apiError as APIError {
            if apiError.isAuthFailure {
                await tokenStore.clearTokens()
            }
            throw apiError
        } catch {
            await tokenStore.clearTokens()
            throw .refreshFailed
        }
    }

    /// Forces a refresh even if the access token still looks fresh — used
    /// after a 401 response. Returns the new tokens or rethrows.
    private func forceRefresh() async throws(APIError) -> BackendTokens {
        guard let tokens = await tokenStore.currentTokens(), !tokens.isRefreshTokenExpired else {
            throw .refreshFailed
        }
        do {
            return try await refresh(using: tokens.refreshToken)
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw .refreshFailed
        }
    }

    private func refresh(using refreshToken: String) async throws -> BackendTokens {
        if let inFlight = inFlightRefresh {
            return try await inFlight.value
        }
        let task = Task { () throws -> BackendTokens in
            try await self.executeRefresh(refreshToken: refreshToken)
        }
        inFlightRefresh = task
        do {
            let tokens = try await task.value
            inFlightRefresh = nil
            return tokens
        } catch {
            inFlightRefresh = nil
            throw error
        }
    }

    private func executeRefresh(refreshToken: String) async throws -> BackendTokens {
        let request = RefreshAuthRequest(refreshToken: refreshToken)
        let payload: Data
        do {
            payload = try encoder.encode(request)
        } catch {
            throw APIError.decoding(error)
        }
        let (data, _) = try await performRequest(
            method: .post,
            path: "/v1/auth/refresh",
            body: payload,
            authenticated: false,
            retryOnUnauthorized: false
        )
        let response: BackendAuthResponse
        do {
            response = try decoder.decode(BackendAuthResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
        let tokens = BackendTokens(
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt,
            refreshToken: response.refreshToken,
            refreshTokenExpiresAt: response.refreshTokenExpiresAt,
            userId: response.userId
        )
        try await tokenStore.storeTokens(tokens)
        AppLogger.backend.info("Refreshed backend tokens.")
        return tokens
    }

    // MARK: Formatters

    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
