import Foundation
import AppKit
import PDFKit

/// Offline tests for the local AI (Ollama) layer: client, email scanning, Quick Capture, receipts,
/// image/PDF preparation, and loading databases saved by older (Gemini/Claude) versions.
/// Run with: PersonalPlanner --test-ollama
@MainActor
public final class OllamaTester {

    // MARK: - Mocks

    /// Stubs HTTP responses so the client can be tested without a running Ollama.
    final class StubURLProtocol: URLProtocol {
        struct Stub {
            let status: Int
            let body: String
        }
        nonisolated(unsafe) static var queue: [Stub] = []
        nonisolated(unsafe) static var requestCount = 0
        nonisolated(unsafe) static var lastBody: [String: Any]? = nil
        nonisolated(unsafe) static var lastPath: String = ""
        nonisolated(unsafe) static var refuseConnection = false

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            StubURLProtocol.requestCount += 1
            StubURLProtocol.lastPath = request.url?.path ?? ""
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 65536)
                var collected = Data()
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    collected.append(buffer, count: read)
                }
                stream.close()
                data = collected
            }
            if let d = data { StubURLProtocol.lastBody = try? JSONSerialization.jsonObject(with: d) as? [String: Any] }
            if StubURLProtocol.refuseConnection {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            let stub = StubURLProtocol.queue.isEmpty ? Stub(status: 500, body: "{}") : StubURLProtocol.queue.removeFirst()
            let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset(_ stubs: [Stub], refuse: Bool = false) {
            queue = stubs
            requestCount = 0
            lastBody = nil
            lastPath = ""
            refuseConnection = refuse
        }
    }

    final class MockOllamaService: OllamaExtractionServiceProtocol {
        var responses: [String: EmailAnalysis] = [:]
        var errors: [String: Error] = [:]
        var callCount = 0
        var lastModel: String? = nil
        var lastTimeZone: TimeZone? = nil

        func analyzeEmail(email: EmailSource, threadContext: [EmailSource], existingTasks: [DiscoveredTask], baseURL: String, model: String, timeZone: TimeZone, checkCancellation: (() -> Bool)?, onRetry: ((String) -> Void)?) async throws -> EmailAnalysis {
            callCount += 1
            lastModel = model
            lastTimeZone = timeZone
            if let error = errors[email.id] { throw error }
            if let response = responses[email.id] { return response }
            return EmailAnalysis(isNewsletterOrMarketing: false, isDirectedAtRecipient: true, hasActionableTask: false, reasoning: "Nothing", tasks: [])
        }
        func installedModels(baseURL: String) async throws -> [String] { [OllamaDefaults.model] }
        func testConnection(baseURL: String, model: String) async throws -> String { "Connected" }
    }

    // MARK: - Helpers

    static let sampleAnalysisJSON = """
    {"isNewsletterOrMarketing":false,"isDirectedAtRecipient":true,"hasActionableTask":true,"reasoning":"Direct request","tasks":[{"title":"Submit lab report","requiredAction":"Upload the lab report","deadlineIso":"2026-11-06T17:00:00-08:00","deadlineIsSupportedByEmail":true,"supportingExcerpt":"Please upload the lab report by Friday 5 PM.","estimatedDurationMinutes":90,"isAmbiguous":false,"uncertainDetails":[],"isDeadlineUpdate":false,"deadlineUpdateNote":null,"originalDeadlineWording":"Friday 5 PM","dateOnlyString":null}]}
    """


    /// Wraps `content` in an Ollama /api/chat response.
    static func chatResponse(_ content: String, doneReason: String = "stop") -> String {
        let json: [String: Any] = ["model": OllamaDefaults.model, "message": ["role": "assistant", "content": content], "done": true, "done_reason": doneReason]
        return String(data: try! JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
    }

    static let showVision = StubURLProtocol.Stub(status: 200, body: "{\"capabilities\":[\"completion\",\"vision\"]}")
    static let showTextOnly = StubURLProtocol.Stub(status: 200, body: "{\"capabilities\":[\"completion\",\"tools\",\"thinking\"]}")

    /// A PNG with large printed text, for on-device text recognition tests.
    static func textImagePNG(_ lines: [String]) -> Data {
        let image = NSImage(size: NSSize(width: 900, height: 120 + 70 * lines.count))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 30, y: image.size.height - 90 - CGFloat(i * 70)), withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func stubbedClient(maxAttempts: Int = 3) -> OllamaClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return OllamaClient(session: URLSession(configuration: config), maxAttempts: maxAttempts, retryDelay: 0, sleeper: { _ in })
    }

    static func sampleEmail(id: String, subject: String, hoursAgo: Double) -> EmailSource {
        EmailSource(
            id: id,
            threadId: "thread_\(id)",
            senderName: "Prof. Lee",
            senderEmail: "lee@university.edu",
            subject: subject,
            receivedDate: Date().addingTimeInterval(-hoursAgo * 3600),
            snippet: "Please upload the lab report by Friday 5 PM.",
            fullBody: "Hi, please upload the lab report by Friday 5 PM. Thanks.",
            category: .assignment,
            isSimulatedDemo: false
        )
    }

    static func samplePDF(pages: Int, at url: URL) {
        let document = PDFDocument()
        for i in 0..<pages {
            let image = NSImage(size: NSSize(width: 300, height: 400))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 300, height: 400).fill()
            ("Receipt page \(i + 1)" as NSString).draw(at: NSPoint(x: 20, y: 200), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
            image.unlockFocus()
            if let page = PDFPage(image: image) { document.insert(page, at: i) }
        }
        document.write(to: url)
    }

    // MARK: - Runner

    public static func runAllTests() -> Bool {
        print("\n=======================================================")
        print(" 🦙 LOCAL AI (OLLAMA) TEST")
        print("=======================================================\n")

        var passed = 0
        var total = 0
        func check(_ name: String, _ condition: Bool, _ details: String = "") {
            total += 1
            if condition {
                passed += 1
                print("  ✅ [PASS] \(name)")
            } else {
                print("  ❌ [FAIL] \(name)")
                if !details.isEmpty { print("     Details: \(details)") }
            }
        }

        let tz = TimeZone(identifier: "America/Los_Angeles")!
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PP_Ollama_Test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // --- Stage 1: Request shape
        print("--- Stage 1: Request Shape ---")
        check("Default model is the vision-capable qwen3-vl:8b", OllamaDefaults.model == "qwen3-vl:8b")
        let body = OllamaClient.buildChatBody(model: "m", system: "sys", user: "u", images: [Data([1, 2, 3])], schema: EmailExtractionPrompt.analysisSchema)
        let messages = body["messages"] as? [[String: Any]]
        check("Non-streaming request", body["stream"] as? Bool == false)
        check("JSON schema sent as format", (body["format"] as? [String: Any])?["type"] as? String == "object")
        check("Raised context window", ((body["options"] as? [String: Any])?["num_ctx"] as? Int) == OllamaDefaults.contextTokens)
        check("System + user messages", messages?.count == 2 && messages?.first?["role"] as? String == "system")
        check("Images sent base64 on the user message", (messages?.last?["images"] as? [String]) == [Data([1, 2, 3]).base64EncodedString()])
        let noImages = OllamaClient.buildChatBody(model: "m", system: "s", user: "u", images: [], schema: [:])
        check("No images field when there are no images", ((noImages["messages"] as? [[String: Any]])?.last?["images"]) == nil)
        check("Model match treats name and name:latest alike", OllamaClient.isInstalled("llama3.1", in: ["llama3.1:latest"]) && !OllamaClient.isInstalled("qwen3-vl:8b", in: ["llama3.1:latest"]))
        check("Bad Ollama address is a setup error", (try? OllamaClient.endpoint("not a url", path: "/api/chat")) == nil)
        check("Empty address falls back to localhost", (try? OllamaClient.endpoint("", path: "/api/chat"))?.absoluteString == "http://localhost:11434/api/chat")
        check("Text is never sent unencrypted to another machine", (try? OllamaClient.endpoint("http://192.168.1.20:11434", path: "/api/chat")) == nil
              && (try? OllamaClient.endpoint("http://ollama.example.com", path: "/api/chat")) == nil
              && (try? OllamaClient.endpoint("ftp://localhost", path: "/api/chat")) == nil)
        check("This Mac or an https server is allowed", (try? OllamaClient.endpoint("http://127.0.0.1:11434", path: "/api/chat")) != nil
              && (try? OllamaClient.endpoint("https://ollama.example.com", path: "/api/chat")) != nil)
        let prompt = EmailExtractionPrompt.buildUserPrompt(email: sampleEmail(id: "p", subject: "Lab", hoursAgo: 1), threadContext: [], existingTasks: [], timeZone: tz, bodyCharacterLimit: 100)
        check("Email prompt includes the user's time zone", prompt.contains("America/Los_Angeles"))
        check("Email system prompt treats content as untrusted data", EmailExtractionPrompt.systemPrompt.contains("untrusted data"))

        // --- Stage 2: Response handling & errors
        print("\n--- Stage 2: Responses & Errors ---")
        if let text = try? OllamaClient.extractContent(fromResponse: Data(chatResponse(sampleAnalysisJSON).utf8)),
           let analysis = try? EmailExtractionPrompt.decodeAnalysis(from: text) {
            check("Parses chat response into email tasks", analysis.tasks.first?.title == "Submit lab report")
        } else {
            check("Parses chat response into email tasks", false)
        }
        do {
            _ = try OllamaClient.extractContent(fromResponse: Data(chatResponse("{\"is", doneReason: "length").utf8))
            check("Cut-off answer raises an error", false)
        } catch let e as AIServiceError {
            check("Cut-off answer is a retryable invalid response", e.kind == .invalidResponse && e.isRetryable)
        } catch { check("Cut-off answer raises AIServiceError", false) }
        let missing = OllamaClient.classify(statusCode: 404, data: Data("{\"error\":\"model 'qwen3-vl:8b' not found\"}".utf8), model: "qwen3-vl:8b")
        check("Missing model is fatal with pull instructions", missing.isFatalForScan && missing.message.contains("ollama pull qwen3-vl:8b"))
        let noVision = OllamaClient.classify(statusCode: 400, data: Data("{\"error\":\"model does not support image input\"}".utf8), model: "llama3.1:8b")
        check("Non-vision model explained", noVision.kind == .setupRequired && noVision.message.contains("can't read images"))
        check("Ollama not running is fatal", OllamaClient.notRunningError().isFatalForScan)
        check("Ollama 500 is retryable", OllamaClient.classify(statusCode: 500, data: Data("{}".utf8), model: "m").isRetryable)

        // --- Stage 3: Client transport (stubbed HTTP)
        print("\n--- Stage 3: Client Retries ---")
        let email = sampleEmail(id: "r1", subject: "Lab report", hoursAgo: 2)
        StubURLProtocol.reset([
            showVision,
            StubURLProtocol.Stub(status: 200, body: chatResponse("not json")),
            StubURLProtocol.Stub(status: 500, body: "{\"error\":\"busy\"}"),
            StubURLProtocol.Stub(status: 200, body: chatResponse(sampleAnalysisJSON))
        ])
        let service = OllamaExtractionService(client: stubbedClient())
        var notes: [String] = []
        let retried: Result<EmailAnalysis, Error> = runAsync {
            try await service.analyzeEmail(email: email, threadContext: [], existingTasks: [], baseURL: OllamaDefaults.baseURL, model: OllamaDefaults.model, timeZone: tz, checkCancellation: nil, onRetry: { notes.append($0) })
        }
        if case .success(let analysis) = retried {
            check("Recovers after a garbled answer and a 500", analysis.tasks.count == 1 && StubURLProtocol.requestCount == 4, "requests=\(StubURLProtocol.requestCount)")
        } else {
            check("Recovers after a garbled answer and a 500", false, "\(retried)")
        }
        check("Reported 2 retry notices", notes.count == 2)
        check("Called /api/chat", StubURLProtocol.lastPath == "/api/chat")

        StubURLProtocol.reset([], refuse: true)
        let refused: Result<EmailAnalysis, Error> = runAsync {
            try await service.analyzeEmail(email: email, threadContext: [], existingTasks: [], baseURL: OllamaDefaults.baseURL, model: OllamaDefaults.model, timeZone: tz, checkCancellation: nil, onRetry: nil)
        }
        if case .failure(let error) = refused, let e = error as? AIServiceError {
            check("Connection refused reported as 'Ollama isn't running'", e.message.contains("Ollama isn't running") && StubURLProtocol.requestCount == 1)
        } else {
            check("Connection refused reported as 'Ollama isn't running'", false, "\(refused)")
        }

        StubURLProtocol.reset([StubURLProtocol.Stub(status: 200, body: "{\"models\":[{\"name\":\"qwen3:8b\"}]}")])
        let testResult: Result<String, Error> = runAsync {
            try await service.testConnection(baseURL: OllamaDefaults.baseURL, model: "qwen3-vl:8b")
        }
        if case .failure(let error) = testResult {
            check("Test Connection names a missing model", error.localizedDescription.contains("ollama pull qwen3-vl:8b") && error.localizedDescription.contains("qwen3:8b"))
        } else {
            check("Test Connection names a missing model", false)
        }

        // --- Stage 4: Images & PDFs
        print("\n--- Stage 4: Images & PDFs ---")
        let pdfURL = tempDir.appendingPathComponent("receipt.pdf")
        samplePDF(pages: 5, at: pdfURL)
        let pdfImages = (try? ImageInputPreparer.images(fromFile: pdfURL)) ?? []
        check("PDF rendered to images (capped at 3 pages)", pdfImages.count == ImageInputPreparer.maxPDFPages, "count=\(pdfImages.count)")
        check("Rendered pages are PNG", pdfImages.first.map { $0.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) } == true)
        let tiffImage = NSImage(size: NSSize(width: 20, height: 20))
        tiffImage.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 20, height: 20).fill(); tiffImage.unlockFocus()
        let tiffData = tiffImage.tiffRepresentation!
        let converted = try? ImageInputPreparer.image(fromData: tiffData, mimeType: "image/tiff")
        check("TIFF converted to JPEG", converted.map { $0.prefix(2) == Data([0xFF, 0xD8]) } == true)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2])
        check("PNG passed through unchanged", (try? ImageInputPreparer.image(fromData: png, mimeType: "image/png")) == png)
        check("Unreadable image gives a clear error", (try? ImageInputPreparer.image(fromData: Data([1, 2, 3]), mimeType: "image/heic")) == nil)


        print("\n--- Stage 6: Quick Capture ---")
        let qcJSON = """
        {"proposals":[{"proposalType":"task","title":"Sign up to meet Tim","requiredAction":"Submit signup form","deadlineIso":"2026-11-06T17:00:00-08:00","dateOnlyString":null,"originalDeadlineWording":"Friday at 5pm","deadlineProvenance":"explicitDateTime","timeZoneAssumption":"Assumed America/Los_Angeles","estimatedDurationMinutes":10,"isDurationInferred":true,"eventStartIso":null,"eventEndIso":null,"isAllDay":null,"location":null,"attendees":null,"originalTimingWording":null,"isTentative":null,"supportingExcerpt":"Sign up by Friday at 5pm","notes":null,"inferredDetails":null,"isAmbiguous":false,"clarificationPrompt":null}],"reasoning":"One task"}
        """
        StubURLProtocol.reset([showVision, StubURLProtocol.Stub(status: 200, body: chatResponse(qcJSON))])
        let qc = QuickCaptureService(client: stubbedClient())
        let screenshot = textImagePNG(["Sign up to meet Tim", "by Friday at 5pm"])
        let qcResult: Result<(proposals: [QuickCaptureProposal], reasoning: String), Error> = runAsync {
            try await qc.analyzeCapture(text: "", imageData: screenshot, imageMimeType: "image/png", referenceDate: Date(), timeZone: tz)
        }
        if case .success(let result) = qcResult {
            check("Quick Capture proposal parsed", result.proposals.first?.title == "Sign up to meet Tim")
            check("Model provenance name mapped (explicitDateTime)", result.proposals.first?.deadlineProvenance == .explicitDateTime)
        } else {
            check("Quick Capture proposal parsed", false, "\(qcResult)")
        }
        check("Non-thinking model: no think field sent", StubURLProtocol.lastBody?["think"] == nil)
        check("Vision model: screenshot sent as an image", (((StubURLProtocol.lastBody?["messages"] as? [[String: Any]])?.last?["images"] as? [String])?.count) == 1)

        // Text-only model (e.g. qwen3:8b): screenshot text is read on this Mac and sent as text
        StubURLProtocol.reset([showTextOnly, StubURLProtocol.Stub(status: 200, body: chatResponse(qcJSON))])
        let qcText = QuickCaptureService(client: stubbedClient())
        let ocrStarted = Date()
        let qcTextResult: Result<(proposals: [QuickCaptureProposal], reasoning: String), Error> = runAsync {
            try await qcText.analyzeCapture(text: "", imageData: screenshot, imageMimeType: "image/png", referenceDate: Date(), timeZone: tz, model: "qwen3:8b")
        }
        print("     (screenshot read + analyzed in \(String(format: "%.1f", Date().timeIntervalSince(ocrStarted)))s)")
        let textUser = (StubURLProtocol.lastBody?["messages"] as? [[String: Any]])?.last
        check("Text-only model: capture still succeeds", (try? qcTextResult.get())?.proposals.count == 1, "\(qcTextResult)")
        check("Text-only model: no image sent", textUser?["images"] == nil)
        check("Thinking model: thinking turned off for speed", StubURLProtocol.lastBody?["think"] as? Bool == false)
        check("Text-only model: recognized screenshot text sent instead", (textUser?["content"] as? String)?.localizedCaseInsensitiveContains("Friday at 5pm") == true, "\(textUser?["content"] ?? "")")

        let ocr = (try? ImageInputPreparer.recognizeTextSync(in: textImagePNG(["Lentils 4.47 F", "TOTAL 4.47"]))) ?? ""
        check("On-device text recognition reads printed text", ocr.contains("4.47") && ocr.localizedCaseInsensitiveContains("Lentils"), ocr)


        // Blank image with a text-only model gives a clear message instead of a vague failure
        StubURLProtocol.reset([showTextOnly])
        let blank = textImagePNG([])
        let blankResult: Result<(proposals: [QuickCaptureProposal], reasoning: String), Error> = runAsync {
            try await QuickCaptureService(client: stubbedClient()).analyzeCapture(text: "", imageData: blank, imageMimeType: "image/png", referenceDate: Date(), timeZone: tz, model: "qwen3:8b")
        }
        if case .failure(let error) = blankResult {
            check("Photo without text explains a vision model is needed", error.localizedDescription.contains("No text was found"))
        } else {
            check("Photo without text explains a vision model is needed", false)
        }
        let multimodal = OllamaClient.classify(statusCode: 400, data: Data("{\"error\":\"Multimodal data provided, but model does not support multimodal requests.\"}".utf8), model: "qwen3:8b")
        check("Ollama's 'multimodal' rejection is explained", multimodal.message.contains("can't read images"))
        check("Quick Capture prompt includes reference time zone", QuickCaptureService.systemPrompt(referenceDate: Date(), timeZone: tz).contains("America/Los_Angeles"))

        // --- Stage 7: AppState email scan
        print("\n--- Stage 7: AppState Email Scan ---")
        let storage = StorageService(customURL: tempDir.appendingPathComponent("planner_database.json"))
        let gmail = EmailDiscoveryTester.MockDiscoveryGmailService()
        let ollama = MockOllamaService()
        let app = AppState(storageService: storage, calendarService: SimulatedCalendarService(), gmailService: gmail, ollamaService: ollama)
        app.isGmailAuthenticated = true
        check("Email scanning ready without any API key", app.isEmailExtractionConfigured)
        let e1 = sampleEmail(id: "o1", subject: "Lab report", hoursAgo: 2)
        let e2 = sampleEmail(id: "o2", subject: "Broken", hoursAgo: 3)
        gmail.stubsToReturn = [e1, e2].map { GmailMessageStub(id: $0.id, threadId: $0.threadId) }
        gmail.emailDetails["o1"] = e1
        gmail.emailDetails["o2"] = e2
        ollama.responses["o1"] = try! EmailExtractionPrompt.decodeAnalysis(from: sampleAnalysisJSON)
        ollama.errors["o2"] = AIServiceError(kind: .invalidResponse, statusCode: 200, message: "Ollama's email analysis did not match the expected format (gave up after 3 attempts)")
        _ = runAsync { await app.scanEmailsFromLast3Days(); return true }
        check("Both emails sent to Ollama", ollama.callCount == 2)
        check("Uses configured model and time zone", ollama.lastModel == OllamaDefaults.model && ollama.lastTimeZone?.identifier == app.preferences.timeZone.identifier)
        check("Task saved", app.tasks.contains { $0.title == "Submit lab report" })
        check("Cache records the local model", app.extractionCache["o1"]?.modelUsed == OllamaDefaults.model)
        check("Garbled email recorded as a validation failure", app.failedEmailRecords.first { $0.id == "o2" }?.failureStage == .validation)

        let before = ollama.callCount
        _ = runAsync { await app.scanEmailsFromLast3Days(); return true }
        check("Rescan only retries the uncached email", ollama.callCount == before + 1)

        let e3 = sampleEmail(id: "o3", subject: "A", hoursAgo: 1)
        let e4 = sampleEmail(id: "o4", subject: "B", hoursAgo: 1.5)
        gmail.stubsToReturn += [e3, e4].map { GmailMessageStub(id: $0.id, threadId: $0.threadId) }
        gmail.emailDetails["o3"] = e3
        gmail.emailDetails["o4"] = e4
        ollama.errors["o2"] = nil
        ollama.errors["o3"] = OllamaClient.notRunningError()
        ollama.errors["o4"] = OllamaClient.notRunningError()
        let beforeDown = ollama.callCount
        _ = runAsync { await app.scanEmailsFromLast3Days(); return true }
        check("Ollama not running stops the scan once", app.lastScanError?.contains("Ollama isn't running") == true)
        check("No failure records for setup errors", !app.failedEmailRecords.contains { $0.id == "o3" || $0.id == "o4" })
        check("Scan stopped at the first setup error", ollama.callCount - beforeDown <= 2)

        app.setOllamaModel("gemma3:12b")
        let reloaded = AppState(storageService: storage, calendarService: SimulatedCalendarService(), gmailService: gmail, ollamaService: ollama)
        check("Model choice survives reload", reloaded.ollamaModel == "gemma3:12b")

        // --- Stage 8: Older databases still load
        print("\n--- Stage 8: Loading Older Databases ---")
        let legacyPrefsJSON = """
        {"preferredGeminiModel":"gemini-3.5-flash-lite","fallbackGeminiModels":["gemini-3.6-flash"],"automaticFallbackEnabled":true,"hasGeminiApiKey":true,"emailExtractionProvider":"claude","claudeEmailModel":"claude-opus-5-5","workStartHour":8}
        """
        let legacy = try? JSONDecoder().decode(UserPreferences.self, from: Data(legacyPrefsJSON.utf8))
        check("Old Gemini/Claude preferences ignored without error", legacy != nil && legacy?.workStartHour == 8)
        check("Old preferences default to the vision model", legacy?.ollamaModel == OllamaDefaults.model)
        let migrated = try? JSONDecoder().decode(UserPreferences.self, from: Data("{\"ollamaEmailModel\":\"qwen3:8b\"}".utf8))
        check("Earlier ollamaEmailModel setting carried over", migrated?.ollamaModel == "qwen3:8b")
        if let encoded = try? JSONEncoder().encode(UserPreferences()),
           let text = String(data: encoded, encoding: .utf8) {
            check("Saved preferences contain no Gemini/Claude settings", !text.contains("Gemini") && !text.contains("claude"))
        } else {
            check("Preferences encode", false)
        }
        let failureJSON = """
        {"id":"x","threadId":"t","subject":"s","sender":"a","receivedDate":0,"failureStage":"gemini","failureReason":"503","firstFailedAt":0,"lastAttemptAt":0,"attemptCount":1}
        """
        let oldFailure = try? JSONDecoder().decode(FailedEmailRecord.self, from: Data(failureJSON.utf8))
        check("Old 'gemini' failure records still load as AI analysis failures", oldFailure?.failureStage == .analysis)

        print("\n=======================================================")
        if passed == total {
            print(" 🎉 ALL OLLAMA CHECKS PASSED (\(passed)/\(total))!")
        } else {
            print(" ⚠️ SOME CHECKS FAILED (\(passed)/\(total)).")
        }
        print("=======================================================\n")
        return passed == total
    }

    private static func runAsync<T>(_ block: @MainActor @escaping () async throws -> T) -> Result<T, Error> {
        var result: Result<T, Error>?
        Task { @MainActor in
            do { result = .success(try await block()) } catch { result = .failure(error) }
        }
        let start = Date()
        while result == nil && Date().timeIntervalSince(start) < 90.0 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.005))
        }
        return result ?? .failure(NSError(domain: "OllamaTest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Async block timed out"]))
    }
}
