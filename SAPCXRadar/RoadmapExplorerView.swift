import SwiftUI
import WebKit
import os

private let roadmapLog = Logger(subsystem: "local.sapcxradar.app", category: "roadmap")

/// Roadmap tab: switches between the live SAP Roadmap Explorer and roadmap/release posts.
struct RoadmapTab: View {
    enum Mode: String, CaseIterable, Identifiable {
        case explorer, posts
        var id: String { rawValue }
        var title: String { self == .explorer ? "Explorer" : "Beiträge" }
    }

    @AppStorage("roadmapMode") private var mode: Mode = .explorer

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .explorer: RoadmapExplorerView()
                case .posts: NewsListContent(topics: [.roadmap, .release])
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Ansicht", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }
}

// MARK: - Explorer

/// Saved Roadmap Explorer pages per product (the user picks them after signing in,
/// because product pages are only reachable with an SAP ID).
enum RoadmapBookmarks {
    static let home = URL(string: "https://roadmaps.sap.com/")!

    private static func key(_ p: Product) -> String { "roadmapURL.\(p.rawValue)" }

    /// Built-in roadmap boards (found in the Roadmap Explorer: Products → CRM → …).
    static let defaults: [Product: URL] = [
        .salesV2: URL(string: "https://roadmaps.sap.com/board?PRODUCT=089E017A62AB1EDA94C15F5EDB3300E1&range=CURRENT-LAST")!,
        // "SAP Field Service and Asset Management" (the Roadmap Explorer's current name for FSM)
        .fsm: URL(string: "https://roadmaps.sap.com/board?PRODUCT=73555000100800001711&range=CURRENT-LAST")!,
    ]

    /// The user's saved page wins over the built-in default.
    static func url(for product: Product) -> URL? {
        UserDefaults.standard.string(forKey: key(product)).flatMap(URL.init(string:)) ?? defaults[product]
    }

    static func hasCustom(_ product: Product) -> Bool {
        UserDefaults.standard.string(forKey: key(product)) != nil
    }

    static func save(_ url: URL, for product: Product) {
        UserDefaults.standard.set(url.absoluteString, forKey: key(product))
    }

    static func remove(for product: Product) {
        UserDefaults.standard.removeObject(forKey: key(product))
    }
}

@MainActor
@Observable
final class WebState {
    var url: URL?
    var title = ""
    var isLoading = false
    var progress = 0.0
    var canGoBack = false
    var canGoForward = false
    var error: String?

    /// True while SAP's sign-in page is showing.
    var isOnLoginPage: Bool {
        guard let host = url?.host() else { return false }
        return host.hasSuffix("accounts.sap.com") || host.hasSuffix("accounts400.sap.com")
            || host.contains("authn") || host.hasPrefix("login.")
    }

    let webView: WKWebView
    private let errorHandler = SAPErrorHandler()
    private var recentReloads: [Date] = []

    /// Reloads after an SAP error page: at most 3 times per minute and never
    /// sooner than 4 s after the last reload (no reload loops).
    private func recoverFromSAPError() {
        recentReloads = recentReloads.filter { Date.now.timeIntervalSince($0) < 60 }
        if let last = recentReloads.last, Date.now.timeIntervalSince(last) < 4 { return }
        guard recentReloads.count < 3 else { return }
        recentReloads.append(.now)
        roadmapLog.debug("SAP error page, reloading")
        webView.reload()
    }

