// MacBrowserPanel.swift — a first-class, embedded recipe browser.

import AppKit
import Observation
import SwiftUI
import WebKit

struct MacBrowserPanel: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(\.dismiss) private var dismiss

    @State var address: String
    var onClose: (() -> Void)? = nil

    @State private var pendingLoad: URL?
    @State private var status: BrowserStatus?
    @State private var session = BrowserSession()
    @State private var isAlreadyImported = false
    @State private var autoCapture = true
    @State private var capturedURLs: Set<String> = []
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            Divider()
            pageBar

            if let status {
                statusBanner(status)
            }

            Divider()

            if let pendingLoad {
                BrowserWebView(request: pendingLoad, session: session)
                    .overlay(alignment: .top) {
                        if session.isLoading {
                            ProgressView(value: session.estimatedProgress)
                                .progressViewStyle(.linear)
                        }
                    }
            } else {
                MacEmpty(
                    title: "Browse the web",
                    message: "Enter a recipe page address, paste one, or drop a link. Stocked checks duplicates before importing.",
                    systemImage: "safari"
                )
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                go()
            } else {
                addressFocused = true
            }
        }
        .onChange(of: session.currentURL) {
            guard let url = session.currentURL else { return }
            address = url.absoluteString
            status = nil
        }
        .task(id: "\(activeURLString ?? "")|\(harvest.recipes.count)") {
            guard let activeURLString else {
                isAlreadyImported = false
                return
            }
            isAlreadyImported = await harvest.isAlreadyImported(activeURLString)
        }
        .task(id: session.completedNavigationID) {
            guard autoCapture, session.completedNavigationID > 0,
                  let url = session.completedURL?.absoluteString,
                  capturedURLs.insert(url).inserted else { return }
            status = BrowserStatus("Checking this page for recipes…", kind: .neutral)
            switch await harvest.captureBrowserPage(url) {
            case .recipe(let added):
                status = BrowserStatus(
                    added ? "Recipe found and added to the durable queue." : "Recipe already imported or queued.",
                    kind: .success
                )
            case .listing(let found, let added):
                status = BrowserStatus(
                    added > 0
                        ? "Found \(found) recipe link\(found == 1 ? "" : "s"); queued \(added) new."
                        : "Checked this listing; its recipe links were already known.",
                    kind: added > 0 ? .success : .neutral
                )
            case .ignored:
                status = nil
            case .failed:
                // Browsing must remain quiet and uninterrupted when a site blocks the
                // background classifier; the page itself is still fully usable.
                status = nil
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !first.isEmpty else { return false }
            address = first
            go()
            return true
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 6) {
            Button(action: session.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!session.canGoBack)
            .help("Back")

            Button(action: session.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!session.canGoForward)
            .help("Forward")

            Button {
                if session.isLoading { session.stop() } else { session.reload() }
            } label: {
                Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
            }
            .disabled(pendingLoad == nil)
            .help(session.isLoading ? "Stop loading" : "Reload")

            TextField("Search or enter a URL", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($addressFocused)
                .onSubmit(go)
                .accessibilityLabel("Recipe web address")

            Button(action: go) {
                Image(systemName: "arrow.right.circle.fill")
            }
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Go to this address")
                .accessibilityLabel("Go")

            Menu {
                Button("Open in Safari") { openExternally() }
                    .disabled(activeURL == nil)
                Button("Copy address") { copyAddress() }
                    .disabled(activeURLString == nil)
                Divider()
                Button("Check whether this is a recipe") {
                    guard let activeURLString else { return }
                    harvest.testLink(activeURLString)
                    status = BrowserStatus("Checking the page…", kind: .neutral)
                }
                .disabled(activeURLString == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("Browser actions")

            Button {
                if let onClose { onClose() } else { dismiss() }
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Close browser")
            .accessibilityLabel("Close browser")
        }
        .buttonStyle(.borderless)
        .padding(10)
    }

    private var pageBar: some View {
        HStack(spacing: 8) {
            if let url = activeURL {
                Image(systemName: url.scheme == "https" ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(url.scheme == "https" ? MacTheme.green : Color.orange)
                    .help(url.scheme == "https" ? "Secure HTTPS connection" : "This page is not using HTTPS")
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title.nilIfBlank ?? url.host ?? "Recipe page")
                        .font(.caption.weight(.medium)).lineLimit(1)
                    Text(url.host ?? url.absoluteString)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("No page loaded")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isAlreadyImported {
                Label("In Harvest", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(MacTheme.green)
            }

            Toggle(isOn: $autoCapture) {
                Label("Auto-queue", systemImage: autoCapture ? "sparkles" : "sparkles.slash")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("Automatically find and queue recipes as pages finish loading")

            Button("Queue") {
                guard let activeURLString else { return }
                harvest.appendImportURLs([activeURLString])
                status = BrowserStatus("Added to the import queue.", kind: .success)
            }
            .disabled(activeURLString == nil || session.isLoading)
            .help("Add this page to the import queue")
            .accessibilityLabel("Add to queue")

            Button(isAlreadyImported ? "Update" : "Import") {
                importPage(force: false)
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeURLString == nil || session.isLoading || harvest.isImporting || harvest.isImportingPage)
            .help(isAlreadyImported ? "Update the existing Harvest recipe" : "Import this recipe into Harvest")
            .accessibilityLabel(isAlreadyImported ? "Update recipe" : "Import recipe")

            Menu {
                Button("Import even if this looks like a category page") {
                    importPage(force: true)
                }
                Button("Add to queue and continue browsing") {
                    guard let activeURLString else { return }
                    harvest.appendImportURLs([activeURLString])
                    status = BrowserStatus("Saved for later.", kind: .success)
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .disabled(activeURLString == nil || session.isLoading || harvest.isImporting || harvest.isImportingPage)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statusBanner(_ status: BrowserStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.kind.systemImage)
            Text(status.message)
            Spacer(minLength: 0)
            Button {
                self.status = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(status.kind.tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(status.kind.tint.opacity(0.08))
    }

    private var activeURL: URL? {
        guard let value = activeURLString else { return nil }
        return URL(string: value)
    }

    private var activeURLString: String? {
        (session.currentURL?.absoluteString ?? address).nilIfBlank
            .flatMap { try? URLSafety.validatedRemoteURL($0).absoluteString }
    }

    private func go() {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if !raw.contains("://") {
            if raw.contains(".") && !raw.contains(" ") {
                raw = "https://" + raw
            } else {
                let query = (raw + " recipe").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
                raw = "https://www.google.com/search?q=\(query)"
            }
        }
        guard let url = try? URLSafety.validatedRemoteURL(raw) else {
            status = BrowserStatus("Enter a valid HTTP or HTTPS address.", kind: .error)
            return
        }
        status = nil
        address = url.absoluteString
        session.prepareForNavigation(to: url)
        pendingLoad = url
    }

    private func importPage(force: Bool) {
        guard let activeURLString else { return }
        harvest.importPage(activeURLString, force: force)
        status = BrowserStatus(
            isAlreadyImported ? "Updating the existing Harvest recipe…" : "Importing into Harvest for review…",
            kind: .success
        )
    }

    private func openExternally() {
        guard let activeURL else { return }
        NSWorkspace.shared.open(activeURL)
    }

    private func copyAddress() {
        guard let activeURLString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activeURLString, forType: .string)
        status = BrowserStatus("Address copied.", kind: .success)
    }
}

private struct BrowserStatus {
    let message: String
    let kind: Kind

    init(_ message: String, kind: Kind) {
        self.message = message
        self.kind = kind
    }

    enum Kind {
        case neutral, success, error

        var tint: Color {
            switch self {
            case .neutral: return .secondary
            case .success: return MacTheme.green
            case .error: return .red
            }
        }

        var systemImage: String {
            switch self {
            case .neutral: return "info.circle"
            case .success: return "checkmark.circle"
            case .error: return "exclamationmark.triangle"
            }
        }
    }
}

@MainActor
@Observable
private final class BrowserSession {
    @ObservationIgnored weak var webView: WKWebView?

    var currentURL: URL?
    var title = ""
    var estimatedProgress = 0.0
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var completedURL: URL?
    var completedNavigationID = 0

    func attach(_ webView: WKWebView) {
        self.webView = webView
        update(from: webView)
    }

    func update(from webView: WKWebView) {
        currentURL = webView.url
        title = webView.title ?? ""
        estimatedProgress = webView.estimatedProgress
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func prepareForNavigation(to url: URL) {
        currentURL = url
        title = ""
        estimatedProgress = 0
        isLoading = true
    }

    func completed(_ webView: WKWebView) {
        update(from: webView)
        completedURL = webView.url
        completedNavigationID &+= 1
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func stop() { webView?.stopLoading() }
}

private struct BrowserWebView: NSViewRepresentable {
    let request: URL
    let session: BrowserSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        context.coordinator.connect(to: view)
        context.coordinator.lastRequested = request
        view.load(URLRequest(url: request))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.lastRequested != request {
            context.coordinator.lastRequested = request
            view.load(URLRequest(url: request))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastRequested: URL?
        let session: BrowserSession
        private var observations: [NSKeyValueObservation] = []

        init(session: BrowserSession) {
            self.session = session
        }

        func connect(to webView: WKWebView) {
            session.attach(webView)
            let keys: [NSKeyValueObservation] = [
                webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak session] view, _ in
                    MainActor.assumeIsolated { session?.update(from: view) }
                },
                webView.observe(\.title, options: [.new]) { [weak session] view, _ in
                    MainActor.assumeIsolated { session?.update(from: view) }
                },
                webView.observe(\.url, options: [.new]) { [weak session] view, _ in
                    MainActor.assumeIsolated { session?.update(from: view) }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak session] view, _ in
                    MainActor.assumeIsolated { session?.update(from: view) }
                }
            ]
            observations = keys
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            session.update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.update(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.completed(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            session.update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            session.update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  !["http", "https", "about"].contains(scheme) else {
                decisionHandler(.allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
