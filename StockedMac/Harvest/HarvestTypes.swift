// HarvestTypes.swift — Type definitions for the Harvester

import Foundation
import CryptoKit

// MARK: - Recipe Draft

nonisolated struct RecipeDraft: Identifiable, Codable, Sendable {
    var id: UUID
    var title: String
    var summary: String?
    var source: HarvestSource
    var image: RecipeImage?
    var ingredientSections: [IngredientSection]
    var instructionSections: [InstructionSection]
    var yield: String?
    var servings: Double?
    var times: RecipeTimes
    var nutrition: [String: String]
    var cuisines: [String]
    var categories: [String]
    var keywords: [String]
    var diets: [String]
    var confidence: Double
    var warnings: [String]
    var parser: String
    var reviewState: ReviewState
    var sourceFingerprint: String
    var contentFingerprint: String?
    var discoveryNote: String?
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        summary: String? = nil,
        source: HarvestSource,
        image: RecipeImage? = nil,
        ingredientSections: [IngredientSection] = [],
        instructionSections: [InstructionSection] = [],
        yield: String? = nil,
        servings: Double? = nil,
        times: RecipeTimes = RecipeTimes(),
        nutrition: [String: String] = [:],
        cuisines: [String] = [],
        categories: [String] = [],
        keywords: [String] = [],
        diets: [String] = [],
        confidence: Double = 0.5,
        warnings: [String] = [],
        parser: String,
        reviewState: ReviewState = .needsReview,
        sourceFingerprint: String,
        contentFingerprint: String? = nil,
        discoveryNote: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.source = source
        self.image = image
        self.ingredientSections = ingredientSections
        self.instructionSections = instructionSections
        self.yield = yield
        self.servings = servings
        self.times = times
        self.nutrition = nutrition
        self.cuisines = cuisines
        self.categories = categories
        self.keywords = keywords
        self.diets = diets
        self.confidence = confidence
        self.warnings = warnings
        self.parser = parser
        self.reviewState = reviewState
        self.sourceFingerprint = sourceFingerprint
        self.contentFingerprint = contentFingerprint
        self.discoveryNote = discoveryNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    nonisolated mutating func refreshFingerprint() {
        let content = [
            title,
            summary ?? "",
            ingredientSections.map { $0.items.map(\.raw).joined() }.joined(),
            instructionSections.map { $0.steps.joined() }.joined()
        ].joined()
        contentFingerprint = Hashing.sha256(content)
    }

    var exportProblems: [String] {
        var problems: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("The recipe needs a title.")
        }
        if ingredientSections.flatMap(\.items).isEmpty {
            problems.append("The recipe needs at least one ingredient.")
        }
        if instructionSections.flatMap(\.steps).isEmpty {
            problems.append("The recipe needs at least one instruction.")
        }
        return problems
    }
}

nonisolated enum ReviewState: String, Codable, Sendable {
    case needsReview
    case approved
    case rejected

    var label: String {
        switch self {
        case .needsReview: return "needs review"
        case .approved: return "approved"
        case .rejected: return "rejected"
        }
    }
}

nonisolated struct HarvestSource: Codable, Sendable {
    var url: String
    var canonicalURL: String?
    var host: String
    var author: String?
    var attribution: String
}

nonisolated struct RecipeImage: Codable, Sendable {
    var originalURL: String
    var localPath: String?
}

// MARK: - Parser Result

nonisolated struct ParserResult: Sendable {
    var title: String
    var summary: String?
    var author: String?
    var imageURL: String?
    var ingredientSections: [IngredientSection]
    var instructionSections: [InstructionSection]
    var yield: String?
    var servings: Double?
    var times: RecipeTimes
    var nutrition: [String: String]
    var cuisines: [String]
    var categories: [String]
    var keywords: [String]
    var diets: [String]
    var canonicalURL: String?
    var confidence: Double
    var warnings: [String]
    var parser: String
    
    var isComplete: Bool {
        !title.isEmpty && !ingredientSections.isEmpty && !instructionSections.isEmpty
    }
}

