// WebKitRenderer.swift — an invisible WebKit view that loads a page like Safari would
// and hands back the rendered HTML (Build 95).
//
// Two jobs feed off it:
//   • the importer's fallback — when a plain fetch returns a bot wall or a JS shell,
//     the rendered document usually contains the recipe (and its JSON-LD) intact;
//   • nothing else. The VISIBLE in-app browser is MacBrowserPanel; this one never
//     joins the view hierarchy.
//
// Requests are serialized — one page at a time — because a single hidden web view is
// cheap and predictable, and the importer only asks when the cheap path failed.

import Foundation
import WebKit

@MainActor
final class WebKitRenderer: NSObject {

    static let shared = WebKitRenderer()

    /// Reuse one renderer for the life of the app. Creating and destroying a WebContent
    /// process for every fallback page produced thousands of sandbox/XPC teardown lines
    /// and intermittent cancellation noise during large imports.
    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.suppressesIncrementalRendering = true
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1280, height: 900),
            configuration: configuration
        )
        view.navigationDelegate = self
        return view
    }()
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var didInstallResourceBlocker = false

    /// Loads the URL in a hidden web view, waits for the page (plus a beat for
    /// client-side hydration), and returns `document.documentElement.outerHTML`.
    func renderedHTML(
        for url: URL,
        userAgent: String,
        timeout: TimeInterval = 18
    ) async throws -> String {
        while busy {
            await withCheckedContinuation { waiters.append($0) }
        }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }

        let view = webView
        await installResourceBlockerIfNeeded(on: view)
        view.customUserAgent = userAgent
        defer {
            // `stopLoading` alone leaves the extracted publisher document and its
            // timers alive in WebContent. Replace it with an inert document so large
            // batches do not accumulate sandbox/XPC noise or background frame work.
            view.stopLoading()
            view.loadHTMLString("", baseURL: nil)
        }

        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(.failure(CompanionError.parseFailed(
                    "The built-in browser timed out loading the page"
                )))
            }
            view.load(URLRequest(url: url))
        }
    }

    /// The importer only reads the DOM and schema.org JSON-LD. Preventing WebKit from
    /// downloading images, media and fonts avoids malformed third-party WEBP/JPEG decode
    /// failures and reduces memory/network pressure during large fallback batches.
    private func installResourceBlockerIfNeeded(on view: WKWebView) async {
        guard !didInstallResourceBlocker else { return }
        let rules = """
        [{"trigger":{"url-filter":".*","resource-type":["image","media","font"]},
          "action":{"type":"block"}}]
        """
        let ruleList: WKContentRuleList? = await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "com.sowens.StockedMac.recipe-html-only.v1",
                encodedContentRuleList: rules
            ) { list, _ in
                continuation.resume(returning: list)
            }
        }
        if let ruleList {
            view.configuration.userContentController.add(ruleList)
            didInstallResourceBlocker = true
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let cont = continuation else { return }
        continuation = nil
        switch result {
        case .success(let html): cont.resume(returning: html)
        case .failure(let error): cont.resume(throwing: error)
        }
    }

    private func harvestDocument(from view: WKWebView) {
        view.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let html = value as? String, !html.isEmpty {
                    self.finish(.success(html))
                } else {
                    self.finish(.failure(error ?? CompanionError.parseFailed(
                        "Could not read the rendered page"
                    )))
                }
            }
        }
    }
}

extension WebKitRenderer: WKNavigationDelegate {

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // A malformed image or an overloaded source can terminate WebKit's helper
        // process. Resume the current importer continuation immediately; WKWebView
        // will launch a fresh helper for the next queued page.
        finish(.failure(CompanionError.parseFailed(
            "The built-in browser restarted while loading this page"
        )))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give client-side rendering a moment to hydrate before reading the DOM.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1300))
            guard let self, self.continuation != nil else { return }
            self.harvestDocument(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(.failure(error))
    }
}
