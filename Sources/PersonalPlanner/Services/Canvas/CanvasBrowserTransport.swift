import Foundation
import AppKit

/// Browsers PersonalPlanner can borrow a signed-in Canvas tab from.
public enum CanvasBrowser: String, CaseIterable, Identifiable, Codable {
    case safari = "Safari"
    case chrome = "Google Chrome"
    case arc = "Arc"

    public var id: String { rawValue }

    public var bundleIdentifier: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .arc: return "company.thebrowser.Browser"
        }
    }

    /// Checked before any AppleScript runs: scripting a browser that isn't installed makes macOS
    /// show a "Where is …?" dialog, and scripting one that isn't open would launch it.
    public var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil }
    public var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }
    public var displayName: String { self == .chrome ? "Chrome" : rawValue }

    /// Where the user turns on "Allow JavaScript from Apple Events" (one time).
    public var enableJavaScriptHint: String {
        switch self {
        case .safari: return "In Safari, choose Settings → Advanced → turn on \"Show features for web developers\", then Develop menu → \"Allow JavaScript from Apple Events\"."
        case .chrome: return "In Chrome, choose View → Developer → \"Allow JavaScript from Apple Events\"."
        case .arc: return "In Arc, choose View → Developer → \"Allow JavaScript from Apple Events\"."
        }
    }

    /// AppleScript that runs `js` (or, with nil, just reports the tab) in the first tab whose URL
    /// starts with one of `prefixes`. When no tab matches it returns "PP_NO_TAB|" plus the hosts of
    /// the open tabs, so the app can say what it saw. Values are embedded as escaped string literals.
    func script(js: String?, prefixes: [String]) -> String {
        func lit(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let action: String
        if let js = js {
            action = self == .safari ? "do JavaScript \(lit(js)) in t" : "execute t javascript \(lit(js))"
        } else {
            action = "\"PP_FOUND\""
        }
        return """
        set prefixes to {\(prefixes.map(lit).joined(separator: ", "))}
        set seen to {}
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                set wTabs to {}
                try
                    set wTabs to tabs of w
                end try
                repeat with t in wTabs
                    set u to ""
                    try
                        set u to (URL of t) as text
                    end try
                    repeat with p in prefixes
                        if u starts with (p as text) then
                            return (\(action))
                        end if
                    end repeat
                    set end of seen to u
                end repeat
            end repeat
        end tell
        set AppleScript's text item delimiters to "\n"
        return "PP_NO_TAB|" & (seen as text)
        """
    }
}

/// Runs Canvas API GET requests inside a Canvas tab the user already has open and signed in to
/// (the approach of a classmate's script). Nothing is stored: the browser keeps the sign-in.
///
/// Requires, one time: macOS Automation permission for PersonalPlanner to control the browser, and
/// "Allow JavaScript from Apple Events" in the browser. Requests are read-only (GET).
public final class CanvasBrowserTransport: @unchecked Sendable {
    public let browser: CanvasBrowser
    private let canvasHosts: [String]

    public init(browser: CanvasBrowser, canvasHost: String) {
        self.browser = browser
        var hosts = [canvasHost.lowercased()]
        // Schools' Canvas often also answers at <school>.instructure.com.
        if let school = canvasHost.lowercased().split(separator: ".").dropFirst().first, canvasHost.hasPrefix("canvas.") {
            hosts.append("\(school).instructure.com")
        }
        self.canvasHosts = hosts
    }