nonisolated struct RecipeTimes: Codable, Sendable {
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    
    func normalized() -> RecipeTimes {
        var result = self
        // If we have prep and cook but not total, calculate it
        if let prep = prepMinutes, let cook = cookMinutes, totalMinutes == nil {
            result.totalMinutes = prep + cook
        }
        // If we have total and one of prep/cook, calculate the other
        if let total = totalMinutes, let prep = prepMinutes, cookMinutes == nil, total > prep {
            result.cookMinutes = total - prep
        }
        if let total = totalMinutes, let cook = cookMinutes, prepMinutes == nil, total > cook {
            result.prepMinutes = total - cook
        }
        return result
    }
}

// MARK: - Ingredients and Instructions

nonisolated struct IngredientSection: Codable, Sendable {
    var name: String?
    var items: [IngredientItem]
}

nonisolated struct IngredientItem: Codable, Sendable {
    var raw: String
    var quantity: Double?
    var quantityText: String?
    var unit: String?
    var name: String?
    var preparation: String?
    var notes: String?
}

nonisolated struct InstructionSection: Codable, Sendable {
    var name: String?
    var steps: [String]
}

// MARK: - App Settings

nonisolated struct AppSettings: Codable, Sendable {
    var userAgent: String
    var parserMode: ParserMode
    var downloadImages: Bool
    var parseIngredientStructure: Bool
    var maximumConcurrentJobs: Int
    var useWorkerFallback: Bool
    var autoApproveConfidence: Double
    var retryFailedImports: Bool
    var autoImportVerified: Bool
    var skipAlreadyImported: Bool
    var cacheMaximumAgeHours: Int
    var maximumCacheBytes: Int
    var retainLogEntries: Int
    var rememberBrowsedSources: Bool
    var lastBrowsedSourceID: String?
    var recentSourceIDs: [String]
    // ── Build 91 (Browse) ────────────────────────────────────────────────
    /// A draft without an image never reaches the kitchen (the phone shows a blank
    /// placeholder for imageless recipes). On by default because the bridge already
    /// enforced it silently; now it is visible and adjustable.
    var requireImageForImport: Bool
    /// After a run, automatically retry image downloads for drafts that recorded an
    /// image URL but whose download failed.
    var autoFetchMissingImages: Bool
    /// Check queued URLs really are recipe pages before importing them.
    var verifyBeforeImport: Bool
    /// Push approved recipes (and their images) to the Worker cache after approval.
    var cloudSyncEnabled: Bool
    /// How many sources "Auto-rotate" walks through in one sitting.
    var autoRotateSourceCount: Int
    // ── Build 93 (Crawler) ───────────────────────────────────────────────
    /// How Browse finds candidate URLs: follow the source's own mode, or force one.
    var preferredCrawlMethod: CrawlMethod
    /// How hard a browse run pushes: delays, page budgets, candidate caps.
    var crawlAggressiveness: CrawlAggressiveness
    /// Auto-approval additionally requires the recipe to pass the Stocked standards
    /// checklist (title, ingredients, steps, image, honest attribution, …).
    var requireStandardsForAutoApprove: Bool
    // ── Build 95 (Importing) ─────────────────────────────────────────────
    /// When a page won't parse from a plain fetch (bot wall, JS-rendered), load it in
    /// an invisible WebKit view and parse the rendered HTML instead.
    var useWebKitFallback: Bool
    /// Extra seconds between imports, on top of the per-domain limiter. 0 = none.
    var importSpacingSeconds: Int
    /// Bumped when defaults change meaning; start() migrates old files forward once.
    var settingsRevision: Int
    /// Hard ceiling on the import queue. Mined and discovered links stop joining once
    /// the queue holds this many — a bound on the snowball, adjustable in the Queue card.
    var queueCap: Int

    static var defaults: AppSettings {
        AppSettings(
            // A real, current Safari UA. The old truncated string ("...AppleWebKit/537.36"
            // and nothing after) is a bot-wall tripwire — Food Network's CDN answers it
            // with a challenge page that contains no recipe at all.
            userAgent: AppSettings.safariUserAgent,
            parserMode: .nativeFirst,
            downloadImages: true,
            parseIngredientStructure: true,
            maximumConcurrentJobs: 3,
            useWorkerFallback: false,
            autoApproveConfidence: 0.9,
            retryFailedImports: true,
            autoImportVerified: true,
            skipAlreadyImported: true,
            cacheMaximumAgeHours: 24,
            maximumCacheBytes: 500_000_000,
            retainLogEntries: 200,
            rememberBrowsedSources: true,
            lastBrowsedSourceID: nil,
            recentSourceIDs: [],
            requireImageForImport: true,
            autoFetchMissingImages: true,
            verifyBeforeImport: false,
            cloudSyncEnabled: false,
            autoRotateSourceCount: 3,
            preferredCrawlMethod: .auto,
            crawlAggressiveness: .balanced,
            requireStandardsForAutoApprove: true,
            useWebKitFallback: true,
            importSpacingSeconds: 0,
            settingsRevision: 2,
            queueCap: 500
        )
    }

    // ── User-agent presets (Build 95) ────────────────────────────────────
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
    static let chromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    static let honestUserAgent =
        "StockedHarvester/1.0 (+https://sowensstudios.com)"
    /// The Build 90-94 default; recognized so migration can replace it.
    static let legacyUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
}

