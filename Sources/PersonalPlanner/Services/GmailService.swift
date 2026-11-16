import Foundation

public struct GmailMessageStub: Equatable, Codable {
    public let id: String
    public let threadId: String
    
    public init(id: String, threadId: String) {
        self.id = id
        self.threadId = threadId
    }
}

public protocol GmailServiceProtocol {
    var isConnected: Bool { get }
    var hasClientConfig: Bool { get }
    func importClientConfig(from data: Data) throws -> GoogleClientConfig
    func loadClientConfig() -> GoogleClientConfig?
    func signIn() async throws
    func disconnect() throws
    func fetchRecentEmailSummaries(limit: Int) async throws -> [RecentEmailSummary]
    func fetchEmailsFromLastDays(days: Int) async throws -> [EmailSource]
    func listInboxMessageStubs(days: Int) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date)
    func listInboxMessageStubs(windowStart: Date, windowEnd: Date) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date)
    func fetchSingleEmail(id: String, threadId: String) async throws -> EmailSource
}

extension GmailServiceProtocol {
    public func listInboxMessageStubs(days: Int = 3) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date) {
        let now = Date()
        let start = now.addingTimeInterval(-Double(days * 86400))
        return try await listInboxMessageStubs(windowStart: start, windowEnd: now)
    }
    
    public func listInboxMessageStubs(windowStart: Date, windowEnd: Date) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date) {
        let emails = try await fetchEmailsFromLastDays(days: 3)
        let filtered = emails.filter { $0.receivedDate >= windowStart && $0.receivedDate <= windowEnd }
        let stubs = filtered.map { GmailMessageStub(id: $0.id, threadId: $0.threadId) }
        return (stubs, windowStart, windowEnd)
    }
    
    public func fetchSingleEmail(id: String, threadId: String) async throws -> EmailSource {
        let emails = try await fetchEmailsFromLastDays(days: 3)
        if let found = emails.first(where: { $0.id == id }) {
            return found
        }
        throw NSError(domain: "GmailService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Message \(id) not found in Gmail inbox."])
    }
}

public final class GmailService: GmailServiceProtocol {
    private let oauthService: GoogleOAuthService
    
    public init(oauthService: GoogleOAuthService = GoogleOAuthService()) {
        self.oauthService = oauthService
    }
    
    public var isConnected: Bool {
        return oauthService.hasAuthorizedTokens
    }
    
    public var hasClientConfig: Bool {
        return oauthService.hasClientCredentials
    }
    
    public func importClientConfig(from data: Data) throws -> GoogleClientConfig {
        let config = try GoogleClientConfig.parse(from: data)
        try oauthService.saveClientConfig(config)
        return config
    }
    
    public func loadClientConfig() -> GoogleClientConfig? {
        return oauthService.loadClientConfig()
    }
    
    public func signIn() async throws {
        try await oauthService.performBrowserSignIn()
    }
    
    public func disconnect() throws {
        try oauthService.disconnect()
    }
    
