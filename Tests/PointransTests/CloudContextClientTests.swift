import CoreGraphics
import Foundation
import XCTest

final class CloudContextClientTests: XCTestCase {
    func testRegistersAnonymousInstallationAndReturnsStructuredCloudResult() async throws {
        let identity = MemoryInstallationIdentity(token: nil)
        let transport = QueuedHTTPTransport(steps: [
            .response(status: 201, body: #"{"token":"signed-token"}"#.data(using: .utf8)!),
            .response(status: 200, body: successBody(remaining: 29))
        ])
        let client = CloudContextClient(
            baseURL: URL(string: "https://pointrans.test")!,
            identity: identity,
            transport: transport
        )

        let result = try await client.analyze(request: request(), base: base())

        XCTAssertEqual(result.route, .cloud)
        XCTAssertEqual(result.insight.contextualMeaning, "持续拉扯")
        XCTAssertEqual(result.remainingCloudQuota, 29)
        let storedToken = await identity.token
        XCTAssertEqual(storedToken, "signed-token")

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.path), ["/v1/installations", "/v1/context"])
        XCTAssertEqual(requests[0].body, "{}")
        XCTAssertFalse(requests[0].body.contains("installationId"))
        XCTAssertFalse(requests[0].body.contains("appVersion"))
        XCTAssertFalse(requests[1].body.contains("dictionary hint"))
        XCTAssertFalse(requests[1].body.lowercased().contains("screenshot"))
        XCTAssertTrue(requests[1].body.contains("pulling"))
    }

    func testUnauthorizedTokenIsClearedReissuedAndRetriedOnce() async throws {
        let identity = MemoryInstallationIdentity(token: "expired-token")
        let transport = QueuedHTTPTransport(steps: [
            .response(status: 401, body: errorBody("unauthorized")),
            .response(status: 201, body: #"{"token":"fresh-token"}"#.data(using: .utf8)!),
            .response(status: 200, body: successBody(remaining: 28))
        ])
        let client = CloudContextClient(
            baseURL: URL(string: "https://pointrans.test")!,
            identity: identity,
            transport: transport
        )

        let result = try await client.analyze(request: request(), base: base())

        XCTAssertEqual(result.remainingCloudQuota, 28)
        let clearCount = await identity.clearCount
        let storedToken = await identity.token
        XCTAssertEqual(clearCount, 1)
        XCTAssertEqual(storedToken, "fresh-token")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.path), ["/v1/context", "/v1/installations", "/v1/context"])
        XCTAssertEqual(requests[0].authorization, "Bearer expired-token")
        XCTAssertEqual(requests[2].authorization, "Bearer fresh-token")
    }

    func testQuotaExhaustionPreservesUTCResetDate() async {
        let identity = MemoryInstallationIdentity(token: "valid-token")
        let body = #"{"error":{"code":"quota_exhausted","details":{"resetAt":"2026-08-26T00:00:00Z"}}}"#.data(using: .utf8)!
        let transport = QueuedHTTPTransport(steps: [.response(status: 429, body: body)])
        let client = CloudContextClient(
            baseURL: URL(string: "https://pointrans.test")!,
            identity: identity,
            transport: transport
        )

        do {
            _ = try await client.analyze(request: request(), base: base())
            XCTFail("Expected quota exhaustion")
        } catch let error as ContextAnalyzerError {
            guard case .quotaExhausted(let resetAt) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(resetAt, ISO8601DateFormatter().date(from: "2026-08-26T00:00:00Z"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOfflineTimeoutAndCancellationRemainDistinct() async {
        for (code, expected) in [
            (URLError.notConnectedToInternet, ContextAnalyzerError.onlineUnavailable),
            (URLError.timedOut, ContextAnalyzerError.onlineUnavailable)
        ] {
            let identity = MemoryInstallationIdentity(token: "valid-token")
            let transport = QueuedHTTPTransport(steps: [.urlFailure(code)])
            let client = CloudContextClient(
                baseURL: URL(string: "https://pointrans.test")!,
                identity: identity,
                transport: transport
            )
            do {
                _ = try await client.analyze(request: request(), base: base())
                XCTFail("Expected network failure")
            } catch let error as ContextAnalyzerError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        let identity = MemoryInstallationIdentity(token: "valid-token")
        let transport = QueuedHTTPTransport(steps: [.urlFailure(.cancelled)])
        let client = CloudContextClient(
            baseURL: URL(string: "https://pointrans.test")!,
            identity: identity,
            transport: transport
        )
        do {
            _ = try await client.analyze(request: request(), base: base())
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLegacyInstallationContractIsReportedAsServiceIncompatible() async {
        let identity = MemoryInstallationIdentity(token: nil)
        let transport = QueuedHTTPTransport(steps: [
            .response(status: 400, body: errorBody("invalid_request"))
        ])
        let client = CloudContextClient(
            baseURL: URL(string: "https://pointrans.test")!,
            identity: identity,
            transport: transport
        )

        do {
            _ = try await client.analyze(request: request(), base: base())
            XCTFail("Expected an incompatible service contract")
        } catch let error as ContextAnalyzerError {
            XCTAssertEqual(error, .onlineServiceIncompatible)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.path), ["/v1/installations"])
        XCTAssertEqual(requests.first?.body, "{}")
    }

    func testInvalidInputNeverTouchesIdentityOrNetwork() async {
        let identity = MemoryInstallationIdentity(token: "valid-token")
        let transport = QueuedHTTPTransport(steps: [])
        let client = CloudContextClient(
            baseURL: URL(string: "https://pointrans.test")!,
            identity: identity,
            transport: transport
        )

        var invalid = request()
        invalid = TranslationRequest(
            id: invalid.id,
            screenPoint: invalid.screenPoint,
            displayID: invalid.displayID,
            word: "   ",
            context: invalid.context,
            direction: invalid.direction,
            createdAt: invalid.createdAt
        )
        do {
            _ = try await client.analyze(request: invalid, base: base())
            XCTFail("Expected invalid input")
        } catch let error as ContextAnalyzerError {
            XCTAssertEqual(error, .invalidInput)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    private func request() -> TranslationRequest {
        TranslationRequest(
            id: UUID(uuidString: "f4925390-e904-4d78-a899-6ce8c2ad6d41")!,
            screenPoint: CGPoint(x: 120, y: 240),
            displayID: 1,
            word: "pulling",
            context: "She kept pulling the thread.",
            targetUTF16Range: NSRange(location: 9, length: 7),
            direction: .englishToChinese,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func base() -> BaseTranslation {
        BaseTranslation(
            meanings: ["dictionary hint"],
            deviceTranslation: nil,
            phonetic: nil,
            pinyin: nil,
            source: .dictionary
        )
    }

    private func successBody(remaining: Int) -> Data {
        """
        {"insight":{"contextualMeaning":"持续拉扯","partOfSpeech":"verb","explanation":"语境解释","contextTranslation":"她持续拉扯线。"},"remainingQuota":\(remaining),"resetAt":"2026-08-26T00:00:00Z"}
        """.data(using: .utf8)!
    }

    private func errorBody(_ code: String) -> Data {
        #"{"error":{"code":"\#(code)"}}"#.data(using: .utf8)!
    }
}

private actor MemoryInstallationIdentity: InstallationIdentityProviding {
    let id = UUID(uuidString: "2f9050b8-4fd6-4c48-84ec-12fc596b8c45")!
    private(set) var token: String?
    private(set) var clearCount = 0

    init(token: String?) {
        self.token = token
    }

    func installationID() async throws -> UUID { id }
    func bearerToken() async throws -> String? { token }
    func storeBearerToken(_ token: String) async throws { self.token = token }
    func clearBearerToken() async throws {
        token = nil
        clearCount += 1
    }
}

private actor QueuedHTTPTransport: HTTPTransporting {
    enum Step: Sendable {
        case response(status: Int, body: Data)
        case urlFailure(URLError.Code)
    }
    enum StubError: Error, Sendable { case exhausted }

    struct RecordedRequest: Equatable, Sendable {
        let path: String
        let authorization: String?
        let body: String
    }

    private var steps: [Step]
    private(set) var requests: [RecordedRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(RecordedRequest(
            path: request.url?.path ?? "",
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        ))
        guard !steps.isEmpty else { throw StubError.exhausted }
        switch steps.removeFirst() {
        case .response(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (body, response)
        case .urlFailure(let code):
            throw URLError(code)
        }
    }
}