// Tolerant decoding: every field falls back to its default when absent, so a settings.json
// written by ANY earlier build (which lacks the Build 91 keys) still loads instead of
// silently resetting the user to factory settings. Encoding stays synthesized-shaped.
nonisolated extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case userAgent, parserMode, downloadImages, parseIngredientStructure
        case maximumConcurrentJobs, useWorkerFallback, autoApproveConfidence
        case retryFailedImports, autoImportVerified, skipAlreadyImported
        case cacheMaximumAgeHours, maximumCacheBytes, retainLogEntries
        case rememberBrowsedSources, lastBrowsedSourceID, recentSourceIDs
        case requireImageForImport, autoFetchMissingImages, verifyBeforeImport
        case cloudSyncEnabled, autoRotateSourceCount
        case preferredCrawlMethod, crawlAggressiveness, requireStandardsForAutoApprove
        case useWebKitFallback, importSpacingSeconds, settingsRevision, queueCap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        userAgent               = (try? c.decodeIfPresent(String.self, forKey: .userAgent)) ?? d.userAgent
        parserMode              = (try? c.decodeIfPresent(ParserMode.self, forKey: .parserMode)) ?? d.parserMode
        downloadImages          = (try? c.decodeIfPresent(Bool.self, forKey: .downloadImages)) ?? d.downloadImages
        parseIngredientStructure = (try? c.decodeIfPresent(Bool.self, forKey: .parseIngredientStructure)) ?? d.parseIngredientStructure
        maximumConcurrentJobs   = (try? c.decodeIfPresent(Int.self, forKey: .maximumConcurrentJobs)) ?? d.maximumConcurrentJobs
        useWorkerFallback       = (try? c.decodeIfPresent(Bool.self, forKey: .useWorkerFallback)) ?? d.useWorkerFallback
        autoApproveConfidence   = (try? c.decodeIfPresent(Double.self, forKey: .autoApproveConfidence)) ?? d.autoApproveConfidence
        retryFailedImports      = (try? c.decodeIfPresent(Bool.self, forKey: .retryFailedImports)) ?? d.retryFailedImports
        autoImportVerified      = (try? c.decodeIfPresent(Bool.self, forKey: .autoImportVerified)) ?? d.autoImportVerified
        skipAlreadyImported     = (try? c.decodeIfPresent(Bool.self, forKey: .skipAlreadyImported)) ?? d.skipAlreadyImported
        cacheMaximumAgeHours    = (try? c.decodeIfPresent(Int.self, forKey: .cacheMaximumAgeHours)) ?? d.cacheMaximumAgeHours
        maximumCacheBytes       = (try? c.decodeIfPresent(Int.self, forKey: .maximumCacheBytes)) ?? d.maximumCacheBytes
        retainLogEntries        = (try? c.decodeIfPresent(Int.self, forKey: .retainLogEntries)) ?? d.retainLogEntries
        rememberBrowsedSources  = (try? c.decodeIfPresent(Bool.self, forKey: .rememberBrowsedSources)) ?? d.rememberBrowsedSources
        lastBrowsedSourceID     = try? c.decodeIfPresent(String.self, forKey: .lastBrowsedSourceID)
        recentSourceIDs         = (try? c.decodeIfPresent([String].self, forKey: .recentSourceIDs)) ?? []
        requireImageForImport   = (try? c.decodeIfPresent(Bool.self, forKey: .requireImageForImport)) ?? d.requireImageForImport
        autoFetchMissingImages  = (try? c.decodeIfPresent(Bool.self, forKey: .autoFetchMissingImages)) ?? d.autoFetchMissingImages
        verifyBeforeImport      = (try? c.decodeIfPresent(Bool.self, forKey: .verifyBeforeImport)) ?? d.verifyBeforeImport
        cloudSyncEnabled        = (try? c.decodeIfPresent(Bool.self, forKey: .cloudSyncEnabled)) ?? d.cloudSyncEnabled
        autoRotateSourceCount   = (try? c.decodeIfPresent(Int.self, forKey: .autoRotateSourceCount)) ?? d.autoRotateSourceCount
        preferredCrawlMethod    = (try? c.decodeIfPresent(CrawlMethod.self, forKey: .preferredCrawlMethod)) ?? d.preferredCrawlMethod
        crawlAggressiveness     = (try? c.decodeIfPresent(CrawlAggressiveness.self, forKey: .crawlAggressiveness)) ?? d.crawlAggressiveness
        requireStandardsForAutoApprove = (try? c.decodeIfPresent(Bool.self, forKey: .requireStandardsForAutoApprove)) ?? d.requireStandardsForAutoApprove
        useWebKitFallback       = (try? c.decodeIfPresent(Bool.self, forKey: .useWebKitFallback)) ?? d.useWebKitFallback
        importSpacingSeconds    = (try? c.decodeIfPresent(Int.self, forKey: .importSpacingSeconds)) ?? d.importSpacingSeconds
        settingsRevision        = (try? c.decodeIfPresent(Int.self, forKey: .settingsRevision)) ?? 0
        queueCap                = (try? c.decodeIfPresent(Int.self, forKey: .queueCap)) ?? d.queueCap
    }
}

