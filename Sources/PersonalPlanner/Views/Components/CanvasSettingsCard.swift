import SwiftUI
import WebKit

/// Settings for reading Canvas: school address, sign-in (or access token), and sync.
public struct CanvasSettingsCard: View {
    @ObservedObject var appState: AppState
    @State private var addressInput: String = ""
    @State private var tokenInput: String = ""
    @State private var showTokenField: Bool = false
    @State private var isCheckingAddress: Bool = false

    public init(appState: AppState) {
        self.appState = appState
        _addressInput = State(initialValue: URL(string: appState.preferences.canvasBaseURL)?.host ?? appState.preferences.canvasBaseURL)
    }

    private var addressIsValid: Bool { CanvasClient.normalizedBaseURL(addressInput) != nil }

    private func connectThroughBrowser(_ browser: CanvasBrowser?) {
        Task {
            isCheckingAddress = true
            if let found = await appState.resolveCanvasAddress(addressInput) {
                addressInput = found.host ?? addressInput
                await appState.connectCanvasThroughBrowser(browser)
                if appState.isCanvasConnected { await appState.syncCanvas() }
            }
            isCheckingAddress = false
        }
    }

    public var body: some View {
        GroupBox(label: Label("Canvas", systemImage: "graduationcap").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reads your assignments, quizzes, announcements, inbox, discussions, feedback, syllabi and course events, and turns them into tasks. Read-only: nothing is ever posted or submitted. Text is analyzed by your local model.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("School address:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)
                    TextField("canvas.yourschool.edu", text: $addressInput, onCommit: {
                        appState.setCanvasAddress(addressInput)
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                    Spacer()
                }

                HStack(spacing: 10) {
                    if appState.isCanvasConnected {
                        Button(action: { Task { await appState.syncCanvas() } }) {
                            HStack(spacing: 4) {
                                if appState.isSyncingCanvas { ProgressView().controlSize(.small) }
                                Text(appState.isSyncingCanvas ? "Syncing..." : "Sync Canvas")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isSyncingCanvas)
                        if appState.isSyncingCanvas {
                            Button("Cancel") { appState.cancelCanvasSync() }
                                .buttonStyle(.bordered)
                        }
                        Button("Disconnect") {
                            appState.disconnectCanvas()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.isSyncingCanvas)
                    } else {
                        Button(action: {
                            Task {
                                isCheckingAddress = true
                                if let found = await appState.resolveCanvasAddress(addressInput) {
                                    addressInput = found.host ?? addressInput
                                    appState.showCanvasSignInSheet = true
                                }
                                isCheckingAddress = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                if isCheckingAddress { ProgressView().controlSize(.small) }
                                Text(isCheckingAddress ? "Checking address..." : "Sign in to Canvas")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!addressIsValid || isCheckingAddress)
                        Menu("Use my browser") {
                            Button("Find my Canvas tab") { connectThroughBrowser(nil) }
                            Divider()
                            ForEach(CanvasBrowser.allCases) { browser in
                                Button(browser.displayName) { connectThroughBrowser(browser) }
                            }
                        }
                        .fixedSize()
                        .disabled(!addressIsValid || isCheckingAddress)
                        .help("Read Canvas through a signed-in Canvas tab in Safari, Chrome or Arc")
                        Button(showTokenField ? "Hide token" : "Use an access token") {
                            showTokenField.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    Spacer()
                    if appState.isCanvasConnected {
                        Label((appState.canvasUserName.isEmpty ? "Connected" : "Connected as \(appState.canvasUserName)")
                              + (appState.preferences.canvasBrowser.map { " via \($0.displayName)" } ?? ""), systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                if showTokenField && !appState.isCanvasConnected {
                    HStack {
                        SecureField("Canvas access token", text: $tokenInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 280)
                        Button("Connect") {
                            Task {
                                if let found = await appState.resolveCanvasAddress(addressInput) {
                                    addressInput = found.host ?? addressInput
                                    await appState.connectCanvas(token: tokenInput)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(tokenInput.isEmpty || !addressIsValid)
                    }
                    Text("Canvas → Account → Settings → Approved Integrations → + New Access Token. Tokens don't expire like sign-ins do.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let last = appState.lastCanvasSyncDate, appState.isCanvasConnected, !appState.isSyncingCanvas {
                    Text("Last synced \(appState.relativeTimeString(from: last)). Also syncs when you press Scan Emails.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let status = appState.canvasStatusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = appState.canvasErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
        }
        .sheet(isPresented: $appState.showCanvasSignInSheet) {
            CanvasSignInSheet(appState: appState)
        }
    }
}

/// Shows the school's own Canvas login (SSO and two-factor work as in a browser). Once the window is
/// on a signed-in Canvas page, the app keeps trying to take over that session (every 2 seconds, or on
/// Continue) and closes the window when Canvas accepts it.
struct CanvasSignInSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CanvasLoginController()
    @State private var isChecking = false
    @State private var attempts = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Canvas")
                    .font(.headline)
                Spacer()
                if isChecking { ProgressView().controlSize(.small) }
                Button("Continue") { Task { await check(force: true) } }
                    .disabled(isChecking || !controller.isOnCanvasPage)
                    .help("Use this once you can see your Canvas dashboard")
                Button("Cancel") { dismiss() }
            }
            .padding(12)
            Divider()
            if let url = appState.canvasBaseURL?.appendingPathComponent("login") {
                CanvasLoginWebView(startURL: url, canvasHost: appState.canvasBaseURL?.host ?? "", controller: controller)
            } else {
                Text("Enter your school's Canvas address first.")
                    .padding()
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(attempts >= 3 ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your password goes only to your school. DayBook AI keeps the resulting Canvas sign-in in your Keychain and only reads data.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(width: 560, height: 720)
        .onAppear { appState.canvasSignInDetail = nil }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            Task { await check(force: false) }
        }
    }

    private var statusText: String {
        if !controller.isOnCanvasPage { return "Sign in with your school account. This window closes by itself when you're done." }
        if let inPage = controller.inPageStatus, attempts >= 2 {
            return "Canvas in this window answers: \(inPage) (\(controller.currentHost)). Waiting for your Canvas dashboard..."
        }
        return "Checking your Canvas sign-in..."
    }

    private func check(force: Bool) async {
        guard !isChecking, controller.isOnCanvasPage || force else { return }
        isChecking = true
        defer { isChecking = false }
        attempts += 1
        // Ask Canvas from inside the signed-in page: this is exactly what the browser itself does.
        guard let me = await controller.signedInUser() else { return }
        let cookies = await controller.allCookies()
        appState.completeCanvasSignInFromWindow(cookies: cookies, host: controller.currentHost, userName: me)
        dismiss()
        await appState.syncCanvas()
    }
}

/// Holds the login web view so the sheet can read its cookies and ask Canvas from inside the page.
@MainActor
final class CanvasLoginController: ObservableObject {
    weak var webView: WKWebView?
    var canvasHost: String = ""
    @Published var isOnCanvasPage = false
    @Published var currentHost: String = ""
    /// What Canvas's API answers when asked from inside the page, e.g. "200" or "401".
    @Published var inPageStatus: String? = nil

    /// Canvas can live at the school's address or at <school>.instructure.com; either counts.
    func pageDidChange() {
        let host = webView?.url?.host?.lowercased() ?? ""
        currentHost = host
        isOnCanvasPage = !host.isEmpty && (host == canvasHost.lowercased() || host.hasSuffix(".instructure.com"))
    }

    /// The signed-in user's name if Canvas, asked from inside this page, says we're signed in.
    func signedInUser() async -> String? {
        pageDidChange()
        guard let webView = webView, isOnCanvasPage else { return nil }
        let script = """
        const r = await fetch('/api/v1/users/self', {credentials: 'same-origin', headers: {'Accept': 'application/json'}});
        const t = await r.text();
        return {status: r.status, body: t};
        """
        guard let result = try? await webView.callAsyncJavaScript(script, arguments: [:], contentWorld: .defaultClient) as? [String: Any] else {
            inPageStatus = "no answer"
            return nil
        }
        let status = (result["status"] as? NSNumber)?.intValue ?? 0
        inPageStatus = "\(status)"
        guard status == 200, let body = result["body"] as? String,
              let json = try? CanvasClient.parseJSON(Data(body.utf8)) as? [String: Any] else { return nil }
        return (json["short_name"] as? String) ?? (json["name"] as? String) ?? ""
    }

    func allCookies() async -> [HTTPCookie] {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return [] }
        return await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }
}

/// The login web view. Reports page changes to the controller (no decisions are made here).
struct CanvasLoginWebView: NSViewRepresentable {
    let startURL: URL
    let canvasHost: String
    let controller: CanvasLoginController

    func makeCoordinator() -> Coordinator { Coordinator(controller) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // nothing kept outside Keychain
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        controller.webView = webView
        controller.canvasHost = canvasHost
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let controller: CanvasLoginController
        init(_ controller: CanvasLoginController) { self.controller = controller }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in controller.pageDidChange() }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in controller.pageDidChange() }
        }

        /// Sign-in pages (e.g. Duo) sometimes open links in a new window; keep them in this one.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }
    }
}
