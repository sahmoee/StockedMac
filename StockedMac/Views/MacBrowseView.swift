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
    @State private var selectedSourceIDs: Set<String> = []
    @State private var showSourcePicker = false
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

    private var selectedSources: [SourceProfile] {
        browsableSources.filter { selectedSourceIDs.contains($0.id) }
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
            HStack(spacing: 8) {
                Text("Sources").font(.caption.weight(.medium))
                Spacer(minLength: 0)
                Text("\(browsableSources.count) sites")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    harvest.importSourcesFromFile()
                } label: {
                    Image(systemName: "square.and.arrow.down").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Update the source list from a file — JSON, or one URL/domain per line (\"Name | url\" works too)")
                Button {
                    harvest.exportSourcesToFile()
                } label: {
                    Image(systemName: "square.and.arrow.up").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Export the source list as JSON for editing")
                Button {
                    harvest.repairSources()
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Restore the built-in catalog (keeps custom and imported sources)")
            }

            // The dropdown: a checklist popover, so several sites can be picked at once.
            Button {
                showSourcePicker.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
                    Text(selectionLabel)
                        .font(.callout)
                        .foregroundStyle(browsableSources.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(browsableSources.isEmpty)
            .popover(isPresented: $showSourcePicker, arrowEdge: .bottom) {
                SourceMultiPicker(
                    search: $sourceSearch,
                    selected: $selectedSourceIDs,
                    american: americanSources,
                    worldwide: worldwideSources,
                    custom: customSources,
                    recent: harvest.recentSources
                )
            }

            if browsableSources.isEmpty {
                HStack(spacing: 6) {
                    Text("No sources loaded.").font(.caption).foregroundStyle(.red)
                    Button("Restore built-in catalog") { harvest.repairSources() }
                        .font(.caption)
                    Spacer(minLength: 0)
                }
            }

            // Actions follow the selection: one source, several, or none.
            HStack(spacing: 6) {
                if selectedSources.count == 1, let source = selectedSources.first {
                    Button("Browse & Import") { harvest.discover(source) }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isDiscovering)
                    Button("Queue only") { harvest.discoverToQueue(source) }
                        .disabled(harvest.isDiscovering)
                } else if selectedSources.count > 1 {
                    Button("Browse \(selectedSources.count) sources") {
                        harvest.browseSources(withIDs: selectedSources.map(\.id))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(harvest.isDiscovering)
                    Button("Queue from \(selectedSources.count)") {
                        harvest.browseSources(withIDs: selectedSources.map(\.id), queueOnly: true)
                    }
                    .disabled(harvest.isDiscovering)
                } else {
                    Button("Next in rotation") { harvest.browseNextSource() }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isDiscovering || browsableSources.isEmpty)
                    Button("Auto-rotate \(max(1, harvest.settings.autoRotateSourceCount))") {
                        harvest.autoRotate()
                    }
                    .disabled(harvest.isDiscovering || browsableSources.isEmpty)
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

            if !harvest.sourceRotationQueue.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "list.number")
                        .font(.caption2).foregroundStyle(MacTheme.gold)
                    Text("\(harvest.sourceRotationQueue.count) selected source\(harvest.sourceRotationQueue.count == 1 ? "" : "s") still to visit")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Stop after this") { harvest.cancelAutoRotate() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }

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
                    Button("\u{2715}") { harvest.discoveryFailure = nil }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var selectionLabel: String {
        if browsableSources.isEmpty { return "No sources loaded" }
        let picked = selectedSources
        switch picked.count {
        case 0:  return "Choose sources\u{2026}"
        case 1:  return picked[0].name
        case 2:  return "\(picked[0].name) + 1 more"
        default: return "\(picked[0].name) + \(picked.count - 1) more"
        }
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

// MARK: - Multi-select source picker (Build 92)

/// The checklist behind the sources dropdown: search, group headers with select-all,
/// health dots, and a running count. Selection lives in the parent so the action
/// buttons can follow it.
private struct SourceMultiPicker: View {
    @Binding var search: String
    @Binding var selected: Set<String>
    let american: [SourceProfile]
    let worldwide: [SourceProfile]
    let custom: [SourceProfile]
    let recent: [SourceProfile]

    private var visibleIDs: [String] {
        (american + worldwide + custom).map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                TextField("Filter by name, tag or domain\u{2026}", text: $search)
                    .textFieldStyle(.plain).font(.callout)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption2)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !recent.isEmpty && search.isEmpty {
                        group("Recent", recent)
                    }
                    group("American \u{2014} Top 50", american)
                    group("Worldwide \u{2014} Top 50", worldwide)
                    if !custom.isEmpty {
                        group("Custom & imported", custom)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(width: 320, height: 360)

            Divider()

            HStack(spacing: 8) {
                Text("\(selected.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("All shown") { selected.formUnion(visibleIDs) }
                    .font(.caption)
                Button("None") { selected.removeAll() }
                    .font(.caption)
                    .disabled(selected.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ sources: [SourceProfile]) -> some View {
        if !sources.isEmpty {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(sources.allSatisfy { selected.contains($0.id) } ? "None" : "All") {
                    let ids = sources.map(\.id)
                    if sources.allSatisfy({ selected.contains($0.id) }) {
                        selected.subtract(ids)
                    } else {
                        selected.formUnion(ids)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(sources) { source in
                Button {
                    if selected.contains(source.id) {
                        selected.remove(source.id)
                    } else {
                        selected.insert(source.id)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selected.contains(source.id)
                              ? "checkmark.square.fill" : "square")
                            .font(.callout)
                            .foregroundStyle(selected.contains(source.id) ? MacTheme.gold : .secondary)
                        healthDot(source.health)
                        Text(source.name).font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(source.domains.first ?? "")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
    }

    private func healthDot(_ health: SourceHealth) -> some View {
        let color: Color
        switch health {
        case .healthy: color = MacTheme.green
        case .limited, .paused: color = .orange
        case .blocked: color = .red
        case .unknown: color = .secondary
        }
        return Circle().fill(color).frame(width: 6, height: 6)
    }
}
