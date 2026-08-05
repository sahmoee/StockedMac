// MacBrowseView.swift — Browse, rebuilt (Build 100).
//
// Browse is now the ONE place recipes are found, imported, AND approved. The old
// standalone Harvest section folded in here as a second pane. A segmented switch at the
// top toggles between:
//
//   • Find & Import — the guided flow: pick a source, pick a category, press Start.
//     Discovery, verification, mining-only-when-needed, and import all run from one
//     button. Every power control (crawler engine, speed, user-agent, queue cap, batch
//     sizes, confidence, delivery) lives behind ONE collapsed "Advanced" disclosure, so
//     the default screen is three things and a button, not four numbered cards.
//
//   • Review — the draft library that used to be its own section: search, filter,
//     bulk approve/reject on the left, the full recipe with its Stocked-standards
//     checklist on the right.
//
// Mining is avoided when direct discovery (sitemaps/feeds) already delivers real recipe
// links; when a category page is mined anyway, the recipes it yields LEAD the queue and
// are verified/imported first (HarvestModel.finishImportRun / bulkVerifyQueue).

import AppKit
import SwiftUI

struct MacBrowseView: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacKitchenStore.self) private var store

    private enum Pane: String, CaseIterable, Identifiable {
        case find, categories, review
        var id: String { rawValue }
    }
    @State private var pane: Pane = .find
    @State private var categorySourceFilter: String? = nil

    // ── Find state ───────────────────────────────────────────────────────
    @State private var sourceSearch = ""
    @State private var selectedSourceIDs: Set<String> = []
    @State private var showSourcePicker = false
    @State private var categorySearch = ""
    @State private var showCategoryPicker = false
    @State private var showURLEditor = false
    @State private var manualImportURL = ""
    @State private var showAdvanced = false
    @State private var showQueuePreview = true
    @State private var isQueueDropTargeted = false
    @State private var clipboardURLCount = 0
    @State private var showDiagnostics = false
    @State private var logScope: LogScope = .all
    /// Non-nil shows the in-app browser over the content — "" opens it blank.
    @State private var inlineBrowser: String? = nil

    // ── Review state ─────────────────────────────────────────────────────
    @State private var reviewSearch = ""
    @State private var reviewFilter: ReviewState? = nil
    @State private var onlyImageless = false
    @State private var addStatus: String? = nil

    private enum LogScope: String, CaseIterable, Identifiable {
        case all = "All"
        case problems = "Problems"
        case success = "Success"
        var id: String { rawValue }
    }

    private enum FlowPhase: Int, CaseIterable, Identifiable {
        case discover, review, importRecipes, finish
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .discover: return "Find"
            case .review: return "Queue"
            case .importRecipes: return "Import"
            case .finish: return "Approve"
            }
        }
        var icon: String {
            switch self {
            case .discover: return "sparkle.magnifyingglass"
            case .review: return "tray.full"
            case .importRecipes: return "square.and.arrow.down"
            case .finish: return "checkmark.seal"
            }
        }
    }

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
            paneSwitcher
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inlineBrowser = inlineBrowser == nil ? "" : nil
                } label: {
                    Label(inlineBrowser == nil ? "Open browser" : "Close browser",
                          systemImage: "safari")
                }
                .help("Browse any site right here and import the page you're looking at")
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
        .onAppear {
            restoreSourceSelection()
            refreshClipboardURLCount()
        }
        .onChange(of: selectedSourceIDs) {
            harvest.settings.lastSelectedSourceIDs = Array(selectedSourceIDs).sorted()
            harvest.scheduleSettingsSave()
        }
        .onChange(of: harvest.settings.selectedBrowseCategoryIDs) {
            harvest.scheduleSettingsSave()
            harvest.applyCategoryFilterToCurrentReport()
        }
        .onChange(of: browsableSources.map(\.id)) {
            selectedSourceIDs.formIntersection(Set(browsableSources.map(\.id)))
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            refreshClipboardURLCount()
        }
    }

    // MARK: - Pane switcher

    private var reviewWaiting: Int {
        harvest.recipes.filter { $0.reviewState == .needsReview }.count
    }

    private var paneSwitcher: some View {
        HStack(spacing: 12) {
            Picker("Pane", selection: $pane) {
                Text("Find & Import").tag(Pane.find)
                Text(harvest.readyCategoryCount > 0
                     ? "Categories · \(harvest.readyCategoryCount)" : "Categories").tag(Pane.categories)
                Text(reviewWaiting > 0 ? "Review · \(reviewWaiting)" : "Review").tag(Pane.review)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            Spacer(minLength: 0)
            Text(paneContextSummary)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var paneContextSummary: String {
        if harvest.isDiscovering { return "Finding recipes…" }
        if harvest.isBulkVerifying { return "Verifying the queue…" }
        if harvest.isImporting { return "Importing \(harvest.importProgress.completed)/\(harvest.importProgress.total)…" }
        switch pane {
        case .find:
            let q = harvest.queuedURLCount
            return q > 0 ? "\(q) queued · \(reviewWaiting) to review" : "\(reviewWaiting) to review"
        case .categories:
            return "\(harvest.allCategories.count) categories · \(harvest.readyCategoryCount) ready"
        case .review:
            return "\(harvest.recipes.count) imported · \(harvest.dashboard.approved) approved"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let address = inlineBrowser {
            // The in-app browser takes over the whole content area when open — the page
            // IS the content, exactly where the import buttons already are.
            MacBrowserPanel(address: address, onClose: { inlineBrowser = nil })
                .id(address)
        } else {
            switch pane {
            case .find:       findPane
            case .categories: categoriesPane
            case .review:     reviewPane
            }
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

    private func restoreSourceSelection() {
        guard selectedSourceIDs.isEmpty else { return }
        let valid = Set(browsableSources.map(\.id))
        selectedSourceIDs = Set(harvest.settings.lastSelectedSourceIDs).intersection(valid)
    }

    private func refreshClipboardURLCount() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            clipboardURLCount = 0
            return
        }
        clipboardURLCount = Set(value.matches(#"https?://[^\s"'<>\)\]]+"#, group: 0)).count
        if clipboardURLCount == 0,
           (try? URLSafety.validatedRemoteURL(value.trimmingCharacters(in: .whitespacesAndNewlines))) != nil {
            clipboardURLCount = 1
        }
    }

    // MARK: - FIND PANE

    private var findPane: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    findCard
                    queueCard
                    advancedCard
                }
                .padding(14)
            }
            .frame(width: 388)

            Divider()

            activityPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Step 1 — Find (guided)

    @ViewBuilder
    private var findCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "Find recipes", systemImage: "sparkle.magnifyingglass",
                footnote: "\(browsableSources.count) sites · \(harvest.cachedSourceCount) saved") {
            VStack(alignment: .leading, spacing: 10) {
                flowFieldLabel("Where should Stocked look?", detail: selectionLabel)
                Button {
                    showSourcePicker.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selectedSources.isEmpty ? "globe" : "checkmark.circle.fill")
                            .foregroundStyle(selectedSources.isEmpty ? Color.secondary : MacTheme.green)
                        Text(selectionLabel)
                            .font(.callout)
                            .foregroundStyle(browsableSources.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
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
                        recent: harvest.recentSources,
                        cachedIDs: Set(harvest.sourceCacheSummaries.keys),
                        favoriteIDs: $harvest.settings.favoriteSourceIDs,
                        onFavoritesChanged: harvest.scheduleSettingsSave
                    )
                }

                if browsableSources.isEmpty {
                    HStack(spacing: 6) {
                        Text("No sources loaded.").font(.caption).foregroundStyle(.red)
                        Button("Restore built-in catalog") { harvest.repairSources() }
                            .font(.caption)
                    }
                }

                flowFieldLabel("What kind of recipes?", detail: categorySelectionLabel)
                Button {
                    showCategoryPicker.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: harvest.settings.selectedBrowseCategoryIDs.isEmpty
                              ? "square.grid.2x2" : "checkmark.circle.fill")
                            .foregroundStyle(harvest.settings.selectedBrowseCategoryIDs.isEmpty
                                             ? Color.secondary : MacTheme.green)
                        Text(categorySelectionLabel).font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(RecipeBrowseTaxonomy.all.count) choices")
                            .font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCategoryPicker, arrowEdge: .bottom) {
                    RecipeCategoryPicker(
                        search: $categorySearch,
                        selectedIDs: $harvest.settings.selectedBrowseCategoryIDs
                    )
                }
                if !harvest.settings.selectedBrowseCategoryIDs.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(categorySelectionSummary)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 0)
                        Button("Clear") { harvest.settings.selectedBrowseCategoryIDs.removeAll() }
                            .buttonStyle(.borderless).font(.caption2)
                    }
                }

                Toggle(isOn: $harvest.settings.autopilot) {
                    Text("Autopilot — fully hands-off").font(.callout.weight(.medium))
                }
                .toggleStyle(.switch)
                .onChange(of: harvest.settings.autopilot) { harvest.scheduleSettingsSave() }

                Text(harvest.settings.autopilot
                     ? "One press: Stocked finds, mines + caches categories, imports, and auto-approves qualifying recipes across sources on its own. Sub-standard ones wait in Review."
                     : "Stocked finds recipes and fills the queue, then stops for your review before importing.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                startControls

                discoveryHints

                manualURLImportRow
            }
        }
    }

    /// Build 102: importing a URL directly is always an option, independent of
    /// Find & Import's guided source/category flow. Bypasses discovery entirely —
    /// the URL goes straight into `importDirect`, the same path a confirmed
    /// discovery result uses.
    @ViewBuilder
    private var manualURLImportRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.badge.plus").font(.caption).foregroundStyle(.secondary)
            TextField("Or paste a recipe URL to import it directly…", text: $manualImportURL)
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit { importManualURL() }
            Button("Import") { importManualURL() }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .disabled(manualImportURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || harvest.isImporting)
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func importManualURL() {
        let trimmed = manualImportURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        harvest.importDirect([trimmed])
        manualImportURL = ""
    }

    @ViewBuilder
    private var startControls: some View {
        if harvest.settings.autopilot {
            HStack(spacing: 8) {
                if harvest.isAutopilotRunning {
                    Button {
                        harvest.stopAutopilot()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
                    ProgressView().controlSize(.small)
                    Text(harvest.discoveryProgress.phase)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Button {
                        harvest.startAutopilot(sourceIDs: selectedSources.map(\.id))
                    } label: {
                        Label(autopilotStartLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(browsableSources.isEmpty)
                }
                Spacer(minLength: 0)
            }
            .font(.callout)
        } else {
            manualStartControls
        }
    }

    private var autopilotStartLabel: String {
        switch selectedSources.count {
        case 0:  return "Start — all sources"
        case 1:  return "Start — \(selectedSources[0].name)"
        default: return "Start — \(selectedSources.count) sources"
        }
    }

    @ViewBuilder
    private var manualStartControls: some View {
        HStack(spacing: 8) {
            if selectedSources.count == 1, let source = selectedSources.first {
                Button(harvest.cacheSummary(for: source.id) != nil
                       && harvest.settings.reuseCachedDiscoveryResults
                       ? "Use Saved & Queue" : "Find Recipes") {
                    harvest.discover(source)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(harvest.isDiscovering)
                if harvest.cacheSummary(for: source.id) != nil {
                    Button {
                        harvest.refreshDiscovery(source, addToQueueOnly: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(harvest.isDiscovering)
                    .help("Read the website again and replace its saved results")
                }
            } else if selectedSources.count > 1 {
                Button("Find from \(selectedSources.count) Sources") {
                    harvest.browseSources(withIDs: selectedSources.map(\.id), queueOnly: true)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(harvest.isDiscovering)
            } else {
                Button("Find Next Source") { harvest.browseNextSource() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(harvest.isDiscovering || browsableSources.isEmpty)
            }
            Spacer(minLength: 0)
            if harvest.isDiscovering {
                Button("Stop") { harvest.cancelDiscovery() }
                    .buttonStyle(.borderless).foregroundStyle(.red)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var discoveryHints: some View {
        if selectedSources.count == 1,
           let source = selectedSources.first,
           let summary = harvest.cacheSummary(for: source.id) {
            HStack(spacing: 5) {
                Image(systemName: "externaldrive.fill").font(.caption2).foregroundStyle(MacTheme.green)
                Text("\(summary.resultCount) saved result\(summary.resultCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Text("·").font(.caption).foregroundStyle(.tertiary)
                Text(summary.savedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .help("Stocked can use these links without reading \(source.name) again")
        }
        if !harvest.sourceRotationQueue.isEmpty || harvest.autoRotateRemaining > 0 {
            let remaining = harvest.sourceRotationQueue.count + harvest.autoRotateRemaining
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(MacTheme.gold)
                Text("\(remaining) more source\(remaining == 1 ? "" : "s") after this one")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Stop after this") { harvest.cancelAutoRotate() }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
    }

    private func flowFieldLabel(_ title: String, detail: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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

    private var selectedBrowseCategories: [RecipeBrowseCategory] {
        harvest.settings.selectedBrowseCategoryIDs
            .compactMap { RecipeBrowseTaxonomy.byID[$0] }
            .sorted {
                if $0.group != $1.group {
                    return (RecipeBrowseTaxonomy.groupOrder.firstIndex(of: $0.group) ?? .max)
                        < (RecipeBrowseTaxonomy.groupOrder.firstIndex(of: $1.group) ?? .max)
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var categorySelectionLabel: String {
        switch selectedBrowseCategories.count {
        case 0: return "All categories"
        case 1: return selectedBrowseCategories[0].name
        default: return "\(selectedBrowseCategories.count) categories selected"
        }
    }

    private var categorySelectionSummary: String {
        let names = selectedBrowseCategories.map(\.name)
        return names.prefix(6).joined(separator: " · ")
            + (names.count > 6 ? " · +\(names.count - 6) more" : "")
    }

    // MARK: Steps 2–3 — Review queue & import (compact)

    @ViewBuilder
    private var queueCard: some View {
        @Bindable var harvest = harvest
        let snapshot = harvest.queueSnapshot
        let queued = snapshot.entries.count
        let hasRawQueue = harvest.importText.nilIfBlank != nil
        MacCard(title: "Queue & import", systemImage: "arrow.right.circle",
                footnote: queueFootnote(queued: queued)) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    flowStatusIcon(done: queued > 0 || harvest.isImporting || harvest.lastImportSummary != nil,
                                   active: harvest.isBulkVerifying)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(queueHeadline(queued: queued)).font(.callout.weight(.semibold))
                        Text(queueSubheadline(queued: queued, domains: snapshot.domainCount))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button(clipboardURLCount > 0 ? "Add \(clipboardURLCount) from clipboard" : "Paste URLs") {
                        harvest.pasteURLsFromClipboard()
                        refreshClipboardURLCount()
                    }
                    .font(.caption)
                    Button(showURLEditor ? "Hide editor" : "Edit") { showURLEditor.toggle() }
                        .font(.caption)
                    if hasRawQueue {
                        Button {
                            harvest.cleanQueue()
                        } label: {
                            Label("Clean", systemImage: "sparkles").font(.caption)
                        }
                        .help("Remove duplicates, links already in the library, and links that failed this session")
                    }
                    Spacer(minLength: 0)
                    if hasRawQueue {
                        Menu {
                            Button("Copy all URLs") { harvest.copyQueueURLs() }.disabled(queued == 0)
                            Button("Undo last queue edit") { harvest.undoQueueChange() }
                                .disabled(!harvest.canUndoQueueChange)
                            Divider()
                            Button("Clear queue", role: .destructive) { harvest.clearQueue() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Queue actions")
                    }
                }
                .buttonStyle(.borderless)

                if queued > 0 || snapshot.invalidCount > 0 || snapshot.duplicateCount > 0 {
                    HStack(spacing: 6) {
                        Label("\(snapshot.domainCount) domain\(snapshot.domainCount == 1 ? "" : "s")",
                              systemImage: "network")
                        if snapshot.duplicateCount > 0 {
                            MacPill(text: "\(snapshot.duplicateCount) duplicate\(snapshot.duplicateCount == 1 ? "" : "s")", tint: .orange)
                        }
                        if snapshot.invalidCount > 0 {
                            MacPill(text: "\(snapshot.invalidCount) invalid", tint: .red)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }

                if queued > harvest.settings.queueCap {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                        Text("Over the \(harvest.settings.queueCap)-URL cap — new mined links won't join until it drains. Clean, import, or raise the cap in Advanced.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if showURLEditor {
                    TextEditor(text: $harvest.importText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }

                if queued > 0 {
                    DisclosureGroup(isExpanded: $showQueuePreview) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(snapshot.entries.prefix(6)) { entry in
                                HStack(spacing: 7) {
                                    Image(systemName: "link").font(.caption2).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.pageLabel).font(.caption.weight(.medium)).lineLimit(1)
                                        Text(entry.host).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Button { inlineBrowser = entry.url } label: {
                                        Image(systemName: "safari").font(.caption)
                                    }
                                    .buttonStyle(.borderless).help("Preview in the built-in browser")
                                    Button { harvest.removeQueuedURL(entry.url) } label: {
                                        Image(systemName: "xmark").font(.caption2)
                                    }
                                    .buttonStyle(.borderless).help("Remove from queue")
                                }
                                .padding(.vertical, 2)
                                .contextMenu {
                                    Button("Move to front") { harvest.prioritizeQueuedURL(entry.url) }
                                    Button("Preview page") { inlineBrowser = entry.url }
                                    Divider()
                                    Button("Remove from queue", role: .destructive) {
                                        harvest.removeQueuedURL(entry.url)
                                    }
                                }
                            }
                            if queued > 6 {
                                Text("…and \(queued - 6) more")
                                    .font(.caption2).foregroundStyle(.secondary).padding(.leading, 18)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Next to import").font(.caption.weight(.medium))
                    }
                }

                if queued > 0 || harvest.isImporting {
                    HStack(spacing: 6) {
                        if harvest.isImporting {
                            ProgressView().scaleEffect(0.45)
                            Text("Importing").font(.callout.weight(.semibold))
                            Text("\(harvest.importProgress.completed)/\(harvest.importProgress.total)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button("Stop") { harvest.cancelImport() }
                                .buttonStyle(.borderless).foregroundStyle(.red)
                        } else {
                            Button(importActionLabel(queued: queued)) { harvest.importURLs() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(harvest.isBulkVerifying || queued == 0)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.callout)
                }

                if let report = harvest.discoveryReport, !report.unverified.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(MacTheme.gold)
                        Text("\(report.unverified.count) more from \(report.sourceName)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Check them") { harvest.verifyRemaining() }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }

                if queued == 0 && !harvest.isImporting && !showURLEditor {
                    HStack(spacing: 6) {
                        Image(systemName: isQueueDropTargeted ? "arrow.down.circle.fill" : "link.badge.plus")
                        Text(isQueueDropTargeted ? "Drop to add these recipe links"
                             : "Found, pasted, or dropped recipe links appear here.")
                    }
                    .font(.caption)
                    .foregroundStyle(isQueueDropTargeted ? MacTheme.green : .secondary)
                }
            }
            .padding(6)
            .background(isQueueDropTargeted ? MacTheme.green.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .dropDestination(for: String.self) { items, _ in
                harvest.appendImportText(items)
                return !items.isEmpty
            } isTargeted: { isQueueDropTargeted = $0 }
        }
    }

    private func queueHeadline(queued: Int) -> String {
        if harvest.isBulkVerifying { return "Verifying the queue" }
        if harvest.isImporting { return "Importing recipes" }
        if queued > 0 { return "\(queued) recipe link\(queued == 1 ? "" : "s") ready" }
        return "Your queue is clear"
    }

    private func queueFootnote(queued: Int) -> String {
        let saved = harvest.cachedMinedPageCount
        if queued > 0, saved > 0 { return "\(queued) ready · \(saved) mined pages saved" }
        if queued > 0 { return "\(queued) ready" }
        if saved > 0 { return "\(saved) mined pages saved" }
        return "Waiting for links"
    }

    private func queueSubheadline(queued: Int, domains: Int) -> String {
        if harvest.isBulkVerifying { return "Mined recipes lead the queue; unrelated pages are removed." }
        if harvest.isImporting { return "\(harvest.importProgress.completed) of \(harvest.importProgress.total) processed" }
        if queued > 0 { return "From \(domains) source domain\(domains == 1 ? "" : "s") · edit only if needed" }
        return "Everything found lands here automatically."
    }

    private func importActionLabel(queued: Int) -> String {
        let count = harvest.settings.importBatchSize > 0
            ? min(queued, harvest.settings.importBatchSize) : queued
        if harvest.settings.verifyBeforeImport { return "Verify & Import \(count)" }
        return "Import \(count) Recipe\(count == 1 ? "" : "s")"
    }

    // MARK: Advanced (everything, collapsed)

    @ViewBuilder
    private var advancedCard: some View {
        @Bindable var harvest = harvest
        MacCard {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 14) {
                    advancedDiscovery
                    Divider()
                    advancedCrawler
                    Divider()
                    advancedQueue
                    Divider()
                    advancedDelivery
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var advancedDiscovery: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovery").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Toggle("Prefer direct recipe links — mine category pages only when needed",
                   isOn: $harvest.settings.preferDirectRecipes)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.preferDirectRecipes) { harvest.scheduleSettingsSave() }
            Toggle("Reuse saved results and skip sites already read",
                   isOn: $harvest.settings.reuseCachedDiscoveryResults)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.reuseCachedDiscoveryResults) { harvest.scheduleSettingsSave() }
            HStack(spacing: 6) {
                Stepper(value: $harvest.settings.autoRotateSourceCount, in: 1...10) {
                    Text("Rotation: \(harvest.settings.autoRotateSourceCount) sources").font(.caption)
                }
                Spacer(minLength: 0)
                Button("Run rotation") { harvest.autoRotate() }
                    .disabled(harvest.isDiscovering || browsableSources.isEmpty)
            }
            .onChange(of: harvest.settings.autoRotateSourceCount) { harvest.scheduleSettingsSave() }
            HStack(spacing: 10) {
                Button("Update sources") { harvest.importSourcesFromFile() }
                Button("Export") { harvest.exportSourcesToFile() }
                Spacer(minLength: 0)
                Button("Restore catalog") { harvest.repairSources() }
            }
            .buttonStyle(.borderless).font(.caption)
        }
    }

    @ViewBuilder
    private var advancedCrawler: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 8) {
            Text("Crawler").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Method").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $harvest.settings.preferredCrawlMethod) {
                    ForEach(CrawlMethod.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().frame(maxWidth: .infinity)
                Text(harvest.settings.preferredCrawlMethod.explanation)
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: harvest.settings.preferredCrawlMethod) { harvest.scheduleSettingsSave() }

            VStack(alignment: .leading, spacing: 4) {
                Text("Speed").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $harvest.settings.crawlAggressiveness) {
                    ForEach(CrawlAggressiveness.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
                Text(harvest.settings.crawlAggressiveness.explanation)
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: harvest.settings.crawlAggressiveness) { harvest.scheduleSettingsSave() }

            Toggle("Use the built-in browser when a site blocks direct fetches",
                   isOn: $harvest.settings.useWebKitFallback)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.useWebKitFallback) { harvest.scheduleSettingsSave() }

            Stepper(value: $harvest.settings.importSpacingSeconds, in: 0...30) {
                Text(harvest.settings.importSpacingSeconds == 0
                     ? "No extra pause between imports"
                     : "Pause \(harvest.settings.importSpacingSeconds) s between imports")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: harvest.settings.importSpacingSeconds) { harvest.scheduleSettingsSave() }

            HStack(spacing: 10) {
                Menu {
                    Button("Safari (recommended)") { setUserAgent(AppSettings.safariUserAgent) }
                    Button("Chrome") { setUserAgent(AppSettings.chromeUserAgent) }
                    Button("Honest bot") { setUserAgent(AppSettings.honestUserAgent) }
                } label: {
                    Label("User agent: \(userAgentLabel)", systemImage: "person.crop.rectangle")
                }
                .menuStyle(.borderlessButton).font(.caption)
                .help("How the crawler identifies itself to sites")
                Spacer(minLength: 0)
                Button {
                    harvest.resetRateLimits()
                } label: {
                    Label("Clear pauses", systemImage: "hare")
                }
                .buttonStyle(.borderless).font(.caption)
                .help("Clear every rate-limit pause and daily counter")
            }

            HStack(alignment: .top, spacing: 7) {
                if harvest.isTestingPythonWorker {
                    ProgressView().scaleEffect(0.45)
                } else {
                    Circle().fill(pythonParserStatusColor).frame(width: 7, height: 7).padding(.top, 4)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bundled Python parser").font(.caption.weight(.medium))
                    Text(harvest.pythonWorkerStatus)
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button("Test") { harvest.testPythonWorker() }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(!harvest.pythonWorkerAvailable || harvest.isTestingPythonWorker)
                    .help("Launch the bundled executable and decode a complete test recipe")
            }
        }
    }

    @ViewBuilder
    private var advancedQueue: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 8) {
            Text("Verify & import").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Toggle("Verify recipe pages before importing (mine category pages only if needed)",
                   isOn: $harvest.settings.verifyBeforeImport)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.verifyBeforeImport) { harvest.scheduleSettingsSave() }
            Toggle("Only auto-approve recipes that meet Stocked standards",
                   isOn: $harvest.settings.requireStandardsForAutoApprove)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.requireStandardsForAutoApprove) { harvest.scheduleSettingsSave() }
            HStack(spacing: 8) {
                Text("Approval confidence").font(.caption)
                Slider(value: $harvest.settings.autoApproveConfidence, in: 0.50...1.0, step: 0.05)
                    .frame(minWidth: 80)
                Text("\(Int(harvest.settings.autoApproveConfidence * 100))%").font(.caption.monospacedDigit())
            }
            .onChange(of: harvest.settings.autoApproveConfidence) { harvest.scheduleSettingsSave() }
            HStack(spacing: 8) {
                Button("Verify now") { harvest.bulkVerifyQueue() }
                    .disabled(harvest.queuedURLCount == 0 || harvest.isImporting || harvest.isBulkVerifying)
                if harvest.cachedMinedPageCount > 0 {
                    Button("Refresh mining") { harvest.bulkVerifyQueue(forceRefreshMining: true) }
                        .disabled(harvest.queuedURLCount == 0 || harvest.isImporting || harvest.isBulkVerifying)
                        .help("Ignore saved mining results and reread queued category pages")
                }
                if harvest.isBulkVerifying {
                    ProgressView().scaleEffect(0.45)
                    Text("\(harvest.bulkVerifyProgress.completed)/\(harvest.bulkVerifyProgress.total)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Stop") { harvest.cancelBulkVerify() }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            Stepper(value: $harvest.settings.bulkVerifyBatchSize, in: 25...1000, step: 25) {
                Text("Verify up to \(harvest.settings.bulkVerifyBatchSize) per pass").font(.caption)
            }
            .onChange(of: harvest.settings.bulkVerifyBatchSize) { harvest.scheduleSettingsSave() }
            Stepper(value: $harvest.settings.queueCap, in: 100...5000, step: 100) {
                Text("Queue cap: \(harvest.settings.queueCap)").font(.caption)
            }
            .onChange(of: harvest.settings.queueCap) { harvest.scheduleSettingsSave() }
            Stepper(value: $harvest.settings.importBatchSize, in: 0...2000, step: 50) {
                Text(harvest.settings.importBatchSize == 0
                     ? "Import everything queued" : "Import \(harvest.settings.importBatchSize) at a time")
                    .font(.caption)
            }
            .onChange(of: harvest.settings.importBatchSize) { harvest.scheduleSettingsSave() }
        }
    }

    @ViewBuilder
    private var advancedDelivery: some View {
        @Bindable var harvest = harvest
        VStack(alignment: .leading, spacing: 8) {
            Text("Delivery").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Toggle("Require an image before a recipe reaches the kitchen",
                   isOn: $harvest.settings.requireImageForImport)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.requireImageForImport) { harvest.scheduleSettingsSave() }
            Toggle("Retry failed image downloads after each run",
                   isOn: $harvest.settings.autoFetchMissingImages)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.autoFetchMissingImages) { harvest.scheduleSettingsSave() }
            Toggle("Sync approved recipes to the Worker automatically",
                   isOn: $harvest.settings.cloudSyncEnabled)
                .toggleStyle(.checkbox).font(.caption)
                .onChange(of: harvest.settings.cloudSyncEnabled) { harvest.scheduleSettingsSave() }
            if let status = harvest.cloudSyncStatus {
                Text(status).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pythonParserStatusColor: Color {
        switch harvest.pythonWorkerTestPassed {
        case true: return MacTheme.green
        case false: return .red
        case nil: return harvest.pythonWorkerAvailable ? MacTheme.gold : .red
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

    // MARK: - Activity pane (right side of Find)

    private var isIdle: Bool {
        !harvest.isDiscovering && !harvest.isImporting && !harvest.isBulkVerifying
    }

    @ViewBuilder
    private var activityPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workflowProgressCard

                if isIdle,
                   harvest.recipes.isEmpty,
                   harvest.sessionHistory.isEmpty,
                   harvest.discoveryReport == nil {
                    MacEmpty(
                        title: "Ready for a recipe run",
                        message: "Pick sources and a category on the left, then press Start. Stocked finds recipe links directly (mining only if it must), fills the queue, imports, and hands the results to Review.",
                        systemImage: "arrow.forward.circle"
                    )
                    .frame(minHeight: 240)
                } else {
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
                        foundCard(report)
                    }

                    if let summary = harvest.lastImportSummary, !harvest.isImporting {
                        MacCard(title: "Import complete", systemImage: "checkmark.circle.fill") {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(MacTheme.green)
                                Text(summary).font(.callout.weight(.medium))
                                Spacer(minLength: 0)
                                if reviewWaiting > 0 {
                                    Button("Review \(reviewWaiting)") { pane = .review }
                                        .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                    }

                    if !harvest.lastFailures.isEmpty { failuresCard }

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showDiagnostics.toggle() }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(showDiagnostics ? "Hide history & diagnostics" : "Show history & diagnostics")
                            Spacer(minLength: 0)
                            Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.weight(.medium)).padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)

                    if showDiagnostics {
                        if !harvest.sessionHistory.isEmpty { historyCard }
                        activityCard
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private func foundCard(_ report: DiscoveryReport) -> some View {
        MacCard(title: "Found — \(report.sourceName)", systemImage: "checkmark.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(report.summary).font(.callout)
                if let note = report.notes.first {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if !report.confirmed.isEmpty {
                    Divider()
                    ForEach(Array(report.confirmed.prefix(5).enumerated()), id: \.offset) { _, link in
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(MacTheme.green)
                            Text(link.title?.nilIfBlank
                                 ?? URL(string: link.url)?.lastPathComponent.nilIfBlank
                                 ?? link.url)
                                .font(.caption).lineLimit(1)
                            Spacer(minLength: 4)
                            Button("Preview") { inlineBrowser = link.url }
                                .buttonStyle(.borderless).font(.caption2)
                        }
                    }
                    if report.confirmed.count > 5 {
                        Text("…and \(report.confirmed.count - 5) more verified recipes")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Button("Add to Queue") { harvest.queue(report.confirmed) }
                        .disabled(report.confirmed.isEmpty)
                    if !report.unverified.isEmpty {
                        Button("Check \(report.unverified.count) Remaining") { harvest.verifyRemaining() }
                    }
                    Spacer(minLength: 0)
                    Button("Dismiss") { harvest.discoveryReport = nil }.foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    // MARK: Workflow progress card (guided)

    private var currentFlowPhase: FlowPhase {
        if harvest.isDiscovering { return .discover }
        if harvest.isBulkVerifying { return .review }
        if harvest.isImporting { return .importRecipes }
        if harvest.queuedURLCount > 0 { return .review }
        if harvest.lastImportSummary != nil { return .finish }
        if harvest.discoveryReport != nil { return .review }
        return .discover
    }

    private func phaseIsComplete(_ phase: FlowPhase) -> Bool {
        switch phase {
        case .discover, .review:
            return currentFlowPhase.rawValue > phase.rawValue
        case .importRecipes:
            return currentFlowPhase == .finish && harvest.lastImportSummary != nil
        case .finish:
            return currentFlowPhase == .finish
                && reviewWaiting == 0
                && harvest.imagelessCount == 0
                && !harvest.recipes.isEmpty
        }
    }

    private var workflowProgressCard: some View {
        MacCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(Array(FlowPhase.allCases.enumerated()), id: \.element.id) { index, phase in
                        flowPhaseView(phase)
                        if index < FlowPhase.allCases.count - 1 {
                            Rectangle()
                                .fill(phaseIsComplete(phase) ? MacTheme.green.opacity(0.65) : Color.secondary.opacity(0.20))
                                .frame(height: 2).frame(maxWidth: .infinity)
                                .padding(.horizontal, 5).accessibilityHidden(true)
                        }
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: flowGuidanceIcon)
                        .foregroundStyle(currentFlowPhase == .finish ? MacTheme.green : MacTheme.gold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flowGuidanceTitle).font(.callout.weight(.semibold))
                        Text(flowGuidanceDetail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    flowContextAction
                }
            }
        }
    }

    private func flowPhaseView(_ phase: FlowPhase) -> some View {
        let complete = phaseIsComplete(phase)
        let active = currentFlowPhase == phase && !complete
        return VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(complete ? MacTheme.green : (active ? MacTheme.gold : Color.secondary.opacity(0.14)))
                    .frame(width: 30, height: 30)
                if active && (harvest.isDiscovering || harvest.isBulkVerifying || harvest.isImporting) {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: complete ? "checkmark" : phase.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(complete || active ? Color.white : .secondary)
                }
            }
            Text(phase.title)
                .font(.caption2.weight(active || complete ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
        }
        .frame(minWidth: 58)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(phase.title), \(complete ? "complete" : (active ? "current step" : "pending"))")
    }

    private var flowGuidanceIcon: String {
        switch currentFlowPhase {
        case .discover: return harvest.isDiscovering ? "magnifyingglass" : "cursorarrow.click"
        case .review: return harvest.isBulkVerifying ? "sparkles" : "tray.full"
        case .importRecipes: return "square.and.arrow.down"
        case .finish: return "checkmark.seal"
        }
    }

    private var flowGuidanceTitle: String {
        switch currentFlowPhase {
        case .discover: return harvest.isDiscovering ? "Finding recipes" : "Choose a source and start"
        case .review: return harvest.isBulkVerifying ? "Verifying the queue" : "Queue ready"
        case .importRecipes: return "Import in progress"
        case .finish: return reviewWaiting > 0 ? "Approve the results" : "Workflow complete"
        }
    }

    private var flowGuidanceDetail: String {
        switch currentFlowPhase {
        case .discover:
            return harvest.isDiscovering
                ? harvest.discoveryProgress.phase
                : "One run can find, verify, import and approve — mining only if a site has no direct links."
        case .review:
            return harvest.isBulkVerifying
                ? "Mined recipes lead the queue; unrelated pages are removed."
                : "\(harvest.queuedURLCount) link\(harvest.queuedURLCount == 1 ? "" : "s") ready to import."
        case .importRecipes:
            return "\(harvest.importProgress.completed) of \(harvest.importProgress.total) processed"
        case .finish:
            return reviewWaiting > 0
                ? "\(reviewWaiting) recipe\(reviewWaiting == 1 ? "" : "s") waiting in Review."
                : "Imported recipes are approved and ready for Stocked."
        }
    }

    @ViewBuilder
    private var flowContextAction: some View {
        switch currentFlowPhase {
        case .discover:
            if harvest.isDiscovering {
                Button("Stop") { harvest.cancelDiscovery() }.foregroundStyle(.red)
            }
        case .review:
            if harvest.isBulkVerifying {
                Button("Stop") { harvest.cancelBulkVerify() }.foregroundStyle(.red)
            } else if harvest.queuedURLCount > 0 {
                Button(importActionLabel(queued: harvest.queuedURLCount)) { harvest.importURLs() }
                    .buttonStyle(.borderedProminent)
            }
        case .importRecipes:
            Button("Stop") { harvest.cancelImport() }.foregroundStyle(.red)
        case .finish:
            if reviewWaiting > 0 {
                Button("Open Review") { pane = .review }.buttonStyle(.borderedProminent)
            }
        }
    }

    private var statsRow: some View {
        let dashboard = harvest.dashboard
        return MacCard {
            HStack(spacing: 0) {
                compactMetric("Imported", "\(dashboard.recipes)", "tray.and.arrow.down")
                Divider().frame(height: 34)
                compactMetric("To review", "\(dashboard.needsReview)", "eye")
                Divider().frame(height: 34)
                compactMetric("Approved", "\(dashboard.approved)", "checkmark.circle")
                Divider().frame(height: 34)
                compactMetric("Images missing", "\(harvest.imagelessCount)", "photo.badge.exclamationmark")
            }
        }
    }

    private func compactMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(MacTheme.gold)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.title3.weight(.semibold).monospacedDigit())
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
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
                let grouped = Dictionary(grouping: harvest.lastFailures) {
                    $0.reason.components(separatedBy: " | ").first ?? $0.reason
                }
                .map { (reason: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
                ForEach(grouped.prefix(3), id: \.reason) { item in
                    HStack(spacing: 6) {
                        Text("\(item.count)×").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.orange)
                        Text(item.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Divider()
                ForEach(harvest.lastFailures.suffix(10)) { failure in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(URL(string: failure.url)?.lastPathComponent.nilIfBlank ?? failure.url)
                                    .font(.caption.weight(.medium)).lineLimit(1)
                                if let host = URL(string: failure.url)?.host {
                                    Text(host).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                            Text(failure.reason.components(separatedBy: " | ").first ?? failure.reason)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(failure.reason)
                        }
                        Spacer(minLength: 0)
                        Button("View") { inlineBrowser = failure.url }
                            .buttonStyle(.borderless).font(.caption)
                            .help("Open this page right here and import it by hand")
                        Button("Retry") { harvest.retryFailure(failure) }
                            .buttonStyle(.borderless).font(.caption).disabled(harvest.isImporting)
                        if harvest.pythonWorkerAvailable {
                            Button("Python") { harvest.retryFailureWithPython(failure) }
                                .buttonStyle(.borderless).font(.caption).disabled(harvest.isImporting)
                                .help("Retry with the bundled Python parser first")
                        }
                    }
                }
                if harvest.lastFailures.count > 10 {
                    Text("…and \(harvest.lastFailures.count - 10) more.").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Retry all") { harvest.retryFailures() }.disabled(harvest.isImporting)
                    if harvest.pythonWorkerAvailable {
                        Button("Retry with Python") { harvest.retryFailuresWithPython() }.disabled(harvest.isImporting)
                    }
                    Menu("Copy") {
                        Button("Failed URLs") { harvest.copyFailedURLs() }
                        Button("Full diagnostics") { harvest.copyFailureDiagnostics() }
                    }
                    .menuStyle(.borderlessButton)
                    Button("Clear") { harvest.clearFailures() }.foregroundStyle(.secondary)
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
                        Text(report.finishedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        Text("· \(report.confirmed.count) verified").font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Restore") { harvest.restoreSession(report) }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
    }

    private var activityCard: some View {
        MacCard(title: "Activity", systemImage: "list.bullet.rectangle") {
            if harvest.logs.isEmpty {
                Text("Nothing yet. Start a run to get going.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Picker("Activity filter", selection: $logScope) {
                            ForEach(LogScope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 250)
                        Spacer(minLength: 0)
                        Button("Copy") { copyVisibleLogs() }.buttonStyle(.borderless).font(.caption)
                        Button("Clear") { harvest.clearLogs() }.buttonStyle(.borderless).font(.caption)
                    }
                    Divider()
                    ForEach(visibleLogs.prefix(14)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle().fill(logTint(entry.level)).frame(width: 5, height: 5).padding(.top, 4)
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(entry.level == .error ? .red : .secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text(entry.timestamp, style: .relative).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    if visibleLogs.isEmpty {
                        Text("No activity matches this filter.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var visibleLogs: [CrawlLogEntry] {
        switch logScope {
        case .all: return harvest.logs
        case .problems: return harvest.logs.filter { $0.level == .warning || $0.level == .error }
        case .success: return harvest.logs.filter { $0.level == .success }
        }
    }

    private func copyVisibleLogs() {
        let value = visibleLogs.prefix(100).map { "[\($0.level.rawValue.uppercased())] \($0.message)" }
            .joined(separator: "\n")
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        harvest.statusMessage = "Copied \(min(100, visibleLogs.count)) activity entries"
    }

    private func logTint(_ level: CrawlLogEntry.Level) -> Color {
        switch level {
        case .info:    return .secondary
        case .success: return MacTheme.green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    // MARK: - CATEGORIES PANE (Build 101)

    private var categoryGroupOrder: [String] {
        RecipeBrowseTaxonomy.groupOrder + ["Other"]
    }

    private var groupedCategories: [(group: String, items: [SourceCategory])] {
        var items = harvest.allCategories
        if let sourceID = categorySourceFilter {
            items = items.filter { $0.sourceID == sourceID }
        }
        let grouped = Dictionary(grouping: items) { $0.group ?? "Other" }
        return categoryGroupOrder.compactMap { group in
            guard let rows = grouped[group], !rows.isEmpty else { return nil }
            return (group, rows)
        }
    }

    private var categorySourceOptions: [(id: String, name: String)] {
        var seen = Set<String>()
        return harvest.allCategories.compactMap { cat in
            guard seen.insert(cat.sourceID).inserted else { return nil }
            return (cat.sourceID, cat.sourceName)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    private var categoriesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                categoriesHeaderCard
                if harvest.allCategories.isEmpty {
                    MacEmpty(
                        title: "No categories yet",
                        message: "Run a source in Find & Import. Every category it discovers is captured here — organized, cached, and ready to import in one click.",
                        systemImage: "square.grid.2x2"
                    )
                    .frame(minHeight: 240)
                } else {
                    ForEach(groupedCategories, id: \.group) { section in
                        MacCard(title: section.group, systemImage: "square.grid.2x2",
                                footnote: "\(section.items.count) categor\(section.items.count == 1 ? "y" : "ies")") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(section.items) { category in
                                    categoryRow(category)
                                    if category.id != section.items.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 920, alignment: .leading)
        }
    }

    private var categoriesHeaderCard: some View {
        MacCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2").foregroundStyle(MacTheme.gold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(harvest.allCategories.count) categories · \(harvest.readyCategoryCount) ready")
                            .font(.callout.weight(.semibold))
                        Text("Discovered on your sources, cached and organized. Ready ones import with no refetch.")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button {
                        harvest.importAllReadyCategories()
                    } label: {
                        Label("Import all ready", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(harvest.readyCategoryCount == 0 || harvest.isImporting)
                }
                if categorySourceOptions.count > 1 {
                    Picker("Source", selection: $categorySourceFilter) {
                        Text("All sources").tag(String?.none)
                        ForEach(categorySourceOptions, id: \.id) { option in
                            Text(option.name).tag(String?.some(option.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                }
            }
        }
    }

    private func categoryRow(_ category: SourceCategory) -> some View {
        HStack(spacing: 8) {
            Image(systemName: category.isReady ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(category.isReady ? MacTheme.green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(category.name).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(category.sourceName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if category.isReady {
                        Text("· \(category.recipeCount) ready").font(.caption2).foregroundStyle(MacTheme.green)
                    } else {
                        Text("· not mined yet").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let mined = category.minedAt {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(mined, style: .relative).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            Button { inlineBrowser = category.url } label: {
                Image(systemName: "safari").font(.caption)
            }
            .buttonStyle(.borderless).help("Preview this category page")
            Button(category.isReady ? "Import \(category.recipeCount)" : "Mine & Import") {
                harvest.importCategory(category)
            }
            .buttonStyle(.bordered)
            .disabled(harvest.isImporting)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(category.isReady ? "Import \(category.recipeCount) recipes" : "Mine & import") {
                harvest.importCategory(category)
            }
            Button("Preview category page") { inlineBrowser = category.url }
        }
    }

    // MARK: - REVIEW PANE (folded-in Harvest library)

    private var reviewVisible: [RecipeDraft] {
        var items = harvest.recipes
        if let f = reviewFilter { items = items.filter { $0.reviewState == f } }
        if onlyImageless { items = items.filter { !($0.image?.hasLocalFile ?? false) } }
        let q = reviewSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q) || $0.source.host.lowercased().contains(q)
            }
        }
        return items
    }

    private var reviewPane: some View {
        @Bindable var harvest = harvest
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                reviewFilterRow
                Divider()
                reviewBulkBar
                reviewList
                Divider()
                reviewFooter
            }
            .frame(minWidth: 300, maxWidth: 400)

            Divider()

            Group {
                if let draft = harvest.recipes.first(where: { $0.id == harvest.selectedRecipeID }) {
                    HarvestDraftDetail(draft: draft, addStatus: $addStatus)
                } else if harvest.recipes.isEmpty {
                    MacEmpty(
                        title: "Nothing to review yet",
                        message: "Find and import recipes in Find & Import, then approve them here.",
                        systemImage: "leaf"
                    )
                } else {
                    MacEmpty(
                        title: "Select a recipe",
                        message: "Choose a recipe from the list to review it.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var reviewFilterRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search recipes", text: $reviewSearch).textFieldStyle(.plain).font(.callout)
            Picker("", selection: $reviewFilter) {
                Text("All").tag(ReviewState?.none)
                Text("Review").tag(ReviewState?.some(.needsReview))
                Text("Approved").tag(ReviewState?.some(.approved))
                Text("Rejected").tag(ReviewState?.some(.rejected))
            }
            .labelsHidden().frame(width: 100)
            Button { onlyImageless.toggle() } label: {
                Image(systemName: onlyImageless ? "photo.badge.exclamationmark.fill" : "photo.badge.exclamationmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(onlyImageless ? MacTheme.gold : .secondary)
            .help("Show only recipes missing an image")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    @ViewBuilder
    private var reviewBulkBar: some View {
        let shown = reviewVisible
        let reviewable = shown.filter { $0.reviewState == .needsReview }
        if shown.count > 1 {
            HStack(spacing: 6) {
                Text("\(shown.count) shown").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !reviewable.isEmpty {
                    Button("Approve \(reviewable.count)") {
                        harvest.setReviewState(.approved, for: Set(reviewable.map(\.id)))
                    }
                    .font(.caption)
                    Button("Reject") {
                        harvest.setReviewState(.rejected, for: Set(reviewable.map(\.id)))
                    }
                    .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10).padding(.vertical, 5)
            Divider()
        }
    }

    @ViewBuilder
    private var reviewList: some View {
        @Bindable var harvest = harvest
        if harvest.recipes.isEmpty {
            MacEmpty(
                title: "No recipes yet",
                message: "Find recipes in Find & Import to fill this up.",
                systemImage: "leaf"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(reviewVisible, selection: $harvest.selectedRecipeID) { draft in
                HStack(spacing: 8) {
                    HarvestThumbnail(draft: draft)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.title).font(.callout).lineLimit(1)
                        HStack(spacing: 5) {
                            reviewStateBadge(draft.reviewState)
                            if !(draft.image?.hasLocalFile ?? false) {
                                Text("no image")
                                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.orange)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                            }
                            if !draft.source.host.isEmpty {
                                Text(draft.source.host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("\(Int(draft.confidence * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(draft.confidence >= 0.85 ? MacTheme.green : .secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(draft.id)
                .contextMenu {
                    Button("Approve") { harvest.setReviewState(.approved, for: [draft.id]) }
                    Button("Reject") { harvest.setReviewState(.rejected, for: [draft.id]) }
                    Divider()
                    Button("Add to Stocked") {
                        addStatus = MacHarvestBridge.summary(added: MacHarvestBridge.add([draft], to: store), of: 1)
                    }
                    if !draft.source.url.isEmpty {
                        Divider()
                        Button("Open in Browser") { harvest.open(draft.source.url) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { harvest.deleteRecipe(draft) }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var reviewFooter: some View {
        HStack(spacing: 6) {
            Text(addStatus ?? harvest.statusMessage)
                .font(.caption)
                .foregroundStyle(addStatus != nil ? MacTheme.green : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if addStatus != nil {
                Button("Clear") { addStatus = nil }.buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func reviewStateBadge(_ state: ReviewState) -> some View {
        let label: String
        let color: Color
        switch state {
        case .needsReview: label = "review";   color = .secondary
        case .approved:    label = "approved"; color = MacTheme.green
        case .rejected:    label = "rejected"; color = .red
        }
        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func flowStatusIcon(done: Bool, active: Bool) -> some View {
        if active {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? MacTheme.green : .secondary)
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
    let cachedIDs: Set<String>
    @Binding var favoriteIDs: [String]
    let onFavoritesChanged: () -> Void

    @State private var healthScope: HealthScope = .available

    private enum HealthScope: String, CaseIterable, Identifiable {
        case available = "Available"
        case healthy = "Healthy"
        case attention = "Needs attention"
        case all = "All"
        var id: String { rawValue }
    }

    private var catalog: [SourceProfile] {
        var seen = Set<String>()
        return (american + worldwide + feeds + custom).filter { seen.insert($0.id).inserted }
    }

    private var favorites: [SourceProfile] {
        catalog.filter { favoriteIDs.contains($0.id) }
    }

    private var visibleIDs: [String] {
        scoped(catalog).map(\.id)
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
                Menu {
                    Picker("Source health", selection: $healthScope) {
                        ForEach(HealthScope.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(healthScope == .all ? Color.secondary : MacTheme.gold)
                }
                .menuStyle(.borderlessButton)
                .help("Filter sources by health")
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !recent.isEmpty && search.isEmpty { group("Recent", recent) }
                    if !favorites.isEmpty { group("Favorites", favorites) }
                    group("American — Top 50", american)
                    group("Worldwide — Top 50", worldwide)
                    if !feeds.isEmpty { group("Communities & feeds", feeds) }
                    if !custom.isEmpty { group("Custom & imported", custom) }
                }
                .padding(.vertical, 6)
            }
            .frame(width: 330, height: 380)

            Divider()

            HStack(spacing: 8) {
                Text("\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !favorites.isEmpty {
                    Button("Favorites") { selected.formUnion(scoped(favorites).map(\.id)) }.font(.caption)
                }
                Button("All shown") { selected.formUnion(visibleIDs) }.font(.caption)
                Button("None") { selected.removeAll() }.font(.caption).disabled(selected.isEmpty)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ sources: [SourceProfile]) -> some View {
        let shown = scoped(sources).sorted {
            if healthRank($0.health) != healthRank($1.health) {
                return healthRank($0.health) < healthRank($1.health)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if !shown.isEmpty {
            HStack(spacing: 6) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(shown.allSatisfy { selected.contains($0.id) } ? "None" : "All") {
                    let ids = shown.map(\.id)
                    if shown.allSatisfy({ selected.contains($0.id) }) {
                        selected.subtract(ids)
                    } else {
                        selected.formUnion(ids)
                    }
                }
                .buttonStyle(.borderless).font(.caption2)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)

            ForEach(shown) { source in
                HStack(spacing: 6) {
                    Button {
                        if selected.contains(source.id) { selected.remove(source.id) }
                        else { selected.insert(source.id) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: selected.contains(source.id) ? "checkmark.square.fill" : "square")
                                .font(.callout)
                                .foregroundStyle(selected.contains(source.id) ? MacTheme.gold : .secondary)
                            healthDot(source.health).help(healthLabel(source.health))
                            Text(source.name).font(.callout).lineLimit(1)
                            Spacer(minLength: 0)
                            if cachedIDs.contains(source.id) {
                                Image(systemName: "externaldrive.fill").font(.caption2).foregroundStyle(MacTheme.green)
                                    .help("Saved results available; this website can be skipped")
                            }
                            Text(source.domains.first ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(selected.contains(source.id) ? "Deselect" : "Select") \(source.name), \(healthLabel(source.health))")
                    Button { toggleFavorite(source.id) } label: {
                        Image(systemName: favoriteIDs.contains(source.id) ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(favoriteIDs.contains(source.id) ? MacTheme.gold : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(favoriteIDs.contains(source.id) ? "Remove from favorites" : "Add to favorites")
                }
                .padding(.horizontal, 12).padding(.vertical, 2)
            }
        }
    }

    private func scoped(_ sources: [SourceProfile]) -> [SourceProfile] {
        sources.filter { source in
            switch healthScope {
            case .available: return source.health != .blocked && source.health != .paused
            case .healthy: return source.health == .healthy
            case .attention: return source.health == .limited || source.health == .paused || source.health == .blocked
            case .all: return true
            }
        }
    }

    private func toggleFavorite(_ id: String) {
        if let index = favoriteIDs.firstIndex(of: id) { favoriteIDs.remove(at: index) }
        else { favoriteIDs.append(id) }
        onFavoritesChanged()
    }

    private func healthRank(_ health: SourceHealth) -> Int {
        switch health {
        case .healthy: return 0
        case .unknown: return 1
        case .limited: return 2
        case .paused: return 3
        case .blocked: return 4
        }
    }

    private func healthLabel(_ health: SourceHealth) -> String {
        switch health {
        case .healthy: return "Healthy"
        case .unknown: return "Not checked yet"
        case .limited: return "Limited"
        case .paused: return "Paused by the site"
        case .blocked: return "Blocked"
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

// MARK: - Recipe category picker

/// A searchable, grouped checklist for the full browsing taxonomy. Selections use OR
/// semantics so broad combinations such as "Korean, weeknight, or birthdays" remain
/// useful during discovery instead of requiring every label to appear in one URL.
private struct RecipeCategoryPicker: View {
    @Binding var search: String
    @Binding var selectedIDs: [String]

    private var selected: Set<String> { Set(selectedIDs) }

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shownCategories(in group: String) -> [RecipeBrowseCategory] {
        let categories = RecipeBrowseTaxonomy.categories(in: group)
        guard !query.isEmpty else { return categories }
        return categories.filter { category in
            category.name.localizedCaseInsensitiveContains(query)
                || category.terms.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.caption2).foregroundStyle(.secondary)
                TextField("Search foods, cuisines, events, diets…", text: $search)
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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(RecipeBrowseTaxonomy.groupOrder, id: \.self) { group in
                        categoryGroup(group)
                    }
                    if RecipeBrowseTaxonomy.groupOrder.allSatisfy({ shownCategories(in: $0).isEmpty }) {
                        ContentUnavailableView.search(text: query)
                            .frame(maxWidth: .infinity).padding(.top, 44)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(width: 390, height: 430)

            Divider()

            HStack(spacing: 8) {
                Text(selectedIDs.isEmpty ? "All categories" : "\(selectedIDs.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("All shown") {
                    let visible = RecipeBrowseTaxonomy.groupOrder.flatMap { shownCategories(in: $0).map(\.id) }
                    updateSelection(selected.union(visible))
                }
                Button("None") { selectedIDs.removeAll() }.disabled(selectedIDs.isEmpty)
            }
            .buttonStyle(.borderless).font(.caption).padding(10)
        }
    }

    @ViewBuilder
    private func categoryGroup(_ group: String) -> some View {
        let shown = shownCategories(in: group)
        if !shown.isEmpty {
            HStack(spacing: 6) {
                Text(group).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(shown.allSatisfy { selected.contains($0.id) } ? "None" : "All") {
                    let ids = Set(shown.map(\.id))
                    if shown.allSatisfy({ selected.contains($0.id) }) {
                        updateSelection(selected.subtracting(ids))
                    } else {
                        updateSelection(selected.union(ids))
                    }
                }
                .buttonStyle(.borderless).font(.caption2)
            }
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 2)

            ForEach(shown) { category in
                Button {
                    var next = selected
                    if next.contains(category.id) { next.remove(category.id) }
                    else { next.insert(category.id) }
                    updateSelection(next)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selected.contains(category.id) ? "checkmark.square.fill" : "square")
                            .font(.callout)
                            .foregroundStyle(selected.contains(category.id) ? MacTheme.gold : .secondary)
                        Text(category.name).font(.callout)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 2).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(selected.contains(category.id) ? "Deselect" : "Select") \(category.name)")
            }
        }
    }

    private func updateSelection(_ values: Set<String>) {
        selectedIDs = values.sorted()
    }
}
