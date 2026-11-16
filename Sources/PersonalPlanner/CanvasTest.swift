import Foundation
import WebKit
import AppKit

/// Offline tests for the Canvas integration. Run with: PersonalPlanner --test-canvas
@MainActor
public final class CanvasTester {

    /// Fake Canvas server: answers by URL path via `handler`, records requests.
    final class FakeCanvas: URLProtocol {
        struct Reply { var status = 200; var body = "[]"; var headers: [String: String] = ["Content-Type": "application/json"]; var data: Data? = nil }
        nonisolated(unsafe) static var handler: (URLRequest) -> Reply = { _ in Reply() }
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            FakeCanvas.requests.append(request)
            let reply = FakeCanvas.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data ?? Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    final class MockReader: CanvasReading {
        var snapshot = CanvasSnapshot()
        var error: Error? = nil
        var calls = 0
        func readEverything(client: CanvasClient, now: Date) async throws -> CanvasSnapshot {
            calls += 1
            if let e = error { throw e }
            return snapshot
        }
    }

    final class MockModel: OllamaExtractionServiceProtocol {
        var calls: [String] = []
        var responses: [String: EmailAnalysis] = [:]   // keyed by email subject
        var error: Error? = nil
        func analyzeEmail(email: EmailSource, threadContext: [EmailSource], existingTasks: [DiscoveredTask], baseURL: String, model: String, timeZone: TimeZone, checkCancellation: (() -> Bool)?, onRetry: ((String) -> Void)?) async throws -> EmailAnalysis {
            calls.append(email.id)
            if let e = error { throw e }
            return responses[email.subject] ?? EmailAnalysis(isNewsletterOrMarketing: false, isDirectedAtRecipient: true, hasActionableTask: false, reasoning: "nothing", tasks: [])
        }
        func installedModels(baseURL: String) async throws -> [String] { [] }
        func testConnection(baseURL: String, model: String) async throws -> String { "" }
        var estimate: TaskTimeEstimate? = nil
        var estimateCalls: [String] = []
        var estimateContexts: [String] = []
        func estimateTaskMinutes(title: String, context: String, baseURL: String, model: String) async throws -> TaskTimeEstimate? {
            estimateCalls.append(title)
            estimateContexts.append(context)
            return estimate
        }
    }

    final class MockKeychain: KeychainServiceProtocol {
        var store: [String: String] = [:]
        func saveCredential(key: String, value: String) throws { store[key] = value }
        func getCredential(key: String) -> String? { store[key] }
        func deleteCredential(key: String) throws { store.removeValue(forKey: key) }
    }

