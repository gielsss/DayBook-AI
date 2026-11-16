import Foundation

public enum OllamaDefaults {
    public static let baseURL = "http://localhost:11434"
    /// One vision-capable model handles email text, Quick Capture screenshots and receipt photos.
    public static let model = "qwen3-vl:8b"
    /// Context window requested from Ollama. Its built-in default is small enough to silently cut long inputs.
    public static let contextTokens = 16384
    /// Rough character budget for an email body so prompt + answer fit inside `contextTokens`.
    public static let bodyCharacterLimit = 24000
}

/// Errors from the local AI (Ollama). `isFatalForScan` errors would fail every email the same way.
public struct AIServiceError: LocalizedError, Equatable {
    public enum Kind: Equatable {
        /// Ollama not running, model not downloaded, or bad address. Fatal for a whole scan.
        case setupRequired
        /// Malformed request (400). Fatal for a whole scan.
        case invalidRequest
        /// Ollama internal error (5xx) after retries.
        case serverError
        /// Connection problem or timeout after retries.
        case network
        /// Answer was cut off or did not match the expected JSON.
        case invalidResponse
    }

    public let kind: Kind
    public let statusCode: Int
    public let message: String

    public init(kind: Kind, statusCode: Int, message: String) {
        self.kind = kind
        self.statusCode = statusCode
        self.message = message
    }

    public var isFatalForScan: Bool {
        kind == .setupRequired || kind == .invalidRequest
    }

    /// Worth retrying inside a single request. A garbled answer from a small local model often succeeds on a second try.
    public var isRetryable: Bool {
        kind == .serverError || kind == .network || kind == .invalidResponse
    }

    public var errorDescription: String? { message }
}

/// Minimal client for a local Ollama server (`/api/chat`, `/api/tags`, `/api/show`).
/// Nothing leaves the Mac and no API key is involved.
@MainActor
public final class OllamaClient {
    private let session: URLSession
    private let maxAttempts: Int
    private let retryDelay: Double
    private let sleeper: (Double) async throws -> Void

    public init(
        session: URLSession = .shared,
        maxAttempts: Int = 3,
        retryDelay: Double = 3.0,
        sleeper: ((Double) async throws -> Void)? = nil
    ) {
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelay = retryDelay
        self.sleeper = sleeper ?? { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    // MARK: Request building

    nonisolated static func endpoint(_ baseURL: String, path: String) throws -> URL {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = OllamaDefaults.baseURL }
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            throw AIServiceError(kind: .setupRequired, statusCode: 0, message: "Ollama address \"\(baseURL)\" is not a valid URL. Use \(OllamaDefaults.baseURL).")
        }
        // Emails, Canvas text and screenshots only go to Ollama on this Mac, or to a server over https.
        let onThisMac = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard scheme == "https" || (scheme == "http" && onThisMac) else {
            throw AIServiceError(kind: .setupRequired, statusCode: 0, message: "Ollama address \"\(baseURL)\" isn't on this Mac and isn't https, so nothing was sent. Use \(OllamaDefaults.baseURL).")
        }
        return url
    }