nonisolated enum ParserMode: String, Codable, Sendable {
    case nativeOnly
    case pythonOnly
    case nativeFirst
    case pythonFirst
}

// MARK: - Source Profile

nonisolated struct SourceProfile: Identifiable, Codable, Sendable {
    var id: String
    var name: String
    var domains: [String]
    var baseURL: String
    var enabled: Bool
    var discoveryEnabled: Bool
    var discoveryMode: DiscoveryMode
    var parserMode: ParserMode
    var minimumDelaySeconds: Int
    var maximumConcurrency: Int
    var dailyRequestLimit: Int
    var robotsRequired: Bool
    var imageDownloadEnabled: Bool
    var sitemapURLs: [String]
    var recipeURLPatterns: [String]
    var excludedURLPatterns: [String]
    var tags: [String]
    var notes: String?
    var health: SourceHealth
    
    init(
        id: String,
        name: String,
        domains: [String],
        baseURL: String,
        enabled: Bool = true,
        discoveryEnabled: Bool = false,
        discoveryMode: DiscoveryMode = .directOnly,
        parserMode: ParserMode = .nativeFirst,
        minimumDelaySeconds: Int = 2,
        maximumConcurrency: Int = 2,
        dailyRequestLimit: Int = 100,
        robotsRequired: Bool = true,
        imageDownloadEnabled: Bool = true,
        sitemapURLs: [String] = [],
        recipeURLPatterns: [String] = [],
        excludedURLPatterns: [String] = [],
        tags: [String] = [],
        notes: String? = nil,
        health: SourceHealth = .unknown
    ) {
        self.id = id
        self.name = name
        self.domains = domains
        self.baseURL = baseURL
        self.enabled = enabled
        self.discoveryEnabled = discoveryEnabled
        self.discoveryMode = discoveryMode
        self.parserMode = parserMode
        self.minimumDelaySeconds = minimumDelaySeconds
        self.maximumConcurrency = maximumConcurrency
        self.dailyRequestLimit = dailyRequestLimit
        self.robotsRequired = robotsRequired
        self.imageDownloadEnabled = imageDownloadEnabled
        self.sitemapURLs = sitemapURLs
        self.recipeURLPatterns = recipeURLPatterns
        self.excludedURLPatterns = excludedURLPatterns
        self.tags = tags
        self.notes = notes
        self.health = health
    }
    
    static var defaultExcludedPatterns: [String] {
        ["/tag/", "/category/", "/author/", "/page/"]
    }
    
    var validationProblems: [String] {
        var problems: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("Name cannot be empty")
        }
        if domains.isEmpty {
            problems.append("At least one domain is required")
        }
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("Base URL cannot be empty")
        }
        return problems
    }
}