    static func fakeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakeCanvas.self]
        return URLSession(configuration: config)
    }

    /// A one-page PDF with real (selectable) text.
    static func textPDF(_ lines: [String]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        (lines.joined(separator: "\n") as NSString).draw(in: CGRect(x: 50, y: 50, width: 500, height: 680), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return data as Data
    }

    static func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    static func due(_ key: String, _ title: String, kind: String = "assignment", course: String = "ECON 101", due: Date?, submitted: Bool = false, missing: Bool = false, points: Double? = 10, description: String = "") -> CanvasDueItem {
        CanvasDueItem(key: key, kind: kind, title: title, courseName: course, dueAt: due, pointsPossible: points, htmlURL: "https://canvas.test.edu/courses/1/assignments/1", isSubmitted: submitted, isMissing: missing, descriptionText: description)
    }

    // MARK: - Runner

    public static func runAllTests() -> Bool {
        print("\n=======================================================")
        print(" 🎓 CANVAS INTEGRATION TEST")
        print("=======================================================\n")
        var passed = 0
        var total = 0
        func check(_ name: String, _ condition: Bool, _ details: String = "") {
            total += 1
            if condition { passed += 1; print("  ✅ [PASS] \(name)") } else {
                print("  ❌ [FAIL] \(name)")
                if !details.isEmpty { print("     Details: \(details)") }
            }
        }
        let now = Date()
        let base = URL(string: "https://canvas.test.edu")!

        // --- Stage 1: Helpers
        print("--- Stage 1: Address, Cookies, Paging, Text ---")
        check("Bare host normalized to https root", CanvasClient.normalizedBaseURL("Canvas.Test.edu/courses/12")?.absoluteString == "https://canvas.test.edu")
        check("http upgraded to https", CanvasClient.normalizedBaseURL("http://canvas.test.edu")?.scheme == "https")
        check("Nonsense address rejected", CanvasClient.normalizedBaseURL("canvas") == nil && CanvasClient.normalizedBaseURL("  ") == nil)
        check("'while(1);' JSON prefix stripped", (try? CanvasClient.parseJSON(Data("while(1);[{\"id\":1}]".utf8)) as? [[String: Any]])?.count == 1)
        check("HTML page reported as invalid response", (try? CanvasClient.parseJSON(Data("<html>".utf8))) == nil)
        let link = "<https://canvas.test.edu/api/v1/x?page=2>; rel=\"next\", <https://canvas.test.edu/api/v1/x?page=5>; rel=\"last\""
        check("Next page link parsed", CanvasClient.nextPageURL(from: link)?.absoluteString == "https://canvas.test.edu/api/v1/x?page=2")
        check("No next page on last page", CanvasClient.nextPageURL(from: "<https://a.b/x>; rel=\"last\"") == nil)
        let parentCookie = StoredCookie(name: "a", value: "1", domain: ".test.edu", path: "/", isSecure: true, expires: nil)
        check("Parent-domain cookie applies to Canvas host", parentCookie.applies(to: "canvas.test.edu"))
        check("Unrelated cookie doesn't apply", !StoredCookie(name: "a", value: "1", domain: "sso.other.com", path: "/", isSecure: true, expires: nil).applies(to: "canvas.test.edu"))
        let plain = CanvasText.plain(fromHTML: "<p>Read <b>Ch. 4</b> &amp; do Q1&ndash;5</p><ul><li>Bring calculator</li></ul><script>x()</script>")
        check("HTML converted to readable text", plain.contains("Read Ch. 4 & do Q1–5") && plain.contains("• Bring calculator") && !plain.contains("x()"), plain)
        check("Fingerprint changes with content", CanvasText.fingerprint("a") != CanvasText.fingerprint("b") && CanvasText.fingerprint("a") == CanvasText.fingerprint("a"))

        let plannerItem: [String: Any] = [
            "plannable_type": "quiz", "plannable_id": 77, "course_id": 5, "html_url": "https://canvas.test.edu/courses/5/quizzes/77",
            "plannable": ["title": "Quiz 3", "due_at": "2026-11-20T07:59:00Z", "points_possible": 20.0],
            "submissions": ["submitted": false, "missing": true]
        ]
        let parsed = CanvasReader.dueItem(from: plannerItem, courses: [5: "STAT 200"])
        check("Planner quiz parsed with course and due date", parsed?.key == "quiz-77" && parsed?.courseName == "STAT 200" && parsed?.dueAt != nil)
        check("Missing flag read", parsed?.isMissing == true && parsed?.isSubmitted == false)
        let announcementItem: [String: Any] = ["plannable_type": "announcement", "plannable_id": 1, "plannable": [:]]
        check("Announcements aren't treated as due items", CanvasReader.dueItem(from: announcementItem, courses: [:]) == nil)

        // --- Open button: where each task was found
        let relItem: [String: Any] = ["plannable_type": "assignment", "plannable_id": 88, "course_id": 5, "html_url": "/courses/5/assignments/88",
                                      "plannable": ["title": "Lab 2", "due_at": "2026-11-20T07:59:00Z"]]
        check("Planner path links are kept (not dropped)", CanvasReader.dueItem(from: relItem, courses: [:])?.htmlURL == "/courses/5/assignments/88")
        let noLinkQuiz: [String: Any] = ["plannable_type": "quiz", "plannable_id": 9, "course_id": 5, "plannable": ["title": "Quiz 1", "due_at": "2026-11-20T07:59:00Z"]]
        check("Missing quiz link built from the course", CanvasReader.dueItem(from: noLinkQuiz, courses: [:])?.htmlURL == "/courses/5/quizzes/9")
        let canvasBase = URL(string: "https://canvas.test.edu")!
        let canvasLinkTask = AppState.makeCanvasTask(CanvasDueItem(key: "assignment-88", kind: "assignment", title: "Lab 2", courseName: "CHEM 1", dueAt: Date(),
                                                                    pointsPossible: nil, htmlURL: "/courses/5/assignments/88", isSubmitted: false, isMissing: false, descriptionText: ""),
                                                     sourceId: "canvas-assignment-88", due: Date(), dueText: "", now: Date(), canvasBase: canvasBase)
        let canvasLink = TaskSourceLink.forTask(canvasLinkTask, canvasBase: canvasBase)
        check("Canvas assignment opens its exact page", canvasLink?.url.absoluteString == "https://canvas.test.edu/courses/5/assignments/88" && canvasLink?.title == "Open in Canvas",
              canvasLink?.url.absoluteString ?? "nil")
        let gmailTask = DiscoveredTask(title: "Reply to advisor", requiredAction: "Reply",
                                       sourceEmail: EmailSource(id: "18c2f0a9b1d3e4f5", threadId: "18c2f0a9b1d3e4f5", senderName: "Dr. Lee",
                                                                senderEmail: "lee@school.edu", subject: "Meeting", receivedDate: Date(),
                                                                snippet: "", fullBody: "", category: .assignment, isSimulatedDemo: false))
        let gmailLink = TaskSourceLink.forTask(gmailTask, canvasBase: canvasBase)
        check("Email task opens the exact Gmail message (even if archived)", gmailLink?.url.absoluteString == "https://mail.google.com/mail/u/0/#all/18c2f0a9b1d3e4f5" && gmailLink?.title == "Open in Gmail",
              gmailLink?.url.absoluteString ?? "nil")
        // Old Canvas tasks were saved with a wrong Gmail link: never send those to Gmail.
        var oldCanvas = canvasLinkTask
        oldCanvas.sourceEmail.webLink = "https://mail.google.com/mail/u/0/#inbox/canvas-assignment-88"
        let oldLink = TaskSourceLink.forTask(oldCanvas, canvasBase: canvasBase)
        check("Old Canvas task with a Gmail link opens Canvas instead", oldLink?.url.host == "canvas.test.edu" && oldLink?.title == "Open in Canvas", oldLink?.url.absoluteString ?? "nil")
        check("Canvas sources no longer get a made-up Gmail link",
              EmailSource(id: "canvas-assignment-5", threadId: "canvas-assignment-5", senderName: "", senderEmail: "", subject: "", receivedDate: Date(),
                          snippet: "", fullBody: "", category: .canvas, isSimulatedDemo: false).webLink == nil)
        let announcementSource = AppState.canvasEmailSource(for: CanvasTextItem(key: "conversation-41", kind: "Message", title: "Lab moved", courseName: "CHEM 1",
                                                                              author: "TA", postedAt: Date(), version: "v1", body: "Lab is Friday", htmlURL: "/conversations/41"),
                                                            canvasBase: canvasBase)
        check("Canvas inbox message links to the conversation", announcementSource.webLink == "https://canvas.test.edu/conversations/41", announcementSource.webLink ?? "nil")
        var captured = gmailTask
        captured.sourceEmail = EmailSource(id: "qc-1", threadId: "qc-1", senderName: "Quick Capture", senderEmail: "quickcapture@local", subject: "", receivedDate: Date(),
                                           snippet: "", fullBody: "", category: .quickCapture, isSimulatedDemo: false)
        check("Quick Capture tasks have no Open button", TaskSourceLink.forTask(captured, canvasBase: canvasBase) == nil)
        let gsLink = TaskSourceLink.forTask(AppState.makeCanvasTask(CanvasDueItem(key: "gradescope-1-2", kind: "gradescope", title: "HW", courseName: "", dueAt: Date(),
                                                                                  pointsPossible: nil, htmlURL: "https://www.gradescope.com/courses/1/assignments/2", isSubmitted: false,
                                                                                  isMissing: false, descriptionText: ""),
                                                                    sourceId: "gradescope-1-2", due: Date(), dueText: "", now: Date(), category: .gradescope), canvasBase: nil)
        check("Gradescope task opens its assignment", gsLink?.url.absoluteString == "https://www.gradescope.com/courses/1/assignments/2" && gsLink?.title == "Open in Gradescope")

        // --- Stage 2: Client against a fake Canvas
        print("\n--- Stage 2: Client ---")
        FakeCanvas.requests = []
        FakeCanvas.handler = { req in
            let page = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value
            if page == nil {
                return .init(body: "while(1);[{\"id\":1},{\"id\":2}]", headers: ["Content-Type": "application/json", "Link": "<https://canvas.test.edu/api/v1/courses?page=2>; rel=\"next\""])
            }
            return .init(body: "while(1);[{\"id\":3}]")
        }
        let cookieClient = CanvasClient(baseURL: base, auth: .session(cookies: [
            StoredCookie(name: "canvas_session", value: "abc", domain: "canvas.test.edu", path: "/", isSecure: true, expires: nil),
            StoredCookie(name: "sso", value: "zzz", domain: "sso.other.com", path: "/", isSecure: true, expires: nil)
        ]), session: fakeSession())
        let pagesResult = runAsync { try await cookieClient.getAll("/api/v1/courses") }
        check("Follows pagination across pages", (try? pagesResult.get())?.count == 3, "\(pagesResult)")
        let cookieHeader = FakeCanvas.requests.first?.value(forHTTPHeaderField: "Cookie") ?? ""
        check("Sends only Canvas cookies", cookieHeader == "canvas_session=abc", cookieHeader)
        check("Only GET requests made", FakeCanvas.requests.allSatisfy { $0.httpMethod == "GET" })

        FakeCanvas.requests = []
        FakeCanvas.handler = { _ in .init(body: "{\"id\":1}") }
        let tokenClient = CanvasClient(baseURL: base, auth: .token("tok123"), session: fakeSession())
        _ = runAsync { try await tokenClient.get("/api/v1/users/self") }
        check("Token sent as Bearer header", FakeCanvas.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer tok123")

        // A "next page" link to another site must never receive the token.
        FakeCanvas.requests = []
        FakeCanvas.handler = { _ in .init(body: "[{\"id\":1}]", headers: ["Content-Type": "application/json", "Link": "<https://evil.example.com/api/v1/courses?page=2>; rel=\"next\""]) }
        let offSite = runAsync { try await tokenClient.getAll("/api/v1/courses") }
        check("Next-page link to another site is refused", (try? offSite.get()) == nil && FakeCanvas.requests.allSatisfy { $0.url?.host == "canvas.test.edu" },
              "\(FakeCanvas.requests.map { $0.url?.host ?? "" })")
        check("Browser tab match can't be fooled by a lookalike domain",
              !"https://canvas.test.edu.evil.com/".hasPrefix(CanvasBrowserTransport(browser: .safari, canvasHost: "canvas.test.edu").prefixes[0]))
        check("Google sign-in only accepts Google's addresses",
              GoogleClientConfig.isGoogleEndpoint("https://oauth2.googleapis.com/token") && GoogleClientConfig.isGoogleEndpoint("https://accounts.google.com/o/oauth2/auth")
              && !GoogleClientConfig.isGoogleEndpoint("https://oauth2.googleapis.com.evil.com/token") && !GoogleClientConfig.isGoogleEndpoint("http://oauth2.googleapis.com/token"))
        let verifier = PKCE.makeVerifier()
        check("PKCE verifier and challenge are URL-safe and differ",
              verifier.count >= 43 && PKCE.challenge(for: verifier).count == 43 && PKCE.challenge(for: verifier) != verifier
              && !(verifier + PKCE.challenge(for: verifier)).contains { "+/=".contains($0) })

        FakeCanvas.handler = { _ in .init(status: 401, body: "{\"errors\":[]}") }
        if case .failure(let e) = runAsync({ try await tokenClient.get("/api/v1/users/self") }), let ce = e as? CanvasError {
            check("401 means sign-in required", ce.kind == .signInRequired && ce.message.contains("Reconnect"))
        } else { check("401 means sign-in required", false) }

        // Address check: a school's main site isn't Canvas; canvas.<school> is.
        FakeCanvas.handler = { req in
            if req.url?.host == "canvas.school.edu" {
                return .init(status: 401, body: "{\"status\":\"unauthenticated\",\"errors\":[{\"message\":\"user authorization required\"}]}", headers: ["Content-Type": "application/json; charset=utf-8"])
            }
            return .init(status: 404, body: "<html>Page Not Found</html>", headers: ["Content-Type": "text/html"])
        }
        let canvasYes = (try? runAsync { await CanvasClient.looksLikeCanvas(URL(string: "https://canvas.school.edu")!, session: fakeSession()) }.get()) ?? false
        let canvasNo = (try? runAsync { await CanvasClient.looksLikeCanvas(URL(string: "https://www.school.edu")!, session: fakeSession()) }.get()) ?? true
        check("Recognizes a Canvas site by its signed-out API reply", canvasYes)
        check("School main website is not Canvas", !canvasNo)
        let addrDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_CanvasAddr_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: addrDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: addrDir) }
        let addrApp = AppState(storageService: StorageService(customURL: addrDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        let resolved = try? runAsync { await addrApp.resolveCanvasAddress("www.school.edu") }.get()
        check("www.school.edu corrected to canvas.school.edu", resolved?.host == "canvas.school.edu" && addrApp.preferences.canvasBaseURL == "https://canvas.school.edu", "\(String(describing: resolved))")
        check("Correction is explained", addrApp.canvasStatusMessage?.contains("isn't Canvas") == true)
        let notFound = try? runAsync { await addrApp.resolveCanvasAddress("example.org") }.get()
        check("Non-Canvas address gives a clear message", notFound == nil && addrApp.canvasErrorMessage?.contains("doesn't look like a Canvas site") == true)

        // --- Stage 3: Reader end-to-end against a fake Canvas
        print("\n--- Stage 3: Reader ---")
        let soon = ISO8601DateFormatter().string(from: now.addingTimeInterval(3 * 86400))
        let recent = ISO8601DateFormatter().string(from: now.addingTimeInterval(-86400))
        FakeCanvas.handler = { req in
            let path = req.url!.path
            switch path {
            case "/api/v1/users/self": return .init(body: json(["id": 9, "short_name": "Sam"]))
            case "/api/v1/courses": return .init(body: json([["id": 5, "name": "ECON 101"]]))
            case "/api/v1/planner/items": return .init(body: json([
                ["plannable_type": "assignment", "plannable_id": 11, "course_id": 5, "plannable": ["title": "Problem Set 5", "due_at": soon, "points_possible": 10.0], "submissions": ["submitted": false]],
                ["plannable_type": "assignment", "plannable_id": 12, "course_id": 5, "plannable": ["title": "Problem Set 4", "due_at": recent], "submissions": ["submitted": true]]
            ]))
            case "/api/v1/courses/5/assignments": return .init(body: json([["id": 11, "description": "<p>Answer all questions.</p>"]]))
            case "/api/v1/announcements": return .init(body: json([["id": 55, "title": "Quiz moved", "message": "<p>Quiz is Friday</p>", "context_code": "course_5", "posted_at": recent]]))
            case "/api/v1/conversations": return .init(body: json([["id": 70, "subject": "Re: office hours", "last_message_at": recent, "context_name": "ECON 101"]]))
            case "/api/v1/conversations/70": return .init(body: json(["participants": [["id": 1, "name": "Prof. Lee"]], "messages": [["author_id": 1, "body": "Please send me your outline by Monday.", "created_at": recent]]]))
            case "/api/v1/users/self/activity_stream": return .init(body: json([
                ["type": "Submission", "id": 900, "assignment_id": 10, "course_id": 5, "updated_at": recent, "assignment": ["name": "Essay 1"], "submission_comments": [["author_name": "TA Kim", "comment": "Please resubmit with citations."]]],
                ["type": "Message", "id": 901, "updated_at": recent]
            ]))
            case "/api/v1/courses/5": return .init(body: json(["id": 5, "syllabus_body": "<p>Read chapter 1 before week 2.</p>"]))
            case "/api/v1/calendar_events": return .init(body: json([["id": 300, "title": "Midterm", "start_at": soon, "end_at": soon, "context_code": "course_5", "location_name": "Hall 2"]]))
            default: return .init(status: 404, body: "{}")
            }
        }
        let readerClient = CanvasClient(baseURL: base, auth: .token("t"), session: fakeSession())
        let snapResult = runAsync { try await CanvasReader().readEverything(client: readerClient, now: now) }
        let snap = (try? snapResult.get()) ?? CanvasSnapshot()
        check("Reads user name", snap.userName == "Sam", "\(snapResult)")
        check("Reads due items with submission status", snap.dueItems.count == 2 && snap.dueItems.contains { $0.key == "assignment-12" && $0.isSubmitted })
        check("Attaches assignment instructions", snap.dueItems.first { $0.key == "assignment-11" }?.descriptionText == "Answer all questions.")
        let kinds = Set(snap.textItems.map(\.kind))
        check("Reads announcements, inbox, feedback and syllabus", kinds == ["Announcement", "Message", "Feedback", "Syllabus"], "\(kinds)")
        check("Inbox message includes sender and full text", snap.textItems.first { $0.kind == "Message" }?.body.contains("Prof. Lee: Please send me your outline") == true)
        check("Reads course events", snap.events.first?.title == "Midterm" && snap.events.first?.courseName == "ECON 101")
        check("No problems reported", snap.problems.isEmpty, "\(snap.problems)")

        FakeCanvas.handler = { req in
            if req.url!.path == "/api/v1/users/self" { return .init(body: json(["short_name": "Sam"])) }
            if req.url!.path == "/api/v1/courses" { return .init(body: json([["id": 5, "name": "ECON 101"]])) }
            if req.url!.path == "/api/v1/conversations" { return .init(status: 500, body: "{}") }
            return .init(body: "[]")
        }
        let partial = (try? runAsync { try await CanvasReader().readEverything(client: readerClient, now: now) }.get())
        check("One failing section doesn't stop the rest", partial?.problems.count == 1 && partial?.problems.first?.hasPrefix("Inbox") == true, "\(partial?.problems ?? [])")

        // --- Stage 4: Sync into the planner
        print("\n--- Stage 4: Sync ---")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_Canvas_Test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let storage = StorageService(customURL: tempDir.appendingPathComponent("planner_database.json"))
        let keychain = MockKeychain()
        let reader = MockReader()
        let model = MockModel()
        let app = AppState(storageService: storage, calendarService: SimulatedCalendarService(), keychainService: keychain, ollamaService: model, canvasReader: reader, canvasURLSession: fakeSession())

        check("Not connected before sign-in", !app.isCanvasConnected)
        app.setCanvasAddress("canvas.test.edu")
        check("Address saved normalized", app.preferences.canvasBaseURL == "https://canvas.test.edu")
        FakeCanvas.handler = { _ in .init(body: json(["short_name": "Sam"])) }
        let signInCookies = [
            HTTPCookie(properties: [.name: "canvas_session", .value: "secret", .domain: "canvas.test.edu", .path: "/"])!,
            HTTPCookie(properties: [.name: "idp", .value: "x", .domain: "sso.other.com", .path: "/"])!
        ]
        let signedIn = (try? runAsync { await app.completeCanvasSignIn(cookies: signInCookies) }.get()) ?? false
        check("Sign-in accepted and connected", signedIn && app.isCanvasConnected && app.canvasUserName == "Sam")
        let storedCookies = keychain.store[AppState.kCanvasCookies] ?? ""
        check("Only Canvas cookies kept, in Keychain", storedCookies.contains("canvas_session") && !storedCookies.contains("sso.other.com"))
        if let prefsData = try? JSONEncoder().encode(app.preferences), let prefsText = String(data: prefsData, encoding: .utf8) {
            check("No sign-in secrets in the planner database", !prefsText.contains("secret"))
        }

        let dueSoon = now.addingTimeInterval(3 * 86400)
        reader.snapshot = CanvasSnapshot(userName: "Sam", dueItems: [
            due("assignment-11", "Problem Set 5", due: dueSoon, description: "Answer all questions."),
            due("assignment-12", "Problem Set 4", due: now.addingTimeInterval(-86400), submitted: true),
            due("quiz-77", "Quiz 3", kind: "quiz", due: dueSoon.addingTimeInterval(86400)),
            due("assignment-13", "Final Project", due: dueSoon.addingTimeInterval(7 * 86400), points: 100),
            due("assignment-14", "Old Homework", due: now.addingTimeInterval(-10 * 86400))
        ], textItems: [
            CanvasTextItem(key: "announcement-55", kind: "Announcement", title: "Reminder", courseName: "ECON 101", author: "Prof. Lee", postedAt: now, version: "v1", body: "Problem Set 5 is due Friday. Also bring a calculator to lab.", htmlURL: nil)
        ], events: [
            CanvasEvent(key: "event-300", title: "Midterm", courseName: "ECON 101", start: dueSoon, end: dueSoon.addingTimeInterval(7200), isAllDay: false, location: "Hall 2")
        ])
        model.responses["[Canvas Announcement] Reminder"] = EmailAnalysis(isNewsletterOrMarketing: false, isDirectedAtRecipient: true, hasActionableTask: true, reasoning: "two items", tasks: [
            CandidateTask(title: "Problem Set 5", requiredAction: "Submit Problem Set 5"),
            CandidateTask(title: "Bring calculator to lab", requiredAction: "Bring a calculator")
        ])
        _ = runAsync { await app.syncCanvas(now: now); return true }
        let canvasTasks = app.tasks.filter { $0.sourceEmail.category == .canvas }
        check("Upcoming unsubmitted items become tasks (3)", canvasTasks.filter { $0.sourceEmail.id.hasPrefix("canvas-assignment") || $0.sourceEmail.id.hasPrefix("canvas-quiz") }.count == 3, "\(canvasTasks.map(\.title))")
        check("Submitted and long-past items skipped", !app.tasks.contains { $0.title == "Problem Set 4" || $0.title == "Old Homework" })
        let ps5 = app.tasks.first { $0.sourceEmail.id == "canvas-assignment-11" }
        check("Task has exact Canvas due date and is ready to schedule", ps5?.extractedDeadline == dueSoon && ps5?.status == .ready)
        check("Instructions and course on the task", ps5?.notes.contains("Answer all questions.") == true && ps5?.notes.contains("ECON 101") == true)
        check("Estimates by type (quiz 45m, project 240m)", app.tasks.first { $0.title == "Quiz 3" }?.estimatedMinutes == 45 && app.tasks.first { $0.title == "Final Project" }?.estimatedMinutes == 240)
        check("Announcement read by the local model", model.calls.count == 1)
        check("New to-do from announcement added", app.tasks.contains { $0.title == "Bring calculator to lab" })
        check("Announcement reminder didn't duplicate the assignment", app.tasks.filter { $0.title == "Problem Set 5" }.count == 1)
        check("Course event added to timeline", app.commitments.contains { $0.title == "Midterm" && $0.calendarName == "Canvas · ECON 101" && $0.isLocalOnly })
        check("Status summarizes the sync", app.canvasStatusMessage?.contains("3 new tasks") == true, app.canvasStatusMessage ?? "")

        // Re-sync: no duplicates, unchanged text not re-read, events replaced not doubled
        let taskCount = app.tasks.count
        _ = runAsync { await app.syncCanvas(now: now); return true }
        check("Re-sync creates no duplicates", app.tasks.count == taskCount)
        check("Unchanged announcement not analyzed again", model.calls.count == 1)
        check("Course events not doubled", app.commitments.filter { $0.title == "Midterm" }.count == 1)

        // Changes in Canvas
        let newDue = dueSoon.addingTimeInterval(2 * 86400)
        if let i = app.tasks.firstIndex(where: { $0.title == "Final Project" }) { app.tasks[i].userOverriddenDeadline = dueSoon }
        reader.snapshot.dueItems = [
            due("assignment-11", "Problem Set 5", due: newDue),
            due("quiz-77", "Quiz 3", kind: "quiz", due: dueSoon.addingTimeInterval(86400), submitted: true),
            due("assignment-13", "Final Project", due: newDue.addingTimeInterval(86400 * 9), points: 100)
        ]
        reader.snapshot.textItems[0] = CanvasTextItem(key: "announcement-55", kind: "Announcement", title: "Reminder", courseName: "ECON 101", author: "Prof. Lee", postedAt: now, version: "v2", body: "Edited: lab cancelled.", htmlURL: nil)
        _ = runAsync { await app.syncCanvas(now: now); return true }
        let ps5b = app.tasks.first { $0.sourceEmail.id == "canvas-assignment-11" }
        check("Due date change in Canvas updates the task", ps5b?.extractedDeadline == newDue && ps5b?.deadlineUpdateNote?.contains("changed in Canvas") == true)
        check("Your own deadline is never overwritten", app.tasks.first { $0.title == "Final Project" }?.extractedDeadline == dueSoon.addingTimeInterval(7 * 86400))
        check("Submitted quiz marked done", app.tasks.first { $0.title == "Quiz 3" }?.status == .completed)
        check("Edited announcement re-read", model.calls.count == 2)

        // Dismissed tasks stay dismissed
        if let ps5Task = app.tasks.first(where: { $0.sourceEmail.id == "canvas-assignment-11" }) {
            app.dismissTask(taskId: ps5Task.id)
            app.clearDismissedTasks()
        }
        _ = runAsync { await app.syncCanvas(now: now); return true }
        check("Dismissed and cleared Canvas task not recreated", !app.tasks.contains { $0.sourceEmail.id == "canvas-assignment-11" && $0.status != .dismissed })

        // Local model down: structured Canvas data still imported
        model.error = OllamaClient.notRunningError()
        reader.snapshot.dueItems.append(due("assignment-20", "Lab Report", due: dueSoon))
        reader.snapshot.textItems.append(CanvasTextItem(key: "conversation-70", kind: "Message", title: "Outline", courseName: "ECON 101", author: "Prof. Lee", postedAt: now, version: "v1", body: "Send me your outline by Monday.", htmlURL: nil))
        _ = runAsync { await app.syncCanvas(now: now); return true }
        check("Assignments still imported when Ollama is down", app.tasks.contains { $0.title == "Lab Report" })
        check("Explains why messages weren't read", app.canvasErrorMessage?.contains("Ollama isn't running") == true, app.canvasErrorMessage ?? "")
        check("Unread message retried next time (not cached)", app.extractionCache["canvas-conversation-70@v1"] == nil)

        // Expired sign-in
        model.error = nil
        reader.error = CanvasError(kind: .signInRequired, message: "Your Canvas sign-in has expired. Reconnect Canvas in Settings.")
        _ = runAsync { await app.syncCanvas(now: now); return true }
        check("Expired sign-in disconnects and asks to reconnect", !app.isCanvasConnected && app.canvasErrorMessage?.contains("Reconnect") == true)

        // Reload and disconnect
        let reloaded = AppState(storageService: storage, calendarService: SimulatedCalendarService(), keychainService: keychain, ollamaService: model, canvasReader: reader, canvasURLSession: fakeSession())
        check("Canvas address and last sync survive reload", reloaded.preferences.canvasBaseURL == "https://canvas.test.edu" && reloaded.lastCanvasSyncDate != nil)
        check("Canvas tasks survive reload", reloaded.tasks.contains { $0.title == "Lab Report" && $0.sourceEmail.category == .canvas })
        reloaded.disconnectCanvas()
        check("Disconnect removes saved sign-in", keychain.store[AppState.kCanvasCookies] == nil && keychain.store[AppState.kCanvasToken] == nil && !reloaded.isCanvasConnected)
        check("Disconnect keeps imported tasks", reloaded.tasks.contains { $0.title == "Lab Report" })

        // --- Stage 5: Browser-tab mode (like a classmate's script)
        print("\n--- Stage 5: Use My Browser ---")
        let jsURL = URL(string: "https://canvas.test.edu/api/v1/planner/items?start_date=2026-11-01&per_page=100")!
        let js = CanvasBrowserTransport.javaScript(for: jsURL)
        check("Request runs same-origin in the tab (relative path + query)", js.contains("'/api/v1/planner/items?start_date=2026-11-01&per_page=100'") && !js.contains("https://"))
        check("Only GET requests from the browser", js.contains("x.open('GET'") && !js.contains("POST"))
        let pre = ["https://canvas.test.edu"]
        check("Safari script uses 'do JavaScript'", CanvasBrowser.safari.script(js: "1+1", prefixes: pre).contains("do JavaScript \"1+1\" in t"))
        check("Chrome/Arc scripts use 'execute ... javascript'", CanvasBrowser.chrome.script(js: "1+1", prefixes: pre).contains("execute t javascript \"1+1\"") && CanvasBrowser.arc.script(js: nil, prefixes: pre).contains("company.thebrowser.Browser"))
        check("Scripts target browsers by bundle ID", CanvasBrowser.allCases.allSatisfy { $0.script(js: nil, prefixes: pre).contains("tell application id \"\($0.bundleIdentifier)\"") })
        for browser in CanvasBrowser.allCases where browser.isInstalled {
            // Compile only (never runs, so no permission prompt). Skipped for browsers not installed,
            // since compiling a script for a missing app makes macOS ask where it is.
            var compileError: NSDictionary?
            let compiled = NSAppleScript(source: browser.script(js: CanvasBrowserTransport.javaScript(for: URL(string: "https://canvas.test.edu/api/v1/users/self?x='y'")!), prefixes: pre))?.compileAndReturnError(&compileError) ?? false
            check("\(browser.displayName) script compiles", compiled, "\(compileError ?? [:])")
        }
        let quoted = CanvasBrowser.safari.script(js: "a \"b\" \\ c", prefixes: pre)
        check("JavaScript safely quoted for AppleScript", quoted.contains("\"a \\\"b\\\" \\\\ c\""), quoted)
        check("Installed check works (Safari is always installed)", CanvasBrowser.safari.isInstalled)
        let tabOutput = json(["status": 200, "link": "<https://canvas.test.edu/api/v1/x?page=2>; rel=\"next\"", "type": "application/json", "url": "https://canvas.test.edu/api/v1/x", "body": "while(1);[{\"id\":1}]"])
        if let (data, resp) = try? CanvasBrowserTransport.response(fromOutput: tabOutput, browser: .safari, requestURL: jsURL),
           let http = resp as? HTTPURLResponse {
            check("Tab result becomes a normal response (status, paging, body)", http.statusCode == 200 && http.value(forHTTPHeaderField: "Link")?.contains("page=2") == true && (try? CanvasClient.parseJSON(data) as? [[String: Any]])?.count == 1)
        } else { check("Tab result becomes a normal response", false) }
        func setupMessage(_ out: String) -> String {
            do { _ = try CanvasBrowserTransport.response(fromOutput: out, browser: .chrome, requestURL: jsURL); return "" } catch { return error.localizedDescription }
        }
        let noTab = setupMessage("PP_NO_TAB|https://www.google.com/search?q=x\nhttps://mail.google.com/mail")
        check("No Canvas tab explained, listing open sites", noTab.contains("No canvas.test.edu tab found in Chrome") && noTab.contains("mail.google.com") && noTab.contains("www.google.com"), noTab)
        check("No visible tabs hints at the Automation permission", setupMessage("PP_NO_TAB|").contains("Automation"))
        check("Browser closed explained", setupMessage("PP_NOT_RUNNING").contains("Chrome isn't open"))
        check("Missing Automation permission explained", CanvasBrowserTransport.error(fromStderr: "execution error: Not authorized to send Apple events to Safari. (-1743)").message.contains("Privacy & Security → Automation"))
        check("Blocked JavaScript explained", CanvasBrowserTransport.error(fromStderr: "execution error: Google Chrome got an error: Executing JavaScript through AppleScript is turned off.").message.contains("Allow JavaScript from Apple Events"))
        let stateu = CanvasBrowserTransport(browser: .safari, canvasHost: "canvas.stateu.edu")
        check("Also matches <school>.instructure.com tabs", Mirror(reflecting: stateu).children.contains { ($0.value as? [String])?.contains("stateu.instructure.com") == true })

        let browserDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_CanvasBrowser_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: browserDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: browserDir) }
        let browserKeychain = MockKeychain()
        let browserReader = MockReader()
        let browserApp = AppState(storageService: StorageService(customURL: browserDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: browserKeychain, ollamaService: MockModel(), canvasReader: browserReader, canvasURLSession: fakeSession())
        browserApp.setCanvasAddress("canvas.test.edu")
        var tabRequests: [String] = []
        var tabSignedIn = true
        browserApp.canvasBrowserTransportFactory = { browser, host in
            return { request in
                tabRequests.append("\(browser.rawValue) \(host) \(request.url?.path ?? "")")
                let body = tabSignedIn ? "{\"short_name\":\"Sam\"}" : "{\"status\":\"unauthenticated\"}"
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: tabSignedIn ? 200 : 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
        }
        _ = runAsync { await browserApp.connectCanvasThroughBrowser(.safari); return true }
        check("Connects through the Safari tab", browserApp.isCanvasConnected && browserApp.preferences.canvasBrowser == .safari && browserApp.canvasUserName == "Sam")
        check("Asked Canvas through the browser for the right site", tabRequests.first == "Safari canvas.test.edu /api/v1/users/self")
        check("Nothing stored in Keychain in browser mode", browserKeychain.store.isEmpty)
        browserReader.snapshot = CanvasSnapshot(userName: "Sam", dueItems: [due("assignment-50", "Reading Response", due: now.addingTimeInterval(86400))])
        _ = runAsync { await browserApp.syncCanvas(now: now); return true }
        check("Sync works in browser mode", browserApp.tasks.contains { $0.title == "Reading Response" })
        browserReader.error = CanvasError(kind: .signInRequired, message: "expired")
        _ = runAsync { await browserApp.syncCanvas(now: now); return true }
        check("Signed-out tab asks to sign in there, stays connected", browserApp.isCanvasConnected && browserApp.canvasErrorMessage?.contains("signed out") == true)
        tabSignedIn = false
        _ = runAsync { await browserApp.connectCanvasThroughBrowser(.chrome); return true }
        check("Connecting to a signed-out tab explains it", browserApp.canvasErrorMessage?.contains("isn't signed in") == true && browserApp.preferences.canvasBrowser == .safari)
        let reloadedBrowser = AppState(storageService: StorageService(customURL: browserDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: browserKeychain, canvasURLSession: fakeSession())
        check("Browser choice survives reload", reloadedBrowser.preferences.canvasBrowser == .safari && reloadedBrowser.isCanvasConnected)
        browserApp.disconnectCanvas()
        check("Disconnect turns browser mode off", browserApp.preferences.canvasBrowser == nil && !browserApp.isCanvasConnected)

        // --- Stage 6: Gradescope
        print("\n--- Stage 6: Gradescope ---")
        let accountHTML = """
        <div id="account-show">
          <h2 class="pageHeading">Instructor Courses</h2>
          <div class="courseList"><div class="courseList--term">Fall 2026</div>
            <a class="courseBox" href="/courses/900"><h3 class="courseBox--shortname">ECON 101 (TA)</h3><div class="courseBox--name">Intro</div></a>
          </div>
          <h2 class="pageHeading">Student Courses</h2>
          <div class="courseList">
            <div class="courseList--term">Fall 2026</div>
            <a class="courseBox" href="/courses/111"><h3 class="courseBox--shortname">ECON 2010</h3><div class="courseBox--name">Microeconomic Analysis</div></a>
            <a class="courseBox" href="/courses/222"><h3 class="courseBox--shortname">ECON 2020</h3><div class="courseBox--name">Dynamic Stochastic</div></a>
            <div class="courseList--term">Spring 2026</div>
            <a class="courseBox" href="/courses/333"><h3 class="courseBox--shortname">ECON 470</h3><div class="courseBox--name">Old course</div></a>
          </div>
        </div>
        """
        let courseHTML = """
        <table id="assignments-student-table"><thead><tr role="row"><th>Name</th><th>Status</th><th>Dates</th></tr></thead><tbody>
          <tr role="row"><th class="table--primaryLink" scope="row"><button class="js-submitAssignment" data-assignment-id="501">Problem Set 6</button></th>
            <td><div class="submissionStatus"><div class="submissionStatus--text">No Submission</div></div></td>
            <td><time class="submissionTimeChart--releaseDate" datetime="2026-11-01 09:00:00 -0700">Nov 01</time>
                <time class="submissionTimeChart--dueDate" datetime="2026-11-12 23:59:00 -0800">Due Nov 12</time>
                <time class="submissionTimeChart--dueDate" datetime="2026-11-14 23:59:00 -0800">Late Due Nov 14</time></td></tr>
          <tr role="row"><th class="table--primaryLink" scope="row"><a href="/courses/111/assignments/502/submissions/9001">Problem Set 5</a></th>
            <td><div class="submissionStatus"><div class="submissionStatus--text">Submitted</div></div></td>
            <td><time class="submissionTimeChart--dueDate" datetime="2026-11-05 23:59:00 -0800">Due</time></td></tr>
          <tr role="row"><th class="table--primaryLink" scope="row"><a href="/courses/111/assignments/503/submissions/9002">Midterm</a></th>
            <td><div class="submissionStatus"><div class="submissionStatus--score">18.0 / 20.0</div></div></td>
            <td><time class="submissionTimeChart--dueDate" datetime="2026-10-20 12:00:00 -0700">Due</time></td></tr>
          <tr role="row"><th class="table--primaryLink" scope="row">Final Exam</th><td>No Submission</td>
            <td><time class="submissionTimeChart--dueDate" datetime="2026-12-10 10:00:00 -0800">Due</time></td></tr>
          <tr role="row"><td colspan="3">Showing 4 assignments</td></tr>
        </tbody></table>
        """
        let parsedPages: Result<String, Error> = runAsync {
            let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
            web.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://www.gradescope.com/"))
            let started = Date()
            while web.isLoading && Date().timeIntervalSince(started) < 10 { try await Task.sleep(nanoseconds: 50_000_000) }
            let out = try await web.callAsyncJavaScript(GradescopeReader.parserJS + "\nreturn JSON.stringify({a: ppParseAccount(acct), c: ppParseCourse(course)});",
                                                        arguments: ["acct": accountHTML, "course": courseHTML], contentWorld: .defaultClient)
            return out as? String ?? ""
        }
        let pages = (try? JSONSerialization.jsonObject(with: Data(((try? parsedPages.get()) ?? "").utf8)) as? [String: Any]) ?? [:]
        let parsedCourses = pages["a"] as? [[String: Any]] ?? []
        let parsedRows = pages["c"] as? [[String: Any]] ?? []
        check("Real page parser runs (WebKit DOMParser)", !pages.isEmpty, "\(parsedPages)")
        check("Only student courses are read (TA course skipped)", parsedCourses.count == 3 && !parsedCourses.contains { $0["id"] as? String == "900" }, "\(parsedCourses)")
        check("Current term marked (Fall 2026 = term 0)", parsedCourses.filter { ($0["termIndex"] as? Int) == 0 }.compactMap { $0["id"] as? String } == ["111", "222"])
        check("All 4 assignment rows parsed, header/footer skipped", parsedRows.count == 4, "\(parsedRows)")
        check("Unsubmitted button row: id, due and late due", parsedRows.first?["id"] as? String == "501" && parsedRows.first?["lateDue"] as? String == "2026-11-14 23:59:00 -0800")
        check("Linked row id taken from /assignments/<id>/", parsedRows.dropFirst().first?["id"] as? String == "502")
        check("Graded row keeps the score as status", (parsedRows.dropFirst(2).first?["status"] as? String)?.contains("18.0 / 20.0") == true)
        check("Plain-text row (no link yet) still parsed", parsedRows.last?["title"] as? String == "Final Exam" && parsedRows.last?["id"] is NSNull)

        let liveOutput = json(["signedIn": true, "courses": [["id": "111", "short": "ECON 2010", "name": "Micro", "term": "Fall 2026", "status": 200, "assignments": parsedRows]]])
        let gsAssignments = (try? GradescopeReader.parse(liveOutput)) ?? []
        check("Assignments parsed with course name", gsAssignments.count == 4 && gsAssignments.allSatisfy { $0.courseName == "ECON 2010" })
        let ps6 = gsAssignments.first { $0.title == "Problem Set 6" }
        check("Gradescope dates read with time zone", ps6?.dueAt == ISO8601DateFormatter().date(from: "2026-11-13T07:59:00Z"), "\(String(describing: ps6?.dueAt))")
        check("Submission status understood", ps6?.isSubmitted == false && gsAssignments.first { $0.title == "Problem Set 5" }?.isSubmitted == true && gsAssignments.first { $0.title == "Midterm" }?.isSubmitted == true)
        check("Stable key without an assignment link", gsAssignments.first { $0.title == "Final Exam" }?.key.hasPrefix("gradescope-111-") == true)
        do { _ = try GradescopeReader.parse(json(["signedIn": false, "status": 302])); check("Signed-out Gradescope explained", false) }
        catch { check("Signed-out Gradescope explained", error.localizedDescription.contains("isn't signed in")) }

        let gsDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_Gradescope_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: gsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: gsDir) }
        let gsApp = AppState(storageService: StorageService(customURL: gsDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        // The fixture is written for Nov 6, 2026. connectGradescope syncs with the real clock, so every
        // fixture date is moved forward by whole days to keep "now" on the fixture's Nov 6.
        let gsFixtureNow = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
        let gsShift = max(0, (Date().timeIntervalSince(gsFixtureNow) / 86400).rounded(.up)) * 86400
        let gsNow = gsFixtureNow.addingTimeInterval(gsShift)
        func gsMoved(_ d: Date?) -> Date? { d?.addingTimeInterval(gsShift) }
        let gsCurrent = gsAssignments.map { GradescopeAssignment(courseId: $0.courseId, courseName: $0.courseName, assignmentId: $0.assignmentId, title: $0.title, status: $0.status, releaseAt: gsMoved($0.releaseAt), dueAt: gsMoved($0.dueAt), lateDueAt: gsMoved($0.lateDueAt)) }
        // Same assignment already imported from Canvas (different course naming, due within a day).
        let twinDue = ISO8601DateFormatter().date(from: "2026-12-10T18:30:00Z")!.addingTimeInterval(gsShift)
        let canvasTwin = AppState.makeCanvasTask(due("assignment-77", "Final Exam", course: "ECON-S2010-S01 - Microeconomic Analysis", due: twinDue), sourceId: "canvas-assignment-77", due: twinDue, dueText: "Dec 10", now: gsNow)
        gsApp.tasks.append(canvasTwin)
        var gsFeed = gsCurrent
        gsApp.gradescopeReadOverride = { _ in gsFeed }
        _ = runAsync { await gsApp.connectGradescope(.safari); return true }
        let gsTasks = gsApp.tasks.filter { $0.sourceEmail.category == .gradescope }
        check("Connected to Gradescope through Safari", gsApp.preferences.gradescopeBrowser == .safari)
        check("Only open future work imported (PS6)", gsTasks.map(\.title) == ["Problem Set 6"], "\(gsTasks.map(\.title)) \(gsApp.gradescopeStatusMessage ?? "") \(gsApp.gradescopeErrorMessage ?? "")")
        check("Not added twice when Canvas has the same assignment", gsApp.tasks.filter { $0.title == "Final Exam" }.count == 1)
        check("Gradescope task says where to submit and the late deadline", gsTasks.first?.requiredAction.contains("Submit on Gradescope") == true && gsTasks.first?.notes.contains("Late submissions accepted") == true)
        check("Task links to Gradescope", gsTasks.first?.sourceEmail.webLink == "https://www.gradescope.com/courses/111/assignments/501")
        // Submitting on Gradescope marks the task done
        gsFeed = gsFeed.map { $0.title == "Problem Set 6" ? GradescopeAssignment(courseId: $0.courseId, courseName: $0.courseName, assignmentId: $0.assignmentId, title: $0.title, status: "Submitted", releaseAt: $0.releaseAt, dueAt: $0.dueAt, lateDueAt: $0.lateDueAt) : $0 }
        _ = runAsync { await gsApp.syncGradescope(now: gsNow); return true }
        check("Submitted on Gradescope → task done", gsApp.tasks.first { $0.title == "Problem Set 6" }?.status == .completed)
        check("Re-sync adds nothing new", gsApp.tasks.filter { $0.sourceEmail.category == .gradescope }.count == 1)
        gsApp.gradescopeReadOverride = { _ in throw CanvasError(kind: .setup, message: "No www.gradescope.com tab found in Safari.") }
        _ = runAsync { await gsApp.syncGradescope(now: gsNow); return true }
        check("Missing Gradescope tab explained", gsApp.gradescopeErrorMessage?.contains("No www.gradescope.com tab") == true)
        let gsBrowserScript = CanvasBrowser.safari.script(js: GradescopeReader.liveJS, prefixes: ["https://www.gradescope.com"])
        var gsCompileError: NSDictionary?
        check("Gradescope browser script compiles", NSAppleScript(source: gsBrowserScript)?.compileAndReturnError(&gsCompileError) == true, "\(gsCompileError ?? [:])")

        print("\n--- Task Memory (no duplicates across syncs) ---")
        check("'Problem Set 5' and 'Reminder: Problem Set 5 due Friday' are the same task", TaskMemory.similarity("Problem Set 5", "Reminder: Problem Set 5 due Friday") >= TaskMemory.matchThreshold)
        check("'Lab 3' is never 'Lab 4'", TaskMemory.similarity("CS 420 Lab 3", "CS 420 Lab 4") == 0 && TaskMemory.similarity("Lab 3", "CS 420 Lab 4") == 0)
        check("'Read Chapter 4' is not 'Quiz Chapter 4'", TaskMemory.similarity("Read Chapter 4", "Quiz Chapter 4") < TaskMemory.matchThreshold)
        check("'Lab 3' matches 'CS 420 Lab 3: Raft Consensus'", TaskMemory.similarity("Lab 3 Raft", "CS 420 Lab 3: Raft Consensus Implementation") >= TaskMemory.matchThreshold)

        let memDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_TaskMemory_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: memDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: memDir) }
        let memApp = AppState(storageService: StorageService(customURL: memDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        memApp.tasks = []
        let memNow = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00Z")!
        func mail(_ id: String, thread: String, subject: String, body: String) -> EmailSource {
            EmailSource(id: id, threadId: thread, senderName: "Prof. Lee", senderEmail: "lee@school.edu", subject: subject,
                        receivedDate: memNow, snippet: body, fullBody: body, category: .assignment, isSimulatedDemo: false)
        }
        func analysis(_ t: CandidateTask) -> EmailAnalysis {
            EmailAnalysis(isNewsletterOrMarketing: false, isDirectedAtRecipient: true, hasActionableTask: true, reasoning: "", tasks: [t])
        }
        var d = 0, u = 0, n = 0, r = 0
        memApp.applyAnalysis(analysis(CandidateTask(title: "Problem Set 5", requiredAction: "Submit Problem Set 5", deadlineIso: "2026-11-10T23:59:00-08:00", deadlineIsSupportedByEmail: true, supportingExcerpt: "Problem Set 5 is due Tuesday at 11:59 PM.")),
                             for: mail("m1", thread: "t1", subject: "PS5", body: "Problem Set 5 is due Tuesday."), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        check("First email creates the task", memApp.tasks.count == 1 && d == 1)
        let originalId = memApp.tasks.first?.id
        // Same task, different email and thread, same deadline, nothing new
        memApp.applyAnalysis(analysis(CandidateTask(title: "Reminder: Problem Set 5", requiredAction: "Submit Problem Set 5", deadlineIso: "2026-11-10T23:59:00-08:00", deadlineIsSupportedByEmail: true, supportingExcerpt: "Problem Set 5 is due Tuesday at 11:59 PM.")),
                             for: mail("m2", thread: "t2", subject: "Reminder", body: "Reminder"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        check("A repeat from another email is not added again", memApp.tasks.count == 1)
        check("A repeat with nothing new shows no Updated reminder", memApp.tasks.first?.hasUnseenUpdate == false)
        // New information: deadline moved and extra details
        memApp.applyAnalysis(analysis(CandidateTask(title: "Problem Set 5", requiredAction: "Submit Problem Set 5", deadlineIso: "2026-11-12T23:59:00-08:00", deadlineIsSupportedByEmail: true, supportingExcerpt: "Extension: Problem Set 5 now due Thursday; question 4 is optional.", isDeadlineUpdate: true, deadlineUpdateNote: "Extended to Thursday; question 4 is optional")),
                             for: mail("m3", thread: "t3", subject: "Extension", body: "Extended"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        let updatedTask = memApp.tasks.first
        check("New information updates the original task (no duplicate)", memApp.tasks.count == 1 && updatedTask?.id == originalId)
        var memPT = Calendar(identifier: .gregorian)
        memPT.timeZone = memApp.preferences.timeZone
        check("Moved deadline applied to the original (now Nov 12)",
              updatedTask?.extractedDeadline.map { memPT.component(.day, from: $0) } == 12, "\(String(describing: updatedTask?.extractedDeadline))")
        check("Original task shows the Updated reminder with what changed",
              updatedTask?.hasUnseenUpdate == true && updatedTask?.syncUpdate?.summary.contains("Due date moved") == true
              && updatedTask?.syncUpdate?.summary.contains("New details") == true, updatedTask?.syncUpdate?.summary ?? "nil")
        check("New details added to the task's notes", updatedTask?.notes.contains("question 4 is optional") == true)
        memApp.acknowledgeTaskUpdate(taskId: originalId!)
        check("Got It hides the Updated reminder", memApp.tasks.first?.hasUnseenUpdate == false)
        // Completed task is remembered: never found again
        memApp.completeTask(taskId: originalId!)
        memApp.applyAnalysis(analysis(CandidateTask(title: "Problem Set 5", requiredAction: "Submit Problem Set 5", deadlineIso: "2026-11-12T23:59:00-08:00", deadlineIsSupportedByEmail: true, supportingExcerpt: "Don't forget Problem Set 5!")),
                             for: mail("m4", thread: "t4", subject: "Don't forget", body: "x"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        check("A completed task is not found again", memApp.tasks.count == 1 && memApp.tasks.first?.status == .completed)
        // Weekly task with the same name a week later is a new occurrence
        memApp.applyAnalysis(analysis(CandidateTask(title: "Weekly Reading Quiz", requiredAction: "Take quiz", deadlineIso: "2026-11-09T09:00:00-08:00", deadlineIsSupportedByEmail: true)),
                             for: mail("m5", thread: "t5", subject: "Quiz", body: "x"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        memApp.applyAnalysis(analysis(CandidateTask(title: "Weekly Reading Quiz", requiredAction: "Take quiz", deadlineIso: "2026-11-16T09:00:00-08:00", deadlineIsSupportedByEmail: true)),
                             for: mail("m6", thread: "t6", subject: "Quiz", body: "x"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        check("Same name due a week later is a separate task", memApp.tasks.filter { $0.title == "Weekly Reading Quiz" }.count == 2)
        // Dismissed and cleared: stays gone even from a different source
        if let quiz = memApp.tasks.first(where: { $0.title == "Weekly Reading Quiz" }) { memApp.dismissTask(taskId: quiz.id) }
        memApp.clearDismissedTasks()
        let countAfterClear = memApp.tasks.count
        memApp.applyAnalysis(analysis(CandidateTask(title: "Weekly reading quiz", requiredAction: "Take quiz", deadlineIso: "2026-11-09T09:00:00-08:00", deadlineIsSupportedByEmail: true)),
                             for: mail("m7", thread: "t7", subject: "Quiz", body: "x"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        check("A dismissed and cleared task never comes back", memApp.tasks.count == countAfterClear)
        // Found in email first, then Canvas posts it: one task, with Canvas's due date
        memApp.applyAnalysis(analysis(CandidateTask(title: "Essay Outline", requiredAction: "Write essay outline", deadlineIso: "2026-11-11T17:00:00-08:00", deadlineIsSupportedByEmail: true)),
                             for: mail("m8", thread: "t8", subject: "Outline", body: "x"), discoveredCount: &d, updatedCount: &u, newslettersFiltered: &n, nonRecipientFiltered: &r)
        let canvasDue = ISO8601DateFormatter().date(from: "2026-11-12T07:59:00Z")!
        _ = memApp.importCanvasDueItems([due("assignment-300", "Essay Outline", due: canvasDue)], now: memNow)
        check("Canvas doesn't duplicate a task already found in email", memApp.tasks.filter { TaskMemory.similarity($0.title, "Essay Outline") > 0.9 }.count == 1)
        check("Canvas due date updates that task, marked Updated",
              memApp.tasks.first { $0.title == "Essay Outline" }?.extractedDeadline == canvasDue
              // Checked directly: hasUnseenUpdate expires 7 days after memNow by the real clock.
              && memApp.tasks.first { $0.title == "Essay Outline" }?.syncUpdate.map { !$0.isSeen && $0.date == memNow } == true)
        let countBeforeResync = memApp.tasks.count
        _ = memApp.importCanvasDueItems([due("assignment-300", "Essay Outline", due: canvasDue)], now: memNow)
        check("Syncing Canvas again finds nothing new", memApp.tasks.count == countBeforeResync)
        // A task saved without a page link gets it on the next sync
        let noLink = CanvasDueItem(key: "assignment-301", kind: "assignment", title: "Problem Set 4", courseName: "ECON 101", dueAt: canvasDue,
                                   pointsPossible: nil, htmlURL: nil, isSubmitted: false, isMissing: false, descriptionText: "")
        _ = memApp.importCanvasDueItems([noLink], now: memNow)
        let withLink = CanvasDueItem(key: "assignment-301", kind: "assignment", title: "Problem Set 4", courseName: "ECON 101", dueAt: canvasDue,
                                     pointsPossible: nil, htmlURL: "https://canvas.test.edu/courses/1/assignments/301", isSubmitted: false, isMissing: false, descriptionText: "")
        _ = memApp.importCanvasDueItems([withLink], now: memNow)
        check("Re-sync fills in the Canvas page link on an older task",
              memApp.tasks.first { $0.sourceEmail.id == "canvas-assignment-301" }?.sourceEmail.webLink == "https://canvas.test.edu/courses/1/assignments/301")

        print("\n--- Planning: AI estimates, plan changes, morning summary ---")
        let estDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_Estimates_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: estDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: estDir) }
        let estModel = MockModel()
        estModel.estimate = TaskTimeEstimate(minutes: 148, reason: "6 proofs plus a short write-up")
        let estReader = MockReader()
        let estApp = AppState(storageService: StorageService(customURL: estDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), ollamaService: estModel, canvasReader: estReader, canvasURLSession: fakeSession())
        estApp.tasks = []
        estApp.setCanvasAddress("canvas.test.edu")
        estApp.canvasBrowserTransportFactory = { _, _ in { request in (Data("{\"short_name\":\"Sam\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!) } }
        _ = runAsync { await estApp.connectCanvasThroughBrowser(.safari); return true }
        let estNow = Date()
        estReader.snapshot = CanvasSnapshot(userName: "Sam", dueItems: [
            due("assignment-501", "Proof Set 3", due: estNow.addingTimeInterval(4 * 86400), description: "Prove the six lemmas in section 2.3 and write a one-page summary.")
        ])
        _ = runAsync { await estApp.syncCanvas(now: estNow); return true }
        let estTask = estApp.tasks.first { $0.title == "Proof Set 3" }
        check("AI estimate used for a new Canvas assignment (148 → 150 min)", estTask?.estimatedMinutes == 150, "\(String(describing: estTask?.estimatedMinutes))")
        check("Estimate reason shown on the task", estTask?.estimateNote == "AI estimate: 2 h 30 min — 6 proofs plus a short write-up", estTask?.estimateNote ?? "nil")
        check("The model saw the assignment description", estModel.estimateCalls == ["Proof Set 3"])
        _ = runAsync { await estApp.syncCanvas(now: estNow); return true }
        check("Each assignment is estimated only once", estModel.estimateCalls.count == 1)
        estReader.snapshot = CanvasSnapshot(userName: "Sam", dueItems: [
            due("assignment-501", "Proof Set 3", due: estNow.addingTimeInterval(4 * 86400)),
            due("assignment-502", "Lab Writeup", due: estNow.addingTimeInterval(5 * 86400))
        ])
        if let i = estApp.tasks.firstIndex(where: { $0.title == "Proof Set 3" }) { estApp.tasks[i].estimateNote = nil; estApp.tasks[i].userOverriddenDuration = 60 }
        _ = runAsync { await estApp.syncCanvas(now: estNow); return true }
        check("Never re-estimates a task whose time you set", estModel.estimateCalls == ["Proof Set 3", "Lab Writeup"], "\(estModel.estimateCalls)")
        estApp.preferences.aiTimeEstimatesEnabled = false
        estReader.snapshot = CanvasSnapshot(userName: "Sam", dueItems: [due("assignment-503", "Reading Notes", due: estNow.addingTimeInterval(3 * 86400))])
        _ = runAsync { await estApp.syncCanvas(now: estNow); return true }
        check("Estimates can be turned off", !estModel.estimateCalls.contains("Reading Notes"))
        check("Estimate rounding keeps 15 min to 10 h", TaskTimeEstimate(minutes: 3, reason: "").plannedMinutes == 15 && TaskTimeEstimate(minutes: 2000, reason: "").plannedMinutes == 600)

        print("\n--- Estimates from instructions, rubric and attached files ---")
        var detailItem = due("assignment-610", "Data Project", due: Date().addingTimeInterval(6 * 86400), points: 100)
        CanvasReader.applyAssignmentDetails([
            "description": "<p>See <a href=\"/courses/5/files/77/download\">instructions.pdf</a> and <a href=\"https://canvas.test.edu/courses/5/files/78\">rubric</a>. <a href=\"/courses/5/files/77\">again</a></p>",
            "submission_types": ["online_upload", "none"],
            "rubric": [["description": "Analysis", "points": 40, "long_description": "<p>Three regressions</p>"], ["description": "Write-up", "points": 60]]
        ], to: &detailItem)
        check("Linked Canvas files found once each, in order", detailItem.attachmentFileIds == [77, 78], "\(detailItem.attachmentFileIds)")
        check("How it's handed in is read", detailItem.submissionTypes == ["online_upload"])
        check("Rubric criteria read with points", detailItem.rubricText == "- Analysis (40 pts): Three regressions\n- Write-up (60 pts)", detailItem.rubricText)
        check("File links in API form are found too", CanvasReader.fileIds(inHTML: "data-api-endpoint=\"https://x.edu/api/v1/courses/1/files/9\" href=\"/files/12/download?wrap=1\"") == [9, 12])

        let pdfText = CanvasAttachmentReader.extractText(from: textPDF(["Problem 1: derive the estimator.", "Problem 2: simulate 1000 draws.", "Write a 3 page report."]), name: "instructions.pdf", contentType: "application/pdf")
        check("Text read from a PDF", pdfText?.contains("simulate 1000 draws") == true && pdfText?.contains("3 page report") == true, pdfText ?? "nil")
        let docx = try? NSAttributedString(string: "Essay: 1500 words on trade policy.\nCite five sources.").data(from: NSRange(location: 0, length: 51), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        let docxText = docx.flatMap { CanvasAttachmentReader.extractText(from: $0, name: "prompt.docx", contentType: "") }
        check("Text read from a Word file", docxText?.contains("1500 words") == true, docxText ?? "nil")
        check("A sign-in page is never taken as the file", CanvasAttachmentReader.extractText(from: Data("<!DOCTYPE html><html>Log in</html>".utf8), name: "a.pdf", contentType: "application/pdf") == nil)
        check("Unsupported files are skipped", CanvasAttachmentReader.kind(name: "slides.pptx", contentType: "application/vnd.ms-powerpoint") == nil)

        FakeCanvas.handler = { req in
            switch req.url!.path {
            case "/files/77": return .init(headers: ["Content-Type": "application/pdf"], data: textPDF(["Answer all 6 questions.", "Each needs a short proof."]))
            case "/files/78": return .init(body: "<!DOCTYPE html><html><body>Please log in</body></html>", headers: ["Content-Type": "text/html"])
            default: return .init(status: 404, body: "")
            }
        }
        let fileReader = CanvasAttachmentReader(session: fakeSession())
        let readPDF = runAsync { await fileReader.read(fileId: 77, info: ["display_name": "instructions.pdf", "content-type": "application/pdf", "size": 2000, "url": "https://files.test.edu/files/77", "updated_at": "v1"]) }
        if case .success(.text(let name, let text)) = readPDF {
            check("Attached PDF downloaded and read", name == "instructions.pdf" && text.contains("6 questions"), text)
        } else { check("Attached PDF downloaded and read", false, "\(readPDF)") }
        _ = runAsync { await fileReader.read(fileId: 77, info: ["display_name": "instructions.pdf", "content-type": "application/pdf", "url": "https://files.test.edu/files/77", "updated_at": "v1"]) }
        check("An unchanged file is read only once", fileReader.downloads == 1)
        let readLogin = runAsync { await fileReader.read(fileId: 78, info: ["display_name": "rubric.pdf", "content-type": "application/pdf", "url": "https://files.test.edu/files/78"]) }
        check("A file behind a sign-in page is reported, not guessed", (try? readLogin.get()) == .unreadable(name: "rubric.pdf", reason: "Canvas asked to sign in for this file"), "\(readLogin)")
        let readLocked = runAsync { await fileReader.read(fileId: 79, info: ["display_name": "key.pdf", "locked_for_user": true, "url": "https://files.test.edu/files/79"]) }
        check("Locked and oversized files aren't downloaded", { if case .unreadable? = try? readLocked.get() { return true } else { return false } }()
              && (try? runAsync { await fileReader.read(fileId: 80, info: ["display_name": "big.pdf", "size": 40_000_000, "url": "https://files.test.edu/files/80"]) }.get()) == .unreadable(name: "big.pdf", reason: "too large")
              && fileReader.downloads == 2)

        FakeCanvas.handler = { _ in .init(headers: ["Content-Type": "application/pdf"], data: Data(repeating: 0x41, count: 5000)) }
        let smallReader = CanvasAttachmentReader(session: fakeSession())
        smallReader.maxBytes = 1000
        let readHuge = runAsync { await smallReader.read(fileId: 81, info: ["display_name": "huge.pdf", "content-type": "application/pdf", "url": "https://files.test.edu/files/81"]) }
        check("A download stops at the size limit even when Canvas gives no size", (try? readHuge.get()) == .unreadable(name: "huge.pdf", reason: "too large"), "\(readHuge)")
        check("Files are only fetched over https", (try? runAsync { await smallReader.read(fileId: 82, info: ["display_name": "a.pdf", "url": "http://files.test.edu/files/82"]) }.get()) == .unreadable(name: "a.pdf", reason: "Canvas gave no download link"))
        detailItem.attachmentText = "Attached file \"instructions.pdf\":\nAnswer all 6 questions."
        detailItem.attachmentNames = ["instructions.pdf"]
        detailItem.unreadableAttachments = ["rubric.pdf"]
        let details = AppState.assignmentDetails(for: detailItem) ?? ""
        check("Assignment details combine handed-in type, rubric and files", details.contains("Handed in as: upload") && details.contains("Rubric:\n- Analysis") && details.contains("6 questions") && details.contains("couldn't be read: rubric.pdf"), details)

        let ctxDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_EstimateCtx_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: ctxDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ctxDir) }
        let ctxModel = MockModel()
        ctxModel.estimate = TaskTimeEstimate(minutes: 300, reason: "6 proofs and a 3 page report", confidence: "high")
        let ctxApp = AppState(storageService: StorageService(customURL: ctxDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), ollamaService: ctxModel, canvasReader: MockReader(), canvasURLSession: fakeSession())
        ctxApp.tasks = []
        ctxApp.preferences.estimateHistory = [EstimateRecord(kind: "problem set", course: "ECON 101", title: "Problem Set 2", estimatedMinutes: 60, actualMinutes: 95, date: Date())]
        let ctxNow = Date()
        _ = ctxApp.importCanvasDueItems([
            detailItem,
            due("assignment-611", "Problem Set 3", due: ctxNow.addingTimeInterval(3 * 86400), points: 20),
            due("assignment-612", "Problem Set 4", due: ctxNow.addingTimeInterval(9 * 86400), points: 20),
            due("assignment-613", "Seminar Reflection 3", due: ctxNow.addingTimeInterval(4 * 86400), points: 5)
        ], now: ctxNow)
        _ = runAsync { await ctxApp.estimateLMSTaskTimes(now: ctxNow); return true }
        let projectContext = zip(ctxModel.estimateCalls, ctxModel.estimateContexts).first { $0.0 == "Data Project" }?.1 ?? ""
        check("The model sees the rubric and attached files", projectContext.contains("Rubric:") && projectContext.contains("6 questions"), projectContext)
        check("…points compared with the course's other assignments", projectContext.contains("Points: 100 (other assignments in this course: typically 20 points)"), projectContext)
        check("…and your recorded times in that course", projectContext.contains("\"Problem Set 2\" planned 1 h, took 1 h 35 min"), projectContext)
        let project = ctxApp.tasks.first { $0.title == "Data Project" }
        check("A well-described assignment keeps the model's confidence", project?.estimateConfidence == "high" && project?.needsEstimateCheck == false)
        let reflection = ctxApp.tasks.first { $0.title == "Seminar Reflection 3" }
        check("A title-only assignment is marked Check Estimate", reflection?.estimateConfidence == "low" && reflection?.needsEstimateCheck == true
              && ctxModel.estimateContexts.contains { $0.contains("No instructions available (title only).") })
        ctxApp.confirmEstimate(taskId: reflection!.id)
        check("Looks Right clears the check", ctxApp.tasks.first { $0.id == reflection!.id }?.needsEstimateCheck == false)
        let callsBefore = ctxModel.estimateCalls.count
        _ = runAsync { await ctxApp.estimateLMSTaskTimes(now: ctxNow); return true }
        check("Nothing changed, nothing estimated again", ctxModel.estimateCalls.count == callsBefore)
        _ = ctxApp.importCanvasDueItems([due("assignment-613", "Seminar Reflection 3", due: ctxNow.addingTimeInterval(4 * 86400), points: 5,
                                             description: "Write a 2 page reflection on the last three seminar talks, with one question for each speaker.")], now: ctxNow)
        _ = runAsync { await ctxApp.estimateLMSTaskTimes(now: ctxNow); return true }
        check("New instructions in Canvas mean a new estimate", ctxModel.estimateCalls.count == callsBefore + 1 && ctxModel.estimateCalls.last == "Seminar Reflection 3")
        check("…which is no longer a guess", ctxApp.tasks.first { $0.id == reflection!.id }?.estimateConfidence == "high")
        if let i = ctxApp.tasks.firstIndex(where: { $0.title == "Problem Set 3" }) { ctxApp.tasks[i].userOverriddenDuration = 45 }
        _ = ctxApp.importCanvasDueItems([due("assignment-611", "Problem Set 3", due: ctxNow.addingTimeInterval(3 * 86400), points: 20, description: "Ten problems from chapter 4, show all work.")], now: ctxNow)
        _ = runAsync { await ctxApp.estimateLMSTaskTimes(now: ctxNow); return true }
        check("A time you set is never estimated again, even with new instructions", ctxModel.estimateCalls.filter { $0 == "Problem Set 3" }.count == 1)

        // What the re-plan changed
        let tA = DiscoveredTask(title: "Essay Draft", sourceEmail: mailSource("pc1"))
        let tB = DiscoveredTask(title: "Problem Set 6", sourceEmail: mailSource("pc2"))
        let tC = DiscoveredTask(title: "Lab Report", sourceEmail: mailSource("pc3"))
        let planBase = Calendar.current.startOfDay(for: Date()).addingTimeInterval(2 * 86400 + 10 * 3600)
        func sess(_ t: DiscoveredTask, _ offsetHours: Double) -> WorkSession {
            WorkSession(taskId: t.id, title: t.title, startTime: planBase.addingTimeInterval(offsetHours * 3600), endTime: planBase.addingTimeInterval(offsetHours * 3600 + 3600), status: .planned)
        }
        let before = [sess(tB, 0), sess(tC, 3)]
        let after = [sess(tA, 1), sess(tB, 2)]
        let planChanges = AppState.describePlanChanges(before: before, after: after, tasks: [tA, tB, tC], now: Date())
        check("Plan changes list what was added, moved and dropped",
              planChanges.count == 3 && planChanges.contains { $0.hasPrefix("Essay Draft added") }
              && planChanges.contains { $0.hasPrefix("Problem Set 6 moved to") } && planChanges.contains("Lab Report no longer planned"), "\(planChanges)")
        check("An unchanged plan reports nothing", AppState.describePlanChanges(before: before, after: before, tasks: [tB, tC], now: Date()).isEmpty)

        // Morning summary
        var pt2 = Calendar(identifier: .gregorian)
        pt2.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let morning = pt2.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8, minute: 5))!
        func at9(_ h: Int, _ m: Int = 0) -> Date { pt2.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: h, minute: m))! }
        var lab = DiscoveredTask(title: "CS 420 Lab 3", sourceEmail: mailSource("ms1"), extractedDeadline: at9(23, 59), isDeadlineSupportedByEmail: true, status: .ready)
        lab.userPriority = .high
        let unclear = DiscoveredTask(title: "Slide 8 diagrams", sourceEmail: mailSource("ms2"), status: .needsClarification)
        let todaySessions = [WorkSession(taskId: lab.id, title: "Lab", startTime: at9(9), endTime: at9(10), status: .planned),
                             WorkSession(taskId: lab.id, title: "Lab", startTime: at9(13), endTime: at9(14), status: .planned),
                             WorkSession(taskId: lab.id, title: "Lab", startTime: at9(15), endTime: at9(16), status: .planned)]
        let summary = AppState.morningSummary(tasks: [lab, unclear], sessions: todaySessions, commitments: [], now: morning, timeZone: pt2.timeZone)
        check("Morning summary lists sessions, what's due and what needs you",
              summary?.body == "3 work sessions (first at 9:00 AM) · CS 420 Lab 3 due 11:59 PM · 1 task needs clarification", summary?.body ?? "nil")
        check("Nothing today → no notification", AppState.morningSummary(tasks: [], sessions: [], commitments: [], now: morning, timeZone: pt2.timeZone) == nil)

        var sent: [String] = []
        let msApp = AppState(storageService: StorageService(customURL: estDir.appendingPathComponent("ms.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        msApp.morningSummarySender = { _, body in sent.append(body) }
        msApp.preferences.timeZoneIdentifier = "America/Los_Angeles"
        msApp.preferences.autoSyncEnabled = false
        msApp.tasks = [lab, unclear]
        msApp.workSessions = todaySessions
        msApp.sendMorningSummaryIfDue(now: at9(7, 30))
        check("No morning summary before 8 AM", sent.isEmpty)
        msApp.sendMorningSummaryIfDue(now: at9(8, 5))
        msApp.sendMorningSummaryIfDue(now: at9(9, 30))
        check("Morning summary sent once a day", sent.count == 1, "\(sent)")
        msApp.preferences.autoSyncEnabled = true
        msApp.preferences.lastMorningSummaryDate = nil
        msApp.preferences.lastFullSyncDate = at9(7, 0)
        sent = []
        msApp.sendMorningSummaryIfDue(now: at9(8, 1))
        check("With auto sync on, it waits for the 8 AM sync", sent.isEmpty)
        msApp.preferences.lastFullSyncDate = at9(8, 3)
        msApp.sendMorningSummaryIfDue(now: at9(8, 6))
        check("…and is sent right after it", sent.count == 1)
        msApp.preferences.morningSummaryEnabled = false
        msApp.preferences.lastMorningSummaryDate = nil
        sent = []
        msApp.sendMorningSummaryIfDue(now: at9(8, 6))
        check("Morning summary can be turned off", sent.isEmpty)

        print("\n--- Daily planner: steady today, learning, evening check-in ---")
        // 1. Keep today steady
        var wcal = Calendar(identifier: .gregorian)
        wcal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var wed = wcal.startOfDay(for: Date())
        repeat { wed = wcal.date(byAdding: .day, value: 1, to: wed)! } while wcal.component(.weekday, from: wed) != 4
        func onWed(_ h: Int, _ m: Int = 0) -> Date { wcal.date(bySettingHour: h, minute: m, second: 0, of: wed)! }
        var steadyPrefs = UserPreferences()
        steadyPrefs.timeZoneIdentifier = "America/Los_Angeles"
        let taskA = DiscoveredTask(title: "Essay Outline", sourceEmail: mailSource("st1"), extractedDeadline: wcal.date(byAdding: .day, value: 3, to: onWed(17))!, isDeadlineSupportedByEmail: true, estimatedMinutes: 60, status: .ready, isClarified: true)
        var taskB = DiscoveredTask(title: "Urgent Form", sourceEmail: mailSource("st2"), extractedDeadline: wcal.date(byAdding: .day, value: 1, to: onWed(12))!, isDeadlineSupportedByEmail: true, estimatedMinutes: 60, status: .ready, isClarified: true)
        taskB.userPriority = .urgent
        let afternoon = WorkSession(taskId: taskA.id, title: taskA.title, startTime: onWed(9), endTime: onWed(10), status: .planned)
        let engine = RuleBasedSchedulingEngine()
        let range = wcal.startOfDay(for: wed)...wcal.date(byAdding: .day, value: 7, to: wed)!
        let steady = engine.generateSchedule(tasks: [taskA, taskB], commitments: [], existingSessions: [afternoon], preferences: steadyPrefs,
                                             dateRange: range, currentDate: onWed(7), deletedProposedMinutesByTaskId: [:],
                                             keepPlannedBefore: wcal.date(byAdding: .day, value: 1, to: wcal.startOfDay(for: wed)))
        check("Steady today: an existing session stays exactly where it was", steady.allSessions.contains { $0.id == afternoon.id && $0.startTime == onWed(9) })
        check("Steady today: new work still uses free time today without overlapping",
              steady.allSessions.contains { $0.taskId == taskB.id && wcal.isDate($0.startTime, inSameDayAs: wed) && $0.startTime >= onWed(10) })
        check("Steady today: no duplicate planning for the kept task", steady.allSessions.filter { $0.taskId == taskA.id }.count == 1)
        let reshuffled = engine.generateSchedule(tasks: [taskA, taskB], commitments: [], existingSessions: [afternoon], preferences: steadyPrefs,
                                                 dateRange: range, currentDate: onWed(7), deletedProposedMinutesByTaskId: [:], keepPlannedBefore: nil)
        check("Without it (Plan My Day) the urgent task takes the 9 AM slot", reshuffled.allSessions.contains { $0.taskId == taskB.id && $0.startTime == onWed(9) }, "\(reshuffled.allSessions.map { "\($0.title) \($0.startTime)" })")

        let steadyApp = AppState(storageService: StorageService(customURL: estDir.appendingPathComponent("steady.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        steadyApp.preferences.lastMorningSummaryDate = Date()
        check("Only sync re-plans keep today steady", steadyApp.keepTodaySteadyUntil() == nil)
        steadyApp.isSyncReplanning = true
        check("A sync after the morning summary keeps today steady until midnight", steadyApp.keepTodaySteadyUntil() == Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())))
        steadyApp.preferences.keepTodaySteady = false
        check("Keeping today steady can be turned off", steadyApp.keepTodaySteadyUntil() == nil)

        // 2. Learn from actual time
        check("Kinds of work recognized", AppState.workKind("ECON Problem Set 6") == "problem set" && AppState.workKind("Lab 4: Sorting") == "lab" && AppState.workKind("Final Essay Draft") == "essay")
        let hist = [
            EstimateRecord(kind: "problem set", course: "ECON 2010", title: "PS3", estimatedMinutes: 60, actualMinutes: 90, date: Date()),
            EstimateRecord(kind: "problem set", course: "ECON 2010", title: "PS4", estimatedMinutes: 60, actualMinutes: 80, date: Date()),
            EstimateRecord(kind: "problem set", course: "ECON 2010", title: "PS5", estimatedMinutes: 90, actualMinutes: 130, date: Date())
        ]
        let cal1 = AppState.calibration(kind: "problem set", course: "ECON 2010", history: hist)
        check("Past problem sets ran ~44% over → scale up", cal1.map { abs($0.factor - 1.444) < 0.01 } == true && cal1?.basis == "your last 3 ECON 2010 problem sets", "\(String(describing: cal1))")
        check("Needs at least 2 finished tasks in the course", AppState.calibration(kind: "problem set", course: "ECON 2010", history: Array(hist.prefix(1))) == nil)
        check("Within ±10% → no change", AppState.calibration(kind: "lab", course: "CS", history: [
            EstimateRecord(kind: "lab", course: "CS", title: "L1", estimatedMinutes: 100, actualMinutes: 105, date: Date()),
            EstimateRecord(kind: "lab", course: "CS", title: "L2", estimatedMinutes: 100, actualMinutes: 95, date: Date())]) == nil)
        check("Adjustment capped at 2×", AppState.calibration(kind: "lab", course: "CS", history: [
            EstimateRecord(kind: "lab", course: "CS", title: "L1", estimatedMinutes: 30, actualMinutes: 300, date: Date()),
            EstimateRecord(kind: "lab", course: "CS", title: "L2", estimatedMinutes: 30, actualMinutes: 300, date: Date())])?.factor == 2.0)

        let learnApp = AppState(storageService: StorageService(customURL: estDir.appendingPathComponent("learn.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        learnApp.tasks = []
        learnApp.workSessions = []
        learnApp.preferences.aiTimeEstimatesEnabled = false
        func lmsSource(_ id: String) -> EmailSource {
            EmailSource(id: id, threadId: id, senderName: "ECON 2010", senderEmail: "canvas@local", subject: id, receivedDate: Date(), snippet: "", fullBody: "", category: .canvas, isSimulatedDemo: false)
        }
        for (n, actual) in [(3, 90), (4, 80)] {
            let t = DiscoveredTask(title: "Problem Set \(n)", sourceEmail: lmsSource("ps\(n)"), estimatedMinutes: 60, status: .ready)
            learnApp.tasks.append(t)
            learnApp.workSessions.append(WorkSession(taskId: t.id, title: t.title, startTime: Date().addingTimeInterval(-Double(actual + 60) * 60), endTime: Date().addingTimeInterval(-3600), status: .completed))
            learnApp.completeTask(taskId: t.id)
        }
        check("Finished tasks ask how long they took, prefilled from checked-off time", learnApp.openTimeQuestions.map(\.suggestedMinutes).sorted() == [80, 90]
              && learnApp.openTimeQuestions.allSatisfy { $0.plannedMinutes == 60 } && learnApp.preferences.estimateHistory.isEmpty, "\(learnApp.timeQuestions)")
        for q in learnApp.openTimeQuestions { learnApp.answerTimeQuestion(taskId: q.taskId, minutes: q.suggestedMinutes) }
        check("Answers record estimate vs. actual", learnApp.preferences.estimateHistory.map(\.actualMinutes).sorted() == [80, 90] && learnApp.timeQuestions.isEmpty, "\(learnApp.preferences.estimateHistory)")
        let skippedPS = DiscoveredTask(title: "Problem Set 5", sourceEmail: lmsSource("ps5"), estimatedMinutes: 60, status: .ready)
        learnApp.tasks.append(skippedPS)
        learnApp.completeTask(taskId: skippedPS.id)
        check("A task finished without sessions is asked about with its planned time", learnApp.openTimeQuestions.first?.suggestedMinutes == 60)
        learnApp.skipTimeQuestion(taskId: skippedPS.id)
        check("Skip records nothing", learnApp.preferences.estimateHistory.count == 2 && learnApp.openTimeQuestions.isEmpty)
        let reopened = DiscoveredTask(title: "Problem Set 9", sourceEmail: lmsSource("ps9"), estimatedMinutes: 60, status: .ready)
        learnApp.tasks.append(reopened)
        learnApp.completeTask(taskId: reopened.id)
        if let i = learnApp.tasks.firstIndex(where: { $0.id == reopened.id }) { learnApp.tasks[i].status = .ready }
        check("A reopened task isn't asked about", learnApp.openTimeQuestions.isEmpty)
        let reloadedLearn = AppState(storageService: learnApp.storageService, calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        check("Questions are saved", reloadedLearn.timeQuestions.map(\.taskId) == [reopened.id])
        learnApp.tasks.removeAll { $0.id == reopened.id }
        learnApp.timeQuestions = []
        let newPS = DiscoveredTask(title: "Problem Set 6", sourceEmail: lmsSource("ps6"), estimatedMinutes: 60, status: .ready)
        var mine = DiscoveredTask(title: "Problem Set 7", sourceEmail: lmsSource("ps7"), estimatedMinutes: 60, status: .ready)
        mine.userOverriddenDuration = 45
        learnApp.tasks.append(contentsOf: [newPS, mine])
        learnApp.calibrateEstimates()
        let newPSAfter = learnApp.tasks.first { $0.id == newPS.id }
        check("A new problem set in that course is planned longer (60 → 90 min)", newPSAfter?.estimatedMinutes == 90 && newPSAfter?.rawEstimateMinutes == 60, "\(String(describing: newPSAfter?.estimatedMinutes))")
        check("…with a note saying why", newPSAfter?.calibrationNote == "Adjusted +42% (1 h → 1 h 30 min) from your last 2 ECON 2010 problem sets", newPSAfter?.calibrationNote ?? "nil")
        check("A duration you set is never adjusted", learnApp.tasks.first { $0.id == mine.id }?.calibrationNote == nil)
        learnApp.calibrateEstimates()
        check("Each task is adjusted only once", learnApp.tasks.first { $0.id == newPS.id }?.estimatedMinutes == 90)

        // 3. Evening check-in
        let eveApp = AppState(storageService: StorageService(customURL: estDir.appendingPathComponent("eve.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        eveApp.preferences.timeZoneIdentifier = "America/Los_Angeles"
        eveApp.preferences.autoSyncEnabled = false
        var eveTask = taskA
        eveTask.estimatedMinutes = 180 // three 1-hour sessions
        eveApp.tasks = [eveTask]
        let doneLater = WorkSession(taskId: taskA.id, title: "Essay Outline", startTime: onWed(10), endTime: onWed(11), status: .planned)
        let skipped = WorkSession(taskId: taskA.id, title: "Essay Outline", startTime: onWed(14), endTime: onWed(15), status: .planned)
        let tonight = WorkSession(taskId: taskA.id, title: "Essay Outline", startTime: onWed(19), endTime: onWed(20), status: .planned)
        eveApp.workSessions = [doneLater, skipped, tonight]
        var asked: [UUID] = []
        eveApp.eveningCheckInSender = { asked = $0.map(\.id) }
        eveApp.sendEveningCheckInIfDue(now: onWed(17, 30))
        check("No check-in before 6 PM", asked.isEmpty)
        eveApp.sendEveningCheckInIfDue(now: onWed(18, 5))
        check("6 PM check-in asks about today's finished, unmarked sessions only", asked == [doneLater.id, skipped.id], "\(asked)")
        asked = []
        eveApp.sendEveningCheckInIfDue(now: onWed(19, 0))
        check("Check-in is sent once a day", asked.isEmpty)
        eveApp.handleCheckIn(sessionId: doneLater.id, done: true)
        check("Done marks the session completed", eveApp.workSessions.first { $0.id == doneLater.id }?.status == .completed)
        eveApp.handleCheckIn(sessionId: skipped.id, done: false)
        let estimateBefore = eveTask.effectiveDuration
        check("Not Done Yet carries the work over (kept as skipped, estimate unchanged)",
              eveApp.workSessions.first { $0.id == skipped.id }?.status == .skipped && eveApp.tasks.first { $0.id == taskA.id }?.isCarryover == true
              && eveApp.tasks.first { $0.id == taskA.id }?.effectiveDuration == estimateBefore)

        print("\n--- Planner urgency: deadline, effort and how busy you are ---")
        var mon = wcal.startOfDay(for: Date())
        repeat { mon = wcal.date(byAdding: .day, value: 1, to: mon)! } while wcal.component(.weekday, from: mon) != 2
        func day(_ offset: Int, _ h: Int, _ m: Int = 0) -> Date { wcal.date(bySettingHour: h, minute: m, second: 0, of: wcal.date(byAdding: .day, value: offset, to: mon)!)! }
        let shortSoon = DiscoveredTask(title: "Reading Quiz", sourceEmail: mailSource("u1"), extractedDeadline: day(1, 17), isDeadlineSupportedByEmail: true, estimatedMinutes: 30, status: .ready, isClarified: true)
        let longLater = DiscoveredTask(title: "Research Paper", sourceEmail: mailSource("u2"), extractedDeadline: day(3, 17), isDeadlineSupportedByEmail: true, estimatedMinutes: 960, status: .ready, isClarified: true)
        let uRange = wcal.startOfDay(for: mon)...wcal.date(byAdding: .day, value: 10, to: mon)!
        let ranked = engine.generateSchedule(tasks: [shortSoon, longLater], commitments: [], existingSessions: [], preferences: steadyPrefs,
                                             dateRange: uRange, currentDate: day(0, 8), deletedProposedMinutesByTaskId: [:], keepPlannedBefore: nil)
        let firstSession = ranked.proposedSessions.min { $0.startTime < $1.startTime }
        check("Long work due soon starts first, ahead of a short task due sooner", firstSession?.taskId == longLater.id,
              "\(ranked.proposedSessions.sorted { $0.startTime < $1.startTime }.prefix(3).map { "\($0.title) \($0.startTime)" })")
        check("The short task still gets done before its deadline",
              ranked.proposedSessions.contains { $0.taskId == shortSoon.id && $0.endTime <= day(1, 17) })
        check("The long paper is fully planned before Thursday", !ranked.unscheduledReports.contains { $0.task.id == longLater.id && $0.unscheduledMinutes > 0 },
              "\(ranked.unscheduledReports.map { "\($0.task.title) \($0.unscheduledMinutes)" })")
        check("Paper judged 'Start now', quiz has room", ranked.urgencyByTaskId[longLater.id]?.level == .startNow
              && (ranked.urgencyByTaskId[shortSoon.id]?.level ?? .overbooked) > .startNow,
              "\(String(describing: ranked.urgencyByTaskId[longLater.id])) \(String(describing: ranked.urgencyByTaskId[shortSoon.id]))")

        let farAway = DiscoveredTask(title: "Course Reflection", sourceEmail: mailSource("u3"), extractedDeadline: day(9, 17), isDeadlineSupportedByEmail: true, estimatedMinutes: 60, status: .ready, isClarified: true)
        let relaxed = engine.generateSchedule(tasks: [farAway], commitments: [], existingSessions: [], preferences: steadyPrefs,
                                              dateRange: uRange, currentDate: day(0, 8), deletedProposedMinutesByTaskId: [:], keepPlannedBefore: nil)
        check("Small task with a far deadline is 'On track'", relaxed.urgencyByTaskId[farAway.id]?.level == .onTrack)

        // A busy week shrinks the slack: classes all day Monday to Wednesday
        let busyWeek = (0...2).map { d in
            CalendarCommitment(title: "Classes", startTime: day(d, 9), endTime: day(d, 17), calendarName: "School", isSimulatedDemo: false)
        }
        let squeezed = engine.generateSchedule(tasks: [longLater], commitments: busyWeek, existingSessions: [], preferences: steadyPrefs,
                                               dateRange: uRange, currentDate: day(0, 8), deletedProposedMinutesByTaskId: [:], keepPlannedBefore: nil)
        check("When the schedule is too busy it says it won't fit", squeezed.urgencyByTaskId[longLater.id]?.level == .overbooked,
              "\(String(describing: squeezed.urgencyByTaskId[longLater.id]))")

        // Urgent still comes first, whatever the slack
        var urgentSmall = DiscoveredTask(title: "Sign Form", sourceEmail: mailSource("u4"), extractedDeadline: day(4, 17), isDeadlineSupportedByEmail: true, estimatedMinutes: 30, status: .ready, isClarified: true)
        urgentSmall.userPriority = .urgent
        let withUrgent = engine.generateSchedule(tasks: [longLater, urgentSmall], commitments: [], existingSessions: [], preferences: steadyPrefs,
                                                 dateRange: uRange, currentDate: day(0, 8), deletedProposedMinutesByTaskId: [:], keepPlannedBefore: nil)
        check("Urgent tasks still take the first slot", withUrgent.proposedSessions.min { $0.startTime < $1.startTime }?.taskId == urgentSmall.id)

        print("\n--- Deleting sessions, priority changes, rising urgency ---")
        let delDir = estDir.appendingPathComponent("del")
        try? FileManager.default.createDirectory(at: delDir, withIntermediateDirectories: true)
        let delApp = AppState(storageService: StorageService(customURL: delDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
        delApp.tasks = []
        delApp.workSessions = []
        delApp.commitments = []
        let essay = DiscoveredTask(title: "History Essay", sourceEmail: mailSource("d1"), extractedDeadline: Date().addingTimeInterval(9 * 86400), isDeadlineSupportedByEmail: true, estimatedMinutes: 180, status: .ready, isClarified: true)
        let labTask = DiscoveredTask(title: "Physics Lab", sourceEmail: mailSource("d2"), extractedDeadline: Date().addingTimeInterval(8 * 86400), isDeadlineSupportedByEmail: true, estimatedMinutes: 90, status: .ready, isClarified: true)
        delApp.tasks = [essay, labTask]
        delApp.generateProposedPlan()
        let essayMinutes = { delApp.workSessions.filter { $0.taskId == essay.id && $0.status == .planned }.reduce(0) { $0 + $1.durationMinutes } }
        if let victim = delApp.workSessions.filter({ $0.taskId == essay.id }).min(by: { $0.startTime < $1.startTime }) {
            let delCal = SessionShifter.calendar(delApp.preferences)
            let onVictimDay = { (s: WorkSession) in delCal.isDate(s.startTime, inSameDayAs: victim.startTime) }
            let labBefore = delApp.workSessions.filter { $0.taskId == labTask.id }
            let essayDayBefore = delApp.workSessions.filter { $0.taskId == essay.id && $0.status == .planned && onVictimDay($0) }.reduce(0) { $0 + $1.durationMinutes }
            delApp.removeSession(id: victim.id)
            check("Deleting a session keeps the task's estimate", delApp.tasks.first { $0.id == essay.id }?.effectiveDuration == 180)
            check("The deleted work is planned again at another time", essayMinutes() == 180, "\(essayMinutes())")
            let essayDayMinutes = { delApp.workSessions.filter { $0.taskId == essay.id && $0.status == .planned && onVictimDay($0) }.reduce(0) { $0 + $1.durationMinutes } }
            let essayDayAfterDelete = essayDayMinutes()
            check("…not on the day you deleted it from (its other sessions there stay)", essayDayAfterDelete == essayDayBefore - victim.durationMinutes, "\(essayDayAfterDelete) vs \(essayDayBefore)")
            let labAfter = delApp.workSessions.filter { $0.taskId == labTask.id }
            check("Other tasks' sessions that day only move earlier", labBefore.filter(onVictimDay).allSatisfy { old in
                labAfter.first { $0.id == old.id }.map { $0.startTime <= old.startTime } ?? false })
            check("…and sessions on other days don't move", labBefore.filter { !onVictimDay($0) }.allSatisfy { old in
                labAfter.contains { $0.id == old.id && $0.startTime == old.startTime } })
            delApp.generateProposedPlan()
            check("Plan My Day doesn't put the deleted work back on that day", essayDayMinutes() <= essayDayAfterDelete, "\(essayDayMinutes())")
            check("…and still plans all of it", essayMinutes() == 180, "\(essayMinutes())")
            let reloadedDel = AppState(storageService: StorageService(customURL: delDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
            check("Deleted day is remembered after a restart", reloadedDel.declinedSlots.contains { abs($0.start.timeIntervalSince(victim.startTime)) < 1 && $0.taskId == essay.id })
        } else {
            check("Plan created sessions to delete", false)
        }

        print("\n--- Shifting sessions up after a delete, dragging sessions ---")
        do {
            var prefs = UserPreferences()
            prefs.workStartHour = 9; prefs.workStartMinute = 0; prefs.workEndHour = 17; prefs.workEndMinute = 0
            prefs.breakMinutes = 15; prefs.lunchStartHour = 12; prefs.lunchDurationMinutes = 60
            prefs.weekdayWorkingHours = [:]
            let cal = SessionShifter.calendar(prefs)
            // A weekday at least two days ahead, so "now" never matters.
            var day = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: Date()))!
            while !prefs.workingHours(for: cal.component(.weekday, from: day)).isWorkday { day = cal.date(byAdding: .day, value: 1, to: day)! }
            func at(_ h: Int, _ m: Int = 0, _ d: Date? = nil) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: d ?? day)! }
            let tA = UUID(), tB = UUID(), tC = UUID(), tD = UUID()
            let deleted = WorkSession(taskId: tA, title: "A", startTime: at(9), endTime: at(10))
            let b = WorkSession(taskId: tB, title: "B", startTime: at(10, 15), endTime: at(11))
            let c = WorkSession(taskId: tC, title: "C", startTime: at(13), endTime: at(14))
            let locked = WorkSession(taskId: tD, title: "D", startTime: at(14, 15), endTime: at(15), isLocked: true)
            let e = WorkSession(taskId: tD, title: "E", startTime: at(15, 15), endTime: at(16))
            let meeting = CalendarCommitment(title: "Meeting", startTime: at(10, 30), endTime: at(10, 45), isBusy: true, calendarName: "Work", isSimulatedDemo: false)
            let shifted = SessionShifter.shiftForward(sessions: [b, c, locked, e], freedFrom: deleted.startTime,
                                                      commitments: [meeting], preferences: prefs, now: Date())
            let pos = { (s: WorkSession) in shifted.first { $0.id == s.id }!.startTime }
            check("The next session moves up into the deleted time", pos(b) == at(9), "\(pos(b))")
            check("…the one after follows (after a break), stopping at an event", pos(c) == at(10, 45), "\(pos(c))")
            check("Locked sessions never move", pos(locked) == at(14, 15))
            check("Sessions after a locked one fill free time before it (after lunch)", pos(e) == at(13), "\(pos(e))")
            check("Shifting keeps every session's length", shifted.allSatisfy { s in
                [b, c, locked, e].first { $0.id == s.id }.map { $0.durationMinutes == s.durationMinutes } ?? false })
            check("Nothing shifted overlaps an event or lunch", !shifted.contains { s in
                (s.startTime < meeting.endTime && s.endTime > meeting.startTime) || (s.startTime < at(13) && s.endTime > at(12)) })
            let otherDay = cal.date(byAdding: .day, value: 1, to: day)!
            let nextDay = WorkSession(taskId: tB, title: "B2", startTime: at(11, 0, otherDay), endTime: at(12, 0, otherDay))
            check("Sessions on other days never move",
                  SessionShifter.shiftForward(sessions: [nextDay], freedFrom: deleted.startTime, commitments: [], preferences: prefs, now: Date()).first?.startTime == nextDay.startTime)
            let manual = WorkSession(taskId: tB, title: "M", startTime: at(15), endTime: at(16), isManuallyAdjusted: true)
            check("Sessions you placed yourself never move",
                  SessionShifter.shiftForward(sessions: [manual], freedFrom: deleted.startTime, commitments: [], preferences: prefs, now: Date()).first?.startTime == manual.startTime)

            // Drag and drop through AppState
            let dragDir = estDir.appendingPathComponent("drag")
            try? FileManager.default.createDirectory(at: dragDir, withIntermediateDirectories: true)
            let dragApp = AppState(storageService: StorageService(customURL: dragDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), canvasURLSession: fakeSession())
            dragApp.preferences = prefs
            let taskX = DiscoveredTask(title: "Reading", sourceEmail: mailSource("g1"), extractedDeadline: cal.date(byAdding: .day, value: 6, to: day), isDeadlineSupportedByEmail: true, estimatedMinutes: 45, status: .ready, isClarified: true)
            let taskY = DiscoveredTask(title: "Lab", sourceEmail: mailSource("g2"), extractedDeadline: cal.date(byAdding: .day, value: 6, to: day), isDeadlineSupportedByEmail: true, estimatedMinutes: 45, status: .ready, isClarified: true)
            dragApp.tasks = [taskX, taskY]
            dragApp.commitments = [meeting]
            let x = WorkSession(taskId: taskX.id, title: "Work Session: Reading", startTime: at(9), endTime: at(9, 45))
            let y = WorkSession(taskId: taskY.id, title: "Work Session: Lab", startTime: at(14), endTime: at(14, 45))
            dragApp.workSessions = [x, y]
            check("Dropping a session after another puts it right after it (with a break)",
                  dragApp.dropSession(id: x.id, onDay: day, after: y.endTime) && dragApp.workSessions.first { $0.id == x.id }?.startTime == at(15))
            let movedX = dragApp.workSessions.first { $0.id == x.id }
            check("A dragged session keeps its length and is marked as adjusted", movedX?.durationMinutes == 45 && movedX?.isManuallyAdjusted == true)
            check("…and the other session stays put", dragApp.workSessions.first { $0.id == y.id }?.startTime == at(14))
            check("…and no duplicate work is planned", dragApp.workSessions.filter { $0.taskId == taskX.id && $0.status == .planned }.count == 1)
            check("Dropping on a day uses its first free time",
                  dragApp.dropSession(id: x.id, onDay: otherDay) && dragApp.workSessions.first { $0.id == x.id }?.startTime == at(9, 0, otherDay))
            dragApp.generateProposedPlan()
            check("A re-plan keeps a dragged session where you put it", dragApp.workSessions.first { $0.id == x.id }?.startTime == at(9, 0, otherDay))
            check("Dropping after the working day ends is refused", !dragApp.dropSession(id: x.id, onDay: day, after: at(16, 50)))
            var lockedY = dragApp.workSessions.first { $0.id == y.id }!
            lockedY.isLocked = true
            check("Locked sessions can't be dragged", !dragApp.canDragSession(lockedY))
            dragApp.declinedSlots = [DeclinedSlot(taskId: taskX.id, start: at(9), end: at(9, 45))]
            _ = dragApp.dropSession(id: x.id, onDay: day)
            check("Dragging a task back onto a day you removed it from brings it back", dragApp.declinedSlots.isEmpty)
            check("Drag payloads only accept DayBook sessions",
                  SessionDrag.sessionId(from: ["hello", SessionDrag.payload(x.id)]) == x.id && SessionDrag.sessionId(from: ["hello"]) == nil)
        }

        // Changing priority makes a new judgement
        let firstBefore = delApp.workSessions.filter { $0.status == .planned }.min { $0.startTime < $1.startTime }?.taskId
        let other = firstBefore == essay.id ? labTask : essay
        delApp.setTaskPriority(id: other.id, priority: .urgent)
        check("Raising a task's priority re-plans it to the front", delApp.workSessions.filter { $0.status == .planned }.min { $0.startTime < $1.startTime }?.taskId == other.id)
        check("High/Low priority moves slack by 3 h", {
            let q = [RuleBasedSchedulingEngine.TaskSchedulingItem(task: { var t = labTask; t.userPriority = .high; return t }(), remainingMinutes: 60, hardCutoff: Date().addingTimeInterval(86400), alreadyCompletedMinutes: 0, scheduledMinutes: 0)]
            let empty = FreeTimeMap(days: [])
            return RuleBasedSchedulingEngine.slack(of: q[0], in: q, at: Date(), usedOnDay: 0, freeTime: empty, calendar: .current) == -60 - 180
        }())

        // Rising urgency: a steady day gives way
        let wasRelaxed = SchedulingResult()
        var nowPressing = SchedulingResult()
        nowPressing.urgencyByTaskId[labTask.id] = TaskUrgency(level: .startNow, slackMinutes: 30, remainingMinutes: 90)
        check("A task that newly needs to start now overrides 'keep today steady'",
              AppState.newlyPressingTask(old: wasRelaxed, new: nowPressing, sessions: [], tasks: [labTask]) == "Physics Lab")
        check("…but not when it already has work today",
              AppState.newlyPressingTask(old: wasRelaxed, new: nowPressing, sessions: [WorkSession(taskId: labTask.id, title: "Lab", startTime: Date(), endTime: Date().addingTimeInterval(3600), status: .planned)], tasks: [labTask]) == nil)
        check("…and not when it was already pressing before", AppState.newlyPressingTask(old: nowPressing, new: nowPressing, sessions: [], tasks: [labTask]) == nil)

        print("\n--- Sync Everything ---")
        let syncDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_SyncAll_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: syncDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: syncDir) }
        let syncReader = MockReader()
        let syncApp = AppState(storageService: StorageService(customURL: syncDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), ollamaService: MockModel(), canvasReader: syncReader, canvasURLSession: fakeSession())
        syncApp.setCanvasAddress("canvas.test.edu")
        syncApp.canvasBrowserTransportFactory = { _, _ in
            return { request in (Data("{\"short_name\":\"Sam\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!) }
        }
        var preparedTabs: [String] = []
        var tabProblem: String? = nil
        syncApp.browserTabPreparerOverride = { browser, url, _ in
            preparedTabs.append("\(browser.displayName) \(url.host ?? "")")
            return BrowserTabOpener.Preparation(openedTab: true, launchedBrowser: true, problem: url.host == "www.gradescope.com" ? tabProblem : nil)
        }
        syncApp.gradescopeReadOverride = { _ in gsCurrent }
        _ = runAsync { await syncApp.connectCanvasThroughBrowser(.safari); return true }
        _ = runAsync { await syncApp.connectGradescope(.safari); return true }
        check("Connecting Gradescope reports the tasks it found as new", syncApp.newlyFoundTasks.contains { $0.title == "Problem Set 6" } && syncApp.showNewTasksPanel)
        syncApp.acknowledgeAllNewTasks()
        check("Got It moves every new task to the regular list and closes the panel", syncApp.newlyFoundTaskIds.isEmpty && !syncApp.showNewTasksPanel)
        var newTaskNotes: [String] = []
        syncApp.newTasksNotificationSender = { title, _ in newTaskNotes.append(title) }
        syncReader.snapshot = CanvasSnapshot(userName: "Sam", dueItems: [due("assignment-90", "Essay Draft", due: Date().addingTimeInterval(5 * 86400))])
        preparedTabs = []
        _ = runAsync { await syncApp.syncEverything(now: gsNow); return true }
        let names = syncApp.lastSyncAllResults.map(\.name)
        check("Sync Everything covers Calendar, Canvas and Gradescope in order", names == ["Calendar", "Canvas", "Gradescope"], "\(names)")
        check("Canvas and Gradescope tabs are opened in the background first",
              preparedTabs == ["Safari canvas.test.edu", "Safari www.gradescope.com"], "\(preparedTabs)")
        check("Canvas items imported by Sync Everything", syncApp.tasks.contains { $0.title == "Essay Draft" })
        check("Gradescope items imported by Sync Everything", syncApp.tasks.contains { $0.title == "Problem Set 6" })
        check("Every source reported success", syncApp.lastSyncAllResults.allSatisfy(\.succeeded), "\(syncApp.lastSyncAllResults)")
        check("Full sync time recorded", syncApp.preferences.lastFullSyncDate == gsNow)
        check("Sync Everything re-plans and reports what changed", syncApp.lastSyncPlanChanges.contains { $0.hasPrefix("Essay Draft added") }, "\(syncApp.lastSyncPlanChanges)")
        check("Only tasks the sync hadn't seen before are New", syncApp.newlyFoundTasks.map(\.title) == ["Essay Draft"], "\(syncApp.newlyFoundTasks.map(\.title))")
        check("The new-tasks panel opens when the sync finishes", syncApp.showNewTasksPanel)
        check("One notification for the whole sync (Canvas inside it doesn't report separately)", newTaskNotes == ["1 new task found"], "\(newTaskNotes)")
        let reloadedNew = AppState(storageService: StorageService(customURL: syncDir.appendingPathComponent("db.json")), calendarService: SimulatedCalendarService(), keychainService: MockKeychain(), ollamaService: MockModel(), canvasReader: MockReader(), canvasURLSession: fakeSession())
        check("New tasks stay New after a restart", reloadedNew.newlyFoundTasks.map(\.title) == ["Essay Draft"])
        tabProblem = "Gradescope didn't finish loading in Safari. It may need you to sign in there."
        _ = runAsync { await syncApp.syncEverything(now: gsNow); return true }
        let gsResult = syncApp.lastSyncAllResults.first { $0.name == "Gradescope" }
        check("A tab that needs sign-in is reported, other sources still sync",
              gsResult?.succeeded == false && gsResult?.detail.contains("sign in") == true
              && syncApp.lastSyncAllResults.first { $0.name == "Canvas" }?.succeeded == true)
        check("Email is skipped when Gmail isn't connected", !syncApp.lastSyncAllResults.contains { $0.name == "Email" })
        check("A sync that finds nothing new adds nothing and sends no notification", syncApp.newlyFoundTasks.count == 1 && newTaskNotes.count == 1, "\(newTaskNotes)")
        if let essayId = syncApp.newlyFoundTasks.first?.id {
            syncApp.acknowledgeNewTask(essayId)
            check("Got It on one task moves it to the regular list", !syncApp.isNewlyFound(essayId) && syncApp.tasks.contains { $0.id == essayId } && !syncApp.showNewTasksPanel)
        }
        // A task found and then finished or dismissed is no longer shown as new.
        let trackedBefore = syncApp.beginNewTaskTracking()
        let quick = DiscoveredTask(title: "Captured flyer", sourceEmail: EmailSource(id: "qc-1", threadId: "qc-1", senderName: "Quick Capture", senderEmail: "", subject: "Flyer", receivedDate: Date(), snippet: "", fullBody: "", category: .quickCapture, isSimulatedDemo: false), extractedDeadline: Date().addingTimeInterval(86400), estimatedMinutes: 30, status: .ready, isClarified: true)
        let mailTask = DiscoveredTask(title: "Reading response", sourceEmail: mailSource("nt1"), extractedDeadline: Date().addingTimeInterval(3 * 86400), isDeadlineSupportedByEmail: true, estimatedMinutes: 30, status: .ready, isClarified: true)
        syncApp.tasks.append(contentsOf: [quick, mailTask])
        syncApp.endNewTaskTracking(trackedBefore)
        check("Quick Captures you add yourself are never shown as new", !syncApp.isNewlyFound(quick.id) && syncApp.isNewlyFound(mailTask.id))
        syncApp.dismissTask(taskId: mailTask.id)
        check("A dismissed new task drops out of the New list", syncApp.newlyFoundTasks.isEmpty)

        var pt = Calendar(identifier: .gregorian)
        pt.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { pt.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }
        check("8 AM slot due at 8:05 when last sync was yesterday evening",
              AppState.dueAutoSyncSlot(now: at(9, 8, 5), lastSync: at(8, 18, 2), calendar: pt) == at(9, 8))
        check("Nothing due at 10 AM after the 8 AM sync ran",
              AppState.dueAutoSyncSlot(now: at(9, 10), lastSync: at(9, 8, 1), calendar: pt) == nil)
        check("A manual sync after the slot counts (no extra auto sync)",
              AppState.dueAutoSyncSlot(now: at(9, 12), lastSync: at(9, 9, 30), calendar: pt) == nil)
        check("1 PM slot due at 1:00 PM",
              AppState.dueAutoSyncSlot(now: at(9, 13), lastSync: at(9, 8, 1), calendar: pt) == at(9, 13))
        check("Missed slots while asleep run once on wake (latest slot only)",
              AppState.dueAutoSyncSlot(now: at(9, 19), lastSync: at(9, 7), calendar: pt) == at(9, 18))
        check("Early morning catches up on yesterday's 6 PM if it was missed",
              AppState.dueAutoSyncSlot(now: at(9, 6), lastSync: at(8, 12), calendar: pt) == at(8, 18))
        check("Next automatic sync after 2 PM is 6 PM", AppState.nextAutoSyncTime(after: at(9, 14), calendar: pt) == at(9, 18))
        check("Next automatic sync after 7 PM is 8 AM tomorrow", AppState.nextAutoSyncTime(after: at(9, 19), calendar: pt) == at(10, 8))
        check("Automatic sync is on by default", UserPreferences().autoSyncEnabled)
        check("A blank new tab doesn't count as loaded", !BrowserTabOpener.isLoaded("complete|about:blank", prefixes: ["https://www.gradescope.com"]))
        check("A loading page doesn't count as loaded", !BrowserTabOpener.isLoaded("interactive|https://www.gradescope.com/account", prefixes: ["https://www.gradescope.com"]))
        check("The loaded site page counts", BrowserTabOpener.isLoaded("complete|https://www.gradescope.com/login", prefixes: ["https://www.gradescope.com"]))
        let closeScriptSample = BrowserTabOpener.Preparation()
        check("Tidy-up does nothing when nothing was opened", closeScriptSample.openedTab == false && closeScriptSample.launchedBrowser == false)

        print("\n=======================================================")
        if passed == total { print(" 🎉 ALL CANVAS CHECKS PASSED (\(passed)/\(total))!") } else { print(" ⚠️ SOME CHECKS FAILED (\(passed)/\(total)).") }
        print("=======================================================\n")
        return passed == total
    }

    static func mailSource(_ id: String) -> EmailSource {
        EmailSource(id: id, threadId: id, senderName: "Prof", senderEmail: "p@school.edu", subject: id, receivedDate: Date(),
                    snippet: "", fullBody: "", category: .assignment, isSimulatedDemo: false)
    }

    private static func runAsync<T>(_ block: @MainActor @escaping () async throws -> T) -> Result<T, Error> {
        var result: Result<T, Error>?
        Task { @MainActor in
            do { result = .success(try await block()) } catch { result = .failure(error) }
        }
        let start = Date()
        while result == nil && Date().timeIntervalSince(start) < 30 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        return result ?? .failure(NSError(domain: "CanvasTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "timed out"]))
    }
}
