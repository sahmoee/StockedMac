// MacActivityLogView.swift — the Harvester's activity log and import-queue tools.
//
// Build 114. HarvestModel already records a bounded, de-duplicated activity log and has
// queue maintenance (clean, undo, copy) and failure diagnostics that were not reachable
// from the UI. This sheet exposes them without adding a new pipeline: every action calls
// the existing HarvestModel method, so queue caps, session guards, normalization and the
// image/attribution gates are unchanged.

import AppKit
import SwiftUI

struct MacActivityLogView: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(\.dismiss) private var dismiss

    @State private var level: CrawlLogEntry.Level?
    @State private var search = ""
    @State private var confirmClear = false

    private var entries: [CrawlLogEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return harvest.logs.filter { entry in
            (level == nil || entry.level == level)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
                    || (entry.url?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            logList
            Divider()
            queueTools
        }
        .frame(minWidth: 680, idealWidth: 820, minHeight: 520, idealHeight: 660)
        .confirmationDialog("Clear the activity log?", isPresented: $confirmClear) {
            Button("Clear Log", role: .destructive) { harvest.clearLogs() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only the log is cleared. Recipes, the queue and failures are unchanged.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.title2).foregroundStyle(MacTheme.gold).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Import Activity").font(.title2.weight(.semibold))
                Text(harvest.statusMessage).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Level", selection: $level) {
                Text("All").tag(CrawlLogEntry.Level?.none)
                Text("Success").tag(CrawlLogEntry.Level?.some(.success))
                Text("Info").tag(CrawlLogEntry.Level?.some(.info))
                Text("Warnings").tag(CrawlLogEntry.Level?.some(.warning))
                Text("Errors").tag(CrawlLogEntry.Level?.some(.error))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 380)
            TextField("Search messages and links", text: $search)
                .textFieldStyle(.roundedBorder)
            Button { copyVisible() } label: { Image(systemName: "doc.on.doc") }
                .help("Copy the visible log entries")
                .disabled(entries.isEmpty)
            Button(role: .destructive) { confirmClear = true } label: { Image(systemName: "trash") }
                .help("Clear the activity log")
                .disabled(harvest.logs.isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder
    private var logList: some View {
        if entries.isEmpty {
            MacEmpty(title: harvest.logs.isEmpty ? "No activity yet" : "No matching entries",
                     message: harvest.logs.isEmpty ? "Imports, discovery runs and repairs are recorded here." : "Try another level or search.",
                     systemImage: "text.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: icon(entry.level)).foregroundStyle(tint(entry.level)).frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message).font(.callout).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(entry.timestamp, style: .time)
                            if let url = entry.url { Text(url).lineLimit(1).truncationMode(.middle) }
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if let raw = entry.url, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Link(destination: url) { Image(systemName: "safari") }.help("Open this page")
                    }
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Copy Message") { MacRecipeClipboard.copy(entry.message) }
                    if let url = entry.url { Button("Copy Link") { MacRecipeClipboard.copy(url) } }
                }
            }
            .listStyle(.inset)
        }
    }

    private var queueTools: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("\(harvest.queuedURLCount) queued", systemImage: "link")
                let snapshot = harvest.queueSnapshot
                if snapshot.duplicateCount + snapshot.invalidCount > 0 {
                    MacPill(text: "\(snapshot.duplicateCount) duplicate · \(snapshot.invalidCount) invalid", tint: .orange)
                }
                MacPill(text: "\(snapshot.domainCount) site\(snapshot.domainCount == 1 ? "" : "s")", tint: .secondary)
                Spacer()
                Label("\(harvest.lastFailures.count) failures", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(harvest.lastFailures.isEmpty ? Color.secondary : Color.orange)
            }
            .font(.caption)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { queueButtons; Spacer(minLength: 0); failureButtons }
                VStack(alignment: .leading, spacing: 8) { HStack { queueButtons }; HStack { failureButtons } }
            }
        }
        .padding(14)
    }

    @ViewBuilder private var queueButtons: some View {
        Button("Clean Queue") { harvest.cleanQueue() }
            .help("Remove duplicates, invalid links, already imported and earlier failures")
            .disabled(harvest.queuedURLCount == 0 && harvest.queueSnapshot.invalidCount == 0)
        Button("Undo Queue Change") { harvest.undoQueueChange() }
            .disabled(!harvest.canUndoQueueChange)
        Button("Copy Queued Links") { harvest.copyQueueURLs() }
            .disabled(harvest.queuedURLCount == 0)
    }

    @ViewBuilder private var failureButtons: some View {
        Button("Copy Failed Links") { harvest.copyFailedURLs() }
            .disabled(harvest.lastFailures.isEmpty)
        Button("Copy Diagnostics") { harvest.copyFailureDiagnostics() }
            .help("Copies URLs and parser reasons only — no page contents or personal data")
            .disabled(harvest.lastFailures.isEmpty)
        Button("Retry Failures") { harvest.retryFailures() }
            .buttonStyle(.borderedProminent)
            .disabled(harvest.lastFailures.isEmpty || harvest.isImporting)
    }

    private func copyVisible() {
        let formatter = ISO8601DateFormatter()
        let text = entries.map { entry in
            "\(formatter.string(from: entry.timestamp)) [\(entry.level.rawValue)] \(entry.message)"
                + (entry.url.map { " — \($0)" } ?? "")
        }.joined(separator: "\n")
        MacRecipeClipboard.copy(text)
    }

    private func icon(_ level: CrawlLogEntry.Level) -> String {
        switch level {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func tint(_ level: CrawlLogEntry.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return MacTheme.green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
