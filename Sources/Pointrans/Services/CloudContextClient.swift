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
    private struct InstallationRequest: Encodable {}

    private struct InstallationResponse: Decodable {
        let token: String
    }

    private struct ContextRequest: Encodable {
        let requestId: String
        let word: String
        let context: String
        let sourceLanguage: String
        let targetLanguage: String
        let targetStart: Int
        let targetLength: Int
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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        identity: any InstallationIdentityProviding = InstallationIdentity(),
        transport: any HTTPTransporting = URLSessionTransport()
    ) {
        self.baseURL = baseURL
        self.identity = identity
        self.transport = transport
        decoder.dateDecodingStrategy = .iso8601
    }

    func analyze(request: TranslationRequest, base: BaseTranslation) async throws -> InsightResult {
        guard Self.isValid(request.word, minimum: 1, maximum: 100),
              Self.isValid(request.context, minimum: 0, maximum: 600),
              Self.isValidTarget(request.targetUTF16Range, word: request.word, in: request.context) else {
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
            let url = baseURL.appending(path: "v1/installations")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(InstallationRequest())
            let (data, http) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard http.statusCode == 201 else {
                throw mapError(status: http.statusCode, data: data)
            }
            let payload = try decoder.decode(InstallationResponse.self, from: data)
            guard !payload.token.isEmpty else { throw ClientError.invalidResponse }
            try await identity.storeBearerToken(payload.token)
            return payload.token
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw ContextAnalyzerError.onlineUnavailable
        } catch let error as ContextAnalyzerError {
            throw error
        } catch {
            throw ContextAnalyzerError.onlineUnavailable
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
            targetLanguage: translation.direction.targetLanguage,
            targetStart: translation.targetUTF16Range?.location ?? 0,
            targetLength: translation.targetUTF16Range?.length ?? translation.word.utf16.count
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
            throw mapError(status: http.statusCode, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as ContextAnalyzerError {
            throw error
        } catch is URLError {
            throw ContextAnalyzerError.onlineUnavailable
        } catch {
            throw ContextAnalyzerError.onlineUnavailable
        }
    }

    private func mapError(status: Int, data: Data) -> ContextAnalyzerError {
        let payload = try? decoder.decode(ErrorResponse.self, from: data)
        return switch payload?.error.code {
        case "invalid_request": .onlineServiceIncompatible
        case "unauthorized": .unauthorized
        case "quota_exhausted": .quotaExhausted(resetAt: payload?.error.details?.resetAt)
        case "timeout", "upstream_unavailable": .onlineUnavailable
        default:
            if status == 401 { .unauthorized }
            else if status == 400 || status == 404 || status == 405 { .onlineServiceIncompatible }
            else { .onlineUnavailable }
        }
    }

    private static func isValid(_ value: String, minimum: Int, maximum: Int) -> Bool {
        let count = value.utf16.count
        return count >= minimum &&
            count <= maximum &&
            value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidTarget(_ range: NSRange?, word: String, in context: String) -> Bool {
        guard let range,
              range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= context.utf16.count,
              let stringRange = Range(range, in: context) else { return false }
        return String(context[stringRange]).localizedCaseInsensitiveCompare(word) == .orderedSame
    }
}

enum AppConfiguration {
    static func appVersion(bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !build.isEmpty else { return version }
        return "\(version)(\(build))"
    }

    static func workerBaseURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: "PointransWorkerURL") as? String,
              let url = URL(string: raw),
              let scheme = url.scheme,
              scheme == "https" || (scheme == "http" && url.host == "127.0.0.1") else { return nil }
        return url
    }
}
