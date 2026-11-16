import Foundation
import AppKit
import CryptoKit
import Security

public struct GoogleClientConfig: Codable {
    public let clientId: String
    public let clientSecret: String
    public let projectId: String?
    public let authUri: String
    public let tokenUri: String
    
    public init(
        clientId: String,
        clientSecret: String,
        projectId: String? = nil,
        authUri: String = "https://accounts.google.com/o/oauth2/auth",
        tokenUri: String = "https://oauth2.googleapis.com/token"
    ) {
        self.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authUri = authUri.isEmpty ? "https://accounts.google.com/o/oauth2/auth" : authUri
        self.tokenUri = tokenUri.isEmpty ? "https://oauth2.googleapis.com/token" : tokenUri
    }
    
    public static func parse(from data: Data) throws -> GoogleClientConfig {
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw NSError(domain: "GoogleOAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format."])
        }
        
        let container: [String: Any]
        if let installed = json["installed"] as? [String: Any] {
            container = installed
        } else if let web = json["web"] as? [String: Any] {
            container = web
        } else {
            container = json
        }
        
        guard let clientId = container["client_id"] as? String, !clientId.isEmpty,
              let clientSecret = container["client_secret"] as? String, !clientSecret.isEmpty else {
            throw NSError(domain: "GoogleOAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "JSON missing 'client_id' or 'client_secret'."])
        }
        
        let projectId = container["project_id"] as? String
        let authUri = container["auth_uri"] as? String ?? "https://accounts.google.com/o/oauth2/auth"
        let tokenUri = container["token_uri"] as? String ?? "https://oauth2.googleapis.com/token"
        // The sign-in code and client secret are sent to these addresses, so only Google's own are accepted.
        guard isGoogleEndpoint(authUri), isGoogleEndpoint(tokenUri) else {
            throw NSError(domain: "GoogleOAuth", code: 3, userInfo: [NSLocalizedDescriptionKey: "This file's sign-in addresses aren't Google's. Download the OAuth client JSON again from the Google Cloud console."])
        }

        return GoogleClientConfig(
            clientId: clientId,
            clientSecret: clientSecret,
            projectId: projectId,
            authUri: authUri,
            tokenUri: tokenUri
        )
    }

    /// True for an https address on google.com or googleapis.com (or a subdomain of either).
    public static func isGoogleEndpoint(_ address: String) -> Bool {
        guard let url = URL(string: address), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return ["google.com", "googleapis.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// PKCE (RFC 7636): a one-time secret that proves the app finishing sign-in is the one that started it.
enum PKCE {
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public final class LoopbackOAuthServer: @unchecked Sendable {
    private var listeningSocket: Int32 = -1
    public private(set) var port: UInt16 = 0
    
    public init() {}
    
    public func start() throws -> UInt16 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw NSError(domain: "LoopbackOAuthServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to create socket."])
        }
        self.listeningSocket = sock
        
        var opt: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        
        // Try ports from 8089 to 8099, then port 0 (ephemeral)
        var boundPort: UInt16? = nil
        let candidatePorts: [UInt16] = [8089, 8090, 8091, 8092, 8095, 0]
        
        for candidate in candidatePorts {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(candidate).bigEndian
            addr.sin_addr.s_addr = in_addr_t(0x7F000001).bigEndian // 127.0.0.1
            
            let res = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    bind(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if res == 0 {
                if candidate == 0 {
                    var boundAddr = sockaddr_in()
                    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                    _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                            getsockname(sock, saPtr, &len)
                        }
                    }
                    boundPort = UInt16(bigEndian: boundAddr.sin_port)
                } else {
                    boundPort = candidate
                }
                break
            }
        }
        
        guard let assignedPort = boundPort else {
            close(sock)
            self.listeningSocket = -1
            throw NSError(domain: "LoopbackOAuthServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to bind to local loopback port."])
        }
        
        if listen(sock, 1) != 0 {
            close(sock)
            self.listeningSocket = -1
            throw NSError(domain: "LoopbackOAuthServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to listen on local loopback port."])
        }
        
        self.port = assignedPort
        return assignedPort
    }
    
    public func waitForAuthorizationCode(expectedState: String, timeoutSeconds: TimeInterval = 180) async throws -> String {
        guard listeningSocket >= 0 else {
            throw NSError(domain: "LoopbackOAuthServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Server not listening."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "LoopbackOAuthServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Server deallocated."]))
                    return
                }
                defer {
                    self.stop()
                }
                
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                
                let clientSock = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        accept(self.listeningSocket, saPtr, &clientLen)
                    }
                }
                
                guard clientSock >= 0 else {
                    continuation.resume(throwing: NSError(domain: "LoopbackOAuthServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to accept loopback connection."]))
                    return
                }
                defer { close(clientSock) }
                
                var buffer = [CChar](repeating: 0, count: 4096)
                let bytesRead = read(clientSock, &buffer, buffer.count - 1)
                guard bytesRead > 0 else {
                    continuation.resume(throwing: NSError(domain: "LoopbackOAuthServer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Empty HTTP request received."]))
                    return
                }
                
                let requestStr = String(cString: buffer)
                guard let firstLine = requestStr.components(separatedBy: "\r\n").first,
                      let path = firstLine.components(separatedBy: " ").dropFirst().first,
                      let components = URLComponents(string: path) else {
                    continuation.resume(throwing: NSError(domain: "LoopbackOAuthServer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Malformed redirect URL."]))
                    return
                }
                
                let queryItems = components.queryItems ?? []
                let receivedState = queryItems.first(where: { $0.name == "state" })?.value
                let code = queryItems.first(where: { $0.name == "code" })?.value
                let error = queryItems.first(where: { $0.name == "error" })?.value
                
                if let error = error {
                    let html = self.makeHTMLResponse(title: "Authentication Canceled", message: "Google sign-in was canceled or denied: \(Self.htmlEscaped(error))", success: false)
                    self.sendHTTPResponse(clientSock: clientSock, html: html)
                    continuation.resume(throwing: NSError(domain: "GoogleOAuth", code: 7, userInfo: [NSLocalizedDescriptionKey: "Google OAuth error: \(error)"]))
                    return
                }
                
                guard receivedState == expectedState else {
                    let html = self.makeHTMLResponse(title: "Security Verification Failed", message: "State token mismatch. Please try signing in again.", success: false)
                    self.sendHTTPResponse(clientSock: clientSock, html: html)
                    continuation.resume(throwing: NSError(domain: "GoogleOAuth", code: 8, userInfo: [NSLocalizedDescriptionKey: "State token mismatch (CSRF check failed)."]))
                    return
                }
                
                guard let authCode = code, !authCode.isEmpty else {
                    let html = self.makeHTMLResponse(title: "Missing Authorization Code", message: "No authorization code found in redirect from Google.", success: false)
                    self.sendHTTPResponse(clientSock: clientSock, html: html)
                    continuation.resume(throwing: NSError(domain: "GoogleOAuth", code: 9, userInfo: [NSLocalizedDescriptionKey: "No authorization code returned from Google."]))
                    return
                }
                
                let html = self.makeHTMLResponse(title: "Connected to Gmail!", message: "Your authorization is complete. You can close this tab and return to DayBook AI.", success: true)
                self.sendHTTPResponse(clientSock: clientSock, html: html)
                
                continuation.resume(returning: authCode)
            }
        }
    }
    
    private func sendHTTPResponse(clientSock: Int32, html: String) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        _ = response.withCString { cstr in
            write(clientSock, cstr, strlen(cstr))
        }
    }
    
    static func htmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func makeHTMLResponse(title: String, message: String, success: Bool) -> String {
        let badgeColor = success ? "#2e7d32" : "#c62828"
        let badgeBg = success ? "#e8f5e9" : "#ffebee"
        let badgeText = success ? "✓ Connected" : "⚠ Notice"
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Personal Planner - \(title)</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 90vh; margin: 0; background: #f5f5f7; }
            .card { background: white; padding: 48px; border-radius: 16px; box-shadow: 0 8px 30px rgba(0,0,0,0.08); text-align: center; max-width: 440px; }
            h2 { color: #1d1d1f; margin-bottom: 12px; font-size: 24px; }
            p { color: #6e6e73; line-height: 1.5; font-size: 15px; }
            .badge { display: inline-block; background: \(badgeBg); color: \(badgeColor); padding: 6px 14px; border-radius: 20px; font-weight: 600; font-size: 14px; margin-bottom: 16px; }
          </style>
        </head>
        <body>
          <div class="card">
            <div class="badge">\(badgeText)</div>
            <h2>\(title)</h2>
            <p>\(message)</p>
          </div>
        </body>
        </html>
        """
    }
    
    public func stop() {
        if listeningSocket >= 0 {
            close(listeningSocket)
            listeningSocket = -1
        }
    }
}

public final class GoogleOAuthService {
    private let keychainService: KeychainServiceProtocol
    
    // Keychain keys
    private let kClientId = "google_oauth_client_id"
    private let kClientSecret = "google_oauth_client_secret"
    private let kProjectId = "google_oauth_project_id"
    private let kAccessToken = "google_oauth_access_token"
    private let kRefreshToken = "google_oauth_refresh_token"
    private let kTokenExpiry = "google_oauth_token_expiry"
    
    // In-memory session cache to avoid repeated Keychain queries
    private var cachedClientConfig: GoogleClientConfig? = nil
    private var isClientConfigLoaded = false
    private var cachedAccessToken: String? = nil
    private var cachedRefreshToken: String? = nil
    private var cachedTokenExpiryTimestamp: Double? = nil
    private var areTokensLoaded = false
    private let stateLock = NSLock()
    
    public init(keychainService: KeychainServiceProtocol = KeychainService()) {
        self.keychainService = keychainService
    }
    
    public var hasClientCredentials: Bool {
        return loadClientConfig() != nil
    }
    
    public var hasAuthorizedTokens: Bool {
        let alreadyLoaded = stateLock.withLock { areTokensLoaded }
        if alreadyLoaded {
            return stateLock.withLock {
                (cachedAccessToken != nil && !cachedAccessToken!.isEmpty) ||
                (cachedRefreshToken != nil && !cachedRefreshToken!.isEmpty)
            }
        }
        
        let access = keychainService.getCredential(key: kAccessToken)
        let refresh = keychainService.getCredential(key: kRefreshToken)
        var expiryTs: Double? = nil
        if let expiryStr = keychainService.getCredential(key: kTokenExpiry) {
            expiryTs = Double(expiryStr)
        }
        
        return stateLock.withLock {
            cachedAccessToken = access
            cachedRefreshToken = refresh
            cachedTokenExpiryTimestamp = expiryTs
            areTokensLoaded = true
            return (access != nil && !access!.isEmpty) || (refresh != nil && !refresh!.isEmpty)
        }
    }
    
    public func saveClientConfig(_ config: GoogleClientConfig) throws {
        try keychainService.saveCredential(key: kClientId, value: config.clientId)
        try keychainService.saveCredential(key: kClientSecret, value: config.clientSecret)
        if let pid = config.projectId {
            try keychainService.saveCredential(key: kProjectId, value: pid)
        }
        stateLock.withLock {
            cachedClientConfig = config
            isClientConfigLoaded = true
        }
    }
    
    public func loadClientConfig() -> GoogleClientConfig? {
        let isLoaded = stateLock.withLock { isClientConfigLoaded }
        if isLoaded {
            return stateLock.withLock { cachedClientConfig }
        }
        
        guard let id = keychainService.getCredential(key: kClientId),
              let secret = keychainService.getCredential(key: kClientSecret) else {
            stateLock.withLock {
                cachedClientConfig = nil
                isClientConfigLoaded = true
            }
            return nil
        }
        let pid = keychainService.getCredential(key: kProjectId)
        let config = GoogleClientConfig(clientId: id, clientSecret: secret, projectId: pid)
        stateLock.withLock {
            cachedClientConfig = config
            isClientConfigLoaded = true
        }
        return config
    }
    
    public func performBrowserSignIn() async throws {
        guard let config = loadClientConfig() else {
            throw NSError(domain: "GoogleOAuth", code: 10, userInfo: [NSLocalizedDescriptionKey: "Client credentials not imported. Please select your Google credentials JSON file first."])
        }
        
        let server = LoopbackOAuthServer()
        let port = try server.start()
        let redirectUri = "http://localhost:\(port)"
        let state = UUID().uuidString
        let codeVerifier = PKCE.makeVerifier()

        // Build authorization URL
        guard var components = URLComponents(string: config.authUri) else {
            server.stop()
            throw NSError(domain: "GoogleOAuth", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid auth URI: \(config.authUri)"])
        }
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        
        guard let authURL = components.url else {
            server.stop()
            throw NSError(domain: "GoogleOAuth", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to construct Google OAuth authorization URL."])
        }
        
        // Open browser
        NSWorkspace.shared.open(authURL)
        
        // Wait for loopback server redirect
        let code = try await server.waitForAuthorizationCode(expectedState: state)
        
        // Exchange authorization code for tokens
        try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier, redirectUri: redirectUri, config: config)
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String, redirectUri: String, config: GoogleClientConfig) async throws {
        guard GoogleClientConfig.isGoogleEndpoint(config.tokenUri), let tokenURL = URL(string: config.tokenUri) else {
            throw NSError(domain: "GoogleOAuth", code: 13, userInfo: [NSLocalizedDescriptionKey: "Invalid token URI."])
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "code": code,
            "code_verifier": codeVerifier,
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GoogleOAuth", code: 14, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "GoogleOAuth", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed (\(httpResponse.statusCode)): \(errorBody)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw NSError(domain: "GoogleOAuth", code: 15, userInfo: [NSLocalizedDescriptionKey: "No access token in response."])
        }
        
        try keychainService.saveCredential(key: kAccessToken, value: accessToken)
        
        if let refreshToken = json["refresh_token"] as? String {
            try keychainService.saveCredential(key: kRefreshToken, value: refreshToken)
        }
        
        var expiryTs: Double? = nil
        if let expiresIn = json["expires_in"] as? Int {
            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            expiryTs = expiryDate.timeIntervalSince1970
            try keychainService.saveCredential(key: kTokenExpiry, value: String(expiryDate.timeIntervalSince1970))
        }
        
        stateLock.withLock {
            cachedAccessToken = accessToken
            if let ref = json["refresh_token"] as? String {
                cachedRefreshToken = ref
            }
            cachedTokenExpiryTimestamp = expiryTs
            areTokensLoaded = true
        }
    }
    
    public func getValidAccessToken() async throws -> String {
        _ = hasAuthorizedTokens
        
        let (expiryTimestamp, currentToken) = stateLock.withLock {
            (cachedTokenExpiryTimestamp, cachedAccessToken)
        }
        
        if let expiryTimestamp = expiryTimestamp {
            let expiryDate = Date(timeIntervalSince1970: expiryTimestamp)
            // If expired or about to expire in 60s, refresh
            if Date().addingTimeInterval(60) > expiryDate {
                return try await refreshAccessToken()
            }
        }
        
        if let token = currentToken, !token.isEmpty {
            return token
        }
        
        // Attempt refresh
        return try await refreshAccessToken()
    }
    
    private func refreshAccessToken() async throws -> String {
        _ = hasAuthorizedTokens
        
        let refreshToken = stateLock.withLock { cachedRefreshToken }
        
        guard let refreshToken = refreshToken, !refreshToken.isEmpty else {
            throw NSError(domain: "GoogleOAuth", code: 16, userInfo: [NSLocalizedDescriptionKey: "No refresh token available. Please sign in again."])
        }
        guard let config = loadClientConfig() else {
            throw NSError(domain: "GoogleOAuth", code: 17, userInfo: [NSLocalizedDescriptionKey: "Client credentials missing."])
        }
        guard GoogleClientConfig.isGoogleEndpoint(config.tokenUri), let tokenURL = URL(string: config.tokenUri) else {
            throw NSError(domain: "GoogleOAuth", code: 18, userInfo: [NSLocalizedDescriptionKey: "Invalid token URI."])
        }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "refresh_token": refreshToken,
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "grant_type": "refresh_token"
        ]
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let err = String(data: data, encoding: .utf8) ?? "Failed to refresh token"
            throw NSError(domain: "GoogleOAuth", code: 19, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed: \(err)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw NSError(domain: "GoogleOAuth", code: 20, userInfo: [NSLocalizedDescriptionKey: "Malformed refresh response."])
        }
        
        try keychainService.saveCredential(key: kAccessToken, value: newAccessToken)
        var newExpiryTs: Double? = nil
        if let expiresIn = json["expires_in"] as? Int {
            let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
            newExpiryTs = expiryDate.timeIntervalSince1970
            try keychainService.saveCredential(key: kTokenExpiry, value: String(expiryDate.timeIntervalSince1970))
        }
        
        stateLock.withLock {
            cachedAccessToken = newAccessToken
            cachedTokenExpiryTimestamp = newExpiryTs
        }
        
        return newAccessToken
    }
    
    public func disconnect() throws {
        stateLock.withLock {
            cachedAccessToken = nil
            cachedRefreshToken = nil
            cachedTokenExpiryTimestamp = nil
            areTokensLoaded = true
        }
        
        try? keychainService.deleteCredential(key: kAccessToken)
        try? keychainService.deleteCredential(key: kRefreshToken)
        try? keychainService.deleteCredential(key: kTokenExpiry)
    }
}
