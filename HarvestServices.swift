// HarvestServices.swift — Service layer for the Harvester

import Foundation

// MARK: - Policy Fetcher

actor PolicyFetcher {
    private let http: HTTPClient
    private let robots: RobotsPolicy
    private let limiter: DomainRateLimiter
    
    init(http: HTTPClient, robots: RobotsPolicy, limiter: DomainRateLimiter) {
        self.http = http
        self.robots = robots
        self.limiter = limiter
    }
    
    struct FetchedPage: Sendable {
        var text: String
        var finalURL: URL
        var fromCache: Bool
    }
    
    func fetch(
        _ url: URL,
        source: SourceProfile,
        settings: AppSettings,
        accept: String
    ) async throws -> FetchedPage {
        // Check robots.txt if required
        if source.robotsRequired {
            let allowed = await robots.isAllowed(url)
            guard allowed else {
                throw CompanionError.robotsDenied
            }
        }
        
        // Apply rate limiting
        await limiter.waitIfNeeded(for: url.host ?? "")
        
        // Fetch the page
        let request = URLRequest(url: url)
        let (data, response) = try await http.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.parseFailed("Invalid response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CompanionError.httpStatus(httpResponse.statusCode, HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        
        guard let text = String(data: data, encoding: .utf8) else {
            throw CompanionError.parseFailed("Could not decode response as text")
        }
        
        return FetchedPage(
            text: text,
            finalURL: httpResponse.url ?? url,
            fromCache: false
        )
    }
    
    func updateUserAgent(_ userAgent: String) async {
        await http.updateUserAgent(userAgent)
    }
    
    func clearPause(for source: SourceProfile) async {
        for domain in source.domains {
            await limiter.clearPause(for: domain)
        }
    }
}

// MARK: - Image Store

actor ImageStore {
    private let directory: URL
    private let http: HTTPClient
    private let robots: RobotsPolicy
    private let limiter: DomainRateLimiter
    
    init(directory: URL, http: HTTPClient, robots: RobotsPolicy, limiter: DomainRateLimiter) {
        self.directory = directory
        self.http = http
        self.robots = robots
        self.limiter = limiter
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    
    func download(
        urlString: String,
        settings: AppSettings,
        referer: String
    ) async throws -> RecipeImage {
        guard let url = URL(string: urlString) else {
            throw CompanionError.invalidURL(urlString)
        }
        
        // Check robots.txt
        let allowed = await robots.isAllowed(url)
        guard allowed else {
            throw CompanionError.robotsDenied
        }
        
        // Apply rate limiting
        await limiter.waitIfNeeded(for: url.host ?? "")
        
        // Download image
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        
        let (data, response) = try await http.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CompanionError.parseFailed("Could not download image")
        }
        
        // Save to disk
        let filename = "\(UUID().uuidString).jpg"
        let localURL = directory.appendingPathComponent(filename)
        try data.write(to: localURL)
        
        return RecipeImage(
            originalURL: urlString,
            localPath: localURL.path
        )
    }
    
    func removeAll() async throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }
    
    func prune(keeping referenced: Set<String>) async -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return 0 }
        
        var removed = 0
        for file in files {
            if !referenced.contains(file.path) {
                try? FileManager.default.removeItem(at: file)
                removed += 1
            }
        }
        return removed
    }
}

// MARK: - Discovery Engine