    init() {
        let config = WKWebViewConfiguration()
        // Persistent store: the SAP sign-in survives app restarts.
        config.websiteDataStore = .default()
        // Identify as mobile Safari; some SAP pages fail for unknown embedded browsers.
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // SAP's single-page app sometimes shows "Something went wrong" or
        // "Your session expired" right after the silent SSO sign-in; a reload fixes it.
        // This script reports those pages so the app can reload automatically.
        let detector = """
        (function () {
          var markers = ["Something went wrong", "Your session expired"];
          // SAP's UI renders inside shadow roots, which innerText does not reach.
          function deepText(node, depth) {
            if (!node || depth > 25) return "";
            var t = "";
            if (node.nodeType === 3) return node.nodeValue || "";
            if (node.shadowRoot) t += deepText(node.shadowRoot, depth + 1);
            for (var c = node.firstChild; c; c = c.nextSibling) t += deepText(c, depth + 1);
            return t;
          }
          var last = 0;
          function check() {
            var now = Date.now();
            if (now - last < 1500 || !document.body) return;
            last = now;
            var t = deepText(document.body, 0);
            for (var i = 0; i < markers.length; i++) {
              if (t.indexOf(markers[i]) >= 0) {
                window.webkit.messageHandlers.sapError.postMessage(location.href);
                return;
              }
            }
          }
          setInterval(check, 2000);
          check();
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: detector, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(errorHandler, name: "sapError")

        webView = WKWebView(frame: .zero, configuration: config)
        errorHandler.onError = { [weak self] in self?.recoverFromSAPError() }
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        error = nil
        webView.load(URLRequest(url: url))
    }

    /// Removes the SAP session (cookies & site data for *.sap.com).
    func signOut() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let sap = records.filter { $0.displayName.contains("sap.com") }
        await store.removeData(ofTypes: types, for: sap)
        load(RoadmapBookmarks.home)
    }
}

struct RoadmapExplorerView: View {
    @State private var web = WebState()
    @State private var didLoad = false
    @State private var savedProducts: Set<Product> = []
    @State private var confirmation: String?
    @State private var showSignOut = false

    var body: some View {
        VStack(spacing: 0) {
            productBar

            if web.isLoading {
                ProgressView(value: web.progress).progressViewStyle(.linear).tint(.blue)
            } else {
                Divider()
            }

            if web.isOnLoginPage {
                Label("Mit deiner SAP-ID anmelden. Die Anmeldung bleibt in der App gespeichert.",
                      systemImage: "lock.shield")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.blue.opacity(0.1))
            }

            ZStack {
                WebView(state: web)
                if let error = web.error {
                    ContentUnavailableView {
                        Label("Seite nicht erreichbar", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Erneut versuchen") { web.webView.reload() }
                    }
                    .background(.background)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { web.webView.goBack() } label: { Image(systemName: "chevron.backward") }
                    .disabled(!web.canGoBack)
            }
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .overlay(alignment: .bottom) {
            if let confirmation {
                Text(confirmation)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog("Von SAP abmelden?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await web.signOut() } }
        } message: {
            Text("Die gespeicherte SAP-Anmeldung wird aus der App entfernt.")
        }
        .onAppear {
            refreshSaved()
            guard !didLoad else { return }
            didLoad = true
            web.load(RoadmapBookmarks.home)
        }
    }

    /// Quick switch between saved product roadmaps.
    private var productBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Start", symbol: "house", color: .gray) { web.load(RoadmapBookmarks.home) }
                ForEach(Product.allCases) { p in
                    let saved = savedProducts.contains(p)
                    chip(title: p.shortTitle, symbol: saved ? p.symbol : "plus", color: p.color, dimmed: !saved) {
                        if let url = RoadmapBookmarks.url(for: p) {
                            web.load(url)
                        } else {
                            flash("Öffne die \(p.title)-Roadmap und speichere sie über das Menü ⋯")
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
    }

    private func chip(title: String, symbol: String, color: Color, dimmed: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(color)
                .background(color.opacity(dimmed ? 0.06 : 0.14), in: .capsule)
                .opacity(dimmed ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }

    private var menu: some View {
        Menu {
            Section("Aktuelle Seite speichern als") {
                ForEach(Product.allCases) { p in
                    Button("\(p.title)-Roadmap", systemImage: p.symbol) {
                        guard let url = web.url, !web.isOnLoginPage else {
                            flash("Bitte zuerst anmelden und die Roadmap öffnen")
                            return
                        }
                        RoadmapBookmarks.save(url, for: p)
                        refreshSaved()
                        flash("Als \(p.shortTitle)-Roadmap gespeichert")
                    }
                }
            }
            if Product.allCases.contains(where: RoadmapBookmarks.hasCustom) {
                Section("Eigene Seite entfernen") {
                    ForEach(Product.allCases.filter(RoadmapBookmarks.hasCustom)) { p in
                        Button(p.title, systemImage: "trash", role: .destructive) {
                            RoadmapBookmarks.remove(for: p)
                            refreshSaved()
                        }
                    }
                }
            }
            Section {
                Button("Neu laden", systemImage: "arrow.clockwise") { web.webView.reload() }
                if let url = web.url {
                    ShareLink(item: url) { Label("Teilen / in Safari öffnen", systemImage: "square.and.arrow.up") }
                }
                Button("Von SAP abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    showSignOut = true
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func refreshSaved() {
        savedProducts = Set(Product.allCases.filter { RoadmapBookmarks.url(for: $0) != nil })
    }

    private func flash(_ text: String) {
        withAnimation(.snappy) { confirmation = text }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.snappy) { if confirmation == text { confirmation = nil } }
        }
    }
}

/// Receives "sapError" messages from the page script. Kept separate from WebState
/// because WKUserContentController retains its handlers strongly.
final class SAPErrorHandler: NSObject, WKScriptMessageHandler {
    var onError: (@MainActor () -> Void)?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { onError?() }
    }
}

// MARK: - WKWebView wrapper

struct WebView: UIViewRepresentable {
    let state: WebState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = state.webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.observe(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        /// Links that open a new window (target=_blank / window.open) load in the same view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        let state: WebState
        private var observations: [NSKeyValueObservation] = []

        init(state: WebState) { self.state = state }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.url) { [weak self] wv, _ in
                    MainActor.assumeIsolated {
                        self?.state.url = wv.url
                        // Log only roadmap pages (never sign-in URLs, which carry one-time codes).
                        if let url = wv.url, url.host() == "roadmaps.sap.com", !url.path().hasPrefix("/login") {
                            roadmapLog.debug("url \(url.absoluteString, privacy: .public)")
                        }
                    }
                },
                webView.observe(\.title) { [weak self] wv, _ in
                    MainActor.assumeIsolated { self?.state.title = wv.title ?? "" }
                },
                webView.observe(\.isLoading) { [weak self] wv, _ in
                    MainActor.assumeIsolated { self?.state.isLoading = wv.isLoading }
                },
                webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                    MainActor.assumeIsolated { self?.state.progress = wv.estimatedProgress }
                },
                webView.observe(\.canGoBack) { [weak self] wv, _ in
                    MainActor.assumeIsolated { self?.state.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward) { [weak self] wv, _ in
                    MainActor.assumeIsolated { self?.state.canGoForward = wv.canGoForward }
                },
            ]
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.error = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            let ns = error as NSError
            // Cancelled loads happen during normal redirects (e.g. SAML sign-in).
            guard ns.code != NSURLErrorCancelled, ns.code != 102 else { return }
            state.error = error.localizedDescription
        }
    }
}
