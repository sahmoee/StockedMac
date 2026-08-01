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
    
    static var defaults: AppSettings {
        AppSettings(
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
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
            recentSourceIDs: []
        )
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
    
    var supportsDiscovery: Bool {
        self != .directOnly
    }

    var label: String {
        switch self {
        case .directOnly: return "Direct links only"
        case .sitemapOnly: return "Sitemaps"
        case .bothDirectAndSitemap: return "Direct links and sitemaps"
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