    /// JavaScript for one request. Synchronous XHR so AppleScript gets the result directly;
    /// the request goes to the tab's own origin, so the browser's Canvas sign-in is used.
    nonisolated static func javaScript(for url: URL) -> String {
        var pathAndQuery = url.path
        if let q = url.query { pathAndQuery += "?" + q }
        let target = pathAndQuery.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(){var x=new XMLHttpRequest();x.open('GET','\(target)',false);x.setRequestHeader('Accept','application/json');\
        try{x.send(null);}catch(e){return JSON.stringify({status:0,body:String(e)});}\
        return JSON.stringify({status:x.status,link:x.getResponseHeader('Link')||'',type:x.getResponseHeader('Content-Type')||'',url:x.responseURL,body:x.responseText});})()
        """
    }

    /// URL prefixes of this school's Canvas tabs.
    var prefixes: [String] { canvasHosts.map { "https://\($0)/" } }

    /// Use as a `CanvasTransport`.
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw CanvasError(kind: .invalidResponse, message: "Missing request URL.") }
        try checkAvailable()
        let source = browser.script(js: Self.javaScript(for: url), prefixes: prefixes)
        let output = try await MainActor.run { try Self.runAppleScript(source) }
        return try Self.response(fromOutput: output, browser: browser, requestURL: url)
    }

    func checkAvailable() throws {
        guard browser.isInstalled else {
            throw CanvasError(kind: .setup, message: "\(browser.displayName) isn't installed on this Mac. Choose another browser in Settings → Canvas.")
        }
        guard browser.isRunning else {
            throw CanvasError(kind: .setup, message: "\(browser.displayName) isn't open. Open Canvas in \(browser.displayName), then sync again.")
        }
    }

    /// Whether this browser has a Canvas tab open. Throws the real reason (e.g. permission) on failure.
    public func hasCanvasTab() async throws -> Bool {
        try checkAvailable()
        let source = browser.script(js: nil, prefixes: prefixes)
        let output = try await MainActor.run { try Self.runAppleScript(source) }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "PP_FOUND" { return true }
        throw Self.noTabError(text, browser: browser, expected: canvasHosts.first ?? "")
    }

    /// Interprets the script's output (exposed for tests).
    nonisolated static func response(fromOutput output: String, browser: CanvasBrowser, requestURL: URL) throws -> (Data, URLResponse) {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "PP_NOT_RUNNING" {
            throw CanvasError(kind: .setup, message: "\(browser.displayName) isn't open. Open Canvas in \(browser.displayName), then sync again.")
        }
        if text.hasPrefix("PP_NO_TAB") {
            throw noTabError(text, browser: browser, expected: requestURL.host ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw CanvasError(kind: .invalidResponse, message: "\(browser.displayName) returned something unexpected from Canvas.")
        }
        let status = (json["status"] as? NSNumber)?.intValue ?? 0
        if status == 0 {
            throw CanvasError(kind: .network, message: "The Canvas tab couldn't reach Canvas: \(json["body"] as? String ?? "network error").")
        }
        var headers: [String: String] = ["Content-Type": json["type"] as? String ?? ""]
        if let link = json["link"] as? String, !link.isEmpty { headers["Link"] = link }
        let finalURL = URL(string: json["url"] as? String ?? "") ?? requestURL
        let response = HTTPURLResponse(url: finalURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data((json["body"] as? String ?? "").utf8), response)
    }

    /// Explains a missing Canvas tab, listing the sites the browser's tabs are on (shown only locally).
    nonisolated static func noTabError(_ output: String, browser: CanvasBrowser, expected: String) -> CanvasError {
        let urls = output.components(separatedBy: "PP_NO_TAB|").last?.split(separator: "\n").map(String.init) ?? []
        let hosts = Array(Set(urls.compactMap { URL(string: $0)?.host })).sorted()
        let seen: String
        if urls.isEmpty || (urls.count == 1 && urls[0].isEmpty) {
            seen = "\(browser.displayName) reported no open tabs (if tabs are open, DayBook AI may not be allowed to see them: System Settings → Privacy & Security → Automation)."
        } else {
            seen = "Tabs open in \(browser.displayName): \(hosts.isEmpty ? "\(urls.count) without a web address" : hosts.prefix(8).joined(separator: ", "))."
        }
        return CanvasError(kind: .setup, message: "No \(expected) tab found in \(browser.displayName). \(seen)")
    }

    /// Runs AppleScript inside PersonalPlanner (so macOS asks permission for PersonalPlanner itself),
    /// mapping permission errors to clear setup messages.
    @MainActor
    static func runAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw CanvasError(kind: .invalidResponse, message: "Couldn't prepare the browser command.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let info = errorInfo {
            let number = info[NSAppleScript.errorNumber] as? Int ?? 0
            let message = info[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw error(fromStderr: "\(message) (\(number))")
        }
        return result.stringValue ?? ""
    }

    nonisolated static func error(fromStderr stderr: String) -> CanvasError {
        let lower = stderr.lowercased()
        if lower.contains("-1743") || lower.contains("not authorized") || lower.contains("not allowed to send") {
            return CanvasError(kind: .setup, message: "DayBook AI isn't allowed to control your browser. Turn it on in System Settings → Privacy & Security → Automation → DayBook AI.")
        }
        if lower.contains("javascript") && (lower.contains("turned off") || lower.contains("not allowed") || lower.contains("apple events")) {
            return CanvasError(kind: .setup, message: "Your browser is blocking JavaScript from Apple Events. Turn on \"Allow JavaScript from Apple Events\" (Develop / View → Developer menu).")
        }
        return CanvasError(kind: .network, message: "Couldn't talk to the browser: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    /// Which running browser has a Canvas tab open (for "Find my Canvas tab"). Returns the browser,
    /// or the most useful reason none was found.
    public static func findBrowserWithCanvasTab(canvasHost: String) async -> (CanvasBrowser?, CanvasError?) {
        var firstProblem: CanvasError? = nil
        for browser in CanvasBrowser.allCases where browser.isInstalled && browser.isRunning {
            do {
                if try await CanvasBrowserTransport(browser: browser, canvasHost: canvasHost).hasCanvasTab() { return (browser, nil) }
            } catch let error as CanvasError {
                // Permission problems are more useful to show than "no tab".
                if firstProblem == nil || error.message.contains("allowed") { firstProblem = error }
            } catch {}
        }
        return (nil, firstProblem)
    }
}

/// Opens Canvas / Gradescope in the user's browser without bringing it to the front, so a sync can
/// run even when no tab is open. Only used by Sync Everything.
public enum BrowserTabOpener {
    /// What `prepare` did, so the sync can tidy up afterwards.
    public struct Preparation: Equatable {
        /// We opened a tab (there was none).
        public var openedTab = false
        /// We started the browser (it wasn't running), hidden.
        public var launchedBrowser = false
        /// Set when the tab never finished loading on the expected site (usually a sign-in page).
        public var problem: String? = nil
        public init(openedTab: Bool = false, launchedBrowser: Bool = false, problem: String? = nil) {
            self.openedTab = openedTab
            self.launchedBrowser = launchedBrowser
            self.problem = problem
        }
    }

    /// Makes sure `browser` has a loaded tab on one of `prefixes`, opening `url` in the background if needed.
    @MainActor
    public static func prepare(browser: CanvasBrowser, url: URL, prefixes: [String], siteName: String,
                               timeout: TimeInterval = 45) async -> Preparation {
        guard browser.isInstalled else {
            return Preparation(problem: "\(browser.displayName) isn't installed on this Mac.")
        }
        var result = Preparation()
        if browser.isRunning, (try? CanvasBrowserTransport.runAppleScript(browser.script(js: nil, prefixes: prefixes))) == "PP_FOUND" {
            return result // a tab is already open: use it, touch nothing
        }
        result.launchedBrowser = !browser.isRunning
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) else {
            return Preparation(problem: "\(browser.displayName) isn't installed on this Mac.")
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = result.launchedBrowser
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        } catch {
            result.problem = "Couldn't open \(siteName) in \(browser.displayName): \(error.localizedDescription)"
            return result
        }
        result.openedTab = true

        // Wait until the page has loaded on the expected site (an SSO sign-in page lives elsewhere).
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            // A new tab reports "complete" for about:blank before the real page arrives, so also
            // require the page itself to be on the site.
            let state = try? CanvasBrowserTransport.runAppleScript(
                browser.script(js: "document.readyState + '|' + location.href", prefixes: prefixes))
            if let state, Self.isLoaded(state, prefixes: prefixes) { return result }
        }
        result.problem = "\(siteName) didn't finish loading in \(browser.displayName). It may need you to sign in there; the tab is open for you."
        return result
    }

    /// Whether a "readyState|location" answer means the real page has loaded on one of the sites.
    nonisolated static func isLoaded(_ state: String, prefixes: [String]) -> Bool {
        let parts = state.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == "complete" else { return false }
        return prefixes.contains { parts[1].hasPrefix($0) }
    }

    /// Closes the tabs `prepare` opened and quits the browser if `prepare` started it.
    /// Leaves everything alone when the site had a problem (usually: it needs the user to sign in).
    @MainActor
    public static func tidyUp(browser: CanvasBrowser, prefixes: [String], preparation: Preparation) {
        guard preparation.problem == nil else { return }
        if preparation.launchedBrowser {
            NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleIdentifier).forEach { $0.terminate() }
            return
        }
        guard preparation.openedTab, browser.isRunning else { return }
        let list = prefixes.map { "\"" + $0.replacingOccurrences(of: "\"", with: "") + "\"" }.joined(separator: ", ")
        let source = """
        set prefixes to {\(list)}
        tell application id "\(browser.bundleIdentifier)"
            repeat with w in windows
                try
                    repeat with t in (reverse of (tabs of w as list))
                        set u to ""
                        try
                            set u to (URL of t) as text
                        end try
                        repeat with p in prefixes
                            if u starts with (p as text) then
                                close t
                                exit repeat
                            end if
                        end repeat
                    end repeat
                end try
            end repeat
        end tell
        return "ok"
        """
        _ = try? CanvasBrowserTransport.runAppleScript(source)
    }
}