nonisolated enum DiscoveryMode: String, Codable, Sendable {
    case directOnly
    case sitemapOnly
    case bothDirectAndSitemap
    /// Build 93: the source is an RSS/Atom/reddit feed; entries (and their outbound
    /// links, for aggregator communities like reddit) are the candidates.
    case feedOnly
    /// Build 93: no useful sitemap — crawl the site's listing/category pages instead.
    case htmlListing

    var supportsDiscovery: Bool {
        self != .directOnly
    }

    var label: String {
        switch self {
        case .directOnly: return "Direct links only"
        case .sitemapOnly: return "Sitemaps"
        case .bothDirectAndSitemap: return "Direct links and sitemaps"
        case .feedOnly: return "Feed (RSS/Atom/reddit)"
        case .htmlListing: return "Category pages"
        }
    }
}

nonisolated enum SourceHealth: String, Codable, Sendable {
    case unknown
    case healthy
    case limited
    case paused
    case blocked
}

// MARK: - Discovery

nonisolated struct DiscoveryReport: Codable, Sendable {
    var sourceID: String
    var sourceName: String
    var startedAt: Date
    var finishedAt: Date
    var workingSeed: String?
    var candidates: [DiscoveredLink]
    var confirmed: [DiscoveredLink]
    var rejected: [DiscoveredLink]
    var unverified: [String]
    var notes: [String]
    
    var summary: String {
        "Found \(candidates.count) candidates, verified \(confirmed.count)"
    }
}

nonisolated struct DiscoveredLink: Codable, Sendable {
    var url: String
    var title: String?
    var imageURL: String?
}

nonisolated struct DiscoveryProgress: Sendable {
    var phase: String
    var currentURL: String?
    var pagesFetched: Int
    var queued: Int
    var confirmed: Int
    var rejected: Int

    static let idle = DiscoveryProgress(
        phase: "Idle",
        currentURL: nil,
        pagesFetched: 0,
        queued: 0,
        confirmed: 0,
        rejected: 0
    )
}

nonisolated struct RecipePageVerdict: Sendable {
    var kind: PageKind
    var evidence: [String]
    var confidence: Double = 0
    var outboundLinks: [String] = []

    var isRecipe: Bool { kind == .recipe }
    
    enum PageKind {
        case recipe
        case listing
        case other
    }
}

// MARK: - Errors

