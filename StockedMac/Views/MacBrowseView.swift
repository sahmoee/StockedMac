import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Vision

struct MacBrowseView: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacKitchenStore.self) private var store

    private enum Pane: String, CaseIterable, Identifiable {
        case find, review
        var id: String { rawValue }
    }
    @State private var pane: Pane = .find

    // ── Find state ────────────────────────────────────────────────────────
    @State private var sourceSearch = ""
    @State private var selectedSourceIDs: Set<String> = []
    @State private var showSourcePicker = false
    @State private var showCategoryPicker = false
    @State private var inlineBrowser: String? = nil
    @State private var directURL = ""
    @State private var manualRecipeText = ""
    @State private var manualImportStatus: String?
    @State private var foundSearch = ""
    @State private var foundSort: FoundSort = .title

    private enum FoundSort: String, CaseIterable, Identifiable {
        case title = "Title", source = "Source"
        var id: String { rawValue }
    }

    // ── Review state ──────────────────────────────────────────────────────
    @State private var reviewSearch = ""
    @State private var reviewFilter: ReviewState? = nil
    @State private var onlyImageless = false
    @State private var onlyNeedsAttention = false
    @State private var reviewSort: ReviewSort = .newest
    @State private var addStatus: String? = nil

    private enum ReviewSort: String, CaseIterable, Identifiable {
        case newest = "Newest", confidence = "Confidence", title = "Title", source = "Source"
        var id: String { rawValue }
    }

    // MARK: - Source grouping

    private var browsableSources: [SourceProfile] {
        harvest.sources.filter {
            $0.enabled && $0.discoveryEnabled && $0.discoveryMode.supportsDiscovery
                && $0.health != .blocked && $0.health != .paused
        }
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
                .help("Browse any site and import the page you're looking at")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { harvest.togglePause() } label: {
                    Label(harvest.isPaused ? "Resume" : "Pause",
                          systemImage: harvest.isPaused ? "play.fill" : "pause.fill")
                }
                .help("Pause or resume downloads")
            }
        }
        .onAppear {
            guard selectedSourceIDs.isEmpty else { return }
            let valid = Set(browsableSources.map(\.id))
            selectedSourceIDs = Set(harvest.settings.lastSelectedSourceIDs).intersection(valid)
        }
        .onChange(of: selectedSourceIDs) {
            harvest.settings.lastSelectedSourceIDs = Array(selectedSourceIDs).sorted()
            harvest.scheduleSettingsSave()
        }
        .onChange(of: browsableSources.map(\.id)) {
            selectedSourceIDs.formIntersection(Set(browsableSources.map(\.id)))
        }
        .onChange(of: harvest.importText) { harvest.persistImportQueue() }
    }

    // MARK: - Pane switcher

    private var reviewWaiting: Int {
        harvest.recipes.filter { $0.reviewState == .needsReview }.count
    }

    private var paneSwitcher: some View {
        HStack(spacing: 12) {
            Picker("Pane", selection: $pane) {
                Text("Find & Import").tag(Pane.find)
                Text(reviewWaiting > 0 ? "Review · \(reviewWaiting)" : "Review").tag(Pane.review)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            Spacer(minLength: 0)
            Text(paneContextSummary)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var paneContextSummary: String {
        if harvest.isDiscovering { return "Finding recipes…" }
        if harvest.isImporting {
            return "Importing \(harvest.importProgress.completed)/\(harvest.importProgress.total)…"
        }
        switch pane {
        case .find:
            let q = harvest.queuedURLCount
            return q > 0 ? "\(q) queued · \(reviewWaiting) to review" : "\(reviewWaiting) to review"
        case .review:
            return "\(harvest.recipes.count) imported · \(harvest.dashboard.approved) approved"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let address = inlineBrowser {
            MacBrowserPanel(address: address, onClose: { inlineBrowser = nil })
                .id(address)
        } else {
            switch pane {
            case .find:   findPane
            case .review: reviewPane
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

    // MARK: - FIND PANE

    private var findPane: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    quickStartCard
                    directImportCard
                    sourceCard
                    if harvest.queuedURLCount > 0 || harvest.isImporting {
                        queueImportCard
                    }
                }
                .padding(14)
            }
            .frame(width: 350)

            Divider()

            resultsPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var quickStartCard: some View {
        MacCard(title: "Add recipes without the hunt", systemImage: "bolt.fill") {
            VStack(alignment: .leading, spacing: 7) {
                workflowStep(1, "Choose sources and press Find Recipes.")
                workflowStep(2, "Found recipes import automatically in finite batches.")
                workflowStep(3, "Complete recipes approve and sync to Stocked iOS automatically.")
                Text("Website discovery is optional and limited to a small source batch. It never runs endlessly in the background from this screen.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func workflowStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(number)").font(.caption2.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(MacTheme.gold, in: Circle())
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var directImportCard: some View {
        MacCard(title: "Quick import", systemImage: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fastest: paste the page that contains the recipe.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Recipe URL", text: $directURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(importDirectURL)
                HStack(spacing: 6) {
                    Button("Import Recipe", action: importDirectURL)
                        .buttonStyle(.borderedProminent)
                        .disabled(directURL.nilIfBlank == nil || harvest.isImporting)
                    Button("Paste") {
                        if let value = NSPasteboard.general.string(forType: .string) { directURL = value }
                    }
                    Spacer()
                }.buttonStyle(.borderless).font(.caption)
                Divider()
                Text("Or paste the recipe itself. Stocked structures ingredients and steps for review.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $manualRecipeText).font(.caption).frame(minHeight: 72)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2)))
                HStack(spacing: 6) {
                    Button("Create from Text") {
                        harvest.importRecipeText(manualRecipeText)
                        manualRecipeText = ""
                        pane = .review
                    }.disabled(manualRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Read Screenshots…", action: importImages)
                    Spacer()
                }.font(.caption)
                HStack(spacing: 6) {
                    Button("Import Link Files…", action: importLinkFiles)
                        .help("Import recipe links from bookmarks, .webloc, HTML, CSV, or text files")
                    Button("Scan Recipe QR…", action: importRecipeQRCodes)
                        .help("Read recipe web addresses from QR-code images")
                    Spacer()
                }.font(.caption)
                if let manualImportStatus { Text(manualImportStatus).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private func importDirectURL() {
        var value = directURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://"), value.contains(".") { value = "https://" + value }
        guard !value.isEmpty else { return }
        harvest.importDirect([value])
        directURL = ""
        manualImportStatus = "Importing one recipe for review…"
    }

    private func importImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        manualImportStatus = "Reading \(panel.urls.count) image\(panel.urls.count == 1 ? "" : "s")…"
        let urls = panel.urls
        Task {
            var pages: [String] = []
            for url in urls {
                guard let image = NSImage(contentsOf: url),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let text = await recognizeText(cg)
                if !text.isEmpty { pages.append(text) }
            }
            let merged = MacRecipeTextParser.mergePages(pages)
            guard !merged.isEmpty else { manualImportStatus = "No readable recipe text found."; return }
            harvest.importRecipeText(merged, sourceLabel: urls.count == 1 ? "Screenshot" : "\(urls.count) screenshots")
            manualImportStatus = "Imported for review."
            pane = .review
        }
    }

    /// Bulk migration path for browser exports, bookmark collections, URL lists, and
    /// Finder .webloc shortcuts. All extracted links still pass through the normal
    /// recipe verifier, image requirement, duplicate handling, and finite batch limits.
    private func importLinkFiles() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.html, .plainText, .commaSeparatedText]
        if let webloc = UTType(filenameExtension: "webloc") { types.append(webloc) }
        if let urlType = UTType(filenameExtension: "url") { types.append(urlType) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.message = "Choose bookmark exports, URL lists, or .webloc recipe shortcuts."
        guard panel.runModal() == .OK else { return }

        let links = panel.urls.flatMap(Self.recipeLinks(in:)).cleanedUnique()
        guard !links.isEmpty else {
            manualImportStatus = "No HTTP or HTTPS links were found in those files."
            return
        }
        harvest.importDirect(links)
        manualImportStatus = "Found \(links.count) unique link\(links.count == 1 ? "" : "s"); importing the first finite batch and queuing the rest."
    }

    private static func recipeLinks(in file: URL) -> [String] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        if file.pathExtension.lowercased() == "webloc",
           let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = value as? [String: Any], let url = dict["URL"] as? String {
            return [url]
        }
        guard var text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return [] }
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.matches(#"https?://[^\s\"'<>\)\]]+"#, group: 0)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",;")) }
    }

    /// Camera-roll, screenshot, printed-card, and packaging path: decode one or many QR
    /// images and feed their web addresses into the exact same bounded importer.
    private func importRecipeQRCodes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose images containing recipe QR codes."
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        manualImportStatus = "Scanning \(files.count) image\(files.count == 1 ? "" : "s") for recipe QR codes…"
        Task {
            var links: [String] = []
            for file in files {
                guard let image = NSImage(contentsOf: file),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                links.append(contentsOf: await Self.qrLinks(in: cg))
            }
            links = links.cleanedUnique()
            guard !links.isEmpty else {
                manualImportStatus = "No recipe web address was found in those QR codes."
                return
            }
            harvest.importDirect(links)
            manualImportStatus = "Found \(links.count) QR recipe link\(links.count == 1 ? "" : "s") and started importing."
        }
    }

    private static func qrLinks(in image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let links = (request.results as? [VNBarcodeObservation])?.compactMap(\.payloadStringValue)
                    .filter { value in
                        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
                        return (scheme == "http" || scheme == "https") && url.host != nil
                    } ?? []
                continuation.resume(returning: links)
            }
            request.symbologies = [.qr]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: image).perform([request]) }
                catch { continuation.resume(returning: []) }
            }
        }
    }

    private func recognizeText(_ image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: image).perform([request])
            }
        }
    }

    // MARK: Source card

    private var sourceCard: some View {
        @Bindable var harvest = harvest
        return MacCard(title: "Explore websites (optional)", systemImage: "sparkle.magnifyingglass",
                footnote: "\(browsableSources.count) sources") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Use this only when you do not already have a recipe. Pick up to five trusted sites; Stocked returns confirmed recipe pages and stops.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { showSourcePicker.toggle() } label: {
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

                Button { showCategoryPicker.toggle() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundStyle(harvest.settings.selectedBrowseCategoryIDs.isEmpty ? Color.secondary : MacTheme.gold)
                        Text(categorySelectionLabel).font(.callout).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showCategoryPicker, arrowEdge: .bottom) {
                    RecipeCategoryMultiPicker(selection: Binding(
                        get: { Set(harvest.settings.selectedBrowseCategoryIDs) },
                        set: { selected in
                            harvest.settings.selectedBrowseCategoryIDs = Array(selected).sorted()
                            harvest.applyCategoryFilterToCurrentReport()
                            harvest.scheduleSettingsSave()
                        }
                    ))
                }

                findButtonRow

                Stepper(value: Binding(
                    get: { harvest.settings.scanLimit },
                    set: { harvest.settings.scanLimit = $0; harvest.scheduleSettingsSave() }
                ), in: 5...500, step: 5) {
                    Text("Scan up to \(harvest.settings.scanLimit) recipes")
                        .font(.caption)
                }

                if selectedSources.count > 5 {
                    Label("Only the first 5 selected sources will be checked in this pass.", systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.orange)
                }

                if let source = selectedSources.first,
                   let summary = harvest.cacheSummary(for: source.id) {
                    HStack(spacing: 5) {
                        Image(systemName: "externaldrive.fill")
                            .font(.caption2).foregroundStyle(MacTheme.green)
                        Text("\(summary.resultCount) saved · \(summary.savedAt, style: .relative) ago")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { startFind(forceRefresh: true) } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless).font(.caption2)
                        .disabled(harvest.isDiscovering)
                        .help("Re-read the website and replace saved results")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var findButtonRow: some View {
        HStack(spacing: 8) {
            if harvest.isDiscovering {
                Button("Stop") { harvest.cancelDiscovery() }
                    .buttonStyle(.borderedProminent).controlSize(.large).tint(.red)
                ProgressView().controlSize(.small)
                Text(harvest.discoveryProgress.phase)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Button(findButtonLabel) { startFind() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(browsableSources.isEmpty)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func startFind(forceRefresh: Bool = false) {
        let preferred = selectedSources.isEmpty ? defaultDiscoverySources : selectedSources
        let sources = Array(preferred.prefix(5))
        guard !sources.isEmpty else { return }
        if forceRefresh, sources.count == 1, let source = sources.first {
            harvest.discover(source, forceRefresh: true, queueResults: false)
        } else {
            harvest.startAutopilot(sourceIDs: sources.map(\.id))
        }
    }

    private var defaultDiscoverySources: [SourceProfile] {
        let favorite = browsableSources.filter { harvest.settings.favoriteSourceIDs.contains($0.id) }
        let recentIDs = Set(harvest.recentSources.map(\.id))
        if let first = favorite.first ?? browsableSources.first(where: { recentIDs.contains($0.id) }) ?? browsableSources.first {
            return [first]
        }
        return []
    }

    private var findButtonLabel: String {
        switch selectedSources.count {
        case 0: return "Find a Small Batch"
        case 1:
            let hasCache = harvest.cacheSummary(for: selectedSources[0].id) != nil
                && harvest.settings.reuseCachedDiscoveryResults
            return hasCache ? "Use Saved Results" : "Find Recipes"
        default: return "Find from \(min(5, selectedSources.count)) Sources"
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

    private var categorySelectionLabel: String {
        let selected = harvest.settings.selectedBrowseCategoryIDs.compactMap { RecipeBrowseTaxonomy.byID[$0]?.name }
        if selected.isEmpty { return "All recipe categories" }
        if selected.count == 1 { return selected[0] }
        return "\(selected[0]) + \(selected.count - 1) more"
    }

    // MARK: Queue / import card

    private var queueImportCard: some View {
        MacCard(title: "Import queue", systemImage: "arrow.right.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if harvest.isImporting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.8)
                        Text("Importing \(harvest.importProgress.completed)/\(harvest.importProgress.total)")
                            .font(.callout.weight(.semibold))
                        Spacer(minLength: 0)
                        Button("Stop") { harvest.cancelImport() }
                            .buttonStyle(.borderless).foregroundStyle(.red)
                    }
                    .font(.callout)
                } else {
                    Stepper(value: Binding(
                        get: { harvest.settings.importBatchSize },
                        set: { harvest.settings.importBatchSize = $0; harvest.scheduleSettingsSave() }
                    ), in: 1...200, step: 5) {
                        Text("Import \(harvest.settings.importBatchSize) per batch")
                            .font(.caption)
                    }
                    HStack(spacing: 6) {
                        let count = min(harvest.queuedURLCount, harvest.settings.importBatchSize)
                        Button("Import \(count)") { harvest.importURLs() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Spacer(minLength: 0)
                        Button { harvest.clearQueue() } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .help("Clear the import queue")
                    }
                    .font(.callout)
                    Text("\(harvest.queuedURLCount) recipe URL\(harvest.queuedURLCount == 1 ? "" : "s") queued")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Results panel

    @ViewBuilder
    private var resultsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if harvest.isDiscovering {
                    browsingProgressCard
                } else if let failure = harvest.discoveryFailure {
                    browseFailureCard(failure)
                } else if let report = harvest.discoveryReport {
                    foundRecipesCard(report)
                }

                if harvest.isImporting {
                    importProgressCard
                } else if let summary = harvest.lastImportSummary {
                    importCompleteCard(summary)
                    if !harvest.lastFailures.isEmpty {
                        failuresCard
                    }
                }

                if !harvest.isDiscovering
                    && !harvest.isImporting
                    && harvest.discoveryReport == nil
                    && harvest.discoveryFailure == nil
                    && harvest.lastImportSummary == nil {
                    MacEmpty(
                        title: "Ready to find recipes",
                        message: "Choose a source on the left and press Find Recipes. Confirmed recipes import, approve when complete, and sync automatically.",
                        systemImage: "arrow.forward.circle"
                    )
                    .frame(minHeight: 240)
                }
            }
            .padding(16)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    // MARK: Browsing progress card

    private var browsingProgressCard: some View {
        MacCard(title: "Finding recipes", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(harvest.discoveryProgress.phase).font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Button("Stop") { harvest.cancelDiscovery() }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                }
                if let url = harvest.discoveryProgress.currentURL {
                    Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                let fetched = harvest.discoveryProgress.pagesFetched
                let queued = harvest.discoveryProgress.queued
                ProgressView(value: Double(fetched), total: Double(max(1, fetched + queued)))
                    .progressViewStyle(.linear)
                HStack(spacing: 12) {
                    Label("\(fetched) pages read", systemImage: "doc.plaintext")
                    Label("\(harvest.discoveryProgress.confirmed) recipes found", systemImage: "fork.knife")
                        .foregroundStyle(MacTheme.green)
                    Spacer(minLength: 0)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Browse failure card

    private func browseFailureCard(_ message: String) -> some View {
        MacCard(title: "Browse failed", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Retry") { harvest.clearPauseAndRetry() }
                    Button("Dismiss") { harvest.discoveryFailure = nil }
                }
                .font(.caption).buttonStyle(.borderless)
            }
        }
    }

    // MARK: Found recipes card (selectable list)

    private func foundRecipesCard(_ report: DiscoveryReport) -> some View {
        MacCard(title: "Found — \(report.sourceName)", systemImage: "checkmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(report.notes.prefix(2), id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let links = visibleFoundLinks(report.confirmed)
                if links.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No recipe pages confirmed. The source may use a different structure — try a different source.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !report.unverified.isEmpty {
                            Button("Check \(report.unverified.count) remaining candidates") {
                                harvest.verifyRemaining()
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("\(links.count) recipe\(links.count == 1 ? "" : "s") found")
                            .font(.callout.weight(.semibold))
                        if report.confirmed.count > links.count && foundSearch.isEmpty {
                            Text("showing first \(links.count)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Label("Automatically importing", systemImage: "arrow.down.circle.fill")
                            .font(.caption).foregroundStyle(MacTheme.green)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                        TextField("Filter found recipes", text: $foundSearch).textFieldStyle(.roundedBorder)
                        Picker("Sort", selection: $foundSort) {
                            ForEach(FoundSort.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 90)
                        if !foundSearch.isEmpty {
                            Button { foundSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.borderless)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(links, id: \.url) { link in
                            foundRecipeRow(link)
                            if link.url != links.last?.url {
                                Divider().padding(.leading, 28)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Text("No queue or review step is required for complete recipes.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)

                        if !report.unverified.isEmpty {
                            Button("Check \(report.unverified.count) more") { harvest.verifyRemaining() }
                                .buttonStyle(.borderless).font(.caption)
                        }
                        Button("Dismiss") { harvest.discoveryReport = nil }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func visibleFoundLinks(_ links: [DiscoveredLink]) -> [DiscoveredLink] {
        let query = foundSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = query.isEmpty ? links : links.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) ||
            $0.url.localizedCaseInsensitiveContains(query)
        }
        switch foundSort {
        case .title:
            result.sort { ($0.title ?? $0.url).localizedCaseInsensitiveCompare($1.title ?? $1.url) == .orderedAscending }
        case .source:
            result.sort { (URL(string: $0.url)?.host ?? "").localizedCaseInsensitiveCompare(URL(string: $1.url)?.host ?? "") == .orderedAscending }
        }
        // Keep discovery useful and finite. A source can expose thousands of archive
        // URLs; showing a focused batch prevents Browse from becoming another mine.
        return Array(result.prefix(max(1, harvest.settings.scanLimit)))
    }

    private func foundRecipeRow(_ link: DiscoveredLink) -> some View {
        return HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.callout).foregroundStyle(MacTheme.green)

            VStack(alignment: .leading, spacing: 1) {
                let displayTitle: String = {
                    if let t = link.title, !t.isEmpty { return t }
                    if let comp = URL(string: link.url)?.lastPathComponent, !comp.isEmpty {
                        return comp.replacingOccurrences(of: "-", with: " ")
                    }
                    return link.url
                }()
                Text(displayTitle).font(.callout).lineLimit(1)
                Text(URL(string: link.url)?.host ?? link.url)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { inlineBrowser = link.url } label: {
                Image(systemName: "safari").font(.caption2)
            }
            .buttonStyle(.borderless).help("Preview in built-in browser")
        }
        .padding(.vertical, 5)
    }

    // MARK: Import progress card

    private var importProgressCard: some View {
        MacCard(title: "Importing", systemImage: "square.and.arrow.down") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("\(harvest.importProgress.completed) of \(harvest.importProgress.total)")
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Button("Stop") { harvest.cancelImport() }
                        .buttonStyle(.borderless).foregroundStyle(.red).font(.caption)
                }
                if let url = harvest.importProgress.currentURL {
                    Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ProgressView(
                    value: Double(harvest.importProgress.completed),
                    total: Double(max(1, harvest.importProgress.total))
                )
                .progressViewStyle(.linear)
            }
        }
    }

    // MARK: Import complete card

    private func importCompleteCard(_ summary: String) -> some View {
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

    // MARK: Failures card

    private var failuresCard: some View {
        MacCard(title: "Import failures", systemImage: "exclamationmark.triangle",
                footnote: "\(harvest.lastFailures.count)") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(harvest.lastFailures.suffix(8)) { failure in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(URL(string: failure.url)?.lastPathComponent.nilIfBlank ?? failure.url)
                                .font(.caption.weight(.medium)).lineLimit(1)
                            Text(failure.reason.components(separatedBy: " | ").first ?? failure.reason)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                .help(failure.reason)
                        }
                        Spacer(minLength: 0)
                        Button("View") { inlineBrowser = failure.url }
                            .buttonStyle(.borderless).font(.caption)
                        Button("Retry") { harvest.retryFailure(failure) }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
                if harvest.lastFailures.count > 8 {
                    Text("…and \(harvest.lastFailures.count - 8) more.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button("Retry all") { harvest.retryFailures() }
                    Button("Clear") { harvest.clearFailures() }.foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.caption).buttonStyle(.borderless)
            }
        }
    }

    // MARK: - REVIEW PANE

    private var reviewVisible: [RecipeDraft] {
        var items = harvest.recipes
        if let f = reviewFilter { items = items.filter { $0.reviewState == f } }
        if onlyImageless { items = items.filter { !($0.image?.hasLocalFile ?? false) } }
        if onlyNeedsAttention { items = items.filter { !$0.warnings.isEmpty || !$0.exportProblems.isEmpty || $0.confidence < 0.75 } }
        let q = reviewSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q) || $0.source.host.lowercased().contains(q)
            }
        }
        switch reviewSort {
        case .newest: items.sort { $0.updatedAt > $1.updatedAt }
        case .confidence: items.sort { $0.confidence < $1.confidence }
        case .title: items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .source: items.sort { $0.source.host.localizedCaseInsensitiveCompare($1.source.host) == .orderedAscending }
        }
        return items
    }

    private var reviewPane: some View {
        @Bindable var harvest = harvest
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                deliveryBanner
                Divider()
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

    private var readyToSend: [RecipeDraft] {
        harvest.recipes.filter {
            $0.reviewState == .needsReview && $0.standards.requiredPassed && ($0.image?.hasLocalFile ?? false)
        }
    }

    private var deliveryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title3).foregroundStyle(MacTheme.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Approve & Send to Stocked").font(.callout.weight(.semibold))
                Text("Approval adds the recipe to the Mac library and Stocked iOS after its required image is saved.")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if !readyToSend.isEmpty {
                Button("Send \(readyToSend.count) Ready") {
                    harvest.setReviewState(.approved, for: Set(readyToSend.map(\.id)))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(MacTheme.green.opacity(0.07))
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
            Button { onlyNeedsAttention.toggle() } label: {
                Image(systemName: onlyNeedsAttention ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
            }
            .buttonStyle(.borderless).foregroundStyle(onlyNeedsAttention ? .orange : .secondary)
            .help("Show only recipes with warnings, missing fields, or low confidence")
            Menu {
                Picker("Sort recipes", selection: $reviewSort) {
                    ForEach(ReviewSort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down.circle") }
            .menuStyle(.borderlessButton).frame(width: 24)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    @ViewBuilder
    private var reviewBulkBar: some View {
        let shown = reviewVisible
        let reviewable = shown.filter {
            $0.reviewState == .needsReview && $0.standards.requiredPassed && ($0.image?.hasLocalFile ?? false)
        }
        if shown.count > 1 {
            HStack(spacing: 6) {
                Text("\(shown.count) shown").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !reviewable.isEmpty {
                    Button("Approve & Send \(reviewable.count)") {
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
                            if !draft.warnings.isEmpty || !draft.exportProblems.isEmpty {
                                Text("needs attention")
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
                    Button("Approve & Send to Stocked") { harvest.setReviewState(.approved, for: [draft.id]) }
                        .disabled(!draft.standards.requiredPassed || !(draft.image?.hasLocalFile ?? false))
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
}

private struct RecipeCategoryMultiPicker: View {
    @Binding var selection: Set<String>
    @State private var search = ""

    private var visibleGroups: [(String, [RecipeBrowseCategory])] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecipeBrowseTaxonomy.groupOrder.compactMap { group in
            let values = RecipeBrowseTaxonomy.categories(in: group).filter {
                query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
            }
            return values.isEmpty ? nil : (group, values)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Birthday, drinks, holiday, cuisine…", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleGroups, id: \.0) { group, values in
                        Text(group).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.top, 8)
                        ForEach(values) { category in
                            Button {
                                if selection.contains(category.id) { selection.remove(category.id) }
                                else { selection.insert(category.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selection.contains(category.id) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(selection.contains(category.id) ? MacTheme.gold : .secondary)
                                    Text(category.name).foregroundStyle(.primary)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider()
            HStack {
                Text("\(selection.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { selection.removeAll() }.disabled(selection.isEmpty)
            }
            .buttonStyle(.borderless).padding(10)
        }
        .frame(width: 360, height: 440)
    }
}

// MARK: - Multi-select source picker

/// The checklist behind the sources dropdown: search, group headers with select-all,
/// health dots, and a running count. Selection lives in the parent so the action
/// buttons can follow it.
private struct SourceMultiPicker: View {
    @Environment(HarvestModel.self) private var harvest
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
    @State private var categoryScope: String?
    @State private var editingSource: SourceProfile?
    @State private var deletingSources: [SourceProfile] = []

    private var sourceCategories: [String] {
        catalog.flatMap(\.tags).cleanedUnique().sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

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
                Menu {
                    Button("All categories") { categoryScope = nil }
                    Divider()
                    ForEach(sourceCategories, id: \.self) { category in
                        Button {
                            categoryScope = category
                        } label: {
                            if categoryScope == category { Label(category, systemImage: "checkmark") }
                            else { Text(category) }
                        }
                    }
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(categoryScope == nil ? Color.secondary : MacTheme.gold)
                }
                .menuStyle(.borderlessButton)
                .help(categoryScope ?? "Filter sources by category")
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

            if !selected.isEmpty {
                Divider()
                Button(role: .destructive) {
                    deletingSources = catalog.filter { selected.contains($0.id) }
                } label: {
                    Label("Delete recipes from selected sources…", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
        }
        .popover(item: $editingSource) { source in
            SourceCategoryEditor(source: source) { updated in
                harvest.updateSource(updated)
                editingSource = nil
            }
        }
        .alert("Delete recipes from sources?", isPresented: Binding(
            get: { !deletingSources.isEmpty },
            set: { if !$0 { deletingSources = [] } }
        )) {
            Button("Cancel", role: .cancel) { deletingSources = [] }
            Button("Delete Everywhere", role: .destructive) {
                let ids = Set(deletingSources.map(\.id))
                deletingSources = []
                harvest.deleteRecipes(from: ids)
            }
        } message: {
            let plan = harvest.sourceRecipeDeletionPlan(sourceIDs: Set(deletingSources.map(\.id)))
            Text("This removes \(plan.recipeCount) recipe\(plan.recipeCount == 1 ? "" : "s") from the Mac library, shared Stocked library, and Cloudflare cache. It also clears \(plan.queuedURLCount) queued link\(plan.queuedURLCount == 1 ? "" : "s"). This cannot be undone.")
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
                .contextMenu {
                    Button("Edit categories…") { editingSource = source }
                    Button("Delete recipes from this source…", role: .destructive) { deletingSources = [source] }
                    if !source.tags.isEmpty {
                        Divider()
                        ForEach(source.tags, id: \.self) { category in
                            Button("Show \(category)") { categoryScope = category }
                        }
                    }
                }
            }
        }
    }

    private func scoped(_ sources: [SourceProfile]) -> [SourceProfile] {
        sources.filter { source in
            let healthMatches: Bool = switch healthScope {
            case .available: source.health != .blocked && source.health != .paused
            case .healthy: source.health == .healthy
            case .attention: source.health == .limited || source.health == .paused || source.health == .blocked
            case .all: true
            }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatches = query.isEmpty || ([source.name, source.baseURL] + source.domains + source.tags)
                .contains { $0.localizedCaseInsensitiveContains(query) }
            let categoryMatches = categoryScope == nil || source.tags.contains {
                $0.caseInsensitiveCompare(categoryScope ?? "") == .orderedSame
            }
            return healthMatches && searchMatches && categoryMatches
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

private struct SourceCategoryEditor: View {
    let source: SourceProfile
    let onSave: (SourceProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(source: SourceProfile, onSave: @escaping (SourceProfile) -> Void) {
        self.source = source
        self.onSave = onSave
        _text = State(initialValue: source.tags.joined(separator: ", "))
    }

    private var categories: [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .cleanedUnique()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categorize \(source.name)").font(.headline)
            Text("Use commas or new lines. A source can belong to multiple categories.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.callout)
                .frame(width: 320, height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
            Text("\(categories.count) categor\(categories.count == 1 ? "y" : "ies")")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Clear") { text = "" }.disabled(categories.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var updated = source
                    updated.tags = categories
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
