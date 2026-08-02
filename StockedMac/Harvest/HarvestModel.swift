import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

private nonisolated struct ImportOutcome: Sendable {
    var url: String
    var detail: ImportOutcomeDetail?
    var error: String?
}

/// One failed import, kept so failures are actionable instead of scrolling away.
nonisolated struct ImportFailure: Identifiable, Sendable {
    let id = UUID()
    let url: String
    let reason: String
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
    // ── Build 91 (Browse) ───────────────────────────────────────────────
    /// One switch that parks every network request (browsing, imports, image
    /// downloads). Nothing is cancelled; Resume continues where work stopped.
    var isPaused = false
    var isBulkVerifying = false
    var bulkVerifyProgress: ImportProgress = .idle
    var isCloudSyncing = false
    var cloudSyncStatus: String?
    /// Past browse sessions, newest first, restored from DiscoveryReports on disk.
    var sessionHistory: [DiscoveryReport] = []
    /// Sources still to visit in the current auto-rotate run.
    var autoRotateRemaining = 0
    /// Explicitly selected sources still waiting their turn (multi-select browsing).
    var sourceRotationQueue: [String] = []
    @ObservationIgnored private var rotationQueueOnly = false
    // ── Build 95 (Importing) ────────────────────────────────────────────
    /// Failed imports from the current/last run, newest last, capped at 50.
    var lastFailures: [ImportFailure] = []
    /// One line describing how the last import run went.
    var lastImportSummary: String?
    @ObservationIgnored private var lastLogKey = ""
    @ObservationIgnored private var lastLogRepeat = 1
    @ObservationIgnored private var autoApprovedThisRun = 0
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
    @ObservationIgnored private let pauseGate: PauseGate
    @ObservationIgnored private var bulkVerifyTask: Task<Void, Never>?
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
            bundledURL: AppPaths.bundledResource("default-sources.json")
        )

        let gate = PauseGate()
        pauseGate = gate
        let http = HTTPClient(
            cacheDirectory: resolved.paths.httpCache,
            userAgent: initialSettings.userAgent,
            pauseGate: gate
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
            migrateSettingsIfNeeded()
            pythonWorkerAvailable = PythonWorkerClient.locate().isAvailable
            logs = await logStore.recent(limit: 200)
            // Bring back the last browse so a relaunch does not throw away work.
            discoveryReport = loadLastReport()
            loadSessionHistory()
            await reload()
            if let added = try? await sourceRegistry.mergeBuiltInAdditions(), added > 0 {
                log(.info, "Added \(added) new built-in source\(added == 1 ? "" : "s").")
                await reload()
            }
            // Build 92 self-heal: a catalog that is empty — or non-empty but with nothing
            // enabled and browsable — is useless, and the screen it produces ("No sources
            // loaded", "No enabled source supports browsing") gives the user nothing to
            // click. Restore the built-in hundred, keeping any custom entries.
            if sources.filter({ $0.enabled && $0.discoveryMode.supportsDiscovery }).isEmpty {
                if let repaired = try? await sourceRegistry.repairCatalog() {
                    log(.warning, "The source catalog was empty or unbrowsable; restored the built-in catalog (\(repaired.count) sources).")
                    await reload()
                }
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

    func importURLs(skipVerify: Bool = false) {
        // "Verify before import" runs the queue through the page detector first, so a
        // pasted category page never becomes a half-parsed draft somebody has to delete.
        if settings.verifyBeforeImport, !skipVerify, !isRetryPass {
            bulkVerifyQueue(thenImport: true)
            return
        }
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
            lastFailures.removeAll()
            lastImportSummary = nil
            autoApprovedThisRun = 0
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
                    if activeSettings.importSpacingSeconds > 0 {
                        try? await Task.sleep(for: .seconds(Double(activeSettings.importSpacingSeconds)))
                    }
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
               detail.duplicateTitles.isEmpty,
               // The image gate: nothing without a picture on disk auto-approves,
               // because the bridge would drop it and the phone shows placeholders.
               !settings.requireImageForImport || detail.recipe.image?.hasLocalFile == true,
               // The standards gate (Build 93): auto-approval also requires the
               // Stocked checklist to pass — real title, 3+ ingredients, 2+ steps,
               // image on disk, source URL, honest attribution.
               !settings.requireStandardsForAutoApprove || detail.recipe.standards.requiredPassed {
                pendingAutoApproval.insert(detail.recipe.id)
                message += " • auto-approved"
            }
            log(detail.duplicateTitles.isEmpty ? .success : .warning, message, url: outcome.url)
        } else {
            importProgress.failed += 1
            if settings.retryFailedImports, !isRetryPass, Self.isRetryable(outcome.error) {
                retryQueue.append(outcome.url)
            } else {
                lastFailures.append(ImportFailure(url: outcome.url, reason: outcome.error ?? "Import failed"))
                if lastFailures.count > 50 { lastFailures.removeFirst(lastFailures.count - 50) }
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
                    autoApprovedThisRun += changed.count
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

        // The run in one line, kept until the next run starts.
        lastImportSummary = "Imported \(importProgress.succeeded) · auto-approved \(autoApprovedThisRun) · failed \(importProgress.failed)"
            + (lastFailures.isEmpty ? "" : " — the failures are listed below with retry.")

        // A recipe whose image download failed gets one more chance before anyone
        // has to notice — a draft without a picture cannot reach the phone.
        if settings.autoFetchMissingImages {
            let recovered = await fetchMissingImagesInternal(quiet: true)
            if recovered > 0 { await reload() }
        }

        // Push freshly approved work to the Worker cache when the user asked for that.
        if settings.cloudSyncEnabled { syncApprovedToCloud() }

        // Selected sources first, then auto-rotate, until both runs are used up.
        if !isDiscovering, advanceSourceRotation() {
            return
        }
        if autoRotateRemaining > 0, !isDiscovering {
            autoRotateRemaining -= 1
            browseNextSource()
            return
        }

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

    /// Number of valid http(s) URLs currently in the import queue text box.
    var queuedURLCount: Int {
        importText.components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && (URL(string: $0)?.scheme?.hasPrefix("http") == true) }
            .count
    }

    /// Crawls a source and always adds found URLs to the queue (ignores autoImportVerified).
    func discoverToQueue(_ source: SourceProfile) {
        discover(source, addToQueueOnly: true)
    }

    func discover(_ source: SourceProfile, addToQueueOnly: Bool = false) {
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
                // Always persist the report so a cancelled session survives relaunch.
                await self.persistReport(report)
                let shouldAutoImport = !addToQueueOnly && self.settings.autoImportVerified
                if shouldAutoImport, !report.confirmed.isEmpty {
                    self.importDirect(report.confirmed.map(\.url))
                } else if shouldAutoImport,
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
                // Chain to whatever is next: an explicitly selected source first, then
                // auto-rotate. Queue-only browsing chains here; the auto-import path
                // chains from finishImportRun instead, after the recipes are actually
                // in. Scheduled as fresh tasks so the `isDiscovering` reset in the
                // defer above lands first.
                if !shouldAutoImport, self.advanceSourceRotation() {
                    // handled — the next selected source is on its way
                } else if !shouldAutoImport, self.autoRotateRemaining > 0 {
                    self.autoRotateRemaining -= 1
                    Task { [weak self] in self?.browseNextSource() }
                } else {
                    self.notifyIfBackgrounded()
                }
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
        loadSessionHistory()
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
                if state == .approved {
                    handOver(changed)
                    if settings.cloudSyncEnabled { syncApprovedToCloud() }
                }
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

    // MARK: - Build 95: migrations, failures, spacing

    /// One-time forward migration when defaults change meaning. Revision 2 (Build 95):
    /// browsing no longer imports by itself, and the crawler stops announcing itself
    /// with a truncated UA that trips bot walls.
    private func migrateSettingsIfNeeded() {
        guard settings.settingsRevision < 2 else { return }
        if settings.userAgent == AppSettings.legacyUserAgent {
            settings.userAgent = AppSettings.safariUserAgent
        }
        if settings.autoImportVerified {
            settings.autoImportVerified = false
        }
        settings.settingsRevision = 2
        scheduleSettingsSave()
        log(.info, "New defaults applied: browsing queues instead of auto-importing, and the crawler identifies as Safari. Both are adjustable in Browse.")
    }

    /// Re-runs every failed import from the last run.
    func retryFailures() {
        let urls = lastFailures.map(\.url)
        guard !urls.isEmpty else { return }
        lastFailures.removeAll()
        importDirect(urls)
    }

    func clearFailures() {
        lastFailures.removeAll()
    }

    // MARK: - Build 91: pause / verify / images / cloud / sessions

    /// Parks every new network request. Requests already in flight finish; nothing
    /// is cancelled, so Resume continues the run exactly where it stopped.
    func togglePause() {
        isPaused.toggle()
        let paused = isPaused
        let gate = pauseGate
        Task {
            if paused {
                await gate.pause()
            } else {
                await gate.resume()
            }
        }
        statusMessage = paused
            ? "Paused — in-flight requests finish, nothing new starts"
            : "Resumed"
        log(.info, paused ? "Paused all browsing and downloads." : "Resumed browsing and downloads.")
    }

    /// Checks every queued URL against the recipe-page detector and removes the ones
    /// that are not recipes. Network failures keep their URL — a timeout is not
    /// evidence against a page.
    func bulkVerifyQueue(thenImport: Bool = false) {
        guard !isBulkVerifying, !isImporting else { return }
        let urls = parsedImportURLs()
        guard !urls.isEmpty else {
            statusMessage = "The queue is empty."
            return
        }
        isBulkVerifying = true
        bulkVerifyProgress = ImportProgress(
            completed: 0, total: urls.count, succeeded: 0, failed: 0, currentURL: nil
        )
        statusMessage = "Verifying \(urls.count) queued URL\(urls.count == 1 ? "" : "s")…"
        let activeSettings = settings
        let coordinator = coordinator

        bulkVerifyTask = Task { [weak self] in
            var keep: [String] = []
            var dropped = 0
            for url in urls {
                if Task.isCancelled {
                    keep.append(url)            // unchecked URLs stay queued
                    continue
                }
                do {
                    let verdict = try await coordinator.inspect(urlString: url, settings: activeSettings)
                    if verdict.isRecipe {
                        keep.append(url)
                        self?.bulkVerifyProgress.succeeded += 1
                    } else {
                        dropped += 1
                        self?.bulkVerifyProgress.failed += 1
                        self?.log(.warning, "Not a recipe page; removed from the queue.", url: url)
                    }
                } catch {
                    keep.append(url)
                    self?.bulkVerifyProgress.failed += 1
                }
                self?.bulkVerifyProgress.completed += 1
                self?.bulkVerifyProgress.currentURL = url
            }
            guard let self else { return }
            let cancelled = Task.isCancelled
            self.importText = keep.joined(separator: "\n")
            self.isBulkVerifying = false
            self.bulkVerifyTask = nil
            self.statusMessage = cancelled
                ? "Verify stopped — kept \(keep.count) URLs"
                : "Verified the queue: kept \(keep.count), removed \(dropped)"
            self.log(dropped > 0 ? .warning : .success,
                     "Bulk verify kept \(keep.count) of \(urls.count) queued URLs.")
            if thenImport, !cancelled, !keep.isEmpty {
                self.importURLs(skipVerify: true)
            }
        }
    }

    func cancelBulkVerify() {
        bulkVerifyTask?.cancel()
        statusMessage = "Stopping verification…"
    }

    /// Drafts whose image bytes never made it to disk (or were cleaned away).
    var imagelessCount: Int {
        recipes.filter { !($0.image?.hasLocalFile ?? false) }.count
    }

    /// Retries the image download for every draft that has an image URL but no bytes.
    func fetchMissingImages() {
        Task {
            let fixed = await fetchMissingImagesInternal(quiet: false)
            if fixed > 0 { await reload() }
        }
    }

    private func fetchMissingImagesInternal(quiet: Bool) async -> Int {
        let targets = recipes.filter {
            !($0.image?.hasLocalFile ?? false) && $0.image?.originalURL.nilIfBlank != nil
        }
        guard !targets.isEmpty else {
            if !quiet { statusMessage = "Every recipe already has its image." }
            return 0
        }
        if !quiet {
            statusMessage = "Fetching \(targets.count) missing image\(targets.count == 1 ? "" : "s")…"
        }
        let activeSettings = settings
        var fixed = 0
        for draft in targets {
            guard !Task.isCancelled, let urlString = draft.image?.originalURL else { continue }
            do {
                let image = try await imageStore.download(
                    urlString: urlString,
                    settings: activeSettings,
                    referer: draft.source.url
                )
                var updated = draft
                updated.image = image
                _ = try? await recipeStore.upsert(updated)
                fixed += 1
            } catch {
                log(.warning, "Image retry failed: \(error.localizedDescription)", url: urlString)
            }
        }
        if fixed > 0 {
            log(.success, "Recovered \(fixed) missing image\(fixed == 1 ? "" : "s").")
        }
        if !quiet {
            statusMessage = fixed > 0 ? "Recovered \(fixed) images" : "No images could be recovered"
        }
        return fixed
    }

    /// Pushes every approved, image-complete recipe (and its image bytes) to the
    /// Stocked Worker's harvest cache, where the household and the iOS app can read
    /// them back. Safe to run repeatedly — the Worker stores by recipe id.
    func syncApprovedToCloud() {
        guard !isCloudSyncing else { return }
        guard MacWorkerClient.isConfigured else {
            cloudSyncStatus = "The Worker key isn't configured (Secrets.xcconfig), so nothing can upload."
            return
        }
        let batch = approvedRecipes.filter { $0.image?.hasLocalFile ?? false }
        guard !batch.isEmpty else {
            cloudSyncStatus = "Nothing approved with an image to sync yet."
            return
        }
        isCloudSyncing = true
        cloudSyncStatus = "Syncing \(batch.count) recipe\(batch.count == 1 ? "" : "s")…"
        Task { [weak self] in
            do {
                let result = try await HarvestCloudSync.push(batch)
                self?.cloudSyncStatus =
                    "Synced \(result.recipes) recipe\(result.recipes == 1 ? "" : "s") and \(result.images) image\(result.images == 1 ? "" : "s") to the Worker cache."
                self?.log(.success, "Cloud cache: \(result.recipes) recipes, \(result.images) images uploaded.")
            } catch {
                self?.cloudSyncStatus = "Cloud sync failed: \(error.localizedDescription)"
                self?.log(.error, "Cloud sync failed: \(error.localizedDescription)")
            }
            self?.isCloudSyncing = false
        }
    }

    /// Restores the saved discovery reports so past sessions are one click to resume.
    func loadSessionHistory() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: paths.discoveryReports,
            includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONCoding.decoder()
        sessionHistory = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DiscoveryReport? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(DiscoveryReport.self, from: data)
            }
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(20)
            .map { $0 }
    }

    /// Brings a past session back as the active report so its links can be queued,
    /// imported, or its unverified remainder finished.
    func restoreSession(_ report: DiscoveryReport) {
        discoveryReport = report
        statusMessage = "Restored the \(report.sourceName) session (\(report.confirmed.count) verified links)"
    }

    /// Browses several sources back to back — the count comes from Settings.
    func autoRotate() {
        guard !isDiscovering else { return }
        autoRotateRemaining = max(1, settings.autoRotateSourceCount) - 1
        browseNextSource()
    }

    func cancelAutoRotate() {
        autoRotateRemaining = 0
        sourceRotationQueue.removeAll()
    }

    // MARK: - Build 92: multi-select browsing

    /// Browses a hand-picked set of sources one after another — the multi-select
    /// dropdown's "Browse N sources" button. `queueOnly` collects links into the queue
    /// instead of importing as it goes.
    func browseSources(withIDs ids: [String], queueOnly: Bool = false) {
        guard !isDiscovering else { return }
        let eligible = ids.compactMap { id in
            sources.first { $0.id == id && $0.enabled && $0.discoveryMode.supportsDiscovery }
        }
        guard let first = eligible.first else {
            discoveryFailure = "None of the selected sources can browse."
            return
        }
        rotationQueueOnly = queueOnly
        sourceRotationQueue = eligible.dropFirst().map(\.id)
        if !sourceRotationQueue.isEmpty {
            log(.info, "Browsing \(eligible.count) selected sources, starting with \(first.name).")
        }
        discover(first, addToQueueOnly: queueOnly)
    }

    /// Starts the next explicitly selected source, if any. Returns whether it did.
    @discardableResult
    private func advanceSourceRotation() -> Bool {
        while !sourceRotationQueue.isEmpty {
            let nextID = sourceRotationQueue.removeFirst()
            guard let source = sources.first(where: { $0.id == nextID }) else { continue }
            let queueOnly = rotationQueueOnly
            // A fresh task so the caller's `isDiscovering` cleanup lands first.
            Task { [weak self] in self?.discover(source, addToQueueOnly: queueOnly) }
            return true
        }
        return false
    }

    // MARK: - Build 92: catalog repair and file import/export

    /// Restores the built-in hundred while keeping custom and imported sources.
    func repairSources() {
        Task {
            do {
                _ = try await sourceRegistry.repairCatalog()
                await reload()
                statusMessage = "Catalog restored — \(sources.count) sources"
                log(.success, "Restored the built-in source catalog (\(sources.count) sources).")
            } catch {
                present(error)
            }
        }
    }

    /// Merges sources from a file the user picks. Accepts:
    ///   • JSON — an array of full source profiles (the same shape as sources.json), or
    ///   • plain text / CSV — one site per line: a URL or domain, optionally
    ///     "Name | url", "Name, url" or "Name<TAB>url". Lines starting with # are notes.
    func importSourcesFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Update the source list"
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .json, .commaSeparatedText, .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "That file could not be read as text."
            return
        }
        let parsed = Self.parseSourceList(raw)
        guard !parsed.isEmpty else {
            errorMessage = "No sources were found in \(url.lastPathComponent). Use one URL or domain per line, or a JSON array of source profiles."
            return
        }
        let existingIDs = Set(sources.map(\.id))
        let newCount = parsed.filter { !existingIDs.contains($0.id) }.count
        Task {
            do {
                try await sourceRegistry.save(all: parsed)
                await reload()
                let updated = parsed.count - newCount
                statusMessage = "Imported \(parsed.count) source\(parsed.count == 1 ? "" : "s") from \(url.lastPathComponent)"
                log(.success, "Source list updated from \(url.lastPathComponent): \(newCount) new, \(updated) refreshed.")
            } catch {
                present(error)
            }
        }
    }

    /// Writes the current catalog to a JSON file that `importSourcesFromFile` (and the
    /// bundled catalog format) can read back — the round-trip for hand-editing.
    func exportSourcesToFile() {
        let panel = NSSavePanel()
        panel.title = "Export the source list"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "stocked-sources.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONCoding.encoder().encode(sources)
            try data.write(to: url, options: .atomic)
            statusMessage = "Exported \(sources.count) sources"
            log(.success, "Exported the source list to \(url.lastPathComponent).")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            present(error)
        }
    }

    /// The parser behind `importSourcesFromFile`, separated so it stays testable.
    nonisolated static func parseSourceList(_ raw: String) -> [SourceProfile] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // JSON array of profiles first — full fidelity, tolerant per element.
        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) {
            if let strict = try? JSONDecoder().decode([SourceProfile].self, from: data) {
                return strict
            }
            if let lossy = try? JSONDecoder().decode(LossyArray<SourceProfile>.self, from: data),
               !lossy.elements.isEmpty {
                return lossy.elements
            }
        }

        // Line-based: "Name | url", "Name, url", "Name<TAB>url", or a bare URL/domain.
        var out: [SourceProfile] = []
        var seen = Set<String>()
        for line in trimmed.components(separatedBy: .newlines) {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty, !cleaned.hasPrefix("#"), !cleaned.hasPrefix("//") else { continue }

            var name: String? = nil
            var address = cleaned
            for separator in ["|", "\t", ","] {
                if let range = cleaned.range(of: separator) {
                    let left = String(cleaned[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let right = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    // Whichever side looks like the address is the address.
                    if right.contains(".") && (left.isEmpty || !left.contains("://")) {
                        name = left.nilIfBlank
                        address = right
                    } else if left.contains(".") {
                        name = right.nilIfBlank
                        address = left
                    }
                    break
                }
            }

            if !address.contains("://") { address = "https://" + address }
            guard let url = URL(string: address),
                  let host = url.host?.lowercased(),
                  host.contains(".") else { continue }
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            guard seen.insert(domain).inserted else { continue }

            let slug = domain.replacingOccurrences(of: ".", with: "-")
            let displayName = name ?? domain
                .components(separatedBy: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() }
                ?? domain
            out.append(SourceProfile(
                id: "imported-\(slug)",
                name: displayName,
                domains: [domain, "www." + domain],
                baseURL: "https://\(host)",
                enabled: true,
                discoveryEnabled: true,
                discoveryMode: .sitemapOnly,
                parserMode: .nativeFirst,
                minimumDelaySeconds: 2,
                maximumConcurrency: 2,
                dailyRequestLimit: 150,
                robotsRequired: true,
                imageDownloadEnabled: true,
                sitemapURLs: ["https://\(host)/sitemap.xml"],
                recipeURLPatterns: [],
                excludedURLPatterns: SourceProfile.defaultExcludedPatterns,
                tags: ["Imported"],
                notes: "Imported from a source list file.",
                health: .unknown
            ))
        }
        return out
    }

    /// Clears out everything already rejected, in one motion.
    func deleteRejected() {
        let ids = Set(recipes.filter { $0.reviewState == .rejected }.map(\.id))
        guard !ids.isEmpty else {
            statusMessage = "No rejected recipes to clear."
            return
        }
        delete(ids: ids)
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
        // Collapse runs of the identical message into one line with a counter, so 200
        // copies of the same parse failure read as one entry, not a wall of red.
        let key = "\(level.rawValue)|\(message)"
        if key == lastLogKey, !logs.isEmpty {
            lastLogRepeat += 1
            logs[0] = CrawlLogEntry(level: level, message: "\(message) (×\(lastLogRepeat))", url: url)
            return
        }
        lastLogKey = key
        lastLogRepeat = 1
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
