import AppKit
import Foundation
import Observation

private nonisolated struct ImportOutcome: Sendable {
    var url: String
    var detail: ImportOutcomeDetail?
    var error: String?
}

@MainActor
@Observable
final class HarvestModel {

    // MARK: - Observable state

    var recipes: [RecipeDraft] = []
    var sources: [SourceProfile] = []
    var logs: [CrawlLogEntry] = []
    var settings: AppSettings = .defaults
    var importText = ""
    var importProgress: ImportProgress = .idle
    var discoveryProgress: DiscoveryProgress = .idle
    var discoveryReport: DiscoveryReport?
    /// Why the last browse run failed, shown inline in the Browse screen
    /// instead of a modal alert.
    var discoveryFailure: String?
    var isImporting = false
    var isDiscovering = false
    var selectedRecipeID: UUID?
    var selectedRecipeIDs: Set<UUID> = []
    var selectedSourceID: String?
    var duplicateGroups: [[RecipeDraft]] = []
    var errorMessage: String?
    var statusMessage = "Ready"
    var pythonWorkerAvailable = false
    var storageWarning: String?

    let paths: AppPaths

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var settingsSaveTask: Task<Void, Never>?
    /// Recipes that qualified for automatic approval during the current run.
    @ObservationIgnored private var pendingAutoApproval: Set<UUID> = []
    /// URLs that failed this run and are eligible for one retry.
    @ObservationIgnored private var retryQueue: [String] = []
    @ObservationIgnored private var isRetryPass = false

    /// The kitchen this Harvester feeds. Set once at launch by `StockedMacApp`.
    ///
    /// Weak and optional so the Harvester still runs standalone (previews, tests, a window
    /// opened before the store exists) — it just does not hand anything over. When it is
    /// set, approving a recipe copies it into the kitchen, which stamps `updatedAt`, marks
    /// the store dirty, and lets household sync carry it to the phone on the next tick.
    @ObservationIgnored weak var kitchen: MacKitchenStore?

    @ObservationIgnored private let recipeStore: RecipeStore
    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored private let sourceRegistry: SourceRegistry
    @ObservationIgnored private let logStore: LogStore
    @ObservationIgnored private let http: HTTPClient
    @ObservationIgnored private let robots: RobotsPolicy
    @ObservationIgnored private let limiter: DomainRateLimiter
    @ObservationIgnored private let imageStore: ImageStore
    @ObservationIgnored private let fetcher: PolicyFetcher
    @ObservationIgnored private let coordinator: CrawlCoordinator
    @ObservationIgnored private let exporter = StockedPackageExporter()

    // MARK: - Lifecycle