nonisolated enum CompanionError: LocalizedError {
    case sourceDisabled(String)
    case notARecipe(String)
    /// A category/hub page that carries recipe links — the links come along so the
    /// caller can queue them instead of merely reporting a failure. (Build 96)
    case listingPage(String, [String])
    case parseFailed(String)
    case robotsDenied
    case rateLimited(String)
    case httpStatus(Int, String)
    case invalidURL(String)
    case persistence(String)
    
    var errorDescription: String? {
        switch self {
        case .sourceDisabled(let name):
            return "The source \"\(name)\" is disabled"
        case .notARecipe(let detail):
            return "Not a recipe page: \(detail)"
        case .listingPage(let url, let links):
            return "Category page, not a recipe (\(links.count) recipe links found on it): \(url)"
        case .parseFailed(let reason):
            return "Could not parse recipe: \(reason)"
        case .robotsDenied:
            return "Access denied by robots.txt"
        case .rateLimited(let detail):
            return "Rate limited: \(detail)"
        case .httpStatus(let code, let message):
            return "HTTP \(code): \(message)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .persistence(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .sourceDisabled:
            return "Enable the source in the Sources tab"
        case .robotsDenied:
            return "The site's robots.txt file blocks automated access"
        case .rateLimited:
            return "Wait a few minutes and try again"
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions

nonisolated extension Array where Element == String {
    func cleanedUnique() -> [String] {
        var seen = Set<String>()
        return compactMap { item -> String? in
            let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { return nil }
            return cleaned
        }
    }
}

// MARK: - Utilities

nonisolated enum Hashing {
    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum URLSafety {
    static func validatedRemoteURL(_ urlString: String) throws -> URL {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw CompanionError.invalidURL(urlString)
        }
        return url
    }
    
    static func normalized(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        // Remove common tracking parameters
        if var queryItems = components?.queryItems {
            queryItems = queryItems.filter { item in
                !["utm_source", "utm_medium", "utm_campaign", "fbclid"].contains(item.name)
            }
            components?.queryItems = queryItems.isEmpty ? nil : queryItems
        }
        return components?.url ?? url
    }
}

// MARK: - Tolerant source decoding (Build 91)
//
// A catalog entry written by an older build — or edited by hand — no longer takes the
// whole catalog down with it. Only id, name, domains and baseURL are truly required;
// everything else falls back to the same defaults the memberwise initializer uses.
// Encoding stays synthesized, so sources.json keeps its full shape on disk.

nonisolated extension SourceProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, domains, baseURL, enabled, discoveryEnabled, discoveryMode
        case parserMode, minimumDelaySeconds, maximumConcurrency, dailyRequestLimit
        case robotsRequired, imageDownloadEnabled, sitemapURLs, recipeURLPatterns
        case excludedURLPatterns, tags, notes, health
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(String.self, forKey: .id)
        name    = try c.decode(String.self, forKey: .name)
        domains = try c.decode([String].self, forKey: .domains)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        enabled              = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        discoveryEnabled     = (try? c.decodeIfPresent(Bool.self, forKey: .discoveryEnabled)) ?? false
        discoveryMode        = (try? c.decodeIfPresent(DiscoveryMode.self, forKey: .discoveryMode)) ?? .sitemapOnly
        parserMode           = (try? c.decodeIfPresent(ParserMode.self, forKey: .parserMode)) ?? .nativeFirst
        minimumDelaySeconds  = (try? c.decodeIfPresent(Int.self, forKey: .minimumDelaySeconds)) ?? 2
        maximumConcurrency   = (try? c.decodeIfPresent(Int.self, forKey: .maximumConcurrency)) ?? 2
        dailyRequestLimit    = (try? c.decodeIfPresent(Int.self, forKey: .dailyRequestLimit)) ?? 100
        robotsRequired       = (try? c.decodeIfPresent(Bool.self, forKey: .robotsRequired)) ?? true
        imageDownloadEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .imageDownloadEnabled)) ?? true
        sitemapURLs          = (try? c.decodeIfPresent([String].self, forKey: .sitemapURLs)) ?? []
        recipeURLPatterns    = (try? c.decodeIfPresent([String].self, forKey: .recipeURLPatterns)) ?? []
        excludedURLPatterns  = (try? c.decodeIfPresent([String].self, forKey: .excludedURLPatterns)) ?? SourceProfile.defaultExcludedPatterns
        tags                 = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        notes                = try? c.decodeIfPresent(String.self, forKey: .notes)
        health               = (try? c.decodeIfPresent(SourceHealth.self, forKey: .health)) ?? .unknown
    }
}

