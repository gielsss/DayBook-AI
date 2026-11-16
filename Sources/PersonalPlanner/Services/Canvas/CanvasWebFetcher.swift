import Foundation
import WebKit

/// Sends Canvas API requests from inside a hidden WebKit page, using the cookies saved at sign-in.
///
/// Canvas (behind school SSO) can reject a session that is replayed outside the browser engine.
/// Running `fetch()` in a real Canvas page reproduces the browser exactly: same cookies, origin
/// and headers. The web view uses a non-persistent store that is filled from Keychain each time,
/// so nothing is written to disk outside Keychain.
@MainActor
public final class CanvasWebFetcher: NSObject, WKNavigationDelegate {
    private let baseURL: URL
    private let cookies: [StoredCookie]
    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?

    public init(baseURL: URL, cookies: [StoredCookie]) {
        self.baseURL = baseURL
        self.cookies = cookies
    }

    /// Use as a `CanvasTransport`.
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let webView = try await preparedWebView()
        guard let url = request.url else { throw CanvasError(kind: .invalidResponse, message: "Missing request URL.") }
        let script = """
        const r = await fetch(url, {credentials: 'include', headers: {'Accept': 'application/json'}});
        const body = await r.text();
        return {status: r.status, link: r.headers.get('Link') || '', type: r.headers.get('Content-Type') || '', finalURL: r.url, body: body};
        """
        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(script, arguments: ["url": url.absoluteString], contentWorld: .defaultClient)
        } catch {
            throw CanvasError(kind: .network, message: "Couldn't reach Canvas: \(error.localizedDescription)")
        }
        guard let result = raw as? [String: Any] else {
            throw CanvasError(kind: .invalidResponse, message: "Canvas returned an unexpected response.")
        }
        let status = (result["status"] as? NSNumber)?.intValue ?? (result["status"] as? Int) ?? 0
        var headers: [String: String] = ["Content-Type": result["type"] as? String ?? ""]
        if let link = result["link"] as? String, !link.isEmpty { headers["Link"] = link }
        let finalURL = URL(string: result["finalURL"] as? String ?? "") ?? url
        let response = HTTPURLResponse(url: finalURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (Data((result["body"] as? String ?? "").utf8), response)
    }

    /// Loads a same-origin Canvas page once, after placing the saved cookies in the web view.
    private func preparedWebView() async throws -> WKWebView {
        if let existing = webView { return existing }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        view.navigationDelegate = self
        let store = config.websiteDataStore.httpCookieStore
        for stored in cookies {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: stored.name, .value: stored.value, .domain: stored.domain, .path: stored.path
            ]
            if stored.isSecure { props[.secure] = "TRUE" }
            if let expires = stored.expires { props[.expires] = expires }
            if let cookie = HTTPCookie(properties: props) {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in store.setCookie(cookie) { c.resume() } }
            }
        }
        webView = view
        // A small Canvas API page gives the web view a same-origin document to fetch from.
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loadContinuation = c
            view.load(URLRequest(url: baseURL.appendingPathComponent("api/v1/users/self"), timeoutInterval: 30))
        }
        guard let host = view.url?.host?.lowercased(), host == baseURL.host?.lowercased(), view.url?.path.hasPrefix("/api") == true else {
            webView = nil
            throw CanvasError(kind: .signInRequired, message: "Your Canvas sign-in has expired. Reconnect Canvas in Settings.")
        }
        return view
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: CanvasError(kind: .network, message: "Couldn't reach Canvas: \(error.localizedDescription)"))
        loadContinuation = nil
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: CanvasError(kind: .network, message: "Couldn't reach Canvas: \(error.localizedDescription)"))
        loadContinuation = nil
    }
}
