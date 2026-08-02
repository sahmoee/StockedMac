// MacBrowserPanel.swift — the visible in-app browser (Build 95, embedded in Build 96).
//
// A real WebKit view over https with an address bar, shown INSIDE the Browse window's
// right pane — no sheet, no separate window. Any site, including one that blocks the
// crawler, can be read by eye and imported from exactly the page on screen. "Import
// this page" runs the normal pipeline; the ⌄ menu can force-import a page the
// category detector reads wrong; "Add to queue" just files the URL.

import AppKit
import SwiftUI
import WebKit

struct MacBrowserPanel: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(\.dismiss) private var dismiss

    @State var address: String
    /// Set when embedded (Build 96); nil means presented as a sheet.
    var onClose: (() -> Void)? = nil
    @State private var currentURL: URL?
    @State private var pendingLoad: URL?
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(.secondary)
                TextField("Enter a URL…", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(go)
                Button("Go", action: go)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                Divider().frame(height: 16)
                Button("Add to queue") {
                    guard let url = activeURLString else { return }
                    harvest.appendImportURLs([url])
                    status = "Queued."
                }
                .disabled(activeURLString == nil)
                Button("Import this page") {
                    guard let url = activeURLString else { return }
                    harvest.importPage(url)
                    status = "Importing — the result lands in Harvest."
                }
                .buttonStyle(.borderedProminent)
                .disabled(activeURLString == nil || harvest.isImporting)
                Menu {
                    Button("Import even if it looks like a category page") {
                        guard let url = activeURLString else { return }
                        harvest.importPage(url, force: true)
                        status = "Importing (forced) — the result lands in Harvest."
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .disabled(activeURLString == nil || harvest.isImporting)
                Button("Close") {
                    if let onClose { onClose() } else { dismiss() }
                }
            }
            .padding(10)

            if let status {
                HStack {
                    Text(status).font(.caption).foregroundStyle(MacTheme.green)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()

            if let pendingLoad {
                BrowserWebView(request: pendingLoad, currentURL: $currentURL)
            } else {
                MacEmpty(
                    title: "Browse the web",
                    message: "Enter a recipe page's address above. What you see is what Import gets.",
                    systemImage: "safari"
                )
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .onAppear {
            if !address.trimmingCharacters(in: .whitespaces).isEmpty { go() }
        }
        .onChange(of: currentURL) {
            if let currentURL { address = currentURL.absoluteString }
        }
    }

    private var activeURLString: String? {
        (currentURL?.absoluteString ?? address).nilIfBlank
            .flatMap { try? URLSafety.validatedRemoteURL($0).absoluteString }
    }

    private func go() {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), url.host != nil else {
            status = "That doesn't look like a web address."
            return
        }
        status = nil
        address = raw
        pendingLoad = url
    }
}

/// WKWebView wrapper that follows navigation and reports the current URL back.
private struct BrowserWebView: NSViewRepresentable {
    let request: URL
    @Binding var currentURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(currentURL: $currentURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.lastRequested = request
        view.load(URLRequest(url: request))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        // Reload only when the requested page genuinely changed, so following links
        // inside the view is never fought by SwiftUI updates.
        if context.coordinator.lastRequested != request {
            context.coordinator.lastRequested = request
            view.load(URLRequest(url: request))
        }
    }

    final class Coordinator: NSObject, @preconcurrency WKNavigationDelegate {
        var lastRequested: URL?
        @Binding var currentURL: URL?

        init(currentURL: Binding<URL?>) {
            _currentURL = currentURL
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            currentURL = webView.url
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            currentURL = webView.url
        }
    }
}
