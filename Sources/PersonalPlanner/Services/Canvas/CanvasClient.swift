import Foundation

/// How PersonalPlanner authenticates to Canvas. Both are read-only uses of the student's own access.
public enum CanvasAuth: Equatable {
    /// Cookies captured after signing in through the in-app Canvas login window (school SSO / 2FA included).
    case session(cookies: [StoredCookie])
    /// A personal access token, for schools that allow them.
    case token(String)
    /// A signed-in Canvas tab in the user's own browser (nothing stored by PersonalPlanner).
    case browser(CanvasBrowser)
}

/// Codable copy of an HTTP cookie, kept in Keychain (never logged).
public struct StoredCookie: Codable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool
    public let expires: Date?

    public init(name: String, value: String, domain: String, path: String, isSecure: Bool, expires: Date?) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
        self.expires = expires
    }

    public init(_ cookie: HTTPCookie) {
        self.init(name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path, isSecure: cookie.isSecure, expires: cookie.expiresDate)
    }

    /// Whether this cookie is sent to `host` (exact match or a parent domain such as ".school.edu").
    public func applies(to host: String) -> Bool {
        let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        let h = host.lowercased()
        return h == d.lowercased() || h.hasSuffix("." + d.lowercased())
    }
}

public struct CanvasError: LocalizedError, Equatable {
    public enum Kind: Equatable {
        /// Login expired or token rejected: the user must reconnect. Stops a sync.
        case signInRequired
        /// Bad Canvas address or not a Canvas site. Stops a sync.
        case setup
        /// Network or server problem for one request.
        case network
        /// Canvas returned something that is not the expected JSON.
        case invalidResponse
    }
    public let kind: Kind
    public let message: String
    public var errorDescription: String? { message }

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// Sends one GET request. URLSession by default; the in-app sign-in uses a hidden browser engine
/// (`CanvasWebFetcher`) so Canvas sees exactly the requests it saw during sign-in.
public typealias CanvasTransport = (URLRequest) async throws -> (Data, URLResponse)

/// Minimal read-only Canvas REST client. Only GET requests are ever made.
@MainActor
public final class CanvasClient {
    public let baseURL: URL
    private let auth: CanvasAuth
    private let session: URLSession
    private let transport: CanvasTransport?
    /// Safety cap so one huge list can't stall a sync.
    private let maxPages: Int

    public init(baseURL: URL, auth: CanvasAuth, session: URLSession = .shared, maxPages: Int = 10, transport: CanvasTransport? = nil) {
        self.baseURL = baseURL
        self.auth = auth
        self.session = session
        self.maxPages = maxPages
        self.transport = transport
    }

