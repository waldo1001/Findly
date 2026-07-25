import Foundation

/// The real `URLSession`-backed `FindlyAPIClient` (specs/004-ios-client.md §3). Every request sets
/// `Authorization: Bearer <token>` + `Content-Type: application/json; charset=utf-8` (specs/001
/// §1.2); device-originated calls additionally set `X-Device-Id`. On a decoded
/// `AUTH_TOKEN_EXPIRED`, the request is retried exactly once after a token refresh (specs/001
/// §2.1) — never more than once, and never for any other error code.
public final class URLSessionAPIClient: FindlyAPIClient {
    let baseURL: URL
    let session: URLSession
    let authProvider: AuthProviding
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    public init(baseURL: URL, authProvider: AuthProviding, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.authProvider = authProvider
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Request building (unit-testable without any network I/O)

    /// Builds the outgoing request. `path` is relative to `baseURL` (no leading slash), e.g.
    /// `"families/me"`. Internal (not `private`) so request-building tests can call it directly.
    func makeRequest(
        method: HTTPMethod,
        path: String,
        deviceId: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: Encodable? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            url = components.url!
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let token = try await authProvider.currentIDToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let deviceId {
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    // MARK: - Sending

    /// Sends a request expecting a `{data,features}` envelope on 2xx.
    func send<T: Decodable>(
        method: HTTPMethod,
        path: String,
        deviceId: String? = nil,
        queryItems: [URLQueryItem] = [],
        body: Encodable? = nil,
        allowRetry: Bool = true
    ) async throws -> Envelope<T> {
        let request = try await makeRequest(method: method, path: path, deviceId: deviceId, queryItems: queryItems, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("response was not an HTTPURLResponse")
        }
        if (200...299).contains(http.statusCode) {
            do {
                return try decoder.decode(Envelope<T>.self, from: data)
            } catch {
                throw APIError.decoding("\(error)")
            }
        }
        return try await handleErrorAndMaybeRetry(data: data, httpStatus: http.statusCode, allowRetry: allowRetry) {
            try await self.send(method: method, path: path, deviceId: deviceId, queryItems: queryItems, body: body, allowRetry: false)
        }
    }

    /// Sends a request expecting a bare 2xx with no body (specs/001 §3.6 — `removeMember`).
    func sendNoContent(
        method: HTTPMethod,
        path: String,
        deviceId: String? = nil,
        body: Encodable? = nil,
        allowRetry: Bool = true
    ) async throws {
        let request = try await makeRequest(method: method, path: path, deviceId: deviceId, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("response was not an HTTPURLResponse")
        }
        if (200...299).contains(http.statusCode) { return }
        try await handleErrorAndMaybeRetry(data: data, httpStatus: http.statusCode, allowRetry: allowRetry) {
            try await self.sendNoContent(method: method, path: path, deviceId: deviceId, body: body, allowRetry: false)
        }
    }

    /// Decodes the error envelope and, on `AUTH_TOKEN_EXPIRED` with a retry still available,
    /// refreshes the token and re-invokes `retry()` exactly once; otherwise throws `.server(...)`.
    private func handleErrorAndMaybeRetry<T>(
        data: Data, httpStatus: Int, allowRetry: Bool, retry: () async throws -> T
    ) async throws -> T {
        let decodedError: APIErrorBody
        do {
            decodedError = try decoder.decode(APIErrorEnvelope.self, from: data).error
        } catch {
            throw APIError.decoding("\(error)")
        }
        if allowRetry, decodedError.code == .authTokenExpired {
            _ = try await authProvider.refreshIDToken()
            return try await retry()
        }
        throw APIError.server(decodedError, httpStatus: httpStatus)
    }

    /// Sends a request expecting a RAW, unenveloped 2xx body (specs/001 §13.1 — the one exception
    /// to the §3.1 `{data,features}` envelope: `GET /export`'s success body is the export document
    /// itself). Error responses still decode through the standard `{error:{...}}` envelope, incl.
    /// the retry-once-on-`AUTH_TOKEN_EXPIRED` path — only the SUCCESS shape is special-cased here.
    func sendRawData(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        allowRetry: Bool = true
    ) async throws -> Data {
        let request = try await makeRequest(method: method, path: path, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("response was not an HTTPURLResponse")
        }
        if (200...299).contains(http.statusCode) {
            return data
        }
        return try await handleErrorAndMaybeRetry(data: data, httpStatus: http.statusCode, allowRetry: allowRetry) {
            try await self.sendRawData(method: method, path: path, queryItems: queryItems, allowRetry: false)
        }
    }

    /// Sends a request whose success path needs the raw `HTTPURLResponse` (specs/001 §7.1/§7.2 —
    /// the ETag lives in a response header, not the JSON body). `notModifiedIsSuccess` treats a
    /// bare `304` as success rather than routing it through error decoding (§7.1 only).
    func sendWithResponse<T: Decodable>(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: Encodable? = nil,
        extraHeaders: [String: String] = [:],
        notModifiedIsSuccess: Bool = false,
        allowRetry: Bool = true
    ) async throws -> (value: T?, response: HTTPURLResponse) {
        let request = try await makeRequest(method: method, path: path, queryItems: queryItems, body: body, extraHeaders: extraHeaders)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("response was not an HTTPURLResponse")
        }
        if notModifiedIsSuccess, http.statusCode == 304 {
            return (nil, http)
        }
        if (200...299).contains(http.statusCode) {
            do {
                return (try decoder.decode(T.self, from: data), http)
            } catch {
                throw APIError.decoding("\(error)")
            }
        }
        return try await handleErrorAndMaybeRetry(data: data, httpStatus: http.statusCode, allowRetry: allowRetry) {
            try await self.sendWithResponse(method: method, path: path, queryItems: queryItems, body: body, extraHeaders: extraHeaders, notModifiedIsSuccess: notModifiedIsSuccess, allowRetry: false)
        }
    }
}
