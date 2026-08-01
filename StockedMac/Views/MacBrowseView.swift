// MacBrowseView.swift — the Browse section (Build 91).
//
// Everything about getting recipes INTO the app now lives here, in the sidebar under
// Household: the source catalog (top 50 American sites + top 50 worldwide), the browse
// controls, the import queue, verification, image recovery, the Worker cloud cache and
// the session history. Harvest keeps what it was always best at — reviewing what came in.
//
// Layout: controls on the left, activity on the right, the same two-pane shape as
// Harvest so the two sections feel like halves of one pipeline.

import AppKit
import SwiftUI

struct MacBrowseView: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacNavigation.self) private var navigation

    @State private var sourceSearch = ""
    @State private var pickedSourceID: String? = nil
    @State private var showURLEditor = false

    // MARK: - Source grouping

    private var browsableSources: [SourceProfile] {
        harvest.sources.filter { $0.enabled && $0.discoveryMode.supportsDiscovery }
    }

    private var filteredSources: [SourceProfile] {
        let q = sourceSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return browsableSources }
        return browsableSources.filter {
            $0.name.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
                || $0.domains.contains { $0.lowercased().contains(q) }
        }
    }

    private var americanSources: [SourceProfile] {
        filteredSources.filter { $0.tags.contains("American") && !$0.id.hasPrefix("custom-") }
    }

    private var worldwideSources: [SourceProfile] {
        filteredSources.filter { !$0.tags.contains("American") && !$0.id.hasPrefix("custom-") }
    }

    private var customSources: [SourceProfile] {
        filteredSources.filter { $0.id.hasPrefix("custom-") }
    }

    private var pickedSource: SourceProfile? {
        pickedSourceID.flatMap { id in browsableSources.first { $0.id == id } }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pauseBar
                    Divider()
                    sourcePanel
                    Divider()
                    verificationPanel
                    Divider()
                    queuePanel
                    Divider()
                    imagePanel
                    Divider()
                    cloudPanel
                }
            }
            .frame(minWidth: 320, maxWidth: 400)

            Divider()

            activityPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Pause bar

    private var pauseBar: some View {
        HStack(spacing: 8) {
            Image(systemName: harvest.isPaused ? "pause.circle.fill" : "globe")
                .foregroundStyle(harvest.isPaused ? .orange : .secondary)
            Text(harvest.isPaused ? "Paused" : "Browse & import")
                .font(.callout.weight(.medium))
            Spacer(minLength: 0)
            Button(harvest.isPaused ? "Resume" : "Pause all") {
                harvest.togglePause()
            }
            .font(.caption)
            .tint(harvest.isPaused ? MacTheme.green : nil)
            .help("Pause or resume every download — browsing, imports and images")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(harvest.isPaused ? Color.orange.opacity(0.08) : Color.clear)
    }

    // MARK: - Sources

    @ViewBuilder
    private var sourcePanel: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Source").font(.caption.weight(.medium))
                Spacer(minLength: 0)
                Text("\(browsableSources.count) sites")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Search
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                TextField("Filter by name, tag or domain…", text: $sourceSearch)
                    .textFieldStyle(.plain).font(.callout)
                if !sourceSearch.isEmpty {
                    Button { sourceSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption2)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }

            // The dropdown, grouped: recents first, then the two halves of the catalog.
            if browsableSources.isEmpty {
                Text("No sources loaded — Tools ▸ Restore catalog, or restart the app.")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Picker("", selection: $pickedSourceID) {
                    Text("Select a site…").tag(String?.none)
                    if !harvest.recentSources.isEmpty && sourceSearch.isEmpty {
                        Section("Recent") {
                            ForEach(harvest.recentSources) { s in
                                Text(sourceLabel(s)).tag(String?.some(s.id))
                            }
                        }
                    }
                    Section("American — Top 50") {
                        ForEach(americanSources) { s in
                            Text(sourceLabel(s)).tag(String?.some(s.id))
                        }
                    }
                    Section("Worldwide — Top 50") {
                        ForEach(worldwideSources) { s in
                            Text(sourceLabel(s)).tag(String?.some(s.id))
                        }
                    }
                    if !customSources.isEmpty {
                        Section("Custom") {
                            ForEach(customSources) { s in
                                Text(sourceLabel(s)).tag(String?.some(s.id))
                            }
                        }
                    }
                }
                .labelsHidden()
                .disabled(harvest.isDiscovering)
            }

            if let source = pickedSource {
                HStack(spacing: 5) {
                    healthDot(source.health)
                    Text(source.domains.first ?? source.baseURL)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    ForEach(source.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            // Actions
            HStack(spacing: 6) {
                if let source = pickedSource {
                    Button("Browse & Import") { harvest.discover(source) }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isDiscovering)
                    Button("Queue only") { harvest.discoverToQueue(source) }
                        .disabled(harvest.isDiscovering)
                } else {
                    Button("Next in rotation") { harvest.browseNextSource() }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isDiscovering)
                    Button("Auto-rotate \(max(1, harvest.settings.autoRotateSourceCount))") {
                        harvest.autoRotate()
                    }
                    .disabled(harvest.isDiscovering)
                    .help("Browse several sources back to back; set the count below")
                }
                Spacer(minLength: 0)
                if harvest.isDiscovering {
                    ProgressView().scaleEffect(0.45)
                    Button("Stop") { harvest.cancelDiscovery() }
                        .buttonStyle(.borderless).foregroundStyle(.red)
                }
            }
            .font(.callout)

            if harvest.autoRotateRemaining > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2).foregroundStyle(MacTheme.gold)
                    Text("\(harvest.autoRotateRemaining) more source\(harvest.autoRotateRemaining == 1 ? "" : "s") after this one")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Stop after this") { harvest.cancelAutoRotate() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }

            Stepper(value: $harvest.settings.autoRotateSourceCount, in: 1...10) {
                Text("Auto-rotate visits \(harvest.settings.autoRotateSourceCount) source\(harvest.settings.autoRotateSourceCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: harvest.settings.autoRotateSourceCount) {
                harvest.scheduleSettingsSave()
            }

            if harvest.isDiscovering {
                Text(harvest.discoveryProgress.phase)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            if let failure = harvest.discoveryFailure {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2).foregroundStyle(.red)
                    Text(failure).font(.caption).foregroundStyle(.red).lineLimit(3)
                    Spacer(minLength: 0)
                    Button("Retry") { harvest.clearPauseAndRetry() }
                        .buttonStyle(.borderless).font(.caption)
                    Button("✕") { harvest.discoveryFailure = nil }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Verification

    @ViewBuilder
    private var verificationPanel: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification").font(.caption.weight(.medium))

            HStack(spacing: 8) {
                Toggle("Auto-verify & approve at", isOn: $harvest.settings.autoImportVerified)
                    .toggleStyle(.checkbox).font(.caption)
                if harvest.settings.autoImportVerified {
                    Slider(value: $harvest.settings.autoApproveConfidence, in: 0.50...1.0, step: 0.05)
                        .frame(width: 70)
                    Text("\(Int(harvest.settings.autoApproveConfidence * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
                Spacer(minLength: 0)
            }

            Toggle("Verify queued URLs before importing", isOn: $harvest.settings.verifyBeforeImport)
                .toggleStyle(.checkbox).font(.caption)

            HStack(spacing: 6) {
                if harvest.isBulkVerifying {
                    ProgressView().scaleEffect(0.45)
                    Text("\(harvest.bulkVerifyProgress.completed)/\(harvest.bulkVerifyProgress.total)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Stop") { harvest.cancelBulkVerify() }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                } else {
                    Button("Bulk verify queue") { harvest.bulkVerifyQueue() }
                        .font(.caption)
                        .disabled(harvest.queuedURLCount == 0 || harvest.isImporting)
                        .help("Check every queued URL is a recipe page; remove the ones that aren't")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: harvest.settings.autoImportVerified) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.autoApproveConfidence) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.verifyBeforeImport) { harvest.scheduleSettingsSave() }
    }

    // MARK: - Queue

    @ViewBuilder
    private var queuePanel: some View {
        @Bindable var harvest = harvest
        let queued = harvest.queuedURLCount
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Queue").font(.caption.weight(.medium))
                if queued > 0 {
                    Text("· \(queued) URL\(queued == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(MacTheme.gold)
                }
                Spacer(minLength: 0)
                Button("Paste") { harvest.pasteURLsFromClipboard() }
                    .buttonStyle(.borderless).font(.caption)
                if queued > 0 {
                    Button("Clear") { harvest.importText = "" }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(.red)
                }
                Button { showURLEditor.toggle() } label: {
                    Image(systemName: "square.and.pencil").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Paste / edit URLs directly")
            }

            if showURLEditor {
                TextEditor(text: $harvest.importText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            if queued > 0 || harvest.isImporting {
                HStack(spacing: 6) {
                    Button("Import \(queued) URL\(queued == 1 ? "" : "s")") { harvest.importURLs() }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isImporting || harvest.isBulkVerifying || queued == 0)
                    if harvest.isImporting {
                        ProgressView().scaleEffect(0.45)
                        Text("\(harvest.importProgress.completed)/\(harvest.importProgress.total)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button("Stop") { harvest.cancelImport() }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
            }

            if let report = harvest.discoveryReport, !report.unverified.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2).foregroundStyle(MacTheme.gold)
                    Text("\(report.unverified.count) more from \(report.sourceName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Resume") { harvest.verifyRemaining() }
                        .buttonStyle(.borderless).font(.caption)
                    Button("✕") { harvest.discoveryReport = nil }
                        .buttonStyle(.borderless).font(.caption).foregroundStyle(.red)
                }
            }

            if queued == 0 && !harvest.isImporting && !showURLEditor {
                Text("Browse a source or paste URLs to fill the queue.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Images

    @ViewBuilder
    private var imagePanel: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 6) {
            Text("Images").font(.caption.weight(.medium))

            Toggle("Require an image before a recipe reaches the kitchen",
                   isOn: $harvest.settings.requireImageForImport)
                .toggleStyle(.checkbox).font(.caption)
            Toggle("Retry failed image downloads after each run",
                   isOn: $harvest.settings.autoFetchMissingImages)
                .toggleStyle(.checkbox).font(.caption)

            HStack(spacing: 6) {
                let missing = harvest.imagelessCount
                Button(missing > 0 ? "Fetch \(missing) missing image\(missing == 1 ? "" : "s")" : "No images missing") {
                    harvest.fetchMissingImages()
                }
                .font(.caption)
                .disabled(missing == 0 || harvest.isImporting)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: harvest.settings.requireImageForImport) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.autoFetchMissingImages) { harvest.scheduleSettingsSave() }
    }

    // MARK: - Cloud cache

    @ViewBuilder
    private var cloudPanel: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 6) {
            Text("Cloud cache").font(.caption.weight(.medium))

            Toggle("Sync approved recipes to the Worker automatically",
                   isOn: $harvest.settings.cloudSyncEnabled)
                .toggleStyle(.checkbox).font(.caption)

            HStack(spacing: 6) {
                if harvest.isCloudSyncing {
                    ProgressView().scaleEffect(0.45)
                    Text("Syncing…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Sync now") { harvest.syncApprovedToCloud() }
                        .font(.caption)
                        .disabled(harvest.approvedRecipes.isEmpty)
                }
                Spacer(minLength: 0)
            }

            if let status = harvest.cloudSyncStatus {
                Text(status)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: harvest.settings.cloudSyncEnabled) { harvest.scheduleSettingsSave() }
    }

    // MARK: - Right pane: activity

    private var activityPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statsRow

                if harvest.isDiscovering {
                    MacCard(title: "Browsing", systemImage: "globe") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(harvest.discoveryProgress.phase).font(.callout)
                            if let url = harvest.discoveryProgress.currentURL {
                                Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text("\(harvest.discoveryProgress.pagesFetched) pages · \(harvest.discoveryProgress.confirmed) found")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if let report = harvest.discoveryReport {
                    MacCard(title: "Last session — \(report.sourceName)", systemImage: "doc.text") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.summary).font(.callout)
                            HStack(spacing: 8) {
                                Button("Queue verified links") { harvest.queue(report.confirmed) }
                                    .disabled(report.confirmed.isEmpty)
                                if !report.unverified.isEmpty {
                                    Button("Finish \(report.unverified.count) unchecked") {
                                        harvest.verifyRemaining()
                                    }
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                if !harvest.sessionHistory.isEmpty {
                    MacCard(title: "Session history", systemImage: "clock.arrow.circlepath") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(harvest.sessionHistory.prefix(8).enumerated()), id: \.offset) { _, report in
                                HStack(spacing: 6) {
                                    Text(report.sourceName).font(.caption.weight(.medium)).lineLimit(1)
                                    Text(report.finishedAt, style: .relative)
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text("· \(report.confirmed.count) verified")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                    Button("Restore") { harvest.restoreSession(report) }
                                        .buttonStyle(.borderless).font(.caption)
                                }
                            }
                        }
                    }
                }

                MacCard(title: "Activity", systemImage: "list.bullet.rectangle") {
                    if harvest.logs.isEmpty {
                        Text("Nothing yet. Browse a source to get started.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(harvest.logs.prefix(14)) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Circle()
                                        .fill(logTint(entry.level))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 4)
                                    Text(entry.message)
                                        .font(.caption)
                                        .foregroundStyle(entry.level == .error ? .red : .secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var statsRow: some View {
        let dashboard = harvest.dashboard
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
            stat("Imported", "\(dashboard.recipes)", "tray.and.arrow.down")
            stat("Awaiting review", "\(dashboard.needsReview)", "eye")
            stat("Approved", "\(dashboard.approved)", "checkmark.circle")
            stat("Missing images", "\(harvest.imagelessCount)", "photo.badge.exclamationmark")
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        MacCard(title: title, systemImage: icon) {
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func sourceLabel(_ source: SourceProfile) -> String {
        switch source.health {
        case .healthy: return "● \(source.name)"
        case .blocked: return "✕ \(source.name)"
        case .paused:  return "⏸ \(source.name)"
        default:       return source.name
        }
    }

    private func healthDot(_ health: SourceHealth) -> some View {
        let color: Color
        switch health {
        case .healthy: color = MacTheme.green
        case .limited: color = .orange
        case .paused:  color = .orange
        case .blocked: color = .red
        case .unknown: color = .secondary
        }
        return Circle().fill(color).frame(width: 6, height: 6)
    }

    private func logTint(_ level: CrawlLogEntry.Level) -> Color {
        switch level {
        case .info:    return .secondary
        case .success: return MacTheme.green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
