// MacBrowseView.swift — the Browse section, redesigned (Build 94).
//
// Build 93 grew controls faster than layout: labels sat beside segmented pickers and
// overlapped at narrow widths, sections were separated by bare dividers, and the right
// pane was mostly air. The redesign puts every control group in a card, stacks labels
// ABOVE their controls so nothing can overlap at any width, gives the activity pane a
// real progress card with a bar, and shows a proper empty state instead of vacancy.

import AppKit
import SwiftUI

struct MacBrowseView: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacNavigation.self) private var navigation

    @State private var sourceSearch = ""
    @State private var selectedSourceIDs: Set<String> = []
    @State private var showSourcePicker = false
    @State private var showURLEditor = false
    @State private var showBrowser = false
    @State private var browserAddress = ""

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

    private func isCustom(_ s: SourceProfile) -> Bool {
        s.id.hasPrefix("custom-") || s.id.hasPrefix("imported-")
    }

    private func isFeed(_ s: SourceProfile) -> Bool {
        s.discoveryMode == .feedOnly || s.tags.contains("Community")
    }

    private var americanSources: [SourceProfile] {
        filteredSources.filter { $0.tags.contains("American") && !isCustom($0) && !isFeed($0) }
    }

    private var worldwideSources: [SourceProfile] {
        filteredSources.filter { !$0.tags.contains("American") && !isCustom($0) && !isFeed($0) }
    }

    private var feedSources: [SourceProfile] {
        filteredSources.filter { isFeed($0) && !isCustom($0) }
    }

    private var customSources: [SourceProfile] {
        filteredSources.filter { isCustom($0) }
    }

    private var selectedSources: [SourceProfile] {
        browsableSources.filter { selectedSourceIDs.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if harvest.isPaused { pauseBanner }
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        sourcesCard
                        crawlerCard
                        verificationCard
                        queueCard
                        imagesCard
                        cloudCard
                    }
                    .padding(14)
                }
                .frame(width: 396)

                Divider()

                activityPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    browserAddress = ""
                    showBrowser = true
                } label: {
                    Label("Open browser", systemImage: "safari")
                }
                .help("Browse any site in-app and import the page you're looking at")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    harvest.togglePause()
                } label: {
                    Label(harvest.isPaused ? "Resume" : "Pause",
                          systemImage: harvest.isPaused ? "play.fill" : "pause.fill")
                }
                .help("Pause or resume every download — browsing, imports and images")
            }
        }
        .sheet(isPresented: $showBrowser) {
            MacBrowserPanel(address: browserAddress)
        }
    }

    // MARK: - Pause banner

    private var pauseBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            Text("Paused — in-flight requests finish, nothing new starts.")
                .font(.callout)
            Spacer(minLength: 0)
            Button("Resume") { harvest.togglePause() }
                .tint(MacTheme.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.10))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Sources card

    @ViewBuilder
    private var sourcesCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "Sources", systemImage: "globe",
                footnote: "\(browsableSources.count) sites") {
            VStack(alignment: .leading, spacing: 8) {
                // Dropdown (multi-select checklist)
                Button {
                    showSourcePicker.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Text(selectionLabel)
                            .font(.callout)
                            .foregroundStyle(browsableSources.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(browsableSources.isEmpty)
                .popover(isPresented: $showSourcePicker, arrowEdge: .bottom) {
                    SourceMultiPicker(
                        search: $sourceSearch,
                        selected: $selectedSourceIDs,
                        american: americanSources,
                        worldwide: worldwideSources,
                        feeds: feedSources,
                        custom: customSources,
                        recent: harvest.recentSources
                    )
                }

                if browsableSources.isEmpty {
                    HStack(spacing: 6) {
                        Text("No sources loaded.").font(.caption).foregroundStyle(.red)
                        Button("Restore built-in catalog") { harvest.repairSources() }
                            .font(.caption)
                    }
                }

                // Actions
                HStack(spacing: 6) {
                    // Build 95: browsing queues; importing is the explicit second step
                    // (unless auto-verify & approve is switched on — then the primary
                    // button says exactly what it will do).
                    let autoImports = harvest.settings.autoImportVerified
                    if selectedSources.count == 1, let source = selectedSources.first {
                        Button(autoImports ? "Browse & Import" : "Browse") {
                            harvest.discover(source)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isDiscovering)
                        if autoImports {
                            Button("Queue only") { harvest.discoverToQueue(source) }
                                .disabled(harvest.isDiscovering)
                        }
                    } else if selectedSources.count > 1 {
                        Button(autoImports
                               ? "Browse & import \(selectedSources.count)"
                               : "Browse \(selectedSources.count) sources") {
                            harvest.browseSources(withIDs: selectedSources.map(\.id),
                                                  queueOnly: !autoImports)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(harvest.isDiscovering)
                    } else {
                        Button("Next in rotation") { harvest.browseNextSource() }
                            .buttonStyle(.borderedProminent)
                            .disabled(harvest.isDiscovering || browsableSources.isEmpty)
                        Button("Auto-rotate \(max(1, harvest.settings.autoRotateSourceCount))") {
                            harvest.autoRotate()
                        }
                        .disabled(harvest.isDiscovering || browsableSources.isEmpty)
                    }
                    Spacer(minLength: 0)
                    if harvest.isDiscovering {
                        Button("Stop") { harvest.cancelDiscovery() }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                }
                .font(.callout)

                if !harvest.sourceRotationQueue.isEmpty || harvest.autoRotateRemaining > 0 {
                    let remaining = harvest.sourceRotationQueue.count + harvest.autoRotateRemaining
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2).foregroundStyle(MacTheme.gold)
                        Text("\(remaining) more source\(remaining == 1 ? "" : "s") after this one")
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

                Divider()

                // List maintenance
                HStack(spacing: 10) {
                    Button {
                        harvest.importSourcesFromFile()
                    } label: {
                        Label("Update from file", systemImage: "square.and.arrow.down")
                    }
                    .help("JSON, or one URL/domain per line (\"Name | url\" works too)")
                    Button {
                        harvest.exportSourcesToFile()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Spacer(minLength: 0)
                    Button {
                        harvest.repairSources()
                    } label: {
                        Label("Restore", systemImage: "arrow.counterclockwise")
                    }
                    .help("Restore the built-in catalog (keeps custom and imported sources)")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private var selectionLabel: String {
        if browsableSources.isEmpty { return "No sources loaded" }
        let picked = selectedSources
        switch picked.count {
        case 0:  return "Choose sources…"
        case 1:  return picked[0].name
        default: return "\(picked[0].name) + \(picked.count - 1) more"
        }
    }

    // MARK: - Crawler card

    @ViewBuilder
    private var crawlerCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "Crawler", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 10) {
                // Labels sit ABOVE their controls — nothing to overlap at any width.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Method").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Picker("", selection: $harvest.settings.preferredCrawlMethod) {
                        ForEach(CrawlMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    Text(harvest.settings.preferredCrawlMethod.explanation)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: harvest.settings.preferredCrawlMethod) {
                    harvest.scheduleSettingsSave()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Picker("", selection: $harvest.settings.crawlAggressiveness) {
                        ForEach(CrawlAggressiveness.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    Text(harvest.settings.crawlAggressiveness.explanation)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: harvest.settings.crawlAggressiveness) {
                    harvest.scheduleSettingsSave()
                }

                Toggle("Use the built-in browser when a site blocks direct fetches",
                       isOn: $harvest.settings.useWebKitFallback)
                    .toggleStyle(.checkbox).font(.caption)
                    .onChange(of: harvest.settings.useWebKitFallback) {
                        harvest.scheduleSettingsSave()
                    }

                Stepper(value: $harvest.settings.importSpacingSeconds, in: 0...30) {
                    Text(harvest.settings.importSpacingSeconds == 0
                         ? "No extra pause between imports"
                         : "Pause \(harvest.settings.importSpacingSeconds) s between imports")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .onChange(of: harvest.settings.importSpacingSeconds) {
                    harvest.scheduleSettingsSave()
                }

                Divider()

                HStack(spacing: 10) {
                    Menu {
                        Button("Safari (recommended)") { setUserAgent(AppSettings.safariUserAgent) }
                        Button("Chrome") { setUserAgent(AppSettings.chromeUserAgent) }
                        Button("Honest bot") { setUserAgent(AppSettings.honestUserAgent) }
                    } label: {
                        Label("User agent: \(userAgentLabel)", systemImage: "person.crop.rectangle")
                    }
                    .menuStyle(.borderlessButton)
                    .font(.caption)
                    .help("How the crawler identifies itself to sites")
                    Spacer(minLength: 0)
                    Button {
                        harvest.resetRateLimits()
                    } label: {
                        Label("Clear pauses", systemImage: "hare")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Clear every rate-limit pause and daily counter")
                }
            }
        }
    }

    private var userAgentLabel: String {
        switch harvest.settings.userAgent {
        case AppSettings.safariUserAgent: return "Safari"
        case AppSettings.chromeUserAgent: return "Chrome"
        case AppSettings.honestUserAgent: return "Honest bot"
        default: return "Custom"
        }
    }

    private func setUserAgent(_ value: String) {
        harvest.settings.userAgent = value
        harvest.scheduleSettingsSave()
    }

    // MARK: - Verification card

    @ViewBuilder
    private var verificationCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "Verification", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Toggle("Auto-verify & approve at", isOn: $harvest.settings.autoImportVerified)
                        .toggleStyle(.checkbox).font(.caption)
                    if harvest.settings.autoImportVerified {
                        Slider(value: $harvest.settings.autoApproveConfidence, in: 0.50...1.0, step: 0.05)
                            .frame(width: 80)
                        Text("\(Int(harvest.settings.autoApproveConfidence * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 32, alignment: .trailing)
                    }
                    Spacer(minLength: 0)
                }
                Toggle("Verify queued URLs before importing", isOn: $harvest.settings.verifyBeforeImport)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle("Only auto-approve recipes that meet Stocked standards",
                       isOn: $harvest.settings.requireStandardsForAutoApprove)
                    .toggleStyle(.checkbox).font(.caption)
                    .help("Title, 3+ ingredients, 2+ steps, image on disk, source URL, honest attribution")

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
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .onChange(of: harvest.settings.autoImportVerified) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.autoApproveConfidence) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.verifyBeforeImport) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.requireStandardsForAutoApprove) { harvest.scheduleSettingsSave() }
    }

    // MARK: - Queue card

    @ViewBuilder
    private var queueCard: some View {
        @Bindable var harvest = harvest
        let queued = harvest.queuedURLCount
        MacCard(title: "Queue", systemImage: "tray.full",
                footnote: queued > 0 ? "\(queued) URLs" : nil) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Button("Paste URLs") { harvest.pasteURLsFromClipboard() }
                        .font(.caption)
                    Button(showURLEditor ? "Hide editor" : "Edit") { showURLEditor.toggle() }
                        .font(.caption)
                    Spacer(minLength: 0)
                    if queued > 0 {
                        Button("Clear") { harvest.importText = "" }
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)

                if showURLEditor {
                    TextEditor(text: $harvest.importText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 70)
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
                    }
                }

                if queued == 0 && !harvest.isImporting && !showURLEditor {
                    Text("Browse a source or paste URLs to fill the queue.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Images card

    @ViewBuilder
    private var imagesCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "Images", systemImage: "photo") {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Require an image before a recipe reaches the kitchen",
                       isOn: $harvest.settings.requireImageForImport)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle("Retry failed image downloads after each run",
                       isOn: $harvest.settings.autoFetchMissingImages)
                    .toggleStyle(.checkbox).font(.caption)
                let missing = harvest.imagelessCount
                HStack {
                    Button(missing > 0 ? "Fetch \(missing) missing image\(missing == 1 ? "" : "s")" : "No images missing") {
                        harvest.fetchMissingImages()
                    }
                    .font(.caption)
                    .disabled(missing == 0 || harvest.isImporting)
                    Spacer(minLength: 0)
                }
            }
        }
        .onChange(of: harvest.settings.requireImageForImport) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.autoFetchMissingImages) { harvest.scheduleSettingsSave() }
    }

    // MARK: - Cloud card

    @ViewBuilder
    private var cloudCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "Cloud cache", systemImage: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 7) {
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
        }
        .onChange(of: harvest.settings.cloudSyncEnabled) { harvest.scheduleSettingsSave() }
    }

    // MARK: - Right pane

    private var isIdle: Bool {
        !harvest.isDiscovering && !harvest.isImporting && !harvest.isBulkVerifying
    }

    @ViewBuilder
    private var activityPane: some View {
        if isIdle, harvest.recipes.isEmpty, harvest.sessionHistory.isEmpty, harvest.discoveryReport == nil {
            MacEmpty(
                title: "Ready to browse",
                message: "Pick a source on the left — or several — and press Browse & Import. Found recipes land in Harvest for review.",
                systemImage: "globe"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statsRow

                    if harvest.isDiscovering { browsingCard }

                    if let failure = harvest.discoveryFailure {
                        MacCard(title: "Browse failed", systemImage: "exclamationmark.triangle") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(failure).font(.callout).foregroundStyle(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Button("Retry") { harvest.clearPauseAndRetry() }
                                    Button("Dismiss") { harvest.discoveryFailure = nil }
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if let report = harvest.discoveryReport, !harvest.isDiscovering {
                        MacCard(title: "Last session — \(report.sourceName)", systemImage: "doc.text") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(report.summary).font(.callout)
                                if let note = report.notes.first {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    Button("Queue verified links") { harvest.queue(report.confirmed) }
                                        .disabled(report.confirmed.isEmpty)
                                    if !report.unverified.isEmpty {
                                        Button("Finish \(report.unverified.count) unchecked") {
                                            harvest.verifyRemaining()
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Button("Dismiss") { harvest.discoveryReport = nil }
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    if let summary = harvest.lastImportSummary, !harvest.isImporting {
                        MacCard(title: "Last import", systemImage: "tray.and.arrow.down") {
                            Text(summary).font(.callout)
                        }
                    }

                    if !harvest.lastFailures.isEmpty { failuresCard }

                    if !harvest.sessionHistory.isEmpty { historyCard }

                    activityCard
                }
                .padding(16)
            }
        }
    }

    private var statsRow: some View {
        let dashboard = harvest.dashboard
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 132))], spacing: 10) {
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

    private var browsingCard: some View {
        MacCard(title: "Browsing", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(harvest.discoveryProgress.phase).font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Button("Stop") { harvest.cancelDiscovery() }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                }
                if let url = harvest.discoveryProgress.currentURL {
                    Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                let fetched = harvest.discoveryProgress.pagesFetched
                let queuedPages = harvest.discoveryProgress.queued
                let total = max(1, fetched + queuedPages)
                ProgressView(value: Double(min(fetched, total)), total: Double(total))
                    .progressViewStyle(.linear)
                HStack(spacing: 12) {
                    Label("\(fetched) pages read", systemImage: "doc.plaintext").font(.caption)
                    Label("\(queuedPages) queued", systemImage: "tray").font(.caption)
                    Label("\(harvest.discoveryProgress.confirmed) recipes found", systemImage: "fork.knife")
                        .font(.caption).foregroundStyle(MacTheme.green)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var failuresCard: some View {
        MacCard(title: "Import failures", systemImage: "exclamationmark.triangle",
                footnote: "\(harvest.lastFailures.count)") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(harvest.lastFailures.suffix(10)) { failure in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(string: failure.url)?.lastPathComponent.nilIfBlank ?? failure.url)
                                .font(.caption.weight(.medium)).lineLimit(1)
                            Text(failure.reason)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Button("Open") {
                            browserAddress = failure.url
                            showBrowser = true
                        }
                        .buttonStyle(.borderless).font(.caption)
                        .help("Open in the built-in browser and import by hand")
                    }
                }
                if harvest.lastFailures.count > 10 {
                    Text("…and \(harvest.lastFailures.count - 10) more.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Retry all") { harvest.retryFailures() }
                        .disabled(harvest.isImporting)
                    Button("Clear") { harvest.clearFailures() }
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
    }

    private var historyCard: some View {
        MacCard(title: "Session history", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(harvest.sessionHistory.prefix(8).enumerated()), id: \.offset) { _, report in
                    HStack(spacing: 8) {
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

    private var activityCard: some View {
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

    private func logTint(_ level: CrawlLogEntry.Level) -> Color {
        switch level {
        case .info:    return .secondary
        case .success: return MacTheme.green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

// MARK: - Multi-select source picker

/// The checklist behind the sources dropdown: search, group headers with select-all,
/// health dots, and a running count. Selection lives in the parent so the action
/// buttons can follow it.
private struct SourceMultiPicker: View {
    @Binding var search: String
    @Binding var selected: Set<String>
    let american: [SourceProfile]
    let worldwide: [SourceProfile]
    let feeds: [SourceProfile]
    let custom: [SourceProfile]
    let recent: [SourceProfile]

    private var visibleIDs: [String] {
        (american + worldwide + feeds + custom).map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                TextField("Filter by name, tag or domain…", text: $search)
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
                    group("American — Top 50", american)
                    group("Worldwide — Top 50", worldwide)
                    if !feeds.isEmpty {
                        group("Communities & feeds", feeds)
                    }
                    if !custom.isEmpty {
                        group("Custom & imported", custom)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(width: 330, height: 380)

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
        case .limited, .paused: return Circle().fill(Color.orange).frame(width: 6, height: 6)
        case .healthy: color = MacTheme.green
        case .blocked: color = .red
        case .unknown: color = .secondary
        }
        return Circle().fill(color).frame(width: 6, height: 6)
    }
}
