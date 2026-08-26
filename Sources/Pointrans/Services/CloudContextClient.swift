import Foundation

protocol InstallationIdentityProviding: Sendable {
    func installationID() async throws -> UUID
    func bearerToken() async throws -> String?
    func storeBearerToken(_ token: String) async throws
    func clearBearerToken() async throws
}

protocol HTTPTransporting: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransporting, Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudContextClient.ClientError.invalidResponse
        }
        return (data, http)
    }
}

actor CloudContextClient: CloudContextAnalyzing {
    private struct InstallationRequest: Encodable {
        let installationId: String
        let appVersion: String
    }

    private struct InstallationResponse: Decodable {
        let token: String
    }

    private struct ContextRequest: Encodable {
        let requestId: String
        let word: String
        let context: String
        let sourceLanguage: String
        let targetLanguage: String
    }

    private struct ContextResponse: Decodable {
        let insight: ContextInsight
        let remainingQuota: Int
        let resetAt: Date
    }

    private struct ErrorResponse: Decodable {
        let error: ErrorBody
        struct ErrorBody: Decodable {
            let code: String
            let details: Details?
        }
        struct Details: Decodable {
            let resetAt: Date?
        }
    }

    enum ClientError: Error, Sendable {
        case invalidConfiguration
        case invalidResponse
    }

    private let baseURL: URL
    private let identity: any InstallationIdentityProviding
    private let transport: any HTTPTransporting
    private let appVersion: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        identity: any InstallationIdentityProviding = InstallationIdentity(),
        transport: any HTTPTransporting = URLSessionTransport(),
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
    ) {
        self.baseURL = baseURL
        self.identity = identity
        self.transport = transport
        self.appVersion = appVersion
        decoder.dateDecodingStrategy = .iso8601
    }

    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult {
        guard Self.isValid(request.word, minimum: 1, maximum: 100),
              Self.isValid(request.context, minimum: 0, maximum: 600) else {
            throw ContextAnalyzerError.invalidInput
        }
        let token = try await validToken()
        do {
            return try await performContextRequest(request, token: token)
        } catch ContextAnalyzerError.unauthorized {
            try await identity.clearBearerToken()
            let replacement = try await validToken()
            return try await performContextRequest(request, token: replacement)
        }
    }

    private func validToken() async throws -> String {
        do {
            try Task.checkCancellation()
            if let existing = try await identity.bearerToken() { return existing }
            let installationID = try await identity.installationID()
            let url = baseURL.appending(path: "v1/installations")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(InstallationRequest(
                installationId: installationID.uuidString.lowercased(),
                appVersion: appVersion
            ))
            let (data, http) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard http.statusCode == 201 else {
                throw ContextAnalyzerError.unavailable
            }
            let payload = try decoder.decode(InstallationResponse.self, from: data)
            guard !payload.token.isEmpty else { throw ClientError.invalidResponse }
            try await identity.storeBearerToken(payload.token)
            return payload.token
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ContextAnalyzerError.transient
        } catch let error as ContextAnalyzerError {
            throw error
        } catch {
            throw ContextAnalyzerError.unavailable
        }
    }

    private func performContextRequest(_ translation: TranslationRequest, token: String) async throws -> InsightResult {
        try Task.checkCancellation()
        let url = baseURL.appending(path: "v1/context")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(ContextRequest(
            requestId: translation.id.uuidString.lowercased(),
            word: translation.word,
            context: translation.context,
            sourceLanguage: translation.direction.sourceLanguage,
            targetLanguage: translation.direction.targetLanguage
        ))

        do {
            let (data, http) = try await transport.data(for: request)
            try Task.checkCancellation()
            if http.statusCode == 200 {
                let value = try decoder.decode(ContextResponse.self, from: data)
                return InsightResult(
                    insight: value.insight,
                    route: .cloud,
                    remainingCloudQuota: value.remainingQuota,
                    quotaResetAt: value.resetAt
                )
            }
            throw try mapError(status: http.statusCode, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as ContextAnalyzerError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw ContextAnalyzerError.transient
        } catch {
            throw ContextAnalyzerError.unavailable
        }
    }

    private func mapError(status: Int, data: Data) throws -> ContextAnalyzerError {
        let payload = try? decoder.decode(ErrorResponse.self, from: data)
        return switch payload?.error.code {
        case "invalid_request": .invalidInput
        case "unauthorized": .unauthorized
        case "quota_exhausted": .quotaExhausted(resetAt: payload?.error.details?.resetAt)
        case "timeout", "upstream_unavailable": .transient
        default: status == 401 ? .unauthorized : .unavailable
        }
    }

    private static func isValid(_ value: String, minimum: Int, maximum: Int) -> Bool {
        let count = value.unicodeScalars.count
        return count >= minimum &&
            count <= maximum &&
            value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AppConfiguration {
    static func workerBaseURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: "PointransWorkerURL") as? String,
              let url = URL(string: raw),
              let scheme = url.scheme,
              scheme == "https" || (scheme == "http" && url.host == "127.0.0.1") else { return nil }
        return url
    }
}