    public func fetchRecentEmailSummaries(limit: Int = 5) async throws -> [RecentEmailSummary] {
        let accessToken = try await oauthService.getValidAccessToken()
        
        guard let listURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(limit)") else {
            throw NSError(domain: "GmailService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid messages list URL."])
        }
        
        var listRequest = URLRequest(url: listURL)
        listRequest.httpMethod = "GET"
        listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        guard let httpListResponse = listResponse as? HTTPURLResponse, (200...299).contains(httpListResponse.statusCode) else {
            let errorText = String(data: listData, encoding: .utf8) ?? "Unknown Gmail API error"
            throw NSError(domain: "GmailService", code: (listResponse as? HTTPURLResponse)?.statusCode ?? 2, userInfo: [NSLocalizedDescriptionKey: "Gmail API error: \(errorText)"])
        }
        
        guard let listJSON = try JSONSerialization.jsonObject(with: listData, options: []) as? [String: Any] else {
            throw NSError(domain: "GmailService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not parse Gmail message list response."])
        }
        
        let messagesArray = listJSON["messages"] as? [[String: Any]] ?? []
        guard !messagesArray.isEmpty else { return [] }
        
        var summaries: [RecentEmailSummary] = []
        for msgItem in messagesArray.prefix(limit) {
            guard let msgId = msgItem["id"] as? String else { continue }
            
            guard let detailURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(msgId)?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date") else {
                continue
            }
            
            var detailRequest = URLRequest(url: detailURL)
            detailRequest.httpMethod = "GET"
            detailRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            do {
                let (detailData, detailResp) = try await URLSession.shared.data(for: detailRequest)
                guard let detailHTTP = detailResp as? HTTPURLResponse, (200...299).contains(detailHTTP.statusCode) else { continue }
                guard let detailJSON = try JSONSerialization.jsonObject(with: detailData, options: []) as? [String: Any] else { continue }
                
                let snippet = detailJSON["snippet"] as? String ?? ""
                var subject = "(No Subject)"
                var sender = "Unknown Sender"
                var date = Date()
                
                if let internalDateStr = detailJSON["internalDate"] as? String,
                   let internalTimestamp = Double(internalDateStr) {
                    date = Date(timeIntervalSince1970: internalTimestamp / 1000.0)
                }
                
                if let payload = detailJSON["payload"] as? [String: Any],
                   let headers = payload["headers"] as? [[String: String]] {
                    for header in headers {
                        let name = header["name"]?.lowercased()
                        let val = header["value"] ?? ""
                        if name == "subject" && !val.isEmpty {
                            subject = val
                        } else if name == "from" && !val.isEmpty {
                            sender = val
                        } else if name == "date" && !val.isEmpty {
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
                            if let parsed = formatter.date(from: val) {
                                date = parsed
                            }
                        }
                    }
                }
                
                summaries.append(RecentEmailSummary(
                    id: msgId,
                    subject: subject,
                    sender: sender,
                    date: date,
                    snippet: snippet
                ))
            } catch {
                continue
            }
        }
        
        return summaries
    }
    
    public func listInboxMessageStubs(windowStart: Date, windowEnd: Date) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date) {
        let accessToken = try await oauthService.getValidAccessToken()
        
        // Precise Unix timestamp boundaries ending at frozen scan start
        let startEpoch = Int(windowStart.timeIntervalSince1970)
        let endEpoch = Int(ceil(windowEnd.timeIntervalSince1970))
        let query = "in:inbox after:\(startEpoch) before:\(endEpoch + 1)"
        
        var allMessageItems: [GmailMessageStub] = []
        var pageToken: String? = nil
        let maxMessagesToFetch = 250 // Safety cap to avoid runaway memory or quota limits
        
        repeat {
            var urlComponents = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            var queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "maxResults", value: "50")
            ]
            if let token = pageToken, !token.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: token))
            }
            urlComponents.queryItems = queryItems
            
            guard let listURL = urlComponents.url else { break }
            
            var listRequest = URLRequest(url: listURL)
            listRequest.httpMethod = "GET"
            listRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
            guard let httpListResponse = listResponse as? HTTPURLResponse, (200...299).contains(httpListResponse.statusCode) else {
                let errorText = String(data: listData, encoding: .utf8) ?? "Failed to query Gmail messages."
                throw NSError(domain: "GmailService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Gmail API search failed: \(errorText)"])
            }
            
            guard let listJSON = try JSONSerialization.jsonObject(with: listData, options: []) as? [String: Any] else {
                throw NSError(domain: "GmailService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not parse Gmail list JSON."])
            }
            
            if let messagesArray = listJSON["messages"] as? [[String: Any]] {
                for msgItem in messagesArray {
                    guard let msgId = msgItem["id"] as? String else { continue }
                    let threadId = msgItem["threadId"] as? String ?? msgId
                    allMessageItems.append(GmailMessageStub(id: msgId, threadId: threadId))
                }
            }
            
            pageToken = listJSON["nextPageToken"] as? String
        } while pageToken != nil && !pageToken!.isEmpty && allMessageItems.count < maxMessagesToFetch
        
        return (allMessageItems, windowStart, windowEnd)
    }
    
    public func listInboxMessageStubs(days: Int = 3) async throws -> (messages: [GmailMessageStub], queryStartDate: Date, queryEndDate: Date) {
        let now = Date()
        let start = now.addingTimeInterval(-Double(days * 86400))
        return try await listInboxMessageStubs(windowStart: start, windowEnd: now)
    }
    
    public func fetchSingleEmail(id msgId: String, threadId: String) async throws -> EmailSource {
        let accessToken = try await oauthService.getValidAccessToken()
        guard let detailURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(msgId)?format=full") else {
            throw NSError(domain: "GmailService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid detail URL for message \(msgId)"])
        }
        
        var detailRequest = URLRequest(url: detailURL)
        detailRequest.httpMethod = "GET"
        detailRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (detailData, detailResp) = try await URLSession.shared.data(for: detailRequest)
        guard let detailHTTP = detailResp as? HTTPURLResponse else {
            throw NSError(domain: "GmailService", code: 502, userInfo: [NSLocalizedDescriptionKey: "No response from Gmail API for message \(msgId)"])
        }
        guard (200...299).contains(detailHTTP.statusCode) else {
            let errorText = String(data: detailData, encoding: .utf8) ?? "HTTP \(detailHTTP.statusCode)"
            throw NSError(domain: "GmailService", code: detailHTTP.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gmail retrieval failed (HTTP \(detailHTTP.statusCode)): \(errorText)"])
        }
        
        guard let detailJSON = try JSONSerialization.jsonObject(with: detailData, options: []) as? [String: Any] else {
            throw NSError(domain: "GmailService", code: 422, userInfo: [NSLocalizedDescriptionKey: "Could not parse JSON payload for message \(msgId)"])
        }
        
        let snippet = detailJSON["snippet"] as? String ?? ""
        var subject = "(No Subject)"
        var sender = "Unknown Sender"
        var date = Date()
        
        if let internalDateStr = detailJSON["internalDate"] as? String,
           let internalTimestamp = Double(internalDateStr) {
            date = Date(timeIntervalSince1970: internalTimestamp / 1000.0)
        }
        
        var fullBody = ""
        if let payload = detailJSON["payload"] as? [String: Any] {
            if let headers = payload["headers"] as? [[String: String]] {
                for header in headers {
                    let name = header["name"]?.lowercased()
                    let val = header["value"] ?? ""
                    if name == "subject" && !val.isEmpty {
                        subject = val
                    } else if name == "from" && !val.isEmpty {
                        sender = val
                    } else if name == "date" && !val.isEmpty {
                        let df = DateFormatter()
                        df.locale = Locale(identifier: "en_US_POSIX")
                        df.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
                        if let parsed = df.date(from: val) {
                            date = parsed
                        }
                    }
                }
            }
            
            fullBody = Self.extractBodyText(from: payload)
        }
        
        if fullBody.isEmpty {
            fullBody = snippet
        }
        
        var senderName = sender
        var senderEmail = sender
        if let match = sender.range(of: "<.+>", options: .regularExpression) {
            senderEmail = sender[match].trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            senderName = sender[..<match.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if senderName.isEmpty { senderName = senderEmail }
        
        let webLink = EmailSource.gmailURL(forMessageId: msgId)
        
        return EmailSource(
            id: msgId,
            threadId: threadId,
            senderName: senderName,
            senderEmail: senderEmail,
            subject: subject,
            receivedDate: date,
            snippet: snippet,
            fullBody: fullBody,
            category: .assignment,
            isSimulatedDemo: false,
            webLink: webLink
        )
    }
    
    public func fetchEmailsFromLastDays(days: Int = 3) async throws -> [EmailSource] {
        let (stubs, _, _) = try await listInboxMessageStubs(days: days)
        var emails: [EmailSource] = []
        for stub in stubs {
            do {
                let email = try await fetchSingleEmail(id: stub.id, threadId: stub.threadId)
                emails.append(email)
            } catch {
                continue
            }
        }
        return emails
    }
    
    public static func extractBodyText(from payload: [String: Any]) -> String {
        if let parts = payload["parts"] as? [[String: Any]], !parts.isEmpty {
            // First pass: plain text parts
            for part in parts {
                let mimeType = part["mimeType"] as? String ?? ""
                if mimeType == "text/plain",
                   let body = part["body"] as? [String: Any],
                   let dataStr = body["data"] as? String,
                   let decoded = decodeBase64URL(dataStr), !decoded.isEmpty {
                    return decoded
                }
            }
            // Second pass: recursively check subparts
            for part in parts {
                let sub = extractBodyText(from: part)
                if !sub.isEmpty { return sub }
            }
            // Third pass: html parts
            for part in parts {
                let mimeType = part["mimeType"] as? String ?? ""
                if mimeType == "text/html",
                   let body = part["body"] as? [String: Any],
                   let dataStr = body["data"] as? String,
                   let decoded = decodeBase64URL(dataStr), !decoded.isEmpty {
                    return stripHTMLTags(from: decoded)
                }
            }
        }
        
        if let body = payload["body"] as? [String: Any],
           let dataStr = body["data"] as? String,
           let decoded = decodeBase64URL(dataStr) {
            let mimeType = payload["mimeType"] as? String ?? ""
            if mimeType == "text/html" {
                return stripHTMLTags(from: decoded)
            }
            return decoded
        }
        
        return ""
    }
    
    public static func decodeBase64URL(_ base64URL: String) -> String? {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }
    
    public static func stripHTMLTags(from html: String) -> String {
        let stripped = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
        let cleaned = stripped.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: nil)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
