import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

private nonisolated struct ImportOutcome: Sendable {
    var url: String
    var detail: ImportOutcomeDetail?
    var error: String?
    /// Recipe links found on a category page that was imported by mistake.
    var mined: [String] = []
}

/// One failed import, kept so failures are actionable instead of scrolling away.
nonisolated struct ImportFailure: Identifiable, Sendable {
    let id = UUID()
    let url: String
    let reason: String
}

/// A normalized, display-ready row in the import queue. Keeping this as a value type
/// makes the queue preview deterministic and gives SwiftUI stable identity while text is
/// edited, cleaned, reordered, or dropped into the app.
nonisolated struct ImportQueueEntry: Identifiable, Hashable, Sendable {
    let url: String
    let host: String

    var id: String { url }

    var pageLabel: String {
        guard let parsed = URL(string: url) else { return url }
        let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.nilIfBlank ?? host
    }
}

nonisolated struct ImportQueueSnapshot: Sendable {
    let entries: [ImportQueueEntry]
    let duplicateCount: Int
    let invalidCount: Int

    static let empty = ImportQueueSnapshot(entries: [], duplicateCount: 0, invalidCount: 0)

    var domainCount: Int { Set(entries.map(\.host)).count }
}

nonisolated enum MacRecipeTextParser {
    struct Result: Sendable {
        var title = ""
        var ingredients: [String] = []
        var steps: [String] = []
        var warnings: [String] = []
        var confidence: Double { min(0.9, 0.35 + (ingredients.isEmpty ? 0 : 0.25) + (steps.isEmpty ? 0 : 0.25)) }
    }

    static func mergePages(_ pages: [String]) -> String {
        var seen = Set<String>()
        return pages.flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                let key = $0.lowercased().filter { $0.isLetter || $0.isNumber }
                return key.count > 2 && seen.insert(key).inserted
            }.joined(separator: "\n")
    }

    static func parse(_ raw: String) -> Result {
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return Result() }
        var result = Result()
        enum Bucket { case none, ingredients, steps }
        var bucket = Bucket.none
        let units = ["cup", "tbsp", "tsp", "ounce", "oz", "pound", "lb", "gram", "kg", "ml", "liter", "clove", "pinch", "can", "package", "bunch", "sprig"]
        func ingredient(_ line: String) -> Bool {
            let lower = line.lowercased()
            return line.first?.isNumber == true || "½⅓¼¾⅔⅛".contains(line.first ?? " ") || units.contains { lower.contains($0) }
        }
        result.title = lines.first(where: { !ingredient($0) && $0.count >= 3 && $0.count <= 100 }) ?? "Imported Recipe"
        for line in lines where line != result.title {
            let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            if lower.hasPrefix("ingredient") { bucket = .ingredients; continue }
            if ["instructions", "directions", "method", "steps", "preparation"].contains(lower) { bucket = .steps; continue }
            let clean = line.replacingOccurrences(of: #"^[\s\-*•]*\d*[.)]?\s*"#, with: "", options: .regularExpression)
            switch bucket {
            case .ingredients: result.ingredients.append(clean)
            case .steps: result.steps.append(clean)
            case .none:
                if ingredient(line) { result.ingredients.append(clean) }
                else if line.count >= 35 || line.range(of: #"^\d+[.)]"#, options: .regularExpression) != nil { result.steps.append(clean) }
            }
        }
        if result.ingredients.isEmpty || result.steps.isEmpty { result.warnings.append("Some fields need review after text recognition.") }
        return result
    }
}

