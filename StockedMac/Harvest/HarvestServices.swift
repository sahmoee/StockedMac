// HarvestServices.swift — Service layer for the Harvester

import Foundation
import ImageIO

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
        
        // Apply rate limiting, honouring the source's own requested delay
        await limiter.waitIfNeeded(
            for: url.host ?? "",
            minimumDelay: Double(source.minimumDelaySeconds)
        )

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
    
    func fetchData(
        _ url: URL,
        source: SourceProfile,
        settings: AppSettings,
        accept: String
    ) async throws -> Data {
        if source.robotsRequired {
            let allowed = await robots.isAllowed(url)
            guard allowed else { throw CompanionError.robotsDenied }
        }
        await limiter.waitIfNeeded(
            for: url.host ?? "",
            minimumDelay: Double(source.minimumDelaySeconds)
        )
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CompanionError.parseFailed("Invalid response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CompanionError.httpStatus(httpResponse.statusCode,
                HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))
        }
        return data
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

        // Content-addressed filename: the same image URL always lands on the same file,
        // so re-importing a recipe reuses the bytes already on disk instead of
        // downloading a second copy under a fresh UUID.
        let filename = Hashing.sha256(urlString) + ".jpg"
        let localURL = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: localURL.path),
           Self.isUsableImageFile(at: localURL) {
            return RecipeImage(originalURL: urlString, localPath: localURL.path)
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
        request.setValue("image/avif,image/webp,image/jpeg,image/png,image/*;q=0.8",
                         forHTTPHeaderField: "Accept")

        let (data, response) = try await http.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CompanionError.parseFailed("Could not download image")
        }

        // Validate before keeping: an HTML error page saved as .jpg used to count as
        // "has an image" and then rendered as a grey square on the phone.
        guard Self.isUsableImageData(data) else {
            throw CompanionError.parseFailed("The downloaded file is not a usable image")
        }

        try data.write(to: localURL, options: .atomic)

        return RecipeImage(
            originalURL: urlString,
            localPath: localURL.path
        )
    }

    /// Real image bytes, decodable, and at least 120 px on the short edge — anything
    /// smaller is a favicon or tracking pixel, not a recipe photo.
    nonisolated static func isUsableImageData(_ data: Data) -> Bool {
        guard data.count > 4096,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return false }
        return min(width, height) >= 120
    }

    nonisolated static func isUsableImageFile(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return isUsableImageData(data)
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
        var notes: [String] = []
        var allURLs: [String] = []
        var unverifiedURLs: [String] = []
        var pagesFetched = 0

        let sitemapList = source.sitemapURLs.isEmpty
            ? [(source.baseURL.hasSuffix("/") ? source.baseURL : source.baseURL + "/") + "sitemap.xml"]
            : source.sitemapURLs

        await progress(DiscoveryProgress(phase: "Starting", currentURL: sitemapList.first,
                                         pagesFetched: 0, queued: sitemapList.count,
                                         confirmed: 0, rejected: 0))

        for sitemapURLString in sitemapList {
            if Task.isCancelled {
                unverifiedURLs = Array(sitemapList.dropFirst(pagesFetched))
                break
            }
            guard let sitemapURL = URL(string: sitemapURLString) else { continue }

            await progress(DiscoveryProgress(phase: "Crawling sitemap",
                                             currentURL: sitemapURLString,
                                             pagesFetched: pagesFetched,
                                             queued: sitemapList.count - pagesFetched,
                                             confirmed: allURLs.count, rejected: 0))
            do {
                let (urls, sitemapNotes) = try await crawlSitemap(
                    url: sitemapURL, source: source, settings: settings, depth: 0
                )
                allURLs.append(contentsOf: urls)
                notes.append(contentsOf: sitemapNotes)
                notes.append("\(sitemapURLString): \(urls.count) recipe URLs")
                pagesFetched += 1
            } catch is CancellationError {
                notes.append("Cancelled at \(sitemapURLString)")
                unverifiedURLs = Array(sitemapList.dropFirst(pagesFetched))
                break
            } catch {
                notes.append("Sitemap failed: \(sitemapURLString) — \(error.localizedDescription)")
                pagesFetched += 1
            }
        }

        var seen = Set<String>()
        let deduplicated = allURLs.filter { seen.insert($0).inserted }
        let filtered = settings.skipAlreadyImported
            ? deduplicated.filter { !knownSourceURLs.contains($0) }
            : deduplicated

        let confirmed = filtered.map { DiscoveredLink(url: $0, title: nil, imageURL: nil) }

        return DiscoveryReport(
            sourceID: source.id,
            sourceName: source.name,
            startedAt: startedAt,
            finishedAt: Date(),
            workingSeed: source.sitemapURLs.first,
            candidates: confirmed,
            confirmed: confirmed,
            rejected: [],
            unverified: unverifiedURLs,
            notes: notes
        )
    }

    private func crawlSitemap(
        url: URL,
        source: SourceProfile,
        settings: AppSettings,
        depth: Int
    ) async throws -> (urls: [String], notes: [String]) {
        guard depth < 5 else {
            return ([], ["Max sitemap depth at \(url.absoluteString)"])
        }
        try Task.checkCancellation()

        let data = try await fetcher.fetchData(
            url, source: source, settings: settings,
            accept: "application/xml,text/xml,*/*"
        )

        let (isSitemapIndex, locs) = parseSitemapData(data)

        if isSitemapIndex {
            var allURLs: [String] = []
            var allNotes: [String] = []
            for childString in locs {
                try Task.checkCancellation()
                guard let childURL = URL(string: childString) else { continue }
                let (childURLs, childNotes) = try await crawlSitemap(
                    url: childURL, source: source, settings: settings, depth: depth + 1
                )
                allURLs.append(contentsOf: childURLs)
                allNotes.append(contentsOf: childNotes)
            }
            return (allURLs, allNotes)
        } else {
            let filtered = locs.filter { matchesSource($0, source: source) }
            return (filtered, [])
        }
    }

    private func parseSitemapData(_ data: Data) -> (isSitemapIndex: Bool, locs: [String]) {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        let isSitemapIndex = text.range(of: "<sitemapindex", options: .caseInsensitive) != nil
        let locs = extractXMLTagContents(named: "loc", from: text)
        return (isSitemapIndex, locs)
    }

    private func extractXMLTagContents(named tag: String, from xml: String) -> [String] {
        var results: [String] = []
        let open = "<\(tag)>"
        let close = "</\(tag)>"
        var pos = xml.startIndex
        while let openRange = xml.range(of: open, options: .caseInsensitive, range: pos..<xml.endIndex),
              let closeRange = xml.range(of: close, options: .caseInsensitive, range: openRange.upperBound..<xml.endIndex) {
            let content = String(xml[openRange.upperBound..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { results.append(content) }
            pos = closeRange.upperBound
        }
        return results
    }

    private func matchesSource(_ urlString: String, source: SourceProfile) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        let onDomain = source.domains.contains { host == $0 || host.hasSuffix("." + $0) }
        guard onDomain else { return false }
        for pattern in source.excludedURLPatterns where urlString.contains(pattern) { return false }
        if source.recipeURLPatterns.isEmpty { return true }
        return source.recipeURLPatterns.contains { urlString.contains($0) }
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
        // Load synchronously to avoid racing with the first all() call.
        // Data(contentsOf:) is fast for small config files.
        //
        // Build 91: the chain is local file → bundled resource → embedded catalog, and an
        // EMPTY local file no longer wins — an interrupted first launch used to leave a
        // valid `[]` on disk, which decoded fine and left the Browse screen saying
        // "No sources loaded" forever. Decoding is lossy per element, so one bad entry
        // costs one entry, not the catalog.
        if let loaded = Self.decodeSources(at: localURL), !loaded.isEmpty {
            sources = loaded
        } else if let url = bundledURL, let loaded = Self.decodeSources(at: url), !loaded.isEmpty {
            sources = loaded
        } else {
            sources = DefaultSourceCatalog.sources()
        }
    }

    /// The catalog every install is guaranteed to have, wherever it came from.
    private func builtInSources() -> [SourceProfile] {
        if let url = bundledURL, let loaded = Self.decodeSources(at: url), !loaded.isEmpty {
            return loaded
        }
        return DefaultSourceCatalog.sources()
    }

    private nonisolated static func decodeSources(at url: URL) -> [SourceProfile]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let strict = try? JSONDecoder().decode([SourceProfile].self, from: data) {
            return strict
        }
        return (try? JSONDecoder().decode(LossyArray<SourceProfile>.self, from: data))?.elements
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
        let loaded = builtInSources()
        guard !loaded.isEmpty else {
            throw CompanionError.parseFailed("Could not load the built-in sources")
        }
        sources = loaded
        try await persist()
        return sources
    }

    func mergeBuiltInAdditions() async throws -> Int {
        let bundled = builtInSources()
        guard !bundled.isEmpty else { return 0 }

        let existingIDs = Set(sources.map(\.id))
        let additions = bundled.filter { !existingIDs.contains($0.id) }

        // Update discovery fields on existing sources that still have the default
        // directOnly mode — fixes installs that pre-date browsing support.
        var updatedCount = 0
        for bundledSource in bundled {
            guard let idx = sources.firstIndex(where: { $0.id == bundledSource.id }) else { continue }
            var local = sources[idx]
            var changed = false
            if local.discoveryMode == .directOnly, bundledSource.discoveryMode != .directOnly {
                local.discoveryMode = bundledSource.discoveryMode
                changed = true
            }
            if local.sitemapURLs.isEmpty, !bundledSource.sitemapURLs.isEmpty {
                local.sitemapURLs = bundledSource.sitemapURLs
                changed = true
            }
            if changed {
                sources[idx] = local
                updatedCount += 1
            }
        }

        sources.append(contentsOf: additions)

        if !additions.isEmpty || updatedCount > 0 {
            try await persist()
        }

        return additions.count + updatedCount
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
        let blocks = extractJSONLDBlocks(from: html)
        for block in blocks {
            if let dict = findRecipeDict(in: block) {
                return try buildResult(from: dict, url: url, html: html)
            }
        }
        throw CompanionError.parseFailed("No schema.org/Recipe JSON-LD found")
    }

    func servings(from yieldText: String?) -> Double? {
        guard let text = yieldText?.lowercased() else { return nil }
        return text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Double($0) }.first
    }

    // MARK: - JSON-LD block extraction

    private func extractJSONLDBlocks(from html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]+type\s*=\s*["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#,
            options: .caseInsensitive
        ) else { return [] }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        return regex.matches(in: html, range: range).compactMap { match -> String? in
            guard match.numberOfRanges > 1 else { return nil }
            let content = nsHTML.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : content
        }
    }

    private func findRecipeDict(in jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let dict = json as? [String: Any] {
            if let graph = dict["@graph"] as? [Any] {
                return graph.compactMap { $0 as? [String: Any] }.first(where: isRecipeType)
            }
            return isRecipeType(dict) ? dict : nil
        }
        if let array = json as? [Any] {
            return array.compactMap { $0 as? [String: Any] }.first(where: isRecipeType)
        }
        return nil
    }

    private func isRecipeType(_ dict: [String: Any]) -> Bool {
        let types: [String]
        if let s = dict["@type"] as? String { types = [s] }
        else if let arr = dict["@type"] as? [String] { types = arr }
        else { return false }
        return types.contains { $0.lowercased().contains("recipe") }
    }

    // MARK: - Result assembly

    private func buildResult(from dict: [String: Any], url: URL, html: String) throws -> ParserResult {
        guard let rawTitle = dict["name"] as? String,
              !rawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CompanionError.parseFailed("Recipe has no name field")
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (dict["description"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let author = extractAuthor(dict["author"])
        let imageURL = extractImageURL(dict["image"])
        let yieldText = (dict["recipeYield"] as? String)
            ?? (dict["recipeYield"] as? [String])?.first

        let prepMin  = parseISO8601Duration(dict["prepTime"])
        let cookMin  = parseISO8601Duration(dict["cookTime"])
        let totalMin = parseISO8601Duration(dict["totalTime"])

        let ingredients = extractStringList(dict["recipeIngredient"])
            .map { IngredientItem(raw: $0) }
        let ingredientSections = ingredients.isEmpty
            ? [] : [IngredientSection(name: nil, items: ingredients)]
        let instructionSections = extractInstructions(dict["recipeInstructions"])

        let categories = extractStringList(dict["recipeCategory"])
        let cuisines   = extractStringList(dict["recipeCuisine"])
        let keywords   = extractKeywords(dict["keywords"])
        let nutrition  = extractNutrition(dict["nutrition"])
        let canonical  = extractCanonicalURL(from: html)

        var warnings: [String] = []
        if ingredients.isEmpty { warnings.append("No ingredients found in structured data") }
        if instructionSections.isEmpty { warnings.append("No instructions found in structured data") }

        return ParserResult(
            title: title,
            summary: description,
            author: author,
            imageURL: imageURL,
            ingredientSections: ingredientSections,
            instructionSections: instructionSections,
            yield: yieldText,
            servings: servings(from: yieldText),
            times: RecipeTimes(prepMinutes: prepMin, cookMinutes: cookMin, totalMinutes: totalMin),
            nutrition: nutrition,
            cuisines: cuisines,
            categories: categories,
            keywords: keywords,
            diets: [],
            canonicalURL: canonical,
            confidence: scoreConfidence(
                hasIngredients: !ingredients.isEmpty,
                hasInstructions: !instructionSections.isEmpty,
                hasImage: imageURL != nil,
                hasTime: prepMin != nil || cookMin != nil || totalMin != nil
            ),
            warnings: warnings,
            parser: "native-jsonld"
        )
    }

    // MARK: - Field extractors

    private func extractAuthor(_ value: Any?) -> String? {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        if let d = value as? [String: Any] {
            return (d["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        if let arr = value as? [[String: Any]] {
            return arr.compactMap { ($0["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }.first
        }
        return nil
    }

    private func extractImageURL(_ value: Any?) -> String? {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        if let d = value as? [String: Any] {
            return (d["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        if let arr = value as? [Any] {
            for item in arr {
                if let s = item as? String, !s.isEmpty { return s }
                if let d = item as? [String: Any], let u = d["url"] as? String, !u.isEmpty { return u }
            }
        }
        return nil
    }

    private func extractStringList(_ value: Any?) -> [String] {
        if let s = value as? String { return [s].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        if let arr = value as? [String] {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    private func extractKeywords(_ value: Any?) -> [String] {
        if let s = value as? String {
            return s.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return extractStringList(value)
    }

    private func extractNutrition(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        let keys = ["calories", "fatContent", "saturatedFatContent", "carbohydrateContent",
                    "sugarContent", "fiberContent", "proteinContent", "sodiumContent"]
        var result: [String: String] = [:]
        for key in keys {
            if let val = dict[key] as? String, !val.isEmpty { result[key] = val }
            else if dict[key] != nil { result[key] = "\(dict[key]!)" }
        }
        return result
    }

    private func extractInstructions(_ value: Any?) -> [InstructionSection] {
        guard let value = value else { return [] }
        if let text = value as? String {
            let steps = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return steps.isEmpty ? [] : [InstructionSection(name: nil, steps: steps)]
        }
        guard let array = value as? [Any] else { return [] }
        var sections: [InstructionSection] = []
        var ungrouped: [String] = []
        for item in array {
            if let text = item as? String {
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { ungrouped.append(t) }
            } else if let dict = item as? [String: Any] {
                let typeName = ((dict["@type"] as? String) ?? "").lowercased()
                if typeName.contains("howtosection") {
                    if !ungrouped.isEmpty {
                        sections.append(InstructionSection(name: nil, steps: ungrouped))
                        ungrouped = []
                    }
                    let sectionName = (dict["name"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                    let items = dict["itemListElement"] as? [Any] ?? []
                    let steps = items.compactMap { extractStepText($0) }
                    if !steps.isEmpty {
                        sections.append(InstructionSection(name: sectionName, steps: steps))
                    }
                } else if let text = extractStepText(dict) {
                    ungrouped.append(text)
                }
            }
        }
        if !ungrouped.isEmpty { sections.append(InstructionSection(name: nil, steps: ungrouped)) }
        return sections
    }

    private func extractStepText(_ item: Any) -> String? {
        if let s = item as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank }
        if let d = item as? [String: Any] {
            return ((d["text"] as? String) ?? (d["name"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        }
        return nil
    }

    private func extractCanonicalURL(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<link[^>]+rel\s*=\s*["']canonical["'][^>]+href\s*=\s*["']([^"']+)["']|<link[^>]+href\s*=\s*["']([^"']+)["'][^>]+rel\s*=\s*["']canonical["']"#,
            options: .caseInsensitive
        ) else { return nil }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        guard let match = regex.firstMatch(in: html, range: range) else { return nil }
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound { return nsHTML.substring(with: r) }
        }
        return nil
    }

    private func parseISO8601Duration(_ value: Any?) -> Int? {
        guard let s = value as? String else { return nil }
        var total = 0
        var current = ""
        var inTime = false
        for ch in s.uppercased() {
            switch ch {
            case "T": inTime = true; current = ""
            case "H" where inTime: total += (Int(current) ?? 0) * 60; current = ""
            case "M" where inTime: total += Int(current) ?? 0; current = ""
            case let c where c.isNumber: current += String(c)
            default: current = ""
            }
        }
        return total > 0 ? total : nil
    }

    private func scoreConfidence(
        hasIngredients: Bool, hasInstructions: Bool,
        hasImage: Bool, hasTime: Bool
    ) -> Double {
        var score = 0.2
        if hasIngredients  { score += 0.35 }
        if hasInstructions { score += 0.35 }
        if hasImage        { score += 0.05 }
        if hasTime         { score += 0.05 }
        return score
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
