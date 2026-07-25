import Foundation

/// Intercepts `URLSession` traffic for request-building tests (specs/004-ios-client.md §9) — no
/// real network I/O. Install via a `URLSessionConfiguration` whose `protocolClasses` includes this
/// type, then set `requestHandler` to assert on the captured request and return a canned response.
final class MockURLProtocol: URLProtocol {
    struct NoHandlerConfigured: Error {}

    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NoHandlerConfigured())
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A minimal JSON success envelope body, `{ "data": <payload>, "features": <free-plan features> }`.
func envelopeJSON(data: String) -> Data {
    let json = """
    { "data": \(data),
      "features": { "subscriptionStatus": "free",
                    "limits": { "maxDevices": 10, "maxGeofences": 20, "historyDays": 90,
                                "minSyncIntervalMinutes": 5, "locateRequestsPerDay": 100 },
                    "flags": { "pushToLocate": true, "geofencing": true, "historyReplay": true } } }
    """
    return json.data(using: .utf8)!
}

func jsonResponse(url: URL, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}

/// `URLSession` sometimes converts `URLRequest.httpBody` into `httpBodyStream` before handing the
/// request to a `URLProtocol` — `request.httpBody` alone is not reliable inside `startLoading()`
/// (confirmed empirically: a naive `request.httpBody`-only read intermittently sees `nil` here).
func fullBody(of request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
