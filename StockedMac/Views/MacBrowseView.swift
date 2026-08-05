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
    @State private var categorySearch = ""
    @State private var showCategoryPicker = false
    @State private var showURLEditor = false
    @State private var showQueuePreview = true
    @State private var isQueueDropTargeted = false
    @State private var clipboardURLCount = 0
    @State private var logScope: LogScope = .all
    @State private var showDiscoveryOptions = false
    @State private var showQueueOptions = false
    @State private var showFinishOptions = false
    @State private var showDiagnostics = false
    /// Non-nil shows the in-app browser IN the right pane (Build 96) — "" opens it blank.
    @State private var inlineBrowser: String? = nil

    private enum LogScope: String, CaseIterable, Identifiable {
        case all = "All"
        case problems = "Problems"
        case success = "Success"
        var id: String { rawValue }
    }

    private enum FlowPhase: Int, CaseIterable, Identifiable {
        case discover
        case review
        case importRecipes
        case finish

        var id: Int { rawValue }
        var title: String {
            switch self {
            case .discover: return "Discover"
            case .review: return "Review"
            case .importRecipes: return "Import"
            case .finish: return "Finish"
            }
        }
        var icon: String {
            switch self {
            case .discover: return "sparkle.magnifyingglass"
            case .review: return "checklist"
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
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        sourcesCard
                        if showDiscoveryOptions { crawlerCard }
                        queueCard
                        finishFlowCard
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

    // MARK: - Step 1: discover and mine

    @ViewBuilder
    private var sourcesCard: some View {
        @Bindable var harvest = harvest
        MacCard(title: "1 · Discover & Mine", systemImage: "sparkle.magnifyingglass",
                footnote: "\(browsableSources.count) sites · \(harvest.cachedSourceCount) saved") {
            VStack(alignment: .leading, spacing: 10) {
                flowFieldLabel("Where should Stocked look?", detail: selectionLabel)
                Button {
                    showSourcePicker.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selectedSources.isEmpty
                              ? "globe" : "checkmark.circle.fill")
                            .foregroundStyle(selectedSources.isEmpty
                                             ? Color.secondary : MacTheme.green)
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
                        Text(categorySelectionLabel)
                            .font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(RecipeBrowseTaxonomy.all.count) choices")
                            .font(.caption2).foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
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

                Picker("Workflow", selection: $harvest.settings.autoImportVerified) {
                    Text("Review first").tag(false)
                    Text("Automatic").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: harvest.settings.autoImportVerified) {
                    harvest.scheduleSettingsSave()
                }

                Text(harvest.settings.autoImportVerified
                     ? "Stocked finds, verifies, imports, and approves qualifying recipes in one run."
                     : "Stocked finds and mines links, then pauses at the review queue.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    let autoImports = harvest.settings.autoImportVerified
                    if selectedSources.count == 1, let source = selectedSources.first {
                        let hasSavedResults = harvest.settings.reuseCachedDiscoveryResults
                            && harvest.cacheSummary(for: source.id) != nil
                        Button(hasSavedResults
                               ? (autoImports ? "Use Saved & Finish" : "Use Saved & Queue")
                               : (autoImports ? "Start Automatic Flow" : "Find & Queue Recipes")) {
                            harvest.discover(source)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(harvest.isDiscovering)
                        if harvest.cacheSummary(for: source.id) != nil {
                            Button {
                                harvest.refreshDiscovery(source, addToQueueOnly: !autoImports)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(harvest.isDiscovering)
                            .help("Read the website again and replace its saved discovery results")
                        }
                    } else if selectedSources.count > 1 {
                        Button(autoImports
                               ? "Run \(selectedSources.count)-Source Flow"
                               : "Find from \(selectedSources.count) Sources") {
                            harvest.browseSources(withIDs: selectedSources.map(\.id),
                                                  queueOnly: !autoImports)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(harvest.isDiscovering)
                    } else {
                        Button(autoImports ? "Start Automatic Flow" : "Find Next Source") {
                            harvest.browseNextSource()
                        }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(harvest.isDiscovering || browsableSources.isEmpty)
                    }
                    Spacer(minLength: 0)
                    if harvest.isDiscovering {
                        Button("Stop") { harvest.cancelDiscovery() }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                }
                .font(.callout)

                if selectedSources.count == 1,
                   let source = selectedSources.first,
                   let summary = harvest.cacheSummary(for: source.id) {
                    HStack(spacing: 5) {
                        Image(systemName: "externaldrive.fill")
                            .font(.caption2).foregroundStyle(MacTheme.green)
                        Text("\(summary.resultCount) saved result\(summary.resultCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("·").font(.caption).foregroundStyle(.tertiary)
                        Text(summary.savedAt, style: .relative)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .help("Stocked can use these links without reading \(source.name) again")
                }

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

                Divider()

                DisclosureGroup(isExpanded: $showDiscoveryOptions) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Reuse saved results and skip sites already read",
                               isOn: $harvest.settings.reuseCachedDiscoveryResults)
                            .toggleStyle(.checkbox).font(.caption)
                            .onChange(of: harvest.settings.reuseCachedDiscoveryResults) {
                                harvest.scheduleSettingsSave()
                            }
                        HStack(spacing: 6) {
                            Stepper(value: $harvest.settings.autoRotateSourceCount, in: 1...10) {
                                Text("Rotation: \(harvest.settings.autoRotateSourceCount) sources")
                                    .font(.caption)
                            }
                            Spacer(minLength: 0)
                            Button("Run rotation") { harvest.autoRotate() }
                                .disabled(harvest.isDiscovering || browsableSources.isEmpty)
                        }
                        .onChange(of: harvest.settings.autoRotateSourceCount) {
                            harvest.scheduleSettingsSave()
                        }
                        HStack(spacing: 10) {
                            Button("Update sources") { harvest.importSourcesFromFile() }
                            Button("Export") { harvest.exportSourcesToFile() }
                            Spacer(minLength: 0)
                            Button("Restore") { harvest.repairSources() }
                        }
                        .buttonStyle(.borderless).font(.caption)
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Advanced discovery", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
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

                Divider()

                HStack(alignment: .top, spacing: 7) {
                    if harvest.isTestingPythonWorker {
                        ProgressView().scaleEffect(0.45)
                    } else {
                        Circle()
                            .fill(pythonParserStatusColor)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bundled Python parser")
                            .font(.caption.weight(.medium))
                        Text(harvest.pythonWorkerStatus)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button("Test") { harvest.testPythonWorker() }
                        .buttonStyle(.borderless).font(.caption)
                        .disabled(!harvest.pythonWorkerAvailable || harvest.isTestingPythonWorker)
                        .help("Launch the bundled executable and decode a complete test recipe")
                }
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

    // MARK: - Steps 2 and 3: review, mine and import

    @ViewBuilder
    private var queueCard: some View {
        @Bindable var harvest = harvest
        let snapshot = harvest.queueSnapshot
        let queued = snapshot.entries.count
        let hasRawQueue = harvest.importText.nilIfBlank != nil
        MacCard(title: "2–3 · Review & Import", systemImage: "arrow.right.circle",
                footnote: queueFootnote(queued: queued)) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    flowStatusIcon(
                        done: queued > 0 || harvest.isImporting || harvest.lastImportSummary != nil,
                        active: harvest.isBulkVerifying
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(queueHeadline(queued: queued))
                            .font(.callout.weight(.semibold))
                        Text(queueSubheadline(queued: queued, domains: snapshot.domainCount))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button(clipboardURLCount > 0
                           ? "Add \(clipboardURLCount) from clipboard"
                           : "Paste URLs") {
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
                        .help("Remove duplicates, recipes already in the library, and links that failed this session — and report the counts")
                    }
                    Spacer(minLength: 0)
                    if hasRawQueue {
                        Menu {
                            Button("Copy all URLs") { harvest.copyQueueURLs() }
                                .disabled(queued == 0)
                            Button("Undo last queue edit") { harvest.undoQueueChange() }
                                .disabled(!harvest.canUndoQueueChange)
                            Divider()
                            Button("Clear queue", role: .destructive) { harvest.clearQueue() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Queue actions")
                        Button("Clear") { harvest.clearQueue() }
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)

                if queued > 0 || snapshot.invalidCount > 0 || snapshot.duplicateCount > 0 {
                    HStack(spacing: 6) {
                        Label("\(snapshot.domainCount) domain\(snapshot.domainCount == 1 ? "" : "s")",
                              systemImage: "network")
                        if snapshot.duplicateCount > 0 {
                            MacPill(text: "\(snapshot.duplicateCount) duplicate\(snapshot.duplicateCount == 1 ? "" : "s")",
                                    tint: .orange)
                        }
                        if snapshot.invalidCount > 0 {
                            MacPill(text: "\(snapshot.invalidCount) invalid",
                                    tint: .red)
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if queued > harvest.settings.queueCap {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                        Text("Over the \(harvest.settings.queueCap)-URL cap — new mined links won't join until it drains. Clean, import, or raise the cap.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Toggle("Verify recipe pages and mine category pages before import",
                       isOn: $harvest.settings.verifyBeforeImport)
                    .toggleStyle(.checkbox).font(.caption)
                    .onChange(of: harvest.settings.verifyBeforeImport) {
                        harvest.scheduleSettingsSave()
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
                                    Image(systemName: "link")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.pageLabel)
                                            .font(.caption.weight(.medium)).lineLimit(1)
                                        Text(entry.host)
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Button {
                                        inlineBrowser = entry.url
                                    } label: {
                                        Image(systemName: "safari").font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Preview in the built-in browser")
                                    Button {
                                        harvest.removeQueuedURL(entry.url)
                                    } label: {
                                        Image(systemName: "xmark").font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove from queue")
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
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .padding(.leading, 18)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("Next to import")
                            .font(.caption.weight(.medium))
                    }
                }

                if queued > 0 || harvest.isImporting {
                    HStack(spacing: 6) {
                        if harvest.isImporting {
                            ProgressView().scaleEffect(0.45)
                            Text("Importing")
                                .font(.callout.weight(.semibold))
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
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2).foregroundStyle(MacTheme.gold)
                        Text("\(report.unverified.count) more from \(report.sourceName)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Resume") { harvest.verifyRemaining() }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }

                DisclosureGroup(isExpanded: $showQueueOptions) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Only auto-approve recipes that meet Stocked standards",
                               isOn: $harvest.settings.requireStandardsForAutoApprove)
                            .toggleStyle(.checkbox).font(.caption)
                            .onChange(of: harvest.settings.requireStandardsForAutoApprove) {
                                harvest.scheduleSettingsSave()
                            }
                        HStack(spacing: 8) {
                            Text("Approval confidence")
                                .font(.caption)
                            Slider(value: $harvest.settings.autoApproveConfidence,
                                   in: 0.50...1.0, step: 0.05)
                                .frame(minWidth: 80)
                            Text("\(Int(harvest.settings.autoApproveConfidence * 100))%")
                                .font(.caption.monospacedDigit())
                        }
                        .onChange(of: harvest.settings.autoApproveConfidence) {
                            harvest.scheduleSettingsSave()
                        }
                        HStack(spacing: 8) {
                            Button("Mine & verify now") { harvest.bulkVerifyQueue() }
                                .disabled(queued == 0 || harvest.isImporting || harvest.isBulkVerifying)
                            if harvest.cachedMinedPageCount > 0 {
                                Button("Refresh mining") {
                                    harvest.bulkVerifyQueue(forceRefreshMining: true)
                                }
                                .disabled(queued == 0 || harvest.isImporting || harvest.isBulkVerifying)
                                .help("Ignore saved mining results and reread queued category pages")
                            }
                            if harvest.isBulkVerifying {
                                ProgressView().scaleEffect(0.45)
                                Text("\(harvest.bulkVerifyProgress.completed)/\(harvest.bulkVerifyProgress.total)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Stepper(value: $harvest.settings.bulkVerifyBatchSize, in: 25...1000, step: 25) {
                            Text("Verify up to \(harvest.settings.bulkVerifyBatchSize) per pass")
                                .font(.caption)
                        }
                        .onChange(of: harvest.settings.bulkVerifyBatchSize) {
                            harvest.scheduleSettingsSave()
                        }
                        Stepper(value: $harvest.settings.queueCap, in: 100...5000, step: 100) {
                            Text("Queue cap: \(harvest.settings.queueCap)").font(.caption)
                        }
                        .onChange(of: harvest.settings.queueCap) { harvest.scheduleSettingsSave() }
                        Stepper(value: $harvest.settings.importBatchSize, in: 0...2000, step: 50) {
                            Text(harvest.settings.importBatchSize == 0
                                 ? "Import everything queued"
                                 : "Import \(harvest.settings.importBatchSize) at a time")
                                .font(.caption)
                        }
                        .onChange(of: harvest.settings.importBatchSize) {
                            harvest.scheduleSettingsSave()
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Review & import options", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }

                if queued == 0 && !harvest.isImporting && !showURLEditor {
                    HStack(spacing: 6) {
                        Image(systemName: isQueueDropTargeted ? "arrow.down.circle.fill" : "link.badge.plus")
                        Text(isQueueDropTargeted
                             ? "Drop to add these recipe links"
                             : "Browse, paste, or drop recipe links here.")
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
            } isTargeted: { targeted in
                isQueueDropTargeted = targeted
            }
        }
    }

    private func queueHeadline(queued: Int) -> String {
        if harvest.isBulkVerifying { return "Mining and verifying the queue" }
        if harvest.isImporting { return "Importing recipes" }
        if queued > 0 { return "\(queued) recipe link\(queued == 1 ? "" : "s") ready" }
        return "Your review queue is clear"
    }

    private func queueFootnote(queued: Int) -> String {
        let saved = harvest.cachedMinedPageCount
        if queued > 0, saved > 0 { return "\(queued) ready · \(saved) mined pages saved" }
        if queued > 0 { return "\(queued) ready" }
        if saved > 0 { return "\(saved) mined pages saved" }
        return "Waiting for links"
    }

    private func queueSubheadline(queued: Int, domains: Int) -> String {
        if harvest.isBulkVerifying {
            return "Category pages are replaced by the recipe links found inside them."
        }
        if harvest.isImporting {
            return "\(harvest.importProgress.completed) of \(harvest.importProgress.total) processed"
        }
        if queued > 0 {
            return "From \(domains) source domain\(domains == 1 ? "" : "s") · edit only if needed"
        }
        return "Found, pasted, and dropped links appear here automatically."
    }

    private func importActionLabel(queued: Int) -> String {
        let count = harvest.settings.importBatchSize > 0
            ? min(queued, harvest.settings.importBatchSize)
            : queued
        if harvest.settings.verifyBeforeImport {
            return "Verify, Mine & Import \(count)"
        }
        return "Import \(count) Recipe\(count == 1 ? "" : "s")"
    }

    // MARK: - Step 4: finish and deliver

    @ViewBuilder
    private var finishFlowCard: some View {
        @Bindable var harvest = harvest
        let waiting = harvest.dashboard.needsReview
        let missing = harvest.imagelessCount
        MacCard(title: "4 · Finish & Deliver", systemImage: "checkmark.seal",
                footnote: finishFootnote(waiting: waiting, missing: missing)) {
            VStack(alignment: .leading, spacing: 9) {
                flowChecklistRow(
                    title: "Recipes imported",
                    detail: harvest.lastImportSummary ?? "Importing creates reviewable recipe drafts.",
                    complete: harvest.lastImportSummary != nil && !harvest.isImporting,
                    warning: false
                )
                flowChecklistRow(
                    title: "Images ready",
                    detail: harvest.recipes.isEmpty
                        ? "Waiting for imported recipes."
                        : (missing == 0 ? "Every imported recipe has an image." : "\(missing) still need an image."),
                    complete: missing == 0 && !harvest.recipes.isEmpty,
                    warning: missing > 0
                )
                flowChecklistRow(
                    title: "Kitchen approval",
                    detail: harvest.recipes.isEmpty
                        ? "Waiting for imported recipes."
                        : (waiting == 0 ? "Nothing is waiting for review." : "\(waiting) recipe\(waiting == 1 ? "" : "s") waiting in Harvest."),
                    complete: waiting == 0 && !harvest.recipes.isEmpty,
                    warning: waiting > 0
                )

                HStack(spacing: 7) {
                    if waiting > 0 {
                        Button("Review \(waiting) in Harvest") { navigation.section = .harvest }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    } else if missing > 0 {
                        Button("Fetch \(missing) Missing Image\(missing == 1 ? "" : "s")") {
                            harvest.fetchMissingImages()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(harvest.isImporting)
                    } else if !harvest.recipes.isEmpty {
                        Button("View Completed Recipes") { navigation.section = .harvest }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    if harvest.settings.cloudSyncEnabled, !harvest.approvedRecipes.isEmpty {
                        Button(harvest.isCloudSyncing ? "Syncing…" : "Sync Now") {
                            harvest.syncApprovedToCloud()
                        }
                        .disabled(harvest.isCloudSyncing)
                    }
                    Spacer(minLength: 0)
                }

                DisclosureGroup(isExpanded: $showFinishOptions) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Require an image before a recipe reaches the kitchen",
                               isOn: $harvest.settings.requireImageForImport)
                            .toggleStyle(.checkbox).font(.caption)
                        Toggle("Retry failed image downloads after each run",
                               isOn: $harvest.settings.autoFetchMissingImages)
                            .toggleStyle(.checkbox).font(.caption)
                        Toggle("Sync approved recipes to the Worker automatically",
                               isOn: $harvest.settings.cloudSyncEnabled)
                            .toggleStyle(.checkbox).font(.caption)
                        if let status = harvest.cloudSyncStatus {
                            Text(status)
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Delivery options", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
            }
        }
        .onChange(of: harvest.settings.requireImageForImport) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.autoFetchMissingImages) { harvest.scheduleSettingsSave() }
        .onChange(of: harvest.settings.cloudSyncEnabled) { harvest.scheduleSettingsSave() }
    }

    private func finishFootnote(waiting: Int, missing: Int) -> String {
        if waiting > 0 { return "\(waiting) to review" }
        if missing > 0 { return "\(missing) images missing" }
        if !harvest.recipes.isEmpty { return "Ready" }
        return "Waiting for import"
    }

    private func flowChecklistRow(
        title: String,
        detail: String,
        complete: Bool,
        warning: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: complete
                  ? "checkmark.circle.fill"
                  : (warning ? "exclamationmark.circle.fill" : "circle"))
                .font(.callout)
                .foregroundStyle(complete ? MacTheme.green : (warning ? Color.orange : .secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
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

    // MARK: - Right pane

    private var isIdle: Bool {
        !harvest.isDiscovering && !harvest.isImporting && !harvest.isBulkVerifying
    }

    @ViewBuilder
    private var activityPane: some View {
        // The in-app browser takes over the right pane when open — the page IS the
        // content, full height, exactly where the import buttons already are.
        if let address = inlineBrowser {
            MacBrowserPanel(address: address, onClose: { inlineBrowser = nil })
                .id(address)   // a new address gets a fresh panel, not a fought-over one
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    workflowProgressCard

                    if isIdle,
                       harvest.recipes.isEmpty,
                       harvest.sessionHistory.isEmpty,
                       harvest.discoveryReport == nil {
                        MacEmpty(
                            title: "Ready for a recipe run",
                            message: "Choose sources and categories, then start the flow. Stocked will find and mine links, review the queue, import recipes, and show exactly what still needs attention.",
                            systemImage: "arrow.forward.circle"
                        )
                        .frame(minHeight: 260)
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
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption2).foregroundStyle(MacTheme.green)
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
                                        Button("Add to Review Queue") { harvest.queue(report.confirmed) }
                                            .disabled(report.confirmed.isEmpty)
                                        if !report.unverified.isEmpty {
                                            Button("Check \(report.unverified.count) Remaining") {
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
                            MacCard(title: "Import complete", systemImage: "checkmark.circle.fill") {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2).foregroundStyle(MacTheme.green)
                                    Text(summary).font(.callout.weight(.medium))
                                }
                            }
                        }

                        if !harvest.lastFailures.isEmpty { failuresCard }

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showDiagnostics.toggle()
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text(showDiagnostics ? "Hide history & diagnostics" : "Show history & diagnostics")
                                Spacer(minLength: 0)
                                Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 4)
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
    }

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
        case .discover:
            return currentFlowPhase.rawValue > phase.rawValue
        case .review:
            return currentFlowPhase.rawValue > phase.rawValue
        case .importRecipes:
            return currentFlowPhase == .finish && harvest.lastImportSummary != nil
        case .finish:
            return currentFlowPhase == .finish
                && harvest.dashboard.needsReview == 0
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
                                .fill(phaseIsComplete(phase)
                                      ? MacTheme.green.opacity(0.65)
                                      : Color.secondary.opacity(0.20))
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 5)
                                .accessibilityHidden(true)
                        }
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: flowGuidanceIcon)
                        .foregroundStyle(currentFlowPhase == .finish ? MacTheme.green : MacTheme.gold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(flowGuidanceTitle).font(.callout.weight(.semibold))
                        Text(flowGuidanceDetail)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
                    .fill(complete
                          ? MacTheme.green
                          : (active ? MacTheme.gold : Color.secondary.opacity(0.14)))
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
        case .discover: return harvest.isDiscovering ? "Finding and mining recipes" : "Choose a source and start"
        case .review: return harvest.isBulkVerifying ? "Mining category pages" : "Review queue ready"
        case .importRecipes: return "Import in progress"
        case .finish: return harvest.dashboard.needsReview > 0 ? "Finish the review" : "Workflow complete"
        }
    }

    private var flowGuidanceDetail: String {
        switch currentFlowPhase {
        case .discover:
            return harvest.isDiscovering
                ? harvest.discoveryProgress.phase
                : "One run can discover, mine, verify, import, and approve automatically."
        case .review:
            return harvest.isBulkVerifying
                ? "Listings become recipe links; unrelated pages are removed."
                : "\(harvest.queuedURLCount) link\(harvest.queuedURLCount == 1 ? "" : "s") ready for the next step."
        case .importRecipes:
            return "\(harvest.importProgress.completed) of \(harvest.importProgress.total) processed"
        case .finish:
            let waiting = harvest.dashboard.needsReview
            return waiting > 0
                ? "\(waiting) recipe\(waiting == 1 ? "" : "s") need a final decision in Harvest."
                : "Imported recipes are approved and ready for Stocked."
        }
    }

    @ViewBuilder
    private var flowContextAction: some View {
        switch currentFlowPhase {
        case .discover:
            if harvest.isDiscovering {
                Button("Stop") { harvest.cancelDiscovery() }
                    .foregroundStyle(.red)
            }
        case .review:
            if harvest.isBulkVerifying {
                Button("Stop") { harvest.cancelBulkVerify() }
                    .foregroundStyle(.red)
            } else if harvest.queuedURLCount > 0 {
                Button(importActionLabel(queued: harvest.queuedURLCount)) {
                    harvest.importURLs()
                }
                .buttonStyle(.borderedProminent)
            }
        case .importRecipes:
            Button("Stop") { harvest.cancelImport() }
                .foregroundStyle(.red)
        case .finish:
            if harvest.dashboard.needsReview > 0 {
                Button("Open Harvest") { navigation.section = .harvest }
                    .buttonStyle(.borderedProminent)
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
                // The shape of the problem before the list of it: reasons, counted.
                let grouped = Dictionary(grouping: harvest.lastFailures) {
                    $0.reason.components(separatedBy: " | ").first ?? $0.reason
                }
                .map { (reason: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
                ForEach(grouped.prefix(3), id: \.reason) { item in
                    HStack(spacing: 6) {
                        Text("\(item.count)×")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(item.reason)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                            // The first engine's verdict is the story; the pipe-chain
                            // of every fallback's echo is noise.
                            Text(failure.reason.components(separatedBy: " | ").first ?? failure.reason)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                .help(failure.reason)
                        }
                        Spacer(minLength: 0)
                        Button("View") {
                            inlineBrowser = failure.url
                        }
                        .buttonStyle(.borderless).font(.caption)
                        .help("Open this page right here and import it by hand")
                        Button("Retry") { harvest.retryFailure(failure) }
                            .buttonStyle(.borderless).font(.caption)
                            .disabled(harvest.isImporting)
                        if harvest.pythonWorkerAvailable {
                            Button("Python") { harvest.retryFailureWithPython(failure) }
                                .buttonStyle(.borderless).font(.caption)
                                .disabled(harvest.isImporting)
                                .help("Retry with the bundled Python parser first")
                        }
                    }
                }
                if harvest.lastFailures.count > 10 {
                    Text("…and \(harvest.lastFailures.count - 10) more.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Retry all") { harvest.retryFailures() }
                        .disabled(harvest.isImporting)
                    if harvest.pythonWorkerAvailable {
                        Button("Retry with Python") { harvest.retryFailuresWithPython() }
                            .disabled(harvest.isImporting)
                    }
                    Menu("Copy") {
                        Button("Failed URLs") { harvest.copyFailedURLs() }
                        Button("Full diagnostics") { harvest.copyFailureDiagnostics() }
                    }
                    .menuStyle(.borderlessButton)
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
                    HStack(spacing: 8) {
                        Picker("Activity filter", selection: $logScope) {
                            ForEach(LogScope.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 250)
                        Spacer(minLength: 0)
                        Button("Copy") { copyVisibleLogs() }
                            .buttonStyle(.borderless).font(.caption)
                        Button("Clear") { harvest.clearLogs() }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    Divider()
                    ForEach(visibleLogs.prefix(14)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(logTint(entry.level))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(entry.level == .error ? .red : .secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Text(entry.timestamp, style: .relative)
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    if visibleLogs.isEmpty {
                        Text("No activity matches this filter.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var visibleLogs: [CrawlLogEntry] {
        switch logScope {
        case .all:
            return harvest.logs
        case .problems:
            return harvest.logs.filter { $0.level == .warning || $0.level == .error }
        case .success:
            return harvest.logs.filter { $0.level == .success }
        }
    }

    private func copyVisibleLogs() {
        let value = visibleLogs.prefix(100).map { entry in
            "[\(entry.level.rawValue.uppercased())] \(entry.message)"
        }.joined(separator: "\n")
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
                    if !recent.isEmpty && search.isEmpty {
                        group("Recent", recent)
                    }
                    if !favorites.isEmpty {
                        group("Favorites", favorites)
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
                if !favorites.isEmpty {
                    Button("Favorites") { selected.formUnion(scoped(favorites).map(\.id)) }
                        .font(.caption)
                }
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
        let shown = scoped(sources).sorted {
            if healthRank($0.health) != healthRank($1.health) {
                return healthRank($0.health) < healthRank($1.health)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        if !shown.isEmpty {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(shown.allSatisfy { selected.contains($0.id) } ? "None" : "All") {
                    let ids = shown.map(\.id)
                    if shown.allSatisfy({ selected.contains($0.id) }) {
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

            ForEach(shown) { source in
                HStack(spacing: 6) {
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
                        healthDot(source.health).help(healthLabel(source.health))
                        Text(source.name).font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                        if cachedIDs.contains(source.id) {
                            Image(systemName: "externaldrive.fill")
                                .font(.caption2)
                                .foregroundStyle(MacTheme.green)
                                .help("Saved results available; this website can be skipped")
                        }
                        Text(source.domains.first ?? "")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(selected.contains(source.id) ? "Deselect" : "Select") \(source.name), \(healthLabel(source.health))")
                    Button {
                        toggleFavorite(source.id)
                    } label: {
                        Image(systemName: favoriteIDs.contains(source.id) ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(favoriteIDs.contains(source.id) ? MacTheme.gold : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(favoriteIDs.contains(source.id) ? "Remove from favorites" : "Add to favorites")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
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
        if let index = favoriteIDs.firstIndex(of: id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(id)
        }
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
                Image(systemName: "magnifyingglass")
                    .font(.caption2).foregroundStyle(.secondary)
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
                            .frame(maxWidth: .infinity)
                            .padding(.top, 44)
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
                    let visible = RecipeBrowseTaxonomy.groupOrder
                        .flatMap { shownCategories(in: $0).map(\.id) }
                    updateSelection(selected.union(visible))
                }
                Button("None") { selectedIDs.removeAll() }
                    .disabled(selectedIDs.isEmpty)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(10)
        }
    }

    @ViewBuilder
    private func categoryGroup(_ group: String) -> some View {
        let shown = shownCategories(in: group)
        if !shown.isEmpty {
            HStack(spacing: 6) {
                Text(group)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(shown.allSatisfy { selected.contains($0.id) } ? "None" : "All") {
                    let ids = Set(shown.map(\.id))
                    if shown.allSatisfy({ selected.contains($0.id) }) {
                        updateSelection(selected.subtracting(ids))
                    } else {
                        updateSelection(selected.union(ids))
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 2)

            ForEach(shown) { category in
                Button {
                    var next = selected
                    if next.contains(category.id) {
                        next.remove(category.id)
                    } else {
                        next.insert(category.id)
                    }
                    updateSelection(next)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selected.contains(category.id)
                              ? "checkmark.square.fill" : "square")
                            .font(.callout)
                            .foregroundStyle(selected.contains(category.id) ? MacTheme.gold : .secondary)
                        Text(category.name).font(.callout)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
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