    init() {
        // A storage problem must degrade to a warning, never a launch crash.
        let resolved = AppPaths.liveOrTemporary()
        paths = resolved.paths
        storageWarning = resolved.warning

        let initialSettings: AppSettings
        if let data = try? Data(contentsOf: resolved.paths.settingsFile),
           let saved = try? JSONCoding.decoder().decode(AppSettings.self, from: data) {
            initialSettings = saved
        } else {
            initialSettings = .defaults
        }
        settings = initialSettings

        recipeStore = RecipeStore(fileURL: resolved.paths.recipesFile)
        settingsStore = SettingsStore(fileURL: resolved.paths.settingsFile)
        logStore = LogStore(fileURL: resolved.paths.logFile)
        // A missing bundled catalog is reported later instead of trapping.
        sourceRegistry = SourceRegistry(
            localURL: resolved.paths.sourcesFile,
            bundledURL: AppPaths.bundledResource("sources.json")
        )

        let http = HTTPClient(
            cacheDirectory: resolved.paths.httpCache,
            userAgent: initialSettings.userAgent
        )
        let robots = RobotsPolicy(userAgent: initialSettings.userAgent)
        let limiter = DomainRateLimiter()
        let imageStore = ImageStore(
            directory: resolved.paths.imageCache,
            http: http,
            robots: robots,
            limiter: limiter
        )
        let fetcher = PolicyFetcher(http: http, robots: robots, limiter: limiter)

        self.http = http
        self.robots = robots
        self.limiter = limiter
        self.imageStore = imageStore
        self.fetcher = fetcher
        coordinator = CrawlCoordinator(
            store: recipeStore,
            registry: sourceRegistry,
            fetcher: fetcher,
            imageStore: imageStore,
            pythonParser: .locate()
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        if let storageWarning {
            log(.warning, storageWarning)
        }
        Task {
            settings = await settingsStore.load()
            pythonWorkerAvailable = PythonWorkerClient.locate().isAvailable
            logs = await logStore.recent(limit: 200)
            // Bring back the last browse so a relaunch does not throw away work.
            discoveryReport = loadLastReport()
            await reload()
            if let added = try? await sourceRegistry.mergeBuiltInAdditions(), added > 0 {
                log(.info, "Added \(added) new built-in source\(added == 1 ? "" : "s").")
                await reload()
            }
            await pruneCaches(quiet: true)
            log(.info, "Stocked Companion is ready.")
        }
    }

    func reload() async {
        do {
            recipes = try await recipeStore.all()
            sources = try await sourceRegistry.all()
            duplicateGroups = (try? await recipeStore.duplicateGroups()) ?? []
            if let id = selectedRecipeID, !recipes.contains(where: { $0.id == id }) {
                selectedRecipeID = recipes.first?.id
            } else if selectedRecipeID == nil {
                selectedRecipeID = recipes.first?.id
            }
            selectedRecipeIDs = selectedRecipeIDs.filter { id in
                recipes.contains { $0.id == id }
            }
            statusMessage = "\(recipes.count) recipes • \(sources.count) sources"
            updateDockBadge()
        } catch {
            present(error)
        }
    }

    // MARK: - Dashboard

    var dashboard: DashboardSnapshot {
        let total = recipes.count
        return DashboardSnapshot(
            recipes: total,
            needsReview: recipes.filter { $0.reviewState == .needsReview }.count,
            approved: recipes.filter { $0.reviewState == .approved }.count,
            rejected: recipes.filter { $0.reviewState == .rejected }.count,
            sourcesEnabled: sources.filter(\.enabled).count,
            sourcesDiscovering: sources.filter { $0.enabled && $0.discoveryEnabled }.count,
            averageConfidence: total == 0
                ? 0
                : recipes.map(\.confidence).reduce(0, +) / Double(total),
            duplicateGroups: duplicateGroups.count
        )
    }

    var approvedRecipes: [RecipeDraft] {
        recipes.filter { $0.reviewState == .approved }
    }

    // MARK: - Import

    func importURLs() {
        beginImport(parsedImportURLs())
    }

    /// Imports a set of URLs immediately — used by the Browse screen so a
    /// verified recipe can be pulled in without a round-trip through the
    /// Import text box.
    func importDirect(_ rawURLs: [String]) {
        var seen = Set<String>()
        let urls = rawURLs
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .filter { seen.insert($0).inserted }
        beginImport(urls)
    }

    /// Appends URLs to the import box without disturbing what is already typed.
    func appendImportURLs(_ rawURLs: [String]) {
        let existing = Set(parsedImportURLs())
        var seen = Set<String>()
        let additions = rawURLs
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .filter { seen.insert($0).inserted && !existing.contains($0) }
        guard !additions.isEmpty else {
            statusMessage = "No new recipe URLs were found in that."
            return
        }
        let prefix = importText.nilIfBlank.map { $0 + "\n" } ?? ""
        importText = prefix + additions.joined(separator: "\n")
        statusMessage = "Added \(additions.count) URL\(additions.count == 1 ? "" : "s")"
    }

    /// Pulls every http(s) URL out of the clipboard, whatever it is wrapped in.
    func pasteURLsFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.nilIfBlank else {
            statusMessage = "The clipboard has no text."
            return
        }
        let found = text.matches(#"https?://[^\s"'<>\)\]]+"#, group: 0)
        appendImportURLs(found.isEmpty ? [text] : found)
    }

    private func beginImport(_ urls: [String]) {
        guard !isImporting else { return }
        guard !urls.isEmpty else {
            errorMessage = "Enter at least one http or https recipe URL."
            return
        }
        if !isRetryPass {
            pendingAutoApproval.removeAll()
            retryQueue.removeAll()
        }

        isImporting = true
        importProgress = ImportProgress(
            completed: 0, total: urls.count, succeeded: 0, failed: 0, currentURL: nil
        )
        statusMessage = "Importing \(urls.count) recipe\(urls.count == 1 ? "" : "s")…"
        let activeSettings = settings
        let concurrency = max(1, min(activeSettings.maximumConcurrentJobs, 8))
        let coordinator = coordinator

        importTask = Task { [weak self] in
            await withTaskGroup(of: ImportOutcome.self) { group in
                var next = 0
                // Keep exactly `concurrency` imports in flight rather than
                // running fixed batches, so one slow host cannot stall a whole
                // batch of fast ones.
                while next < min(concurrency, urls.count) {
                    let url = urls[next]
                    next += 1
                    group.addTask {
                        await HarvestModel.performImport(
                            url: url, settings: activeSettings, coordinator: coordinator
                        )
                    }
                }

                for await outcome in group {
                    self?.record(outcome)
                    guard !Task.isCancelled, next < urls.count else { continue }
                    let url = urls[next]
                    next += 1
                    group.addTask {
                        await HarvestModel.performImport(
                            url: url, settings: activeSettings, coordinator: coordinator
                        )
                    }
                }
            }

            guard let self else { return }
            let cancelled = Task.isCancelled
            self.isImporting = false
            self.importProgress.currentURL = nil
            self.statusMessage = cancelled
                ? "Import canceled after \(self.importProgress.completed) of \(self.importProgress.total)"
                : "Imported \(self.importProgress.succeeded), failed \(self.importProgress.failed)"
            self.importTask = nil
            if cancelled {
                self.retryQueue.removeAll()
                self.pendingAutoApproval.removeAll()
                self.isRetryPass = false
                await self.reload()
            } else {
                await self.finishImportRun()
            }
        }
    }

    private nonisolated static func performImport(
        url: String,
        settings: AppSettings,
        coordinator: CrawlCoordinator
    ) async -> ImportOutcome {
        do {
            let detail = try await coordinator.importRecipe(urlString: url, settings: settings)
            return ImportOutcome(url: url, detail: detail, error: nil)
        } catch is CancellationError {
            return ImportOutcome(url: url, detail: nil, error: "Canceled")
        } catch {
            return ImportOutcome(url: url, detail: nil, error: error.localizedDescription)
        }
    }

    private func record(_ outcome: ImportOutcome) {
        importProgress.completed += 1
        importProgress.currentURL = outcome.url
        if let detail = outcome.detail {
            importProgress.succeeded += 1
            var message = detail.wasUpdate
                ? "Updated \(detail.recipe.title)"
                : "Imported \(detail.recipe.title)"
            if !detail.duplicateTitles.isEmpty {
                message += " (duplicate of \(detail.duplicateTitles.joined(separator: ", ")))"
            }
            // A clean, high-confidence extraction does not need a human to
            // click Approve; anything with a warning still waits for review.
            let threshold = settings.autoApproveConfidence
            if threshold > 0,
               detail.recipe.reviewState == .needsReview,
               detail.recipe.confidence >= threshold,
               detail.recipe.warnings.isEmpty,
               detail.recipe.exportProblems.isEmpty,
               detail.duplicateTitles.isEmpty {
                pendingAutoApproval.insert(detail.recipe.id)
                message += " • auto-approved"
            }
            log(detail.duplicateTitles.isEmpty ? .success : .warning, message, url: outcome.url)
        } else {
            importProgress.failed += 1
            if settings.retryFailedImports, !isRetryPass, Self.isRetryable(outcome.error) {
                retryQueue.append(outcome.url)
            }
            log(.error, outcome.error ?? "Import failed", url: outcome.url)
        }
    }

    /// Only transient problems are worth a second attempt — a page that is not
    /// a recipe will not become one.
    private static func isRetryable(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        if message.contains("not a single recipe") || message.contains("robots.txt") {
            return false
        }
        return message.contains("timed out")
            || message.contains("network")
            || message.contains("connection")
            || message.contains("http 5")
            || message.contains("http 429")
            || message.contains("could not be read")
    }

    private func finishImportRun() async {
        if !pendingAutoApproval.isEmpty {
            let ids = pendingAutoApproval
            pendingAutoApproval.removeAll()
            do {
                let changed = try await recipeStore.setReviewState(.approved, for: ids)
                if !changed.isEmpty {
                    log(.success, "Approved \(changed.count) high-confidence recipe\(changed.count == 1 ? "" : "s") automatically.")
                    handOver(changed)
                }
            } catch {
                present(error)
            }
        }
        await reload()

        if !retryQueue.isEmpty {
            let retries = retryQueue
            retryQueue.removeAll()
            isRetryPass = true
            log(.info, "Retrying \(retries.count) import\(retries.count == 1 ? "" : "s") that failed for a transient reason.")
            importDirect(retries)
            return
        }
        isRetryPass = false
        notifyIfBackgrounded()
    }

    /// Bounce the Dock icon when a long run finishes while the app is behind
    /// something else. No notification permission required.
    private func notifyIfBackgrounded() {
        guard !NSApp.isActive else { return }
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func updateDockBadge() {
        let count = recipes.filter { $0.reviewState == .needsReview }.count
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    func cancelImport() {
        importTask?.cancel()
        statusMessage = "Stopping after the active requests finish…"
    }

    /// Checks one URL and reports what it is without saving anything.
    func testLink(_ urlString: String) {
        let activeSettings = settings
        let coordinator = coordinator
        Task {
            do {
                let verdict = try await coordinator.inspect(
                    urlString: urlString,
                    settings: activeSettings
                )
                let description: String
                switch verdict.kind {
                case .recipe:
                    description = "Recipe page (\(percent(verdict.confidence)) confidence)"
                case .listing:
                    description = "Listing page with \(verdict.outboundLinks.count) linked recipes"
                case .other:
                    description = "Not a recipe page"
                }
                statusMessage = description
                log(
                    verdict.isRecipe ? .success : .warning,
                    "\(description) — \(verdict.evidence.first ?? "no signals")",
                    url: urlString
                )
            } catch {
                present(error)
                log(.error, error.localizedDescription, url: urlString)
            }
        }
    }

    // MARK: - Discovery

    func discover(_ source: SourceProfile) {
        guard !isDiscovering else { return }
        guard source.enabled else {
            discoveryFailure = "\(source.name) is disabled. Enable it in Sources first."
            return
        }
        guard source.discoveryMode.supportsDiscovery else {
            discoveryFailure = "\(source.name) is set to \(source.discoveryMode.label), which does not crawl."
            return
        }

        isDiscovering = true
        discoveryReport = nil
        discoveryFailure = nil
        rememberSource(source.id)
        discoveryProgress = DiscoveryProgress(
            phase: "Starting", currentURL: nil, pagesFetched: 0,
            queued: 0, confirmed: 0, rejected: 0
        )
        statusMessage = "Discovering recipes on \(source.name)…"
        let activeSettings = settings
        let coordinator = coordinator

        discoveryTask = Task { [weak self] in
            defer { self?.isDiscovering = false }
            do {
                let report = try await coordinator.discoverRecipeURLs(
                    source: source,
                    settings: activeSettings,
                    manual: true,
                    progress: { [weak self] update in
                        guard let self else { return }
                        await self.updateDiscoveryProgress(update)
                    }
                )
                guard let self else { return }
                self.discoveryReport = report
                // One action, not two: browsing a source imports what it found.
                if self.settings.autoImportVerified, !report.confirmed.isEmpty {
                    self.importDirect(report.confirmed.map(\.url))
                } else if self.settings.autoImportVerified,
                          report.confirmed.isEmpty,
                          !report.unverified.isEmpty {
                    // A run that stopped early still found real links. Finish
                    // the job instead of showing an empty screen.
                    let batch = Array(report.unverified.prefix(60))
                    self.log(
                        .info,
                        "Nothing was verified before the run stopped; checking \(batch.count) of the \(report.unverified.count) links it found."
                    )
                    self.importDirect(batch)
                } else {
                    self.queue(report.confirmed)
                }
                self.statusMessage = "\(source.name): \(report.summary)"
                self.log(
                    report.confirmed.isEmpty ? .warning : .success,
                    "\(source.name) — \(report.summary)",
                    url: source.baseURL
                )
                for note in report.notes.prefix(5) {
                    self.log(.info, note, url: source.baseURL)
                }
                // Remember the seed that answered so the next run skips the
                // guessing, and adopt a source that worked into the rotation.
                var updated = source
                var changed = false
                if let seed = report.workingSeed,
                   seed.lowercased().contains("sitemap") || seed.lowercased().contains("feed"),
                   !updated.sitemapURLs.contains(seed) {
                    updated.sitemapURLs.insert(seed, at: 0)
                    updated.sitemapURLs = Array(updated.sitemapURLs.prefix(6))
                    changed = true
                }
                if self.settings.rememberBrowsedSources,
                   !report.confirmed.isEmpty,
                   !updated.discoveryEnabled {
                    updated.discoveryEnabled = true
                    changed = true
                }
                if changed { self.updateSource(updated) }
                await self.updateHealth(
                    for: source,
                    health: report.confirmed.isEmpty ? .limited : .healthy,
                    message: report.summary
                )
                await self.persistReport(report)
                self.notifyIfBackgrounded()
            } catch is CancellationError {
                self?.statusMessage = "Browse canceled"
            } catch {
                guard let self else { return }
                // Shown inline on the Browse screen — a modal alert here could
                // leave the split view blank after dismissal on macOS 14/15.
                var message = error.localizedDescription
                if let companion = error as? CompanionError,
                   let suggestion = companion.recoverySuggestion {
                    message += " " + suggestion
                }
                self.discoveryFailure = message
                self.statusMessage = "Browse failed"
                self.log(.error, error.localizedDescription, url: source.baseURL)
                await self.updateHealth(
                    for: source,
                    health: Self.health(for: error),
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancelDiscovery() {
        discoveryTask?.cancel()
        statusMessage = "Stopping discovery…"
    }

    private func updateDiscoveryProgress(_ update: DiscoveryProgress) {
        discoveryProgress = update
    }

    /// Adds verified links to the import queue without disturbing what is
    /// already typed there.
    func queue(_ links: [DiscoveredLink]) {
        let existing = Set(parsedImportURLs())
        let additions = links.map(\.url).filter { !existing.contains($0) }
        guard !additions.isEmpty else {
            statusMessage = "Every discovered recipe is already queued."
            return
        }
        let prefix = importText.nilIfBlank.map { $0 + "\n" } ?? ""
        importText = prefix + additions.joined(separator: "\n")
        statusMessage = "Queued \(additions.count) verified recipe URL\(additions.count == 1 ? "" : "s")"
    }

    private func persistReport(_ report: DiscoveryReport) async {
        guard let data = try? JSONCoding.encoder().encode(report) else { return }
        let name = "\(report.sourceID)-\(Int(report.finishedAt.timeIntervalSince1970)).json"
        try? data.write(
            to: paths.discoveryReports.appendingPathComponent(name),
            options: .atomic
        )
        // A stable copy so the last run can be restored on the next launch.
        try? data.write(to: paths.lastDiscoveryReport, options: .atomic)
    }

    private func loadLastReport() -> DiscoveryReport? {
        guard let data = try? Data(contentsOf: paths.lastDiscoveryReport) else { return nil }
        return try? JSONCoding.decoder().decode(DiscoveryReport.self, from: data)
    }

    /// Most-recently browsed sources first, for the picker.
    var recentSources: [SourceProfile] {
        settings.recentSourceIDs.compactMap { id in
            sources.first { $0.id == id }
        }
    }

    private func rememberSource(_ id: String) {
        settings.lastBrowsedSourceID = id
        var recents = settings.recentSourceIDs.filter { $0 != id }
        recents.insert(id, at: 0)
        settings.recentSourceIDs = Array(recents.prefix(12))
        scheduleSettingsSave()
    }

    /// Clears a rate-limit pause for the last browsed source and tries again.
    func clearPauseAndRetry() {
        guard let id = discoveryReport?.sourceID ?? settings.lastBrowsedSourceID,
              let source = sources.first(where: { $0.id == id }) else {
            discoveryFailure = "There is no source to retry."
            return
        }
        Task {
            await fetcher.clearPause(for: source)
            log(.info, "Cleared the pause on \(source.name).")
            discover(source)
        }
    }

    /// Verifies the candidates a stopped run never opened, by importing them —
    /// the importer performs the same recipe check the verifier would.
    func verifyRemaining() {
        guard let report = discoveryReport, !report.unverified.isEmpty else { return }
        statusMessage = "Checking \(report.unverified.count) remaining candidate\(report.unverified.count == 1 ? "" : "s")…"
        importDirect(report.unverified)
    }

    /// Moves to the next crawlable source in the catalog and browses it.
    func browseNextSource() {
        let eligible = sources.filter { $0.enabled && $0.discoveryMode.supportsDiscovery }
        guard !eligible.isEmpty else {
            discoveryFailure = "No enabled source supports browsing."
            return
        }
        let current = discoveryReport?.sourceID ?? settings.lastBrowsedSourceID
        let next: SourceProfile
        if let index = eligible.firstIndex(where: { $0.id == current }) {
            next = eligible[(index + 1) % eligible.count]
        } else {
            next = eligible[0]
        }
        discover(next)
    }

    private static func health(for error: any Error) -> SourceHealth {
        guard let companion = error as? CompanionError else { return .limited }
        switch companion {
        case .robotsDenied: return .blocked
        case .rateLimited: return .paused
        case .httpStatus(let code, _): return code == 403 || code == 451 ? .blocked : .limited
        case .sourceDisabled: return .paused
        default: return .limited
        }
    }

    private func updateHealth(
        for source: SourceProfile,
        health: SourceHealth,
        message: String?
    ) async {
        _ = try? await sourceRegistry.recordHealth(health, message: message, for: source.id)
        await reload()
    }

    // MARK: - Recipes

    func saveRecipe(_ recipe: RecipeDraft) {
        Task {
            do {
                let saved = try await recipeStore.upsert(recipe)
                selectedRecipeID = saved.id
                await reload()
                log(.success, "Saved \(saved.title).")
            } catch {
                present(error)
            }
        }
    }

    func deleteRecipe(_ recipe: RecipeDraft) {
        delete(ids: [recipe.id])
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let titles = recipes.filter { ids.contains($0.id) }.map(\.title)
        Task {
            do {
                try await recipeStore.delete(ids: ids)
                if let selected = selectedRecipeID, ids.contains(selected) {
                    selectedRecipeID = nil
                }
                selectedRecipeIDs.subtract(ids)
                await reload()
                log(.warning, "Deleted \(titles.count) recipe\(titles.count == 1 ? "" : "s").")
            } catch {
                present(error)
            }
        }
    }

    func setReviewState(_ state: ReviewState, for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        Task {
            do {
                let changed = try await recipeStore.setReviewState(state, for: ids)
                await reload()
                log(.info, "Marked \(changed.count) recipe\(changed.count == 1 ? "" : "s") as \(state.label).")
                if state == .approved { handOver(changed) }
            } catch {
                present(error)
            }
        }
    }

    /// Copies approved drafts into the kitchen so they reach the rest of the household.
    ///
    /// Approval used to mean nothing outside the Harvester: the recipe sat in the
    /// Harvester's own library, and only a separate "Add to Stocked" button press moved it
    /// across. So a crawl could approve forty recipes and the phone would still show none
    /// of them. Approving is the decision; carrying it over is bookkeeping, and bookkeeping
    /// should not need a button.
    ///
    /// Safe to call more than once — the bridge skips titles the kitchen already holds, so
    /// re-approving or re-importing cannot duplicate anything.
    private func handOver(_ drafts: [RecipeDraft]) {
        guard let kitchen, !drafts.isEmpty else { return }
        let added = MacHarvestBridge.add(drafts, to: kitchen)
        guard added > 0 else { return }
        log(.success, "Added \(added) recipe\(added == 1 ? "" : "s") to Stocked; the household will pick \(added == 1 ? "it" : "them") up on the next sync.")
    }

    /// Re-runs the parser on an existing recipe's source URL.
    func reimport(_ recipe: RecipeDraft) {
        guard !recipe.source.url.isEmpty else {
            errorMessage = "This recipe has no source URL to re-import."
            return
        }
        let activeSettings = settings
        let coordinator = coordinator
        let url = recipe.source.url
        Task {
            do {
                let detail = try await coordinator.importRecipe(
                    urlString: url,
                    settings: activeSettings
                )
                selectedRecipeID = detail.recipe.id
                await reload()
                log(.success, "Re-imported \(detail.recipe.title).", url: url)
            } catch {
                present(error)
                log(.error, error.localizedDescription, url: url)
            }
        }
    }

    // MARK: - Export

    func exportRecipe(_ recipe: RecipeDraft) {
        let problems = recipe.exportProblems
        guard problems.isEmpty else {
            errorMessage = problems.joined(separator: " ")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export for Stocked"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = StockedPackageExporter.safeFilename(recipe.title)
            + "." + StockedPackageExporter.fileExtension
        guard panel.runModal() == .OK, var destination = panel.url else { return }
        if destination.pathExtension.lowercased() != StockedPackageExporter.fileExtension {
            destination.appendPathExtension(StockedPackageExporter.fileExtension)
        }

        do {
            try exporter.export(recipe, to: destination)
            statusMessage = "Exported \(destination.lastPathComponent)"
            log(.success, "Exported \(recipe.title) for Stocked.")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            present(error)
        }
    }

    /// Exports every approved recipe, or a specific selection, into one folder.
    func exportBatch(_ batch: [RecipeDraft]) {
        let exportable = batch.filter { $0.exportProblems.isEmpty }
        guard !exportable.isEmpty else {
            errorMessage = "None of the selected recipes are complete enough to export."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose a folder for \(exportable.count) packages"
        panel.prompt = "Export Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            let result = try exporter.exportAll(exportable, toDirectory: directory)
            statusMessage = "Exported \(result.written.count) package\(result.written.count == 1 ? "" : "s")"
            log(.success, "Exported \(result.written.count) packages to \(directory.lastPathComponent).")
            for failure in result.failures {
                log(.error, "\(failure.title): \(failure.reason)")
            }
            if let first = result.written.first {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
        } catch {
            present(error)
        }
    }

    // MARK: - Sources

    func setSourceEnabled(_ source: SourceProfile, enabled: Bool) {
        var updated = source
        updated.enabled = enabled
        saveSource(updated)
    }

    func setDiscoveryEnabled(_ source: SourceProfile, enabled: Bool) {
        var updated = source
        updated.discoveryEnabled = enabled
        saveSource(updated)
    }

    func updateSource(_ source: SourceProfile) {
        let problems = source.validationProblems
        guard problems.isEmpty else {
            errorMessage = problems.joined(separator: " ")
            return
        }
        saveSource(source)
    }

    func addSource() {
        let profile = SourceProfile(
            id: "custom-\(UUID().uuidString.prefix(8).lowercased())",
            name: "New source",
            domains: ["example.com"],
            baseURL: "https://example.com",
            discoveryEnabled: false,
            tags: ["Custom"],
            notes: "Created in Stocked Companion."
        )
        saveSource(profile)
        selectedSourceID = profile.id
    }

    func deleteSource(_ source: SourceProfile) {
        Task {
            do {
                try await sourceRegistry.delete(id: source.id)
                await reload()
                log(.warning, "Removed the source \(source.name).")
            } catch {
                present(error)
            }
        }
    }

    func resetSources() {
        Task {
            do {
                sources = try await sourceRegistry.resetToBuiltIn()
                statusMessage = "Source catalog restored"
                log(.warning, "Restored the built-in source catalog.")
            } catch {
                present(error)
            }
        }
    }

    func resetRateLimits() {
        Task {
            await limiter.resetAll()
            statusMessage = "Rate-limit pauses cleared"
            log(.info, "Cleared every rate-limit pause and daily counter.")
        }
    }

    private func saveSource(_ source: SourceProfile) {
        Task {
            do {
                try await sourceRegistry.save(source)
                await reload()
            } catch {
                present(error)
            }
        }
    }

    // MARK: - Settings and maintenance

    /// Settings save themselves shortly after the last edit, so there is no
    /// Save button to forget.
    func scheduleSettingsSave() {
        settingsSaveTask?.cancel()
        let current = settings
        settingsSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            do {
                try await self.settingsStore.save(current)
                await self.fetcher.updateUserAgent(current.userAgent)
                self.statusMessage = "Settings saved"
            } catch {
                self.present(error)
            }
        }
    }

    func applyCrawlPreset(_ preset: CrawlPreset) {
        var updated = settings
        preset.apply(to: &updated)
        settings = updated
        scheduleSettingsSave()
        log(.info, "Applied the \(preset.label) crawl profile.")
    }

    /// Enables browsing for a batch of sources at once.
    func setDiscoveryEnabled(_ enabled: Bool, for profiles: [SourceProfile]) {
        let targets = profiles.filter {
            $0.discoveryMode.supportsDiscovery && $0.discoveryEnabled != enabled
        }
        guard !targets.isEmpty else { return }
        Task {
            do {
                var updated: [SourceProfile] = []
                for var profile in targets {
                    profile.discoveryEnabled = enabled
                    updated.append(profile)
                }
                try await sourceRegistry.save(all: updated)
                await reload()
                log(
                    .info,
                    "\(enabled ? "Enabled" : "Disabled") browsing for \(updated.count) source\(updated.count == 1 ? "" : "s")."
                )
            } catch {
                present(error)
            }
        }
    }

    func clearCaches() {
        Task {
            do {
                try await http.removeAllCache()
                try await imageStore.removeAll()
                statusMessage = "Caches cleared"
                log(.warning, "HTTP and image caches cleared.")
            } catch {
                present(error)
            }
        }
    }

    /// Removes stale HTTP entries and any cached image no recipe references.
    func pruneCaches(quiet: Bool = false) async {
        let removedHTTP = await http.pruneCache(
            maximumAgeHours: max(settings.cacheMaximumAgeHours * 4, 168),
            maximumBytes: settings.maximumCacheBytes
        )
        let referenced = Set(recipes.compactMap { $0.image?.localPath })
        let removedImages = await imageStore.prune(keeping: referenced)
        let total = removedHTTP + removedImages
        if total > 0 {
            log(
                .info,
                "Cache maintenance removed \(removedHTTP) HTTP file\(removedHTTP == 1 ? "" : "s") "
                    + "and \(removedImages) unused image\(removedImages == 1 ? "" : "s")."
            )
        } else if !quiet {
            log(.info, "Cache maintenance found nothing to remove.")
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.root])
    }

    func open(_ urlString: String) {
        guard let url = URL(string: urlString),
              url.scheme != nil else {
            errorMessage = "That link could not be opened."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func clearLogs() {
        logs.removeAll()
        Task { await logStore.clear() }
    }

    // MARK: - Helpers

    private func parsedImportURLs() -> [String] {
        importText
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
    }

    private func log(_ level: CrawlLogEntry.Level, _ message: String, url: String? = nil) {
        let entry = CrawlLogEntry(level: level, message: message, url: url)
        logs.insert(entry, at: 0)
        let retain = max(50, settings.retainLogEntries)
        if logs.count > retain {
            logs.removeLast(logs.count - retain)
        }
        Task { await logStore.append(entry) }
    }

    private func present(_ error: any Error) {
        if error is CancellationError { return }
        var message = error.localizedDescription
        if let companion = error as? CompanionError,
           let suggestion = companion.recoverySuggestion {
            message += "\n\n" + suggestion
        }
        errorMessage = message
        statusMessage = "Action failed"
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