actor DiscoveryEngine {
    private let fetcher: PolicyFetcher
    
    init(fetcher: PolicyFetcher) {
        self.fetcher = fetcher
    }
    
    func discover(
        source: SourceProfile,
        settings: AppSettings,
        manual: Bool,
        knownSourceURLs: Set<String>,
        progress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async throws -> DiscoveryReport {
        let startedAt = Date()
        
        // Placeholder implementation - would crawl sitemaps, RSS feeds, etc.
        let candidates: [DiscoveredLink] = []
        let confirmed: [DiscoveredLink] = []
        let rejected: [DiscoveredLink] = []
        var notes: [String] = []
        
        // Discover candidates from sitemaps
        for sitemapURL in source.sitemapURLs {
            guard let url = URL(string: sitemapURL) else { continue }
            
            do {
                _ = try await fetcher.fetch(
                    url,
                    source: source,
                    settings: settings,
                    accept: "application/xml,text/xml,*/*"
                )
                // Parse sitemap XML and extract URLs
                // This is a simplified version
                notes.append("Checked sitemap: \(sitemapURL)")
            } catch {
                notes.append("Sitemap failed: \(sitemapURL) — \(error.localizedDescription)")
            }
        }
        
        return DiscoveryReport(
            sourceID: source.id,
            sourceName: source.name,
            startedAt: startedAt,
            finishedAt: Date(),
            workingSeed: source.sitemapURLs.first,
            candidates: candidates,
            confirmed: confirmed,
            rejected: rejected,
            unverified: [],
            notes: notes
        )
    }
}

// MARK: - Source Registry

actor SourceRegistry {
    private let localURL: URL
    private let bundledURL: URL?
    private var sources: [SourceProfile] = []
    
    init(localURL: URL, bundledURL: URL?) {
        self.localURL = localURL
        self.bundledURL = bundledURL
        Task {
            await loadSources()
        }
    }
    
    private func loadSources() async {
        // Try to load from local file first
        if let data = try? Data(contentsOf: localURL),
           let loaded = try? JSONDecoder().decode([SourceProfile].self, from: data) {
            sources = loaded
            return
        }
        
        // Fall back to bundled
        if let bundledURL,
           let data = try? Data(contentsOf: bundledURL),
           let loaded = try? JSONDecoder().decode([SourceProfile].self, from: data) {
            sources = loaded
        }
    }
    
    func all() async throws -> [SourceProfile] {
        sources
    }
    
    func profile(for url: URL) async throws -> SourceProfile? {
        guard let host = url.host?.lowercased() else { return nil }
        return sources.first { profile in
            profile.domains.contains { domain in
                host == domain || host.hasSuffix("." + domain)
            }
        }
    }
    
    func save(_ profile: SourceProfile) async throws {
        if let index = sources.firstIndex(where: { $0.id == profile.id }) {
            sources[index] = profile
        } else {
            sources.append(profile)
        }
        try await persist()
    }
    
    func save(all profiles: [SourceProfile]) async throws {
        for profile in profiles {
            if let index = sources.firstIndex(where: { $0.id == profile.id }) {
                sources[index] = profile
            } else {
                sources.append(profile)
            }
        }
        try await persist()
    }
    
    func delete(id: String) async throws {
        sources.removeAll { $0.id == id }
        try await persist()
    }
    
    func resetToBuiltIn() async throws -> [SourceProfile] {
        guard let bundledURL,
              let data = try? Data(contentsOf: bundledURL),
              let loaded = try? JSONDecoder().decode([SourceProfile].self, from: data) else {
            throw CompanionError.parseFailed("Could not load bundled sources")
        }
        sources = loaded
        try await persist()
        return sources
    }
    
    func mergeBuiltInAdditions() async throws -> Int {
        guard let bundledURL,
              let data = try? Data(contentsOf: bundledURL),
              let bundled = try? JSONDecoder().decode([SourceProfile].self, from: data) else {
            return 0
        }
        
        let existingIDs = Set(sources.map(\.id))
        let additions = bundled.filter { !existingIDs.contains($0.id) }
        sources.append(contentsOf: additions)
        
        if !additions.isEmpty {
            try await persist()
        }
        
        return additions.count
    }
    
    func recordHealth(_ health: SourceHealth, message: String?, for id: String) async throws {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].health = health
        try await persist()
    }
    
    func knownSourceURLs() async throws -> Set<String> {
        // This would query the recipe store for all source URLs
        []
    }
    
    private func persist() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sources)
        try data.write(to: localURL, options: .atomic)
    }
}

// MARK: - Python Worker Client

actor PythonWorkerClient {
    nonisolated let isAvailable: Bool
    
    init(isAvailable: Bool = false) {
        self.isAvailable = isAvailable
    }
    
    static func locate() -> PythonWorkerClient {
        // Check if Python worker is available
        PythonWorkerClient(isAvailable: false)
    }
    
    func parse(html: String, url: URL) async throws -> ParserResult {
        guard isAvailable else {
            throw CompanionError.parseFailed("Python worker not available")
        }
        
        // Placeholder - would call Python parser
        throw CompanionError.parseFailed("Python parsing not implemented")
    }
}

// MARK: - Parsers

nonisolated struct NativeRecipeParser {
    func parse(html: String, url: URL) throws -> ParserResult {
        // Simplified native parser - would use SwiftSoup or similar
        // to extract recipe data from HTML
        
        throw CompanionError.parseFailed("Could not extract recipe data")
    }
    
    func servings(from yieldText: String?) -> Double? {
        guard let text = yieldText?.lowercased() else { return nil }
        
        // Extract number from strings like "4 servings", "Makes 6", etc.
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Double($0) }
        
        return numbers.first
    }
}

nonisolated struct HarvestWorkerParser {
    static var isAvailable: Bool {
        // Check if worker endpoint is configured
        false
    }
    
    static func parse(html: String, url: URL) async throws -> ParserResult {
        // Would call remote worker API
        throw CompanionError.parseFailed("Worker parsing not available")
    }
}

nonisolated struct IngredientParser {
    func parseSections(_ sections: [IngredientSection]) -> [IngredientSection] {
        sections.map { section in
            var parsed = section
            parsed.items = section.items.map(parseItem)
            return parsed
        }
    }
    
    private func parseItem(_ item: IngredientItem) -> IngredientItem {
        // Would parse structured data from raw ingredient text
        // This is a placeholder
        item
    }
}

nonisolated struct RecipePageDetector {
    func inspect(html: String, url: URL, source: SourceProfile) -> RecipePageVerdict {
        let lowercased = html.lowercased()
        
        // Check for recipe indicators
        let hasRecipeSchema = lowercased.contains("schema.org/recipe")
        let hasIngredients = lowercased.contains("ingredient")
        let hasInstructions = lowercased.contains("instruction") || lowercased.contains("direction")
        
        // Check for listing indicators
        let hasMultipleRecipeLinks = (try? NSRegularExpression(pattern: "/recipe/", options: .caseInsensitive)
            .numberOfMatches(in: html, range: NSRange(html.startIndex..., in: html))) ?? 0 > 5
        
        if hasRecipeSchema && hasIngredients && hasInstructions {
            return RecipePageVerdict(kind: .recipe, evidence: ["Recipe schema found", "Has ingredients and instructions"])
        } else if hasMultipleRecipeLinks {
            return RecipePageVerdict(kind: .listing, evidence: ["Multiple recipe links found"])
        } else {
            return RecipePageVerdict(kind: .other, evidence: ["No clear recipe markers"])
        }
    }
}