/// Decodes an array element-by-element, dropping the elements that fail instead of
/// failing the whole array. Used for both the source catalog and stray recipe records.
nonisolated struct LossyArray<Element: Codable & Sendable>: Codable, Sendable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                out.append(value)
            } else {
                _ = try? container.decode(AnyDiscard.self)   // skip the bad element
            }
        }
        elements = out
    }

    func encode(to encoder: Encoder) throws {
        try elements.encode(to: encoder)
    }

    private struct AnyDiscard: Codable {}
}

nonisolated extension RecipeImage {
    /// True when the image bytes are actually on disk, not merely promised by a URL.
    var hasLocalFile: Bool {
        guard let path = localPath, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

// MARK: - Crawl method & aggressiveness (Build 93)

/// How a browse run hunts for candidate URLs. `.auto` follows each source's own
/// `discoveryMode`; the rest force one engine for this run.
nonisolated enum CrawlMethod: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto
    case sitemap
    case categories
    case feed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:       return "Auto (per source)"
        case .sitemap:    return "Sitemaps"
        case .categories: return "Category pages"
        case .feed:       return "Feeds"
        }
    }

    var explanation: String {
        switch self {
        case .auto:       return "Each source uses the engine it is configured for."
        case .sitemap:    return "Reads the site's sitemap.xml for recipe URLs."
        case .categories: return "Crawls listing and category pages and follows the recipe links on them."
        case .feed:       return "Reads RSS/Atom feeds — including reddit — and follows entry links."
        }
    }
}

/// One knob for how hard a run pushes: request spacing, how many index pages are
/// fetched, how many category pages get expanded, and how many candidates a single
/// run may return. Politeness floors still apply — robots.txt and per-source daily
/// limits are never overridden.
nonisolated enum CrawlAggressiveness: String, Codable, Sendable, CaseIterable, Identifiable {
    case gentle
    case balanced
    case aggressive
    case maximum

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle:     return "Gentle"
        case .balanced:   return "Balanced"
        case .aggressive: return "Aggressive"
        case .maximum:    return "Maximum"
        }
    }

    /// Multiplies each source's own minimum delay between requests.
    var delayMultiplier: Double {
        switch self {
        case .gentle:     return 2.0
        case .balanced:   return 1.0
        case .aggressive: return 0.5
        case .maximum:    return 0.25
        }
    }

    /// TOTAL sitemap files a run may fetch, children of sitemap indexes included.
    /// Build 94 — the old engine recursed through EVERY child of a sitemap index
    /// (Food Network's has hundreds), which read as "stuck on Reading sitemaps".
    var sitemapFileCap: Int {
        switch self {
        case .gentle:     return 6
        case .balanced:   return 15
        case .aggressive: return 40
        case .maximum:    return 100
        }
    }

    /// Seed feed URLs / seed listing pages fetched per run.
    var seedPageCap: Int {
        switch self {
        case .gentle:     return 3
        case .balanced:   return 6
        case .aggressive: return 12
        case .maximum:    return 24
        }
    }

    /// Category/listing pages expanded (fetched for their recipe links) per run.
    var expansionCap: Int {
        switch self {
        case .gentle:     return 4
        case .balanced:   return 10
        case .aggressive: return 20
        case .maximum:    return 40
        }
    }

    /// Candidate URLs a single run may hand back.
    var candidateCap: Int {
        switch self {
        case .gentle:     return 150
        case .balanced:   return 400
        case .aggressive: return 1000
        case .maximum:    return 2500
        }
    }

    var explanation: String {
        switch self {
        case .gentle:     return "Half speed, small budgets. Kind to small blogs."
        case .balanced:   return "The default. Respects each site's own pace."
        case .aggressive: return "Faster requests, bigger budgets. For large sites."
        case .maximum:    return "Everything at once. Robots.txt and daily limits still apply."
        }
    }
}