    nonisolated static func buildChatBody(model: String, system: String, user: String, images: [Data], schema: [String: Any], disableThinking: Bool = false) -> [String: Any] {
        var userMessage: [String: Any] = ["role": "user", "content": user]
        if !images.isEmpty {
            userMessage["images"] = images.map { $0.base64EncodedString() }
        }
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": schema,
            "messages": [
                ["role": "system", "content": system],
                userMessage
            ],
            "options": [
                "temperature": 0,
                "num_ctx": OllamaDefaults.contextTokens
            ]
        ]
        // Thinking models (e.g. qwen3) otherwise reason at length first: measured 151s vs 34s for one capture.
        // Only sent to models that report "thinking"; others reject the field.
        if disableThinking { body["think"] = false }
        return body
    }

    // MARK: Chat

    /// Sends one chat request constrained to `schema` and returns the model's JSON text.
    public func chat(
        baseURL: String,
        model: String,
        system: String,
        user: String,
        images: [Data] = [],
        schema: [String: Any],
        decode: ((String) throws -> Void)? = nil,
        checkCancellation: (() -> Bool)? = nil,
        onRetry: ((String) -> Void)? = nil
    ) async throws -> String {
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? OllamaDefaults.model : model
        let caps = await cachedCapabilities(baseURL: baseURL, model: resolvedModel)
        let body = Self.buildChatBody(model: resolvedModel, system: system, user: user, images: images, schema: schema, disableThinking: caps.contains("thinking"))

        var request = URLRequest(url: try Self.endpoint(baseURL, path: "/api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        // Local models can be slow, especially on the first request while the model loads.
        request.timeoutInterval = 600

        var lastError: AIServiceError? = nil
        for attempt in 1...maxAttempts {
            if checkCancellation?() == true { throw CancellationError() }
            do {
                let (data, response) = try await session.data(for: request)
                if checkCancellation?() == true { throw CancellationError() }
                guard let http = response as? HTTPURLResponse else {
                    throw AIServiceError(kind: .network, statusCode: 0, message: "No HTTP response from Ollama.")
                }
                guard (200...299).contains(http.statusCode) else {
                    throw Self.classify(statusCode: http.statusCode, data: data, model: resolvedModel)
                }
                let text = try Self.extractContent(fromResponse: data)
                // Let the caller validate the JSON inside the retry loop so a garbled answer gets another try.
                try decode?(text)
                return text
            } catch let error as AIServiceError {
                guard error.isRetryable else { throw error }
                lastError = error
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError {
                switch urlError.code {
                case .cancelled:
                    throw CancellationError()
                case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                    throw Self.notRunningError()
                case .timedOut:
                    lastError = AIServiceError(kind: .network, statusCode: 0, message: "Ollama took longer than 10 minutes to answer.")
                default:
                    lastError = AIServiceError(kind: .network, statusCode: 0, message: "Could not reach Ollama: \(urlError.localizedDescription)")
                }
            } catch {
                lastError = AIServiceError(kind: .network, statusCode: 0, message: "Could not reach Ollama: \(error.localizedDescription)")
            }

            guard attempt < maxAttempts, let pending = lastError else { break }
            onRetry?("\(pending.message) Retrying (attempt \(attempt + 1) of \(maxAttempts))...")
            try await sleeper(retryDelay)
        }

        let final = lastError ?? AIServiceError(kind: .network, statusCode: 0, message: "Ollama request failed.")
        throw AIServiceError(kind: final.kind, statusCode: final.statusCode, message: "\(final.message) (gave up after \(maxAttempts) attempts)")
    }

    // MARK: Model management

    public func installedModels(baseURL: String) async throws -> [String] {
        var request = URLRequest(url: try Self.endpoint(baseURL, path: "/api/tags"))
        request.timeoutInterval = 5
        let data = try await fetch(request, unexpected: "Ollama answered unexpectedly at \(baseURL).")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// Capabilities reported by Ollama for a model, e.g. ["completion", "vision"].
    public func capabilities(baseURL: String, model: String) async throws -> [String] {
        var request = URLRequest(url: try Self.endpoint(baseURL, path: "/api/show"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        request.timeoutInterval = 10
        let data = try await fetch(request, unexpected: "Ollama could not describe model \"\(model)\".")
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["capabilities"] as? [String] ?? []
    }

    /// Whether the model can read images. Cached per model; `false` if Ollama can't describe it
    /// (callers then fall back to on-device text recognition, which works with any model).
    public func supportsVision(baseURL: String, model: String) async -> Bool {
        await cachedCapabilities(baseURL: baseURL, model: model).contains("vision")
    }

    /// Capabilities per model, cached after the first successful lookup. Empty if Ollama can't describe the model.
    func cachedCapabilities(baseURL: String, model: String) async -> [String] {
        let key = baseURL + "|" + model
        if let cached = capabilityCache[key] { return cached }
        guard let caps = try? await capabilities(baseURL: baseURL, model: model) else { return [] }
        capabilityCache[key] = caps
        return caps
    }

    private var capabilityCache: [String: [String]] = [:]

    private func fetch(_ request: URLRequest, unexpected: String) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AIServiceError(kind: .setupRequired, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: unexpected)
            }
            return data
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw Self.notRunningError()
        }
    }

    // MARK: Helpers

    /// Ollama treats "name" and "name:latest" as the same model.
    nonisolated static func isInstalled(_ model: String, in installed: [String]) -> Bool {
        let wanted = model.contains(":") ? model : model + ":latest"
        return installed.contains(model) || installed.contains(wanted)
    }

    nonisolated static func notRunningError() -> AIServiceError {
        AIServiceError(kind: .setupRequired, statusCode: 0, message: "Ollama isn't running. Open the Ollama app (llama icon in the menu bar), then try again.")
    }

    nonisolated static func modelMissingError(_ model: String, installed: [String]) -> AIServiceError {
        let have = installed.isEmpty ? "No models are downloaded yet." : "Downloaded models: \(installed.joined(separator: ", "))."
        return AIServiceError(kind: .setupRequired, statusCode: 404, message: "Model \"\(model)\" isn't downloaded. Run `ollama pull \(model)` in Terminal. \(have)")
    }

    nonisolated static func extractContent(fromResponse data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError(kind: .invalidResponse, statusCode: 200, message: "Ollama returned a response that was not valid JSON.")
        }
        if (json["done_reason"] as? String) == "length" {
            throw AIServiceError(kind: .invalidResponse, statusCode: 200, message: "Ollama's answer was cut off before it finished.")
        }
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError(kind: .invalidResponse, statusCode: 200, message: "Ollama returned no answer text.")
        }
        return content
    }

    nonisolated static func classify(statusCode: Int, data: Data, model: String) -> AIServiceError {
        var apiMessage = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let message = json["error"] as? String {
            apiMessage = message
        }
        let lower = apiMessage.lowercased()
        if statusCode == 404 || (lower.contains("model") && lower.contains("not found")) {
            return modelMissingError(model, installed: [])
        }
        let suffix = apiMessage.isEmpty ? "" : ": \(apiMessage)"
        if statusCode == 400 {
            if lower.contains("image") || lower.contains("vision") || lower.contains("multimodal") {
                return AIServiceError(kind: .setupRequired, statusCode: statusCode, message: "Model \"\(model)\" can't read images. Choose a vision model such as \(OllamaDefaults.model) in Settings\(suffix)")
            }
            return AIServiceError(kind: .invalidRequest, statusCode: statusCode, message: "Ollama rejected the request (400)\(suffix)")
        }
        if statusCode >= 500 {
            return AIServiceError(kind: .serverError, statusCode: statusCode, message: "Ollama had an internal error (\(statusCode))\(suffix)")
        }
        return AIServiceError(kind: .invalidRequest, statusCode: statusCode, message: "Unexpected Ollama response (\(statusCode))\(suffix)")
    }

    /// Decodes JSON text into `T`, reporting a schema mismatch as a retryable `.invalidResponse`.
    nonisolated static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String, what: String) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw AIServiceError(kind: .invalidResponse, statusCode: 200, message: "Ollama returned text that could not be read.")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AIServiceError(kind: .invalidResponse, statusCode: 200, message: "Ollama's \(what) did not match the expected format: \(error.localizedDescription)")
        }
    }

    /// Helper for building JSON schemas: a nullable field of the given JSON type.
    nonisolated static func nullable(_ type: String) -> [String: Any] {
        ["anyOf": [["type": type], ["type": "null"]]]
    }
}