@MainActor
@Observable
final class HarvestModel {
    /// Increment whenever an import/model fix must be applied to historical recipes.
    /// The versioned pass repairs local records and seeds their sources for bounded reparse.
    static let currentRecipeRepairRevision = 4

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
    var isImportingPage = false
    var isDiscovering = false
    /// URLs requested (via the Browse screen's per-category or "Import all ready"
    /// buttons, or a direct-import call) while an import was already running.
    /// Previously these were silently dropped — a click while Autopilot's own
    /// background import was in flight had no visible effect and no queued
    /// follow-up. Now they wait here and run automatically the moment the
    /// current import finishes.
    private var pendingManualImportURLs: [String] = []
    /// Set when the user presses Import while a bulk-verify pass is running (usually a
    /// stalled one). The verify pass is cancelled, and its completion handler starts
    /// the import with whatever survived instead of dropping the press on the floor.
    private var importAfterBulkVerify = false
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
    /// One durable, unfiltered discovery snapshot per source. These summaries let the
    /// picker show what can be reused without loading every report into the UI.
    var sourceCacheSummaries: [String: SourceDiscoveryCacheSummary] = [:]
    /// Number of category/listing pages whose mined recipe links can be reused offline.
    var cachedMinedPageCount = 0
    var retroactiveRefreshRemaining = 0
    /// Build 101: the category catalog — one entry per source, each holding the categories
    /// discovered on it (organized, with a cached-recipe count). Browseable and cached.
    var sourceCategories: [String: SourceCategoryCatalog] = [:]
    /// Sources still to visit in the current auto-rotate run.
    var autoRotateRemaining = 0
    /// Explicitly selected sources still waiting their turn (multi-select browsing).
    var sourceRotationQueue: [String] = []
    @ObservationIgnored private var rotationQueueOnly = false
    /// Build 101: set when the user presses Stop during autopilot, so the rotation and
    /// mined-import continuation halt instead of rolling on to the next source.
    @ObservationIgnored private var autopilotStopRequested = false
    @ObservationIgnored private var activeRawDiscoveryReport: DiscoveryReport?
    @ObservationIgnored private var activeReportCameFromCache = false
    // ── Build 95 (Importing) ────────────────────────────────────────────
    /// Failed imports from the current/last run, newest last, capped at 50.
    var lastFailures: [ImportFailure] = []
    /// One line describing how the last import run went.
    var lastImportSummary: String?
    /// One-level undo for explicit queue edits. Importing intentionally does not use it:
    /// restoring already-imported URLs would create a misleading duplicate queue.
    private(set) var queueUndoText: String?
    @ObservationIgnored private var minedURLs: [String] = []
    /// Every link that arrived via category-page mining THIS SESSION. A link is only
    /// ever mined once (no re-expanding the same URL, no re-queuing it twice).
    @ObservationIgnored private var sessionMinedSet: Set<String> = []
    /// Build 102: how many hops of category-page mining a link is from an original,
    /// directly-discovered candidate. Sites nest roundup/collection posts inside other
    /// roundup posts (a "40 favorite appetizers" post that links to a "9 favorite
    /// things" post that links to the actual dish) — one flat generation limit stopped
    /// expanding after the first hop and just dropped the rest as dead ends. This tracks
    /// depth per link instead, so mining recurses automatically in the background until
    /// it bottoms out at real recipes or hits `maxMineDepth`.
    @ObservationIgnored private var mineDepth: [String: Int] = [:]
    private let maxMineDepth = 4
    /// Rolled up across a whole import pass so category mining reports ONE summary line
    /// instead of one log entry per hub page — the Activity feed should read as "these
    /// recipes were found," not "these category pages were opened."
    @ObservationIgnored private var minedPagesThisPass = 0
    @ObservationIgnored private var minedLinksThisPass = 0
    @ObservationIgnored private var mineDepthLimitHitThisPass = 0
    /// Consecutive failures per host this run; 8 trips the breaker for that host.
    @ObservationIgnored private var hostFailureStreaks: [String: Int] = [:]
    @ObservationIgnored private var trippedHosts: Set<String> = []
    @ObservationIgnored private var skippedByBreaker = 0
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
    var pythonWorkerStatus = "Checking Python parser…"
    var pythonWorkerTestPassed: Bool?
    var isTestingPythonWorker = false
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
    /// URLs owned by the current batch but not yet resolved. Cancellation puts these
    /// back at the front of the durable queue instead of losing them.
    @ObservationIgnored private var activeImportPending: Set<String> = []
    @ObservationIgnored private var activeRetroactiveRefresh: Set<String> = []
    @ObservationIgnored private var retroactiveRunActive = false
    @ObservationIgnored private var retroactiveAttemptedThisRun: Set<String> = []

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
    @ObservationIgnored private let pythonParser: PythonWorkerClient
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
        importText = (try? String(contentsOf: resolved.paths.importQueueFile, encoding: .utf8)) ?? ""

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
        let pythonParser = PythonWorkerClient.locate()
        self.pythonParser = pythonParser
        coordinator = CrawlCoordinator(
            store: recipeStore,
            registry: sourceRegistry,
            fetcher: fetcher,
            imageStore: imageStore,
            pythonParser: pythonParser
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
            settings.selectedBrowseCategoryIDs = settings.selectedBrowseCategoryIDs.filter {
                RecipeBrowseTaxonomy.byID[$0] != nil
            }
            pythonWorkerAvailable = pythonParser.isAvailable
            pythonWorkerStatus = pythonParser.availabilityMessage
            logs = await logStore.recent(limit: 200)
            loadSessionHistory()
            reloadMiningCacheCount()
            loadCategoryCatalog()
            await reload()
            await runRetroactiveRecipeRepairsIfNeeded()
            // Bring back the last browse and apply today's category selection to the
            // unfiltered saved report. Changing filters never destroys cached links.
            if let restored = loadLastReport() {
                activeRawDiscoveryReport = restored
                activeReportCameFromCache = true
                discoveryReport = categoryFilteredReport(restored, fromCache: true)
            }
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
            let removedDrafts = try await recipeStore.purgeImageLessImports()
            var removedShared = 0
            if let kitchen {
                let invalid = Set(kitchen.recipes.filter(Self.isImportedWithoutUsableImage).map(\.id))
                removedShared = invalid.count
                kitchen.deleteRecipe(ids: invalid)
            }
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
            if removedDrafts + removedShared > 0 {
                log(.warning, "Removed \(removedDrafts + removedShared) previously imported recipe\(removedDrafts + removedShared == 1 ? "" : "s") without a usable image.")
            }
        } catch {
            present(error)
        }
    }

    private static func isImportedWithoutUsableImage(_ recipe: UserRecipe) -> Bool {
        guard recipe.sourceURL?.nilIfBlank != nil else { return false }
        if let data = recipe.imageData, !data.isEmpty { return false }
        guard let raw = recipe.imageURL?.nilIfBlank,
              let url = URL(string: raw), url.scheme == "https", url.host != nil else { return true }
        return false
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
            if isBulkVerifying {
                // A verify pass is already running — possibly stalled on a slow or
                // unresponsive site. An Import press must never be a dead click:
                // stop the running pass and import as soon as it lets go.
                importAfterBulkVerify = true
                cancelBulkVerify()
                statusMessage = "Stopping the running verification — the import starts the moment it stops."
                return
            }
            bulkVerifyQueue(thenImport: true)
            return
        }
        // Build 99: Import DRAINS the queue now — taken URLs leave the text, and an
        // import-batch size takes only the first N, leaving the rest for next press.
        let all = parsedImportURLs()
        guard !all.isEmpty else {
            errorMessage = "Enter at least one http or https recipe URL."
            return
        }
        let batchSize = settings.importBatchSize
        let batch = (batchSize > 0 && all.count > batchSize) ? Array(all.prefix(batchSize)) : all
        let rest = Array(all.dropFirst(batch.count))
        importText = rest.joined(separator: "\n")
        persistImportQueue()
        if !rest.isEmpty {
            log(.info, "Importing \(batch.count) URLs; \(rest.count) stay queued for the next batch.")
        }
        beginImport(batch)
    }

    /// Imports a set of URLs immediately — used by the Browse screen so a
    /// verified recipe can be pulled in without a round-trip through the
    /// Import text box.
    func importDirect(_ rawURLs: [String], parserModeOverride: ParserMode? = nil) {
        var seen = Set<String>()
        let urls = rawURLs
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .filter { seen.insert($0).inserted }
        let batchSize = max(1, settings.importBatchSize)
        let batch = Array(urls.prefix(batchSize))
        let remainder = Array(urls.dropFirst(batch.count))
        if !remainder.isEmpty { _ = prependImportURLs(remainder) }
        beginImport(batch, parserModeOverride: parserModeOverride)
    }

    /// Appends URLs to the import box without disturbing what is already typed.
    func appendImportURLs(_ rawURLs: [String]) {
        let existing = Set(parsedImportURLs())
        var seen = Set<String>()
        let available = max(0, settings.queueCap - existing.count)
        let additions = rawURLs
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .filter { seen.insert($0).inserted && !existing.contains($0) }
            .prefix(available)
        guard !additions.isEmpty else {
            statusMessage = available == 0
                ? "The queue is at its \(settings.queueCap)-recipe limit. Import a batch to make room."
                : "No new recipe URLs were found in that."
            return
        }
        let prefix = importText.nilIfBlank.map { $0 + "\n" } ?? ""
        importText = prefix + additions.joined(separator: "\n")
        persistImportQueue()
        statusMessage = "Added \(additions.count) URL\(additions.count == 1 ? "" : "s")"
    }

    /// Adds URLs to the FRONT of the import queue (Build 100). Recipes surfaced by
    /// mining a category page jump ahead of everything already queued, so the next
    /// verify/import pass — which always works front-first — checks and imports them
    /// first. This is the other half of "avoid mining, but never lose what it found".
    /// Returns the number of URLs actually added.
    @discardableResult
    func prependImportURLs(_ rawURLs: [String]) -> Int {
        let existing = Set(parsedImportURLs())
        var seen = Set<String>()
        let available = max(0, settings.queueCap - existing.count)
        let additions = rawURLs
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .filter { seen.insert($0).inserted && !existing.contains($0) }
            .prefix(available)
        guard !additions.isEmpty else { return 0 }
        let suffix = importText.nilIfBlank.map { "\n" + $0 } ?? ""
        importText = additions.joined(separator: "\n") + suffix
        persistImportQueue()
        return additions.count
    }

    /// Saves the queue independently of app settings and recipe data. The Browse text
    /// editor calls this as it changes, and every programmatic queue mutation calls it.
    func persistImportQueue() {
        do {
            try Data(importText.utf8).write(to: paths.importQueueFile, options: .atomic)
        } catch {
            log(.warning, "Could not cache the import queue: \(error.localizedDescription)")
        }
    }

    /// Pulls every http(s) URL out of the clipboard, whatever it is wrapped in.
    func pasteURLsFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.nilIfBlank else {
            statusMessage = "The clipboard has no text."
            return
        }
        appendImportText([text])
    }

    /// Accepts rich/plain pasted or dropped text and extracts every embedded web link.
    func appendImportText(_ values: [String]) {
        let found = values.flatMap { value -> [String] in
            let matches = value.matches(#"https?://[^\s"'<>\)\]]+"#, group: 0)
            return matches.isEmpty ? [value] : matches
        }
        appendImportURLs(found)
    }

    /// Creates a reviewable draft from pasted or OCR text. This is intentionally
    /// conservative: uncertain text is kept as a warning instead of invented data.
    func importRecipeText(_ raw: String, sourceLabel: String = "Pasted text") {
        let parsed = MacRecipeTextParser.parse(raw)
        guard !parsed.title.isEmpty || !parsed.ingredients.isEmpty || !parsed.steps.isEmpty else {
            statusMessage = "No recipe structure was found in that text."
            return
        }
        var warnings = parsed.warnings
        if parsed.ingredients.isEmpty { warnings.append("No ingredients were recognized.") }
        if parsed.steps.isEmpty { warnings.append("No instructions were recognized.") }
        let sourceURL = "stocked-text://\(UUID().uuidString)"
        let draft = RecipeDraft(
            title: parsed.title.nilIfBlank ?? "Imported Recipe",
            summary: "Imported from \(sourceLabel)",
            source: HarvestSource(url: sourceURL, canonicalURL: nil, host: sourceLabel,
                                  author: nil, attribution: sourceLabel),
            ingredientSections: parsed.ingredients.isEmpty ? [] : [IngredientSection(
                name: nil, items: parsed.ingredients.map { IngredientItem(raw: $0, quantity: nil,
                    quantityText: nil, unit: nil, name: nil, preparation: nil, notes: nil) })],
            instructionSections: parsed.steps.isEmpty ? [] : [InstructionSection(name: nil, steps: parsed.steps)],
            confidence: parsed.confidence,
            warnings: warnings,
            parser: "mac-text",
            sourceFingerprint: Hashing.sha256(sourceURL)
        )
        Task {
            do {
                let saved = try await recipeStore.upsert(draft)
                await reload()
                selectedRecipeID = saved.id
                statusMessage = "Imported \(saved.title) for review · \(parsed.ingredients.count) ingredients · \(parsed.steps.count) steps"
            } catch { present(error) }
        }
    }

    private func beginImport(
        _ urls: [String],
        parserModeOverride: ParserMode? = nil,
        forceRefresh: Bool = false
    ) {
        guard !urls.isEmpty else {
            errorMessage = "Enter at least one http or https recipe URL."
            return
        }
        // An import (often Autopilot's own background pass) is already running.
        // Queue this request instead of dropping it — it starts automatically
        // as soon as the current import finishes, and the user sees why nothing
        // happened immediately instead of a dead click.
        guard !isImporting else {
            var seen = Set(pendingManualImportURLs)
            let additions = urls.filter { seen.insert($0).inserted }
            pendingManualImportURLs.append(contentsOf: additions)
            statusMessage = "Import already in progress — \(pendingManualImportURLs.count) recipe\(pendingManualImportURLs.count == 1 ? "" : "s") queued to start right after."
            return
        }
        if !isRetryPass {
            pendingAutoApproval.removeAll()
            retryQueue.removeAll()
            lastFailures.removeAll()
            lastImportSummary = nil
            autoApprovedThisRun = 0
            minedURLs.removeAll()
            hostFailureStreaks.removeAll()
            trippedHosts.removeAll()
            skippedByBreaker = 0
        }

        isImporting = true
        activeImportPending = Set(urls)
        importProgress = ImportProgress(
            completed: 0, total: urls.count, succeeded: 0, failed: 0, currentURL: nil
        )
        statusMessage = "Importing \(urls.count) recipe\(urls.count == 1 ? "" : "s")…"
        let activeSettings = settings
        let concurrency = max(1, min(activeSettings.maximumConcurrentJobs, 8))
        let coordinator = coordinator
        let store = recipeStore

        importTask = Task { [weak self] in
            // Skip what the library already holds BEFORE spending requests on it —
            // re-running a big queue no longer re-fetches every known recipe.
            var urls = urls
            if activeSettings.skipAlreadyImported, !forceRefresh,
               let known = try? await store.knownSourceURLs(), !known.isEmpty {
                let before = urls.count
                urls = urls.filter { !known.contains($0) }
                let skipped = before - urls.count
                self?.activeImportPending.formIntersection(urls)
                if skipped > 0 {
                    self?.importProgress.total = urls.count
                    self?.log(.info, "Skipped \(skipped) URL\(skipped == 1 ? "" : "s") already in the library.")
                }
            }
            guard !urls.isEmpty else {
                self?.isImporting = false
                self?.statusMessage = "Everything queued is already in the library."
                self?.importTask = nil
                if let self, !self.pendingManualImportURLs.isEmpty {
                    let queued = self.pendingManualImportURLs
                    self.pendingManualImportURLs.removeAll()
                    self.importDirect(queued)
                }
                return
            }
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
                            url: url,
                            settings: activeSettings,
                            parserModeOverride: parserModeOverride,
                            coordinator: coordinator
                        )
                    }
                }

                for await outcome in group {
                    self?.record(outcome)
                    guard !Task.isCancelled, next < urls.count else { continue }
                    if activeSettings.importSpacingSeconds > 0 {
                        try? await Task.sleep(for: .seconds(Double(activeSettings.importSpacingSeconds)))
                    }
                    // The circuit breaker: a host that failed 8 straight times gets its
                    // remaining URLs skipped instead of failing them one by one.
                    var scheduled = false
                    while !scheduled, next < urls.count {
                        let url = urls[next]
                        next += 1
                        if let host = URL(string: url)?.host?.lowercased(),
                           self?.isHostTripped(host) == true {
                            self?.noteBreakerSkip(url)
                            continue
                        }
                        group.addTask {
                            await HarvestModel.performImport(
                                url: url,
                                settings: activeSettings,
                                parserModeOverride: parserModeOverride,
                                coordinator: coordinator
                            )
                        }
                        scheduled = true
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
                self.retroactiveRunActive = false
                self.activeRetroactiveRefresh.removeAll()
                self.retryQueue.removeAll()
                self.pendingAutoApproval.removeAll()
                self.isRetryPass = false
                let recoverable = Array(self.activeImportPending) + self.pendingManualImportURLs + self.minedURLs
                self.pendingManualImportURLs.removeAll()
                self.minedURLs.removeAll()
                let restored = self.prependImportURLs(recoverable)
                self.log(.info, "Stopped safely — restored \(restored) unfinished or newly mined link\(restored == 1 ? "" : "s") to the queue.")
                await self.reload()
            } else {
                await self.finishImportRun()
            }
            // Anything queued while this import was running (e.g. a Categories-tab
            // "Import" click that landed mid-Autopilot-run) starts now.
            if !cancelled, !self.pendingManualImportURLs.isEmpty {
                let queued = self.pendingManualImportURLs
                self.pendingManualImportURLs.removeAll()
                self.importDirect(queued)
            }
        }
    }

    private nonisolated static func performImport(
        url: String,
        settings: AppSettings,
        parserModeOverride: ParserMode?,
        coordinator: CrawlCoordinator
    ) async -> ImportOutcome {
        do {
            let detail = try await coordinator.importRecipe(
                urlString: url,
                settings: settings,
                parserModeOverride: parserModeOverride
            )
            return ImportOutcome(url: url, detail: detail, error: nil)
        } catch is CancellationError {
            return ImportOutcome(url: url, detail: nil, error: "Canceled")
        } catch let CompanionError.listingPage(_, links) {
            return ImportOutcome(url: url, detail: nil,
                                 error: "Category page — its recipes were queued instead", mined: links)
        } catch {
            return ImportOutcome(url: url, detail: nil, error: error.localizedDescription)
        }
    }

    private func record(_ outcome: ImportOutcome) {
        activeImportPending.remove(outcome.url)
        if activeRetroactiveRefresh.contains(outcome.url), outcome.error != "Canceled" {
            activeRetroactiveRefresh.remove(outcome.url)
            retroactiveAttemptedThisRun.insert(outcome.url)
            if outcome.detail?.recipe.image?.hasLocalFile == true {
                removeRetroactiveRefreshURL(outcome.url)
            }
        }
        importProgress.completed += 1
        importProgress.currentURL = outcome.url
        let host = URL(string: outcome.url)?.host?.lowercased()
        if let detail = outcome.detail {
            if let host { hostFailureStreaks[host] = 0 }
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
            let isCompleteAutopilotRecipe = settings.autopilot
                && detail.recipe.standards.requiredPassed
                && detail.recipe.exportProblems.isEmpty
                && detail.recipe.image?.hasLocalFile == true
            if (isCompleteAutopilotRecipe || threshold > 0),
               detail.recipe.reviewState == .needsReview,
               (isCompleteAutopilotRecipe || detail.recipe.confidence >= threshold),
               (isCompleteAutopilotRecipe || detail.recipe.warnings.allSatisfy(Self.isNonBlockingImportWarning)),
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
            if detail.wasUpdate, detail.recipe.reviewState == .approved {
                handOver([detail.recipe])
            }
        } else if outcome.error == "Canceled" {
            // A cancelled import is the user's decision, not a failure — no red row.
        } else if !outcome.mined.isEmpty {
            importProgress.failed += 1
            persistMinedLinks(outcome.mined, for: outcome.url)
            let added = prependImportURLs(outcome.mined)
            log(.info, "Category page cached; queued \(added) newly found recipe link\(added == 1 ? "" : "s").", url: outcome.url)
        } else {
            importProgress.failed += 1
            if let host, Self.countsTowardHostCircuitBreaker(outcome.error) {
                let streak = (hostFailureStreaks[host] ?? 0) + 1
                hostFailureStreaks[host] = streak
                if let disposition = Self.discoveryQuarantineDisposition(for: outcome.error),
                   !trippedHosts.contains(host) {
                    trippedHosts.insert(host)
                    Task { [weak self] in
                        guard let self else { return }
                        if let sourceName = try? await self.sourceRegistry.quarantineDiscoveryHost(
                            host,
                            health: disposition.health,
                            reason: disposition.reason
                        ) {
                            await self.reload()
                            self.log(.warning, "Removed \(sourceName) from automatic discovery: \(disposition.reason). Direct links remain available.")
                        }
                    }
                } else if streak == 5, !trippedHosts.contains(host) {
                    trippedHosts.insert(host)
                    log(.warning, "5 straight access failures from \(host) — skipping the rest of its URLs this run.")
                }
            } else if let host {
                // A parser miss proves the host responded successfully. It is not a
                // network outage and must never suppress hundreds of later recipes.
                hostFailureStreaks[host] = 0
            }
            if Self.isRateLimited(outcome.error) {
                _ = prependImportURLs([outcome.url])
                log(.warning, "Rate limited; deferred this URL to a later import instead of retrying in a loop.", url: outcome.url)
            } else if settings.retryFailedImports, !isRetryPass, Self.isRetryable(outcome.error) {
                retryQueue.append(outcome.url)
            } else if !lastFailures.contains(where: { $0.url == outcome.url }) {
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
            || message.contains("could not be read")
    }

    /// Image recovery and transparent browser fallbacks should not strand an otherwise
    /// complete recipe in Review. Structural/parser warnings still require attention.
    private static func isNonBlockingImportWarning(_ warning: String) -> Bool {
        let value = warning.lowercased()
        return value.contains("image could not be downloaded")
            || value.contains("loaded with the built-in browser")
            || value.contains("followed the web story")
    }

    private static func isRateLimited(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return message.contains("http 429") || message.contains("rate limit")
    }

    /// Only transport/access failures participate in the per-host breaker. Parser and
    /// page-classification misses are content-specific and say nothing about host health.
    private static func countsTowardHostCircuitBreaker(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        if message.contains("could not parse recipe")
            || message.contains("not a recipe")
            || message.contains("category page") {
            return false
        }
        return message.contains("timed out")
            || message.contains("network")
            || message.contains("connection")
            || message.contains("bot wall")
            || message.contains("blocking automated access")
            || message.contains("robots.txt")
            || message.contains("rate limited")
            || message.contains("http 4")
            || message.contains("http 5")
    }

    /// Permanent access restrictions and explicit request limits should not consume
    /// another batch on the next Browse pass. Parser misses deliberately do not enter
    /// this path because they may affect only one malformed page.
    private static func discoveryQuarantineDisposition(
        for message: String?
    ) -> (health: SourceHealth, reason: String)? {
        guard let message = message?.lowercased() else { return nil }
        if message.contains("http 429") || message.contains("rate limited") {
            return (.paused, "the site rate-limited recipe access")
        }
        if message.contains("robots.txt") {
            return (.blocked, "the site disallows automated recipe access")
        }
        if message.contains("http 401") || message.contains("http 402")
            || message.contains("http 403") || message.contains("http 451")
            || message.contains("paywall") || message.contains("subscription required")
            || message.contains("blocking automated access") || message.contains("bot wall") {
            return (.blocked, "recipes require restricted or interactive access")
        }
        return nil
    }

    private func finishImportRun() async {
        // Recover images before approval hands drafts into the shared library. Images are
        // optional, but when recovery succeeds the first synced copy should include it.
        if settings.autoFetchMissingImages {
            let recovered = await fetchMissingImagesInternal(quiet: true)
            if recovered > 0 { await reload() }
        }

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

        // Recipes mined off category pages join the FRONT of the queue (Build 100) —
        // deduplicated against this session's mining, the library, and the queue cap, so
        // rounds CONVERGE instead of snowballing. Leading the queue means the next
        // verify/import pass, which is always front-first, handles them before anything
        // else — mining is avoided where it can be, but what it finds is imported first.
        // Build 102: one roll-up line for however much background mining this pass did,
        // instead of one Activity entry per category/hub page opened. Mining is plumbing —
        // what the user should see is the recipes it turned up, not the pages it visited.
        // The run in one line, kept until the next run starts.
        lastImportSummary = "Imported \(importProgress.succeeded) · auto-approved \(autoApprovedThisRun) · failed \(importProgress.failed)"
            + (skippedByBreaker > 0 ? " · \(skippedByBreaker) skipped by the circuit breaker" : "")
            + (lastFailures.isEmpty ? "" : " — the failures are listed below with retry.")

        // Approved recipes are part of Stocked's shared catalogue. Publishing is
        // automatic so every Stocked install can discover them; the setting remains
        // visible as status for older preference files but no longer gates delivery.
        syncApprovedToCloud()

        // A historical refresh is a finite, shrinking backlog. Continue in bounded
        // batches while idle; Stop cancels the chain and leaves every unfinished URL on
        // disk for the next launch or manual Resume.
        if retroactiveRunActive {
            if retroactiveRefreshRemaining > 0 {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.refreshNextHistoricalBatch()
                }
                return
            }
            retroactiveRunActive = false
            statusMessage = "Historical recipe refresh complete."
            log(.success, "Every previously imported source has been refreshed for repair v\(Self.currentRecipeRepairRevision).")
        }

        // Selected sources first, then auto-rotate, until both runs are used up.
        if !autopilotStopRequested, !isDiscovering, advanceSourceRotation() {
            return
        }
        if autoRotateRemaining > 0, !isDiscovering, !autopilotStopRequested {
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
        retroactiveRunActive = false
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

    /// Parsed queue information powers the preview, domain summary, validation badges,
    /// and the import pipeline from one canonical normalization pass.
    var queueSnapshot: ImportQueueSnapshot {
        Self.makeQueueSnapshot(from: importText)
    }

    var queuedURLs: [String] {
        queueSnapshot.entries.map(\.url)
    }

    /// Number of unique, valid http(s) URLs currently in the import queue text box.
    var queuedURLCount: Int {
        queueSnapshot.entries.count
    }

    /// Crawls a source and always adds found URLs to the queue (ignores autoImportVerified).
    func discoverToQueue(_ source: SourceProfile) {
        discover(source, addToQueueOnly: true)
    }

    func discover(
        _ source: SourceProfile,
        addToQueueOnly: Bool = false,
        forceRefresh: Bool = false,
        queueResults: Bool = true
    ) {
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
        autopilotStopRequested = false
        rememberSource(source.id)
        let activeSettings = settings
        let reusableReport = activeSettings.reuseCachedDiscoveryResults && !forceRefresh
            ? cachedReport(for: source.id)
            : nil
        discoveryProgress = DiscoveryProgress(
            phase: reusableReport == nil ? "Starting" : "Loading saved results",
            currentURL: nil, pagesFetched: 0,
            queued: 0, confirmed: 0, rejected: 0
        )
        statusMessage = reusableReport == nil
            ? "Discovering recipes on \(source.name)…"
            : "Using saved results for \(source.name)…"
        let coordinator = coordinator

        discoveryTask = Task { [weak self] in
            defer { self?.isDiscovering = false }
            do {
                let rawReport: DiscoveryReport
                let fromCache: Bool
                if let reusableReport {
                    rawReport = reusableReport
                    fromCache = true
                    self?.discoveryProgress = DiscoveryProgress(
                        phase: "Saved results ready",
                        currentURL: nil,
                        pagesFetched: 0,
                        queued: 0,
                        confirmed: reusableReport.confirmed.count,
                        rejected: reusableReport.rejected.count
                    )
                } else {
                    let outcome = try await coordinator.discoverRecipeURLs(
                        source: source,
                        settings: activeSettings,
                        manual: true,
                        progress: { [weak self] update in
                            guard let self else { return }
                            await self.updateDiscoveryProgress(update)
                        }
                    )
                    rawReport = outcome.report
                    fromCache = false
                    // Build 101: fold the categories this run surfaced into the source's
                    // catalog and cache each one's recipes, so they're instantly browseable.
                    self?.recordCategories(outcome.categories, for: source)
                }
                guard let self else { return }
                self.activeRawDiscoveryReport = rawReport
                self.activeReportCameFromCache = fromCache
                let report = self.categoryFilteredReport(rawReport, source: source, fromCache: fromCache)
                self.discoveryReport = report
                // Save the complete, unfiltered source result. Category selections can
                // change later without forcing another crawl or losing any links.
                if !fromCache { await self.persistReport(rawReport) }
                let shouldAutoImport = !addToQueueOnly
                    && (self.settings.autoImportVerified || self.settings.autopilot)
                if shouldAutoImport, !report.confirmed.isEmpty {
                    self.importDirect(report.confirmed.map(\.url))
                } else if shouldAutoImport,
                          report.confirmed.isEmpty,
                          !report.unverified.isEmpty {
                    let batch = Array(report.unverified.prefix(self.settings.scanLimit))
                    self.log(
                        .info,
                        "Nothing was verified before the run stopped; checking \(batch.count) of the \(report.unverified.count) links it found."
                    )
                    self.importDirect(batch)
                } else if queueResults {
                    self.queue(report.confirmed)
                }
                self.statusMessage = fromCache
                    ? "\(source.name): reused saved results · \(report.summary)"
                    : "\(source.name): \(report.summary)"
                self.log(
                    report.confirmed.isEmpty ? .warning : .success,
                    "\(source.name) — \(fromCache ? "saved results · " : "")\(report.summary)",
                    url: source.baseURL
                )
                for note in report.notes.prefix(5) {
                    self.log(.info, note, url: source.baseURL)
                }
                // Remember the seed that answered so the next run skips the
                // guessing, and adopt a source that worked into the rotation.
                var updated = source
                var changed = false
                if let seed = rawReport.workingSeed,
                   seed.lowercased().contains("sitemap") || seed.lowercased().contains("feed"),
                   !updated.sitemapURLs.contains(seed) {
                    updated.sitemapURLs.insert(seed, at: 0)
                    updated.sitemapURLs = Array(updated.sitemapURLs.prefix(6))
                    changed = true
                }
                if self.settings.rememberBrowsedSources,
                   !rawReport.confirmed.isEmpty,
                   !updated.discoveryEnabled {
                    updated.discoveryEnabled = true
                    changed = true
                }
                if changed { self.updateSource(updated) }
                if !fromCache {
                    await self.updateHealth(
                        for: source,
                        health: rawReport.confirmed.isEmpty ? .limited : .healthy,
                        message: rawReport.summary
                    )
                }
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
                // Build 102: DiscoveryEngine now absorbs cancellation internally and
                // returns whatever it found instead of throwing, so this branch should
                // be effectively unreachable in normal use. It stays as a backstop for
                // an unexpected cancellation elsewhere (e.g. the known-URLs lookup)
                // that happens before any report exists to import from.
                self?.statusMessage = "Stopped — nothing was found yet to import."
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
        let failed = Set(lastFailures.map(\.url))
        let additions = links.map(\.url).filter { !existing.contains($0) && !failed.contains($0) }
        guard !additions.isEmpty else {
            statusMessage = "Every discovered recipe is already queued."
            return
        }
        let prefix = importText.nilIfBlank.map { $0 + "\n" } ?? ""
        importText = prefix + additions.joined(separator: "\n")
        persistImportQueue()
        statusMessage = "Queued \(additions.count) verified recipe URL\(additions.count == 1 ? "" : "s")"
    }

    var cachedSourceCount: Int { sourceCacheSummaries.count }

    func cacheSummary(for sourceID: String) -> SourceDiscoveryCacheSummary? {
        sourceCacheSummaries[sourceID]
    }

    func refreshDiscovery(_ source: SourceProfile, addToQueueOnly: Bool = false) {
        discover(source, addToQueueOnly: addToQueueOnly, forceRefresh: true)
    }

    /// Re-slices the active unfiltered report immediately when category choices change.
    /// No source request is made and the durable cache remains complete.
    func applyCategoryFilterToCurrentReport() {
        guard let raw = activeRawDiscoveryReport else { return }
        discoveryReport = categoryFilteredReport(raw, fromCache: activeReportCameFromCache)
        if settings.selectedBrowseCategoryIDs.isEmpty {
            statusMessage = "Showing every category · \(raw.confirmed.count) verified links"
        } else {
            statusMessage = "Category filter applied · \(discoveryReport?.confirmed.count ?? 0) matches"
        }
    }

    private func categoryFilteredReport(
        _ raw: DiscoveryReport,
        source explicitSource: SourceProfile? = nil,
        fromCache: Bool
    ) -> DiscoveryReport {
        var report = raw
        let selected = Set(settings.selectedBrowseCategoryIDs)
        let source = explicitSource ?? sources.first { $0.id == raw.sourceID }
        let sourceSignals = ([source?.name].compactMap { $0 } + (source?.tags ?? []))
            .joined(separator: " ")

        var savedSignals: [String: String] = [:]
        for recipe in recipes {
            let signals = ([recipe.title, recipe.summary].compactMap { $0 }
                + recipe.categories + recipe.cuisines + recipe.keywords + recipe.diets)
                .joined(separator: " ")
            savedSignals[Self.discoveryURLKey(recipe.source.url)] = signals
            if let canonical = recipe.source.canonicalURL {
                savedSignals[Self.discoveryURLKey(canonical)] = signals
            }
        }

        func keep(_ link: DiscoveredLink) -> Bool {
            let supplemental = sourceSignals + " " + (savedSignals[Self.discoveryURLKey(link.url)] ?? "")
            return RecipeBrowseTaxonomy.matches(
                link,
                selectedIDs: selected,
                supplementalText: supplemental
            )
        }

        if !selected.isEmpty {
            report.candidates = raw.candidates.filter(keep)
            report.confirmed = raw.confirmed.filter(keep)
            report.unverified = raw.unverified.filter {
                keep(DiscoveredLink(url: $0, title: nil, imageURL: nil))
            }
            let names = selected.compactMap { RecipeBrowseTaxonomy.byID[$0]?.name }.sorted()
            let selection = names.prefix(4).joined(separator: ", ")
                + (names.count > 4 ? " +\(names.count - 4) more" : "")
            report.notes.insert(
                "Category filter: \(report.confirmed.count) of \(raw.confirmed.count) verified links match \(selection).",
                at: 0
            )
        }
        if fromCache {
            report.notes.insert(
                "Reused the saved \(raw.sourceName) result from \(raw.finishedAt.formatted(date: .abbreviated, time: .shortened)); the website was not read again.",
                at: 0
            )
        }
        return report
    }

    private nonisolated static func discoveryURLKey(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw.lowercased() }
        return URLSafety.normalized(url).absoluteString.lowercased()
    }

    private func sourceCacheURL(for sourceID: String) -> URL {
        paths.sourceDiscoveryCache
            .appendingPathComponent(String(Hashing.sha256(sourceID).prefix(24)))
            .appendingPathExtension("json")
    }

    private func miningCacheURL(for pageURL: String) -> URL {
        let key = Self.discoveryURLKey(pageURL)
        return paths.miningResultCache
            .appendingPathComponent(String(Hashing.sha256(key).prefix(32)))
            .appendingPathExtension("json")
    }

    private func cachedMinedLinks(for pageURL: String) -> [String]? {
        guard let data = try? Data(contentsOf: miningCacheURL(for: pageURL)),
              let record = try? JSONCoding.decoder().decode(MinedPageCacheRecord.self, from: data),
              !record.recipeURLs.isEmpty else { return nil }
        return record.recipeURLs
    }

    private func persistMinedLinks(_ rawLinks: [String], for pageURL: String) {
        var seen = Set<String>()
        let links = rawLinks
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
            .filter { seen.insert($0).inserted }
        guard !links.isEmpty else { return }
        let file = miningCacheURL(for: pageURL)
        let isNew = !FileManager.default.fileExists(atPath: file.path)
        let record = MinedPageCacheRecord(
            pageURL: Self.discoveryURLKey(pageURL),
            savedAt: Date(),
            recipeURLs: links
        )
        guard let data = try? JSONCoding.encoder().encode(record) else { return }
        do {
            try data.write(to: file, options: .atomic)
            if isNew { cachedMinedPageCount += 1 }
        } catch {
            log(.warning, "Could not save mined links for later reuse: \(error.localizedDescription)", url: pageURL)
        }
    }

    private func reloadMiningCacheCount() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: paths.miningResultCache,
            includingPropertiesForKeys: nil
        )) ?? []
        cachedMinedPageCount = files.filter { $0.pathExtension == "json" }.count
    }

    // MARK: - Category catalog (Build 101)

    private func categoryCatalogURL(for sourceID: String) -> URL {
        paths.categoryCatalog
            .appendingPathComponent(String(Hashing.sha256(sourceID).prefix(24)))
            .appendingPathExtension("json")
    }

    /// Every discovered category across sources, most-ready first — for the browser.
    var allCategories: [SourceCategory] {
        sourceCategories.values.flatMap(\.categories).sorted { lhs, rhs in
            if lhs.recipeCount != rhs.recipeCount { return lhs.recipeCount > rhs.recipeCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Categories with recipes cached and ready to import right now.
    var readyCategoryCount: Int { allCategories.filter(\.isReady).count }

    /// Folds a run's mined categories into the source's catalog: caches each category's
    /// recipes (so drill-in import is instant), derives its ready count, organizes and
    /// persists. Called after every fresh discovery.
    func recordCategories(_ mined: [MinedCategory], for source: SourceProfile) {
        guard !mined.isEmpty else { return }
        var byID: [String: SourceCategory] = Dictionary(
            uniqueKeysWithValues: (sourceCategories[source.id]?.categories ?? []).map { ($0.id, $0) }
        )
        for cat in mined {
            guard let valid = try? URLSafety.validatedRemoteURL(cat.url) else { continue }
            let url = URLSafety.normalized(valid).absoluteString
            let id = String(Hashing.sha256(source.id + "|" + url).prefix(24))
            if !cat.recipeURLs.isEmpty { persistMinedLinks(cat.recipeURLs, for: url) }
            let cachedCount = cachedMinedLinks(for: url)?.count ?? cat.recipeURLs.count
            var record = byID[id] ?? SourceCategory(
                id: id, sourceID: source.id, sourceName: source.name,
                url: url, name: cat.name, group: cat.group,
                recipeCount: 0, minedAt: nil, lastImportedAt: nil
            )
            record.name = cat.name
            if let group = cat.group { record.group = group }
            record.recipeCount = max(record.recipeCount, cachedCount)
            if !cat.recipeURLs.isEmpty { record.minedAt = Date() }
            byID[id] = record
        }
        let organized = byID.values.sorted { lhs, rhs in
            if lhs.recipeCount != rhs.recipeCount { return lhs.recipeCount > rhs.recipeCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        let catalog = SourceCategoryCatalog(
            sourceID: source.id, sourceName: source.name,
            updatedAt: Date(), categories: organized
        )
        sourceCategories[source.id] = catalog
        persistCategoryCatalog(catalog)
        let ready = organized.filter(\.isReady).count
        log(.success, "\(source.name): \(organized.count) categories organized, \(ready) ready to import.",
            url: source.baseURL)
    }

    private func persistCategoryCatalog(_ catalog: SourceCategoryCatalog) {
        guard let data = try? JSONCoding.encoder().encode(catalog) else { return }
        try? data.write(to: categoryCatalogURL(for: catalog.sourceID), options: .atomic)
    }

    private func loadCategoryCatalog() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: paths.categoryCatalog, includingPropertiesForKeys: nil
        )) ?? []
        var loaded: [String: SourceCategoryCatalog] = [:]
        let decoder = JSONCoding.decoder()
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let catalog = try? decoder.decode(SourceCategoryCatalog.self, from: data) {
                loaded[catalog.sourceID] = catalog
            }
        }
        sourceCategories = loaded
    }

    private func markCategoryImported(_ category: SourceCategory) {
        guard var catalog = sourceCategories[category.sourceID],
              let idx = catalog.categories.firstIndex(where: { $0.id == category.id }) else { return }
        catalog.categories[idx].lastImportedAt = Date()
        sourceCategories[category.sourceID] = catalog
        persistCategoryCatalog(catalog)
    }

    /// Import a category's recipes. Cached ones import instantly with no refetch; an
    /// unmined category is queued so the importer mines and imports it autonomously.
    func importCategory(_ category: SourceCategory) {
        markCategoryImported(category)
        if let recipes = cachedMinedLinks(for: category.url), !recipes.isEmpty {
            statusMessage = "Importing \(recipes.count) recipe\(recipes.count == 1 ? "" : "s") from \(category.name)…"
            importDirect(recipes)
        } else {
            statusMessage = "Mining \(category.name) and importing what it holds…"
            importDirect([category.url])
        }
    }

    /// Cached recipe URLs known for a category, if any (used by the browser for counts).
    func cachedRecipes(for category: SourceCategory) -> [String] {
        cachedMinedLinks(for: category.url) ?? []
    }

    /// Import every ready (already-mined) category's recipes in one press — no refetch.
    func importAllReadyCategories() {
        let ready = allCategories.filter(\.isReady)
        var seen = Set<String>()
        let urls = ready.flatMap { cachedRecipes(for: $0) }.filter { seen.insert($0).inserted }
        guard !urls.isEmpty else {
            statusMessage = "No cached category recipes to import yet."
            return
        }
        ready.forEach { markCategoryImported($0) }
        statusMessage = "Importing \(urls.count) recipe\(urls.count == 1 ? "" : "s") from \(ready.count) ready categor\(ready.count == 1 ? "y" : "ies")…"
        importDirect(urls)
    }

    private func cachedReport(for sourceID: String) -> DiscoveryReport? {
        let decoder = JSONCoding.decoder()
        if let data = try? Data(contentsOf: sourceCacheURL(for: sourceID)),
           let report = try? decoder.decode(DiscoveryReport.self, from: data) {
            return report
        }
        // Existing installations already have session reports. Treat the newest one as
        // an immediate cache hit; the next fresh crawl materializes the stable cache file.
        return sessionHistory.first { $0.sourceID == sourceID }
    }

    private func persistReport(_ report: DiscoveryReport) async {
        guard let data = try? JSONCoding.encoder().encode(report) else { return }
        // Stable per-source copy: an anomalous empty refresh must not destroy a useful
        // earlier result. The empty run remains in history for diagnosis, and Refresh
        // can replace the cache once the site answers normally again.
        let cacheURL = sourceCacheURL(for: report.sourceID)
        let existing: DiscoveryReport?
        if let existingData = try? Data(contentsOf: cacheURL) {
            existing = try? JSONCoding.decoder().decode(DiscoveryReport.self, from: existingData)
        } else {
            existing = nil
        }
        let reportHasLinks = !report.candidates.isEmpty
            || !report.confirmed.isEmpty
            || !report.unverified.isEmpty
        let existingHasLinks = existing.map {
            !$0.candidates.isEmpty || !$0.confirmed.isEmpty || !$0.unverified.isEmpty
        } ?? false
        if reportHasLinks || !existingHasLinks {
            try? data.write(to: cacheURL, options: .atomic)
            sourceCacheSummaries[report.sourceID] = SourceDiscoveryCacheSummary(
                sourceID: report.sourceID,
                sourceName: report.sourceName,
                savedAt: report.finishedAt,
                resultCount: report.confirmed.count
            )
        } else {
            log(.warning, "The refreshed \(report.sourceName) result was empty; kept its last useful saved result.")
        }
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
            discover(source, forceRefresh: true)
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
        let eligible = sources.filter {
            $0.enabled && $0.discoveryEnabled && $0.discoveryMode.supportsDiscovery
                && $0.health != .blocked && $0.health != .paused
        }
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
                    syncApprovedToCloud()
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

    // MARK: - Versioned historical repairs

    /// Applies every repair revision once, then reparses a finite slice of old source
    /// pages. The durable backlog means quitting, cancellation, or a rate limit cannot
    /// make historical recipes miss a future parser fix.
    private func runRetroactiveRecipeRepairsIfNeeded() async {
        loadRetroactiveRefreshCount()
        guard settings.recipeRepairRevision < Self.currentRecipeRepairRevision else {
            if retroactiveRefreshRemaining > 0 { refreshNextHistoricalBatch() }
            return
        }

        let repairedDrafts = (try? await recipeStore.repairExisting()) ?? 0
        await reload()
        let repairedShared = repairSharedRecipeLibrary()

        var sources = retroactiveRefreshURLs()
        sources.append(contentsOf: recipes.compactMap {
            $0.source.canonicalURL?.nilIfBlank ?? $0.source.url.nilIfBlank
        })
        if let kitchen {
            sources.append(contentsOf: kitchen.recipes.compactMap(\.sourceURL))
        }
        persistRetroactiveRefreshURLs(sources)

        settings.recipeRepairRevision = Self.currentRecipeRepairRevision
        scheduleSettingsSave()
        log(.success, "Historical repair v\(Self.currentRecipeRepairRevision): normalized \(repairedDrafts) imported draft\(repairedDrafts == 1 ? "" : "s") and \(repairedShared) shared recipe\(repairedShared == 1 ? "" : "s"); \(retroactiveRefreshRemaining) source page\(retroactiveRefreshRemaining == 1 ? "" : "s") queued for bounded refresh.")
        refreshNextHistoricalBatch()
    }

    /// Public so Recipe Sync can advance the backlog without changing normal imports.
    func refreshNextHistoricalBatch() {
        guard !isImporting, !isDiscovering, !isBulkVerifying else {
            statusMessage = "Historical refresh will continue when current recipe work finishes."
            return
        }
        let allURLs = retroactiveRefreshURLs()
        let urls = allURLs.filter { !retroactiveAttemptedThisRun.contains($0) }
        if urls.isEmpty, !allURLs.isEmpty {
            retroactiveRunActive = false
            statusMessage = "Historical refresh paused — \(allURLs.count) source\(allURLs.count == 1 ? "" : "s") still need an image and will retry next launch."
            return
        }
        guard !urls.isEmpty else {
            retroactiveRefreshRemaining = 0
            statusMessage = "Every historical recipe has the latest repair."
            return
        }
        let batch = Array(urls.prefix(max(1, settings.retroactiveRefreshBatchSize)))
        activeRetroactiveRefresh = Set(batch)
        retroactiveRunActive = true
        statusMessage = "Refreshing \(batch.count) historical recipe\(batch.count == 1 ? "" : "s")…"
        beginImport(batch, forceRefresh: true)
    }

    func restartHistoricalRefresh() {
        retroactiveAttemptedThisRun.removeAll()
        refreshNextHistoricalBatch()
    }

    private func retroactiveRefreshURLs() -> [String] {
        guard let text = try? String(contentsOf: paths.retroactiveRefreshFile, encoding: .utf8) else {
            return []
        }
        var seen = Set<String>()
        return text.components(separatedBy: .newlines).compactMap { raw in
            guard let parsed = try? URLSafety.validatedRemoteURL(raw) else { return nil }
            let normalized = URLSafety.normalized(parsed).absoluteString
            return seen.insert(normalized).inserted ? normalized : nil
        }
    }

    private func persistRetroactiveRefreshURLs(_ rawURLs: [String]) {
        var seen = Set<String>()
        let urls = rawURLs.compactMap { raw -> String? in
            guard let parsed = try? URLSafety.validatedRemoteURL(raw) else { return nil }
            let normalized = URLSafety.normalized(parsed).absoluteString
            return seen.insert(normalized).inserted ? normalized : nil
        }
        try? Data(urls.joined(separator: "\n").utf8)
            .write(to: paths.retroactiveRefreshFile, options: .atomic)
        retroactiveRefreshRemaining = urls.count
    }

    private func removeRetroactiveRefreshURL(_ rawURL: String) {
        guard let parsed = try? URLSafety.validatedRemoteURL(rawURL) else { return }
        let key = URLSafety.normalized(parsed).absoluteString
        persistRetroactiveRefreshURLs(retroactiveRefreshURLs().filter { $0 != key })
    }

    private func loadRetroactiveRefreshCount() {
        retroactiveRefreshRemaining = retroactiveRefreshURLs().count
    }

    /// Backfills optional provenance/categories added after older household recipes were
    /// created. Future local model repairs can be appended here under a new revision.
    private func repairSharedRecipeLibrary() -> Int {
        guard let kitchen else { return 0 }
        var repaired = 0
        for snapshot in kitchen.recipes {
            let metadata = Self.sourceMetadata(from: snapshot.notes)
            let sourceURL = snapshot.sourceURL?.nilIfBlank ?? metadata.url
            let normalizedURL = sourceURL.flatMap { try? URLSafety.validatedRemoteURL($0) }
                .map { URLSafety.normalized($0).absoluteString }
            let sourceName = snapshot.sourceName?.nilIfBlank
                ?? metadata.name
                ?? normalizedURL.flatMap { URL(string: $0)?.host }
            let inferred = RecipeBrowseTaxonomy.inferredCategoryNames(from: [
                snapshot.title,
                snapshot.description,
                snapshot.cuisine,
                snapshot.sourceURL ?? "",
            ] + snapshot.tags + (snapshot.categories ?? []))
            let categories = ((snapshot.categories ?? []) + snapshot.tags + inferred).cleanedUnique()
            guard normalizedURL != snapshot.sourceURL
                    || sourceName != snapshot.sourceName
                    || categories != (snapshot.categories ?? []) else { continue }
            kitchen.updateRecipe(id: snapshot.id) { recipe in
                recipe.sourceURL = normalizedURL
                recipe.sourceName = sourceName
                recipe.categories = categories
            }
            repaired += 1
        }
        return repaired
    }

    private static func sourceMetadata(from notes: String) -> (name: String?, url: String?) {
        guard let line = notes.components(separatedBy: .newlines)
            .first(where: { $0.lowercased().hasPrefix("source:") }) else { return (nil, nil) }
        let value = line.dropFirst("Source:".count).trimmingCharacters(in: .whitespaces)
        let parts = value.components(separatedBy: " — ")
        if parts.count > 1 {
            return (parts[0].nilIfBlank, parts.dropFirst().joined(separator: " — ").nilIfBlank)
        }
        return value.hasPrefix("http") ? (URL(string: value)?.host, value) : (value.nilIfBlank, nil)
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

    /// One-time forward migration when defaults change meaning. Revision 3 makes the
    /// guided flow safe by default: pasted/listing pages are verified and mined before
    /// import, while Automatic remains an explicit choice in Browse.
    private func migrateSettingsIfNeeded() {
        // This is no longer user-adjustable behavior: every launch repairs stale defaults.
        if !settings.requireImageForImport || !settings.downloadImages {
            settings.requireImageForImport = true
            settings.downloadImages = true
            scheduleSettingsSave()
        }
        guard settings.settingsRevision < 10 else { return }
        var changes: [String] = []
        if settings.settingsRevision < 2 {
            if settings.userAgent == AppSettings.legacyUserAgent {
                settings.userAgent = AppSettings.safariUserAgent
            }
            if settings.autoImportVerified {
                settings.autoImportVerified = false
            }
            changes.append("browsing now pauses for review")
        }
        if settings.settingsRevision < 3 {
            settings.verifyBeforeImport = true
            changes.append("queue imports now verify and mine category pages first")
        }
        if settings.settingsRevision < 4 {
            settings.preferDirectRecipes = true
            changes.append("Browse now prefers direct recipe links and mines only when needed; mined recipes are imported first")
        }
        if settings.settingsRevision < 5 {
            settings.autopilot = true
            changes.append("Autopilot is on — one press finds, mines + caches categories, imports and auto-approves hands-off")
        }
        if settings.settingsRevision < 6 {
            settings.cloudSyncEnabled = true
            changes.append("approved recipes now publish to the shared Stocked recipe database automatically")
        }
        if settings.settingsRevision < 7 {
            settings.scanLimit = 50
            if settings.importBatchSize == 0 { settings.importBatchSize = 25 }
            changes.append("browse and import now use explicit finite batches and preserve stopped work")
        }
        if settings.settingsRevision < 8 {
            settings.maximumConcurrentJobs = max(settings.maximumConcurrentJobs, 4)
            settings.autoApproveConfidence = min(settings.autoApproveConfidence, 0.78)
            settings.requireImageForImport = false
            settings.requireStandardsForAutoApprove = false
            settings.verifyBeforeImport = false
            settings.autoRotateSourceCount = max(settings.autoRotateSourceCount, 5)
            settings.queueCap = max(settings.queueCap, 2_000)
            settings.bulkVerifyBatchSize = max(settings.bulkVerifyBatchSize, 200)
            settings.importBatchSize = max(settings.importBatchSize, 50)
            settings.scanLimit = max(settings.scanLimit, 100)
            changes.append("recipe intake now favors complete text over optional images and uses larger finite batches")
        }
        if settings.settingsRevision < 9 {
            settings.retroactiveRefreshBatchSize = max(1, settings.retroactiveRefreshBatchSize)
            settings.requireImageForImport = true
            changes.append("historical imports now receive versioned repairs and bounded source refreshes")
        }
        if settings.settingsRevision < 10 {
            settings.autopilot = true
            settings.autoImportVerified = true
            settings.requireImageForImport = true
            settings.autoFetchMissingImages = true
            changes.append("found recipes now import, approve when complete, and sync without intermediate queue or review steps")
        }
        settings.settingsRevision = 10
        scheduleSettingsSave()
        log(.info, "New Browse flow defaults applied: \(changes.joined(separator: "; ")).")
    }

    /// Reports whether the current browser page is already represented by a harvested
    /// recipe. The browser uses this to say "Update" instead of pretending it is new.
    func isAlreadyImported(_ urlString: String) async -> Bool {
        guard let valid = try? URLSafety.validatedRemoteURL(urlString) else { return false }
        let normalized = URLSafety.normalized(valid).absoluteString
        let known = (try? await recipeStore.knownSourceURLs()) ?? []
        return known.contains(urlString) || known.contains(normalized)
    }

    /// Imports one page immediately — the in-app browser's buttons. `force` skips the
    /// category-page refusal for the rare page the detector reads wrong. Re-importing is
    /// safe: RecipeStore merges by source fingerprint and preserves review decisions.
    func importPage(_ urlString: String, force: Bool = false) {
        guard !isImportingPage else { return }
        let activeSettings = settings
        let coordinator = coordinator
        isImportingPage = true
        statusMessage = "Importing the open page…"
        Task {
            defer { isImportingPage = false }
            do {
                let detail = try await coordinator.importRecipe(
                    urlString: urlString,
                    settings: activeSettings,
                    allowNonRecipePages: force
                )
                selectedRecipeID = detail.recipe.id
                await reload()
                statusMessage = "Imported \(detail.recipe.title)"
                log(.success, "Imported \(detail.recipe.title) from the built-in browser.", url: urlString)
            } catch let CompanionError.listingPage(_, links) {
                appendImportURLs(links)
                log(.info, "That page is a category; queued \(links.count) recipes from it instead.", url: urlString)
            } catch {
                present(error)
                log(.error, error.localizedDescription, url: urlString)
            }
        }
    }

    private func isHostTripped(_ host: String) -> Bool {
        trippedHosts.contains(host)
    }

    private func noteBreakerSkip(_ url: String) {
        activeImportPending.remove(url)
        skippedByBreaker += 1
        importProgress.completed += 1
        importProgress.currentURL = url
    }

    /// One press that answers "are these duplicates?": removes exact duplicates,
    /// everything already in the library, and everything that failed this session —
    /// and says how many of each it removed.
    func cleanQueue() {
        guard importText.nilIfBlank != nil else {
            statusMessage = "The queue is empty."
            return
        }
        let invalid = queueSnapshot.invalidCount
        let raw = importText
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { try? URLSafety.validatedRemoteURL($0) }
            .map { URLSafety.normalized($0).absoluteString }
        let failed = Set(lastFailures.map(\.url))
        let store = recipeStore
        rememberQueueForUndo()
        statusMessage = "Cleaning the queue…"
        Task {
            let known = (try? await store.knownSourceURLs()) ?? []
            var seen = Set<String>()
            var duplicates = 0
            var alreadyImported = 0
            var failedEarlier = 0
            var keep: [String] = []
            for url in raw {
                if !seen.insert(url).inserted { duplicates += 1; continue }
                if known.contains(url) { alreadyImported += 1; continue }
                if failed.contains(url) { failedEarlier += 1; continue }
                keep.append(url)
            }
            importText = keep.joined(separator: "\n")
            persistImportQueue()
            let removed = duplicates + alreadyImported + failedEarlier + invalid
            statusMessage = removed == 0
                ? "Queue is clean — \(keep.count) unique new URLs."
                : "Cleaned: kept \(keep.count) — removed \(duplicates) duplicate\(duplicates == 1 ? "" : "s"), \(invalid) invalid, \(alreadyImported) already imported, \(failedEarlier) failed earlier"
            log(removed == 0 ? .info : .success, statusMessage)
        }
    }

    /// Removes one preview row without forcing the user into the raw text editor.
    func removeQueuedURL(_ url: String) {
        let entries = queuedURLs
        guard entries.contains(url) else { return }
        rememberQueueForUndo()
        importText = entries.filter { $0 != url }.joined(separator: "\n")
        persistImportQueue()
        statusMessage = "Removed 1 URL · \(queuedURLCount) remain"
    }

    /// Moves a URL to the front, which is meaningful when imports are intentionally
    /// processed in bounded batches.
    func prioritizeQueuedURL(_ url: String) {
        var entries = queuedURLs
        guard let index = entries.firstIndex(of: url), index > 0 else { return }
        rememberQueueForUndo()
        let value = entries.remove(at: index)
        entries.insert(value, at: 0)
        importText = entries.joined(separator: "\n")
        persistImportQueue()
        statusMessage = "Moved that recipe to the front of the queue."
    }

    func clearQueue() {
        guard !importText.isEmpty else { return }
        rememberQueueForUndo()
        importText = ""
        persistImportQueue()
        statusMessage = "Queue cleared. Undo is available."
    }

    var canUndoQueueChange: Bool { queueUndoText != nil }

    func undoQueueChange() {
        guard let previous = queueUndoText else { return }
        let current = importText
        importText = previous
        persistImportQueue()
        queueUndoText = current
        statusMessage = "Queue restored · \(queuedURLCount) URL\(queuedURLCount == 1 ? "" : "s")"
    }

    func copyQueueURLs() {
        let value = queuedURLs.joined(separator: "\n")
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        statusMessage = "Copied \(queuedURLCount) queued URL\(queuedURLCount == 1 ? "" : "s")"
    }

    private func rememberQueueForUndo() {
        queueUndoText = importText
    }

    /// Copies every failed URL to the clipboard, one per line.
    func copyFailedURLs() {
        let text = lastFailures.map(\.url).joined(separator: "\n")
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Copied \(lastFailures.count) failed URL\(lastFailures.count == 1 ? "" : "s")"
    }

    /// Copies a support-grade report: unlike "Copy URLs", this preserves the complete
    /// parser chain and local parser health without exposing recipe HTML or user data.
    func copyFailureDiagnostics() {
        guard !lastFailures.isEmpty else { return }
        let header = [
            "Stocked recipe import diagnostics",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Parser mode: \(settings.parserMode.rawValue)",
            "Python parser: \(pythonWorkerStatus)",
            "Failures: \(lastFailures.count)",
        ].joined(separator: "\n")
        let details = lastFailures.enumerated().map { index, failure in
            "\n\(index + 1). \(failure.url)\n   \(failure.reason)"
        }.joined()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(header + details, forType: .string)
        statusMessage = "Copied full import diagnostics"
    }

    /// Re-runs every failed import from the last run.
    func retryFailures() {
        let urls = lastFailures.map(\.url)
        guard !urls.isEmpty else { return }
        lastFailures.removeAll()
        importDirect(urls)
    }

    func retryFailure(_ failure: ImportFailure) {
        lastFailures.removeAll { $0.id == failure.id }
        isRetryPass = true
        importDirect([failure.url])
    }

    /// Bypasses a failing native-first path for this retry without changing the user's
    /// global parser preference. Native/microdata remain available as fallbacks.
    func retryFailuresWithPython() {
        let urls = lastFailures.map(\.url)
        guard pythonWorkerAvailable, !urls.isEmpty else { return }
        lastFailures.removeAll()
        isRetryPass = true
        importDirect(urls, parserModeOverride: .pythonFirst)
    }

    func retryFailureWithPython(_ failure: ImportFailure) {
        guard pythonWorkerAvailable else { return }
        lastFailures.removeAll { $0.id == failure.id }
        isRetryPass = true
        importDirect([failure.url], parserModeOverride: .pythonFirst)
    }

    func clearFailures() {
        lastFailures.removeAll()
    }

    func testPythonWorker() {
        guard pythonWorkerAvailable, !isTestingPythonWorker else { return }
        isTestingPythonWorker = true
        pythonWorkerStatus = "Running live Python parser test…"
        let parser = pythonParser
        Task { [weak self] in
            do {
                let result = try await parser.healthCheck()
                guard let self else { return }
                self.pythonWorkerStatus = result
                self.pythonWorkerTestPassed = true
                self.log(.success, result)
            } catch {
                guard let self else { return }
                self.pythonWorkerStatus = error.localizedDescription
                self.pythonWorkerTestPassed = false
                self.log(.error, "Python parser test failed: \(error.localizedDescription)")
            }
            self?.isTestingPythonWorker = false
        }
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
    func bulkVerifyQueue(thenImport: Bool = false, forceRefreshMining: Bool = false) {
        guard !isBulkVerifying else {
            statusMessage = "A verification pass is already running."
            return
        }
        guard !isImporting else {
            statusMessage = "An import is running — verify again once it finishes."
            return
        }
        let all = parsedImportURLs()
        guard !all.isEmpty else {
            statusMessage = "The queue is empty."
            return
        }
        // A pass checks the FRONT of the queue, up to the batch size from Verification.
        let batchSize = settings.bulkVerifyBatchSize
        let batch = (batchSize > 0 && all.count > batchSize) ? Array(all.prefix(batchSize)) : all
        let rest = Array(all.dropFirst(batch.count))

        // Each explicit verification pass is a new mining session. Links remain in the
        // durable page cache, but an earlier pass must not prevent those saved results
        // from being restored to a newly created queue in the same app launch.
        sessionMinedSet.removeAll()
        isBulkVerifying = true
        bulkVerifyProgress = ImportProgress(
            completed: 0, total: batch.count, succeeded: 0, failed: 0, currentURL: nil
        )
        statusMessage = "Verifying \(batch.count) of \(all.count) queued URL\(all.count == 1 ? "" : "s")…"
        let activeSettings = settings
        let coordinator = coordinator

        bulkVerifyTask = Task { [weak self] in
            var keep: [String] = []
            var dropped = 0
            for url in batch {
                if Task.isCancelled {
                    keep.append(url)            // unchecked URLs stay queued
                    continue
                }
                do {
                    // A page check that never answers must not freeze the whole pass
                    // (a frozen pass leaves isBulkVerifying stuck true, which used to
                    // turn every later Import press into a silent dead click).
                    let check: PageCheck = try await Self.withTimeout(seconds: 45) {
                        try await coordinator.verifyOrMine(
                            urlString: url,
                            settings: activeSettings
                        )
                    }
                    switch check {
                    case .recipe(let resolvedURL):
                        keep.append(resolvedURL ?? url)
                        self?.bulkVerifyProgress.succeeded += 1
                        if let resolvedURL, resolvedURL != url {
                            self?.log(.success, "Web Story resolved to its publisher recipe page.", url: resolvedURL)
                        }
                    case .listing(let mined):
                        dropped += 1
                        self?.persistMinedLinks(mined, for: url)
                        for found in mined where !keep.contains(found) && !rest.contains(found) {
                            keep.append(found)
                        }
                        self?.bulkVerifyProgress.failed += 1
                        self?.log(.info, "Category page — not a recipe, skipped.", url: url)
                    case .other:
                        dropped += 1
                        self?.bulkVerifyProgress.failed += 1
                        self?.log(.warning, "Not a recipe page; removed from the queue.", url: url)
                    }
                } catch {
                    keep.append(url)            // network trouble is not evidence
                    self?.bulkVerifyProgress.failed += 1
                }
                self?.bulkVerifyProgress.completed += 1
                self?.bulkVerifyProgress.currentURL = url
            }
            guard let self else { return }
            let cancelled = Task.isCancelled

            var final = keep + rest
            var capped = 0
            if final.count > self.settings.queueCap {
                capped = final.count - self.settings.queueCap
                final = Array(final.prefix(self.settings.queueCap))
            }
            self.importText = final.joined(separator: "\n")
            self.persistImportQueue()
            self.isBulkVerifying = false
            self.bulkVerifyTask = nil
            var summary = "Verified \(batch.count): kept \(keep.count)"
            if dropped > 0 { summary += ", skipped \(dropped) non-recipe page\(dropped == 1 ? "" : "s")" }
            if !rest.isEmpty { summary += " · \(rest.count) unchecked stay queued" }
            if capped > 0 { summary += " · \(capped) over the queue cap left out" }
            self.statusMessage = cancelled ? "Verify stopped — " + summary : summary
            self.log(.success, "Bulk verify: " + summary)
            // An Import press that arrived while this pass was running (and cancelled
            // it) must follow through now — a cancelled pass keeps unchecked URLs, so
            // there is always something sensible to import.
            let breakThrough = self.importAfterBulkVerify
            self.importAfterBulkVerify = false
            if !final.isEmpty, (thenImport && !cancelled) || breakThrough {
                self.importURLs(skipVerify: true)
            }
        }
    }

    func cancelBulkVerify() {
        bulkVerifyTask?.cancel()
        statusMessage = "Stopping verification…"
    }

    /// Races an operation against a deadline. Rethrows the operation's own error; a
    /// missed deadline throws `CancellationError`, and the loser is cancelled either way.
    private nonisolated static func withTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            guard let winner = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return winner
        }
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
        let batch = approvedRecipes.filter { $0.image?.hasLocalFile == true }
        guard !batch.isEmpty else {
            cloudSyncStatus = "Nothing approved to sync yet."
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

    /// Publishes the Recipes-sidebar collection, including recipes that predate the
    /// Harvester approval flow. Safe on every launch because the Worker upserts by UUID.
    func syncKitchenToCloud(_ recipes: [UserRecipe]) {
        guard !isCloudSyncing, !recipes.isEmpty, MacWorkerClient.isConfigured else { return }
        isCloudSyncing = true
        cloudSyncStatus = "Syncing all \(recipes.count) kitchen recipes…"
        Task { [weak self] in
            do {
                let result = try await HarvestCloudSync.pushKitchenRecipes(recipes)
                self?.cloudSyncStatus = "Synced all \(result.recipes) kitchen recipes to iPhone and iPad."
                self?.log(.success, "Shared catalog backfill: \(result.recipes) recipes uploaded.")
            } catch {
                self?.cloudSyncStatus = "Full catalog sync failed: \(error.localizedDescription)"
                self?.log(.error, "Shared catalog backfill failed: \(error.localizedDescription)")
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
        let reports = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DiscoveryReport? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(DiscoveryReport.self, from: data)
            }
            .sorted { $0.finishedAt > $1.finishedAt }
        sessionHistory = Array(reports.prefix(20))
        rebuildSourceCacheSummaries(historicalReports: reports)
    }

    private func rebuildSourceCacheSummaries(historicalReports: [DiscoveryReport]) {
        func hasLinks(_ report: DiscoveryReport) -> Bool {
            !report.candidates.isEmpty || !report.confirmed.isEmpty || !report.unverified.isEmpty
        }
        var stableReports: [String: DiscoveryReport] = [:]
        let stableFiles = (try? FileManager.default.contentsOfDirectory(
            at: paths.sourceDiscoveryCache,
            includingPropertiesForKeys: nil
        )) ?? []
        let decoder = JSONCoding.decoder()
        for url in stableFiles where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let report = try? decoder.decode(DiscoveryReport.self, from: data) else { continue }
            if (stableReports[report.sourceID]?.finishedAt ?? .distantPast) < report.finishedAt {
                stableReports[report.sourceID] = report
            }
        }
        // Upgrade every existing discovery history automatically. This gives longtime
        // installs the same skip-and-reuse behavior immediately, even when a source's
        // last visit is older than the 20 sessions shown in the UI.
        var newestHistorical: [String: DiscoveryReport] = [:]
        var newestUsefulHistorical: [String: DiscoveryReport] = [:]
        for report in historicalReports {
            if (newestHistorical[report.sourceID]?.finishedAt ?? .distantPast) < report.finishedAt {
                newestHistorical[report.sourceID] = report
            }
            if hasLinks(report),
               (newestUsefulHistorical[report.sourceID]?.finishedAt ?? .distantPast) < report.finishedAt {
                newestUsefulHistorical[report.sourceID] = report
            }
        }
        for (sourceID, newest) in newestHistorical {
            let report = newestUsefulHistorical[sourceID] ?? newest
            let existing = stableReports[sourceID]
            let existingHasLinks = existing.map(hasLinks) ?? false
            let shouldReplace = existing == nil
                || (hasLinks(report) && !existingHasLinks)
                || (report.finishedAt > (existing?.finishedAt ?? .distantPast)
                    && (hasLinks(report) || !existingHasLinks))
            guard shouldReplace else { continue }
            guard let data = try? JSONCoding.encoder().encode(report) else { continue }
            try? data.write(to: sourceCacheURL(for: sourceID), options: .atomic)
            stableReports[sourceID] = report
        }
        sourceCacheSummaries = Dictionary(uniqueKeysWithValues: stableReports.map { sourceID, report in
            (sourceID, SourceDiscoveryCacheSummary(
                sourceID: sourceID,
                sourceName: report.sourceName,
                savedAt: report.finishedAt,
                resultCount: report.confirmed.count
            ))
        })
    }

    /// Brings a past session back as the active report so its links can be queued,
    /// imported, or its unverified remainder finished.
    func restoreSession(_ report: DiscoveryReport) {
        activeRawDiscoveryReport = report
        activeReportCameFromCache = true
        discoveryReport = categoryFilteredReport(report, fromCache: true)
        statusMessage = "Restored \(report.sourceName) from saved results (\(discoveryReport?.confirmed.count ?? 0) matching links)"
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
    func browseSources(withIDs ids: [String], queueOnly: Bool = false, queueResults: Bool = true) {
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
        discover(first, addToQueueOnly: queueOnly, queueResults: queueResults)
    }

    // MARK: - Autopilot (Build 101)

    /// True whenever a hands-off run is in flight — discovering, mining, importing, or
    /// waiting to roll on to the next source.
    var isAutopilotRunning: Bool {
        isDiscovering || isImporting || isBulkVerifying || !sourceRotationQueue.isEmpty
    }

    /// The one hands-off entry point. Runs the chosen sources — or the whole catalog when
    /// none are given — end to end: discover, mine + cache categories, import, and
    /// auto-approve qualifying recipes, rolling across sources on its own until it runs out
    /// or you press Stop. Reuses the existing rotation + auto-import chain.
    func startAutopilot(sourceIDs: [String] = []) {
        guard !isDiscovering, !isImporting, !isBulkVerifying else { return }
        let eligible = sources.filter { $0.enabled && $0.discoveryMode.supportsDiscovery }
        guard !eligible.isEmpty else {
            discoveryFailure = "No enabled source supports browsing."
            return
        }
        let chosen: [String] = sourceIDs.isEmpty
            ? Array(eligible.map(\.id).prefix(max(1, settings.autoRotateSourceCount)))
            : eligible.map(\.id).filter { sourceIDs.contains($0) }
        guard !chosen.isEmpty else {
            discoveryFailure = "None of the selected sources can browse."
            return
        }
        autopilotStopRequested = false
        autoRotateRemaining = 0
        log(.info, "Autopilot: \(chosen.count) source\(chosen.count == 1 ? "" : "s"), hands-off.")
        // queueOnly:false → discover imports and auto-approves; rotation chains the rest.
        browseSources(withIDs: chosen, queueOnly: false)
    }

    /// One Stop for the whole thing: cancels the active discovery/import/verify, clears
    /// the remaining rotation, and keeps everything already imported.
    func stopAutopilot() {
        autopilotStopRequested = true
        sourceRotationQueue.removeAll()
        autoRotateRemaining = 0
        discoveryTask?.cancel()
        importTask?.cancel()
        bulkVerifyTask?.cancel()
        statusMessage = "Autopilot stopping — the active request finishes, nothing new starts."
        log(.info, "Autopilot stopped. Everything imported so far is kept.")
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

    /// Restores the complete built-in catalog while keeping custom and imported sources.
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
        queueSnapshot.entries.map(\.url)
    }

    private nonisolated static func makeQueueSnapshot(from text: String) -> ImportQueueSnapshot {
        let raw = text
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var entries: [ImportQueueEntry] = []
        var seen = Set<String>()
        var duplicates = 0
        var invalid = 0
        for value in raw {
            guard let valid = try? URLSafety.validatedRemoteURL(value) else {
                invalid += 1
                continue
            }
            let normalized = URLSafety.normalized(valid)
            let string = normalized.absoluteString
            guard seen.insert(string).inserted else {
                duplicates += 1
                continue
            }
            entries.append(ImportQueueEntry(
                url: string,
                host: normalized.host?.lowercased() ?? "Unknown host"
            ))
        }
        return ImportQueueSnapshot(
            entries: entries,
            duplicateCount: duplicates,
            invalidCount: invalid
        )
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