// MARK: - Stocked standards (Build 93)

/// One item on the standards checklist.
nonisolated struct StandardsCheck: Identifiable, Sendable {
    var id: String { label }
    let label: String
    let passed: Bool
    let required: Bool
    let detail: String?
}

/// Whether a draft meets Stocked's bar for entering the kitchen. Required checks gate
/// auto-approval (when the setting is on); recommended ones only inform the reviewer.
nonisolated struct StandardsReport: Sendable {
    let checks: [StandardsCheck]

    var requiredPassed: Bool { checks.filter(\.required).allSatisfy(\.passed) }
    var passedCount: Int { checks.filter(\.passed).count }
    var summary: String { "\(passedCount) of \(checks.count) checks" }
    var failedRequired: [StandardsCheck] { checks.filter { $0.required && !$0.passed } }
}

nonisolated extension RecipeDraft {
    /// The Stocked standards checklist for this draft.
    var standards: StandardsReport {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ingredientCount = ingredientSections.flatMap(\.items).count
        let stepCount = instructionSections.flatMap(\.steps).filter { !$0.isEmpty }.count
        let attribution = SourceAttribution.displayName(
            host: source.host, sourceName: source.attribution, author: source.author
        )
        let times = self.times.normalized()

        return StandardsReport(checks: [
            StandardsCheck(
                label: "Titled like a recipe",
                passed: title.count >= 3 && title.count <= 120,
                required: true,
                detail: title.isEmpty ? "No title" : nil
            ),
            StandardsCheck(
                label: "At least 3 ingredients",
                passed: ingredientCount >= 3,
                required: true,
                detail: "\(ingredientCount) found"
            ),
            StandardsCheck(
                label: "At least 2 method steps",
                passed: stepCount >= 2,
                required: true,
                detail: "\(stepCount) found"
            ),
            StandardsCheck(
                label: "Image saved to disk",
                passed: image?.hasLocalFile ?? false,
                required: true,
                detail: image == nil ? "No image at all" : (image?.hasLocalFile == true ? nil : "URL known, bytes missing")
            ),
            StandardsCheck(
                label: "Real source URL",
                passed: !source.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                required: true,
                detail: nil
            ),
            StandardsCheck(
                label: "Honest attribution",
                passed: !SourceAttribution.isGeneric(attribution),
                required: true,
                detail: attribution
            ),
            StandardsCheck(
                label: "Servings known",
                passed: (servings ?? 0) > 0,
                required: false,
                detail: nil
            ),
            StandardsCheck(
                label: "A cooking time known",
                passed: times.prepMinutes != nil || times.cookMinutes != nil || times.totalMinutes != nil,
                required: false,
                detail: nil
            ),
            StandardsCheck(
                label: "Has a description",
                passed: summary?.nilIfBlank != nil,
                required: false,
                detail: nil
            ),
        ])
    }
}

// MARK: - Source attribution (Build 93)
//
// The one place that decides what "Source:" says in Stocked. Internal handles
// ("Sowens", "Stocked Companion", "custom-3f9a…", "New source") never qualify — the
// answer is the site's real name, the author, or the plain host, in that order.

nonisolated enum SourceAttribution {

    static func displayName(host: String, sourceName: String?, author: String? = nil) -> String {
        if let name = sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
           !isGeneric(name) {
            return name
        }
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
           !isGeneric(author) {
            return author
        }
        return prettyHost(host)
    }

    static func isGeneric(_ value: String) -> Bool {
        let lower = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return true }
        let generic = ["sowens", "stocked", "companion", "unknown", "new source",
                       "custom-", "imported-", "example.com"]
        return generic.contains { lower.contains($0) }
    }

    /// "www.simplyrecipes.com" → "simplyrecipes.com"; a reddit host keeps its subreddit
    /// elsewhere (the URL is always shown alongside), so the plain domain is enough here.
    static func prettyHost(_ host: String) -> String {
        var clean = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("www.") { clean = String(clean.dropFirst(4)) }
        return clean.isEmpty ? "the web" : clean
    }
}