    /// Normalizes what the user typed ("canvas.school.edu", "https://canvas.school.edu/courses") to the site root.
    public nonisolated static func normalizedBaseURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text), let host = components.host, host.contains(".") else { return nil }
        components.scheme = "https"
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.host = host.lowercased()
        return components.url
    }

    /// True if `baseURL` is a Canvas site: its API answers signed-out requests with a JSON
    /// "unauthenticated / user authorization required" error (or succeeds).
    public static func looksLikeCanvas(_ baseURL: URL, session: URLSession = .shared) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/users/self"))
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        let isJSON = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json")
        if http.statusCode == 200 && isJSON { return true }
        let body = String(data: data.prefix(500), encoding: .utf8)?.lowercased() ?? ""
        return http.statusCode == 401 && isJSON && (body.contains("unauthenticated") || body.contains("authorization required"))
    }

    // MARK: Requests

    /// GET a single JSON object or array.
    public func get(_ path: String, query: [URLQueryItem] = []) async throws -> Any {
        let (json, _) = try await fetch(url(path, query: query))
        return json
    }

    /// GET a paginated JSON array, following `Link: <...>; rel="next"` up to `maxPages`.
    public func getAll(_ path: String, query: [URLQueryItem] = []) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var next: URL? = url(path, query: query + [URLQueryItem(name: "per_page", value: "100")])
        var pages = 0
        while let pageURL = next, pages < maxPages {
            let (json, response) = try await fetch(pageURL)
            guard let array = json as? [[String: Any]] else {
                throw CanvasError(kind: .invalidResponse, message: "Canvas returned an unexpected list from \(path).")
            }
            results += array
            next = Self.nextPageURL(from: response.value(forHTTPHeaderField: "Link"))
            pages += 1
        }
        return results
    }

    func url(_ path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/" + path
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    private func fetch(_ url: URL) async throws -> (Any, HTTPURLResponse) {
        // Your token or cookies only ever go to your Canvas site over https, even if a
        // "next page" link points somewhere else.
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == baseURL.host?.lowercased() else {
            throw CanvasError(kind: .invalidResponse, message: "Canvas pointed to another site (\(url.host ?? "unknown")); it wasn't contacted.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        switch auth {
        case .token(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .session(let cookies):
            let host = url.host ?? ""
            let header = cookies
                .filter { $0.applies(to: host) && ($0.expires.map { $0 > Date() } ?? true) }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            request.setValue(header, forHTTPHeaderField: "Cookie")
        case .browser:
            break // the browser tab supplies its own sign-in
        }

        let data: Data
        let response: URLResponse
        do {
            if let transport = transport {
                (data, response) = try await transport(request)
            } else {
                (data, response) = try await session.data(for: request, delegate: SameHostRedirectGuard())
            }
        } catch let canvasError as CanvasError {
            throw canvasError
        } catch let urlError as URLError where urlError.code == .cannotFindHost || urlError.code == .badURL {
            throw CanvasError(kind: .setup, message: "Couldn't find a Canvas site at \(baseURL.host ?? baseURL.absoluteString). Check the address in Settings.")
        } catch {
            throw CanvasError(kind: .network, message: "Couldn't reach Canvas: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw CanvasError(kind: .network, message: "No response from Canvas.")
        }
        // A login redirect lands on an HTML page instead of JSON, which also means the session ended.
        let isHTML = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/html")
        if http.statusCode == 401 || (isHTML && (http.url?.path.contains("login") ?? false)) {
            throw CanvasError(kind: .signInRequired, message: "Your Canvas sign-in has expired. Reconnect Canvas in Settings.")
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 404 && url.path.hasSuffix("/users/self") {
                throw CanvasError(kind: .setup, message: "\(baseURL.host ?? "") doesn't look like a Canvas site. Check the address in Settings.")
            }
            throw CanvasError(kind: .network, message: "Canvas returned an error (\(http.statusCode)) for \(url.path).")
        }
        return (try Self.parseJSON(data), http)
    }

    /// Canvas prefixes JSON with `while(1);` for cookie-authenticated requests (JSON hijacking protection).
    nonisolated static func parseJSON(_ data: Data) throws -> Any {
        var body = data
        let prefix = Data("while(1);".utf8)
        if body.starts(with: prefix) { body = body.dropFirst(prefix.count) }
        do {
            return try JSONSerialization.jsonObject(with: body)
        } catch {
            throw CanvasError(kind: .invalidResponse, message: "Canvas returned a page that isn't JSON. If this keeps happening, reconnect Canvas.")
        }
    }

    nonisolated static func nextPageURL(from linkHeader: String?) -> URL? {
        guard let header = linkHeader else { return nil }
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains(where: { $0 == "rel=\"next\"" }) else { continue }
            let link = pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            return URL(string: link)
        }
        return nil
    }
}

/// Drops the Authorization and Cookie headers when Canvas redirects to a different host
/// (or away from https), so a token or session cookie is never handed to another site.
final class SameHostRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let fromHost = task.originalRequest?.url?.host?.lowercased()
        let sameSite = request.url?.host?.lowercased() == fromHost && request.url?.scheme?.lowercased() == "https"
        guard !sameSite else { return completionHandler(request) }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        stripped.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(stripped)
    }
}
