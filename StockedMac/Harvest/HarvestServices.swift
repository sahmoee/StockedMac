// HarvestServices.swift — Service layer for the Harvester

import Compression
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
        
        // Apply rate limiting, honouring the source's own requested delay scaled by
        // the run's aggressiveness (politeness floor of 0.5 s lives in the limiter).
        await limiter.waitIfNeeded(
            for: url.host ?? "",
            minimumDelay: Double(source.minimumDelaySeconds) * settings.crawlAggressiveness.delayMultiplier
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
            minimumDelay: Double(source.minimumDelaySeconds) * settings.crawlAggressiveness.delayMultiplier
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
//
// Build 93: three engines behind one door, plus a throttle.
//
//   • Sitemaps        — the Build 90 path, now budgeted and category-aware.
//   • Category pages  — for sites with useless sitemaps: crawl listing pages and
//                       follow the recipe links printed on them.
//   • Feeds           — RSS/Atom, including reddit (r/<sub>/.rss): entry links are
//                       candidates, and for aggregator hosts the OUTBOUND links in
//                       entry bodies are too, since the recipe lives off-site.
//
// The old engine treated every sitemap URL as a recipe. Real sitemaps are full of
// "Birthdays", "Holidays", "Our favorite 50…" hub pages; those now get CLASSIFIED —
// recipe-shaped URLs go straight to the candidate list, listing-shaped URLs get
// fetched (up to the aggressiveness budget) and mined for the recipe links they
// contain. Either way the importer still verifies every page before anything is
// saved, so a hub that slips through is refused there, not stored.

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
        let level = settings.crawlAggressiveness
        let method = resolveMethod(settings.preferredCrawlMethod, source: source)
        var notes: [String] = ["Engine: \(methodLabel(method)) · Speed: \(level.label)"]
        var recipeURLs: [String] = []
        var listingURLs: [String] = []
        var unverifiedURLs: [String] = []
        var workingSeed: String?

        await progress(DiscoveryProgress(phase: "Starting (\(methodLabel(method)))",
                                         currentURL: nil, pagesFetched: 0,
                                         queued: 0, confirmed: 0, rejected: 0))

        // Build 94: engines run as a CHAIN. The picked engine goes first; if it (plus
        // category expansion) produces nothing, the next engine gets a turn — so a site
        // whose sitemap is blocked, gzip-only, or junk no longer ends the run at zero.
        // A forced method runs alone; only Auto falls through.
        let chain: [CrawlMethod]
        if settings.preferredCrawlMethod == .auto {
            chain = [method] + [CrawlMethod.sitemap, .categories, .feed].filter { $0 != method }
        } else {
            chain = [method]
        }

        for (attempt, engine) in chain.enumerated() {
            if Task.isCancelled { break }
            if attempt > 0 {
                notes.append("\(methodLabel(chain[attempt - 1])) came up empty; trying \(methodLabel(engine).lowercased()).")
            }
            switch engine {
            case .feed:
                let result = try await crawlFeeds(source: source, settings: settings,
                                                  level: level, progress: progress)
                recipeURLs = result.urls
                notes.append(contentsOf: result.notes)
                if workingSeed == nil { workingSeed = result.workingSeed }
                unverifiedURLs = result.unverified

            case .categories:
                let result = try await crawlListings(source: source, settings: settings,
                                                     level: level, progress: progress)
                recipeURLs = result.urls
                notes.append(contentsOf: result.notes)
                if workingSeed == nil { workingSeed = result.workingSeed }

            case .sitemap, .auto:
                let result = try await crawlSitemaps(source: source, settings: settings,
                                                     level: level, progress: progress)
                recipeURLs = result.recipeURLs
                listingURLs = result.listingURLs
                notes.append(contentsOf: result.notes)
                if workingSeed == nil { workingSeed = result.workingSeed }
                unverifiedURLs = result.unverified
            }

            try await expandListings(&recipeURLs, listingURLs: &listingURLs,
                                     source: source, settings: settings,
                                     level: level, notes: &notes, progress: progress)
            if !recipeURLs.isEmpty { break }
        }

        // Dedupe, drop what's already imported, cap to the run budget — loudly.
        var seen = Set<String>()
        var deduplicated = recipeURLs.filter { seen.insert($0).inserted }
        if settings.skipAlreadyImported {
            deduplicated = deduplicated.filter { !knownSourceURLs.contains($0) }
        }
        if deduplicated.count > level.candidateCap {
            notes.append("Capped at \(level.candidateCap) of \(deduplicated.count) candidates (\(level.label) speed).")
            deduplicated = Array(deduplicated.prefix(level.candidateCap))
        }

        let confirmed = deduplicated.map { DiscoveredLink(url: $0, title: nil, imageURL: nil) }

        return DiscoveryReport(
            sourceID: source.id,
            sourceName: source.name,
            startedAt: startedAt,
            finishedAt: Date(),
            workingSeed: workingSeed ?? source.sitemapURLs.first,
            candidates: confirmed,
            confirmed: confirmed,
            rejected: [],
            unverified: unverifiedURLs,
            notes: notes
        )
    }

    /// Opens listing/category pages — "Birthdays", "Holiday favorites" and friends —
    /// and mines them for the recipe links they carry, within the speed budget.
    private func expandListings(
        _ recipeURLs: inout [String],
        listingURLs: inout [String],
        source: SourceProfile,
        settings: AppSettings,
        level: CrawlAggressiveness,
        notes: inout [String],
        progress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async throws {
        guard !listingURLs.isEmpty else { return }
        let budget = min(listingURLs.count, level.expansionCap)
        notes.append("\(listingURLs.count) category pages found; expanding \(budget).")
        var expanded = 0
        for listing in listingURLs.prefix(budget) {
            if Task.isCancelled { break }
            await progress(DiscoveryProgress(phase: "Opening category pages (\(expanded + 1)/\(budget))",
                                             currentURL: listing,
                                             pagesFetched: expanded,
                                             queued: budget - expanded,
                                             confirmed: recipeURLs.count, rejected: 0))
            guard let url = URL(string: listing) else { continue }
            do {
                let page = try await fetcher.fetch(
                    url, source: source, settings: settings,
                    accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
                )
                let links = Self.extractLinks(from: page.text, base: page.finalURL)
                    .filter { Self.classify($0, source: source) == .recipe }
                recipeURLs.append(contentsOf: links)
                expanded += 1
            } catch is CancellationError {
                break
            } catch {
                notes.append("Category page failed: \(listing)")
                expanded += 1
            }
        }
        if listingURLs.count > budget {
            notes.append("\(listingURLs.count - budget) category pages left for the next run (raise the speed to expand more).")
        }
        listingURLs.removeAll()
    }

    // MARK: Method resolution

    private nonisolated func resolveMethod(_ preferred: CrawlMethod, source: SourceProfile) -> CrawlMethod {
        switch preferred {
        case .auto:
            switch source.discoveryMode {
            case .feedOnly:    return .feed
            case .htmlListing: return .categories
            default:           return .sitemap
            }
        default:
            return preferred
        }
    }

    private nonisolated func methodLabel(_ method: CrawlMethod) -> String {
        method == .auto ? "Auto" : method.label
    }

    // MARK: Sitemap engine

    private struct SitemapResult {
        var recipeURLs: [String] = []
        var listingURLs: [String] = []
        var notes: [String] = []
        var unverified: [String] = []
        var workingSeed: String?
    }

    private func crawlSitemaps(
        source: SourceProfile,
        settings: AppSettings,
        level: CrawlAggressiveness,
        progress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async throws -> SitemapResult {
        // Build 94: breadth-first over sitemap FILES with one budget for the whole
        // walk, children included. The old engine recursed through every child of a
        // sitemap index — hundreds of files at 2 s spacing reads as "stuck". Children
        // that smell like recipes are visited first, gzipped files are inflated, and
        // the walk stops early once the candidate cap is reached.
        var result = SitemapResult()
        let base = source.baseURL.hasSuffix("/") ? source.baseURL : source.baseURL + "/"
        let seeds = source.sitemapURLs.isEmpty
            ? [base + "sitemap.xml", base + "sitemap_index.xml", base + "wp-sitemap.xml"]
            : source.sitemapURLs
        var queue = seeds
        var visited = Set<String>()
        let fileBudget = level.sitemapFileCap
        var fetched = 0

        while !queue.isEmpty, fetched < fileBudget, result.recipeURLs.count < level.candidateCap {
            if Task.isCancelled {
                result.unverified = queue
                result.notes.append("Cancelled with \(queue.count) sitemap files unread.")
                break
            }
            let sitemapURLString = queue.removeFirst()
            guard visited.insert(sitemapURLString).inserted,
                  let sitemapURL = URL(string: sitemapURLString) else { continue }

            await progress(DiscoveryProgress(phase: "Reading sitemaps (\(fetched + 1)/\(fileBudget))",
                                             currentURL: sitemapURLString,
                                             pagesFetched: fetched,
                                             queued: queue.count,
                                             confirmed: result.recipeURLs.count, rejected: 0))
            do {
                let data = try await fetcher.fetchData(
                    sitemapURL, source: source, settings: settings,
                    accept: "application/xml,text/xml,application/gzip,*/*"
                )
                fetched += 1
                let text = Self.decodeSitemapText(data)
                guard !text.isEmpty else {
                    result.notes.append("Unreadable sitemap: \(sitemapURLString)")
                    continue
                }
                let isIndex = text.range(of: "<sitemapindex", options: .caseInsensitive) != nil
                let locs = Self.extractXMLTagContents(named: "loc", from: text)
                if isIndex {
                    let children = Self.prioritizeSitemapChildren(locs)
                    queue.insert(contentsOf: children, at: 0)
                    result.notes.append("\(sitemapURLString): index with \(locs.count) child sitemaps")
                } else {
                    var recipes = 0
                    for urlString in locs where Self.matchesDomain(urlString, source: source) {
                        switch Self.classify(urlString, source: source) {
                        case .recipe:  result.recipeURLs.append(urlString); recipes += 1
                        case .listing: result.listingURLs.append(urlString)
                        case .skip:    break
                        }
                    }
                    result.notes.append("\(sitemapURLString): \(locs.count) URLs, \(recipes) recipe-shaped")
                    if result.workingSeed == nil, recipes > 0 { result.workingSeed = sitemapURLString }
                }
            } catch is CancellationError {
                result.unverified = queue
                result.notes.append("Cancelled at \(sitemapURLString)")
                break
            } catch {
                fetched += 1
                result.notes.append("Sitemap failed: \(sitemapURLString) — \(error.localizedDescription)")
            }
        }

        if !queue.isEmpty {
            if fetched >= fileBudget {
                result.notes.append("Stopped at the \(level.label) budget of \(fileBudget) sitemap files; \(queue.count) unread. Raise the speed for more.")
            } else if result.recipeURLs.count >= level.candidateCap {
                result.notes.append("Candidate cap reached with \(queue.count) sitemap files unread.")
            }
        }
        return result
    }

    /// Children that smell like recipe content go first; media, video, category and
    /// author sitemaps go last, so a small file budget is spent where recipes live.
    nonisolated static func prioritizeSitemapChildren(_ children: [String]) -> [String] {
        func score(_ urlString: String) -> Int {
            let lower = urlString.lowercased()
            if lower.contains("recipe") { return 0 }
            if lower.contains("post") || lower.contains("content") || lower.contains("article") { return 1 }
            if lower.contains("video") || lower.contains("image") || lower.contains("photo")
                || lower.contains("category") || lower.contains("tag") || lower.contains("author")
                || lower.contains("shows") || lower.contains("chefs") || lower.contains("news") { return 3 }
            return 2
        }
        return children.enumerated()
            .sorted { (score($0.element), $0.offset) < (score($1.element), $1.offset) }
            .map(\.element)
    }

    /// UTF-8 (or Latin-1) text out of a sitemap response, inflating gzip when the file
    /// arrives as raw .xml.gz bytes — large sites ship most sitemaps that way, which
    /// is one of the two reasons runs used to end at "0 found".
    nonisolated static func decodeSitemapText(_ data: Data) -> String {
        var payload = data
        let bytes = [UInt8](data.prefix(2))
        if bytes.count == 2, bytes[0] == 0x1f, bytes[1] == 0x8b, let inflated = gunzip(data) {
            payload = inflated
        }
        return String(data: payload, encoding: .utf8)
            ?? String(data: payload, encoding: .isoLatin1)
            ?? ""
    }

    /// Minimal gzip container parse + raw-DEFLATE inflate via Compression.
    nonisolated static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {                                    // FEXTRA
            guard index + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + xlen
        }
        if flags & 0x08 != 0 {                                    // FNAME
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x10 != 0 {                                    // FCOMMENT
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        if flags & 0x02 != 0 { index += 2 }                       // FHCRC
        guard index < bytes.count else { return nil }
        let deflated = Data(bytes[index...])

        let capacity = min(max(deflated.count * 24, 4_000_000), 96_000_000)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            deflated.withUnsafeBytes { src -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, capacity,
                                                 srcBase, deflated.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        output.removeSubrange(written..<output.count)
        return output
    }

    // MARK: Category-page engine

    private struct LinkCrawlResult {
        var urls: [String] = []
        var notes: [String] = []
        var workingSeed: String?
    }

    /// Crawls listing pages: the base URL plus any configured seeds, breadth-first one
    /// level deep, collecting recipe-shaped links and following listing-shaped ones.
    private func crawlListings(
        source: SourceProfile,
        settings: AppSettings,
        level: CrawlAggressiveness,
        progress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async throws -> LinkCrawlResult {
        var result = LinkCrawlResult()
        var frontier: [String] = [source.baseURL]
        // Non-feed seeds double as starting listing pages when the mode is category crawl.
        frontier.append(contentsOf: source.sitemapURLs.filter { !$0.lowercased().contains("sitemap") })
        var visited = Set<String>()
        var fetched = 0
        let pageBudget = level.seedPageCap + level.expansionCap

        while !frontier.isEmpty, fetched < pageBudget {
            if Task.isCancelled { break }
            let pageURLString = frontier.removeFirst()
            guard visited.insert(pageURLString).inserted,
                  let pageURL = URL(string: pageURLString) else { continue }
            await progress(DiscoveryProgress(phase: "Crawling category pages",
                                             currentURL: pageURLString,
                                             pagesFetched: fetched,
                                             queued: frontier.count,
                                             confirmed: result.urls.count, rejected: 0))
            do {
                let page = try await fetcher.fetch(
                    pageURL, source: source, settings: settings,
                    accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1"
                )
                if result.workingSeed == nil { result.workingSeed = pageURLString }
                let links = Self.extractLinks(from: page.text, base: page.finalURL)
                for link in links {
                    switch Self.classify(link, source: source) {
                    case .recipe:
                        result.urls.append(link)
                    case .listing:
                        if !visited.contains(link), frontier.count < pageBudget * 3 {
                            frontier.append(link)
                        }
                    case .skip:
                        break
                    }
                }
                fetched += 1
            } catch is CancellationError {
                break
            } catch {
                result.notes.append("Page failed: \(pageURLString) — \(error.localizedDescription)")
                fetched += 1
            }
        }
        result.notes.append("Crawled \(fetched) pages, found \(result.urls.count) recipe links.")
        if !frontier.isEmpty {
            result.notes.append("\(frontier.count) more listing pages available at a higher speed.")
        }
        return result
    }

    // MARK: Feed engine (RSS / Atom / reddit)

    private struct FeedResult {
        var urls: [String] = []
        var notes: [String] = []
        var unverified: [String] = []
        var workingSeed: String?
    }

    private func crawlFeeds(
        source: SourceProfile,
        settings: AppSettings,
        level: CrawlAggressiveness,
        progress: @Sendable @escaping (DiscoveryProgress) async -> Void
    ) async throws -> FeedResult {
        var result = FeedResult()
        var seeds = source.sitemapURLs.filter {
            let lower = $0.lowercased()
            return lower.contains("feed") || lower.contains("rss") || lower.contains(".json") || lower.contains(".rss")
        }
        if seeds.isEmpty {
            let base = source.baseURL.hasSuffix("/") ? String(source.baseURL.dropLast()) : source.baseURL
            if base.lowercased().contains("reddit.com") {
                seeds = [base + "/.rss", base + "/top/.rss"]
            } else {
                seeds = [base + "/feed", base + "/rss", base + "/feed.xml", base + "/atom.xml"]
            }
        }
        let isAggregator = Self.isAggregatorHost(source)
        var fetched = 0

        for seed in seeds.prefix(level.seedPageCap) {
            if Task.isCancelled {
                result.unverified = Array(seeds.dropFirst(fetched))
                break
            }
            guard let url = URL(string: seed) else { continue }
            await progress(DiscoveryProgress(phase: "Reading feed",
                                             currentURL: seed,
                                             pagesFetched: fetched,
                                             queued: seeds.count - fetched,
                                             confirmed: result.urls.count, rejected: 0))
            do {
                let data = try await fetcher.fetchData(
                    url, source: source, settings: settings,
                    accept: "application/rss+xml,application/atom+xml,application/xml,text/xml,application/json,*/*"
                )
                let text = String(data: data, encoding: .utf8) ?? ""
                guard !text.isEmpty else { continue }
                let links = Self.extractFeedLinks(from: text)
                var kept = 0
                for link in links {
                    guard let linkURL = URL(string: link), let host = linkURL.host?.lowercased() else { continue }
                    if isAggregator {
                        // Aggregator feeds (reddit): the recipe is the OUTBOUND link in
                        // the entry, not the entry itself. Keep off-site article links,
                        // drop media hosts and the aggregator's own pages.
                        guard !Self.matchesDomain(link, source: source),
                              !Self.isMediaOrJunkHost(host),
                              !Self.looksLikeMediaFile(link) else { continue }
                    } else {
                        // A site's own feed: entries are the recipe pages.
                        guard Self.matchesDomain(link, source: source),
                              Self.classify(link, source: source) == .recipe else { continue }
                    }
                    result.urls.append(link)
                    kept += 1
                }
                result.notes.append("\(seed): \(kept) links")
                if result.workingSeed == nil, kept > 0 { result.workingSeed = seed }
                fetched += 1
                // One good feed is usually the whole story; stop early unless pushing.
                if kept > 0, level == .gentle { break }
            } catch is CancellationError {
                result.unverified = Array(seeds.dropFirst(fetched))
                break
            } catch {
                result.notes.append("Feed failed: \(seed) — \(error.localizedDescription)")
                fetched += 1
            }
        }
        if isAggregator {
            result.notes.append("Aggregator feed: every link gets the full recipe check at import.")
        }
        return result
    }

    // MARK: URL classification

    enum URLClass { case recipe, listing, skip }

    /// Decides what a URL is likely to be — a recipe page, a listing/category page
    /// worth mining for links, or noise. The importer's page detector remains the
    /// final judge; this only routes the crawl.
    nonisolated static func classify(_ urlString: String, source: SourceProfile) -> URLClass {
        guard matchesDomain(urlString, source: source) else { return .skip }
        for pattern in source.excludedURLPatterns where urlString.contains(pattern) { return .skip }
        guard let url = URL(string: urlString) else { return .skip }
        let path = url.path.lowercased()
        if looksLikeMediaFile(urlString) { return .skip }

        // Listing tells: category-style path segments, seasonal/occasion hubs,
        // roundups, pagination, or a bare section index like …/recipes/.
        let listingMarkers = [
            "/category/", "/categories/", "/collection", "/collections/", "/tag/",
            "/tags/", "/topics/", "/topic/", "/holiday", "/holidays", "/occasion",
            "/birthday", "/christmas", "/thanksgiving", "/easter", "/halloween",
            "/roundup", "/round-up", "/best-", "/menus/", "/menu/", "/gallery/",
            "/hub/", "/index/", "/page/", "/archive",
        ]
        // Media galleries and video shells never parse into recipes; skip outright.
        let skipMarkers = ["/photos/", "/photo/", "/galleries/", "/packages/", "/videos/", "/video/"]
        if skipMarkers.contains(where: { path.contains($0) }) { return .skip }
        if listingMarkers.contains(where: { path.contains($0) }) { return .listing }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if trimmed.isEmpty { return .listing }
        let segments = trimmed.split(separator: "/")
        if let last = segments.last,
           ["recipes", "recipe", "food", "cooking", "dishes"].contains(String(last)),
           segments.count <= 2 {
            return .listing
        }

        // Recipe tells: a slug-shaped final segment — hyphens or digits, some length.
        // "breakfast", "dinner", "chicken" under /recipes/ are HUBS, not dishes; the
        // Build 95 rule let them through because they matched the "/recipes/" pattern,
        // and the importer then failed them 288 at a time.
        let last = segments.last.map(String.init) ?? ""
        let slugLike = (last.contains("-") && last.count >= 6)
            || last.rangeOfCharacter(from: .decimalDigits) != nil
        if !source.recipeURLPatterns.isEmpty {
            guard source.recipeURLPatterns.contains(where: { urlString.contains($0) }) else {
                return .listing
            }
            return slugLike ? .recipe : .listing
        }
        if slugLike, segments.count >= 2 { return .recipe }
        return .listing
    }

    nonisolated static func matchesDomain(_ urlString: String, source: SourceProfile) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        return source.domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Communities whose feed entries point at recipes hosted elsewhere.
    nonisolated static func isAggregatorHost(_ source: SourceProfile) -> Bool {
        source.domains.contains { $0.contains("reddit.com") }
            || source.tags.contains("Community") && source.discoveryMode == .feedOnly
    }

    nonisolated static func isMediaOrJunkHost(_ host: String) -> Bool {
        let junk = ["imgur.com", "i.redd.it", "v.redd.it", "redd.it", "youtube.com",
                    "youtu.be", "gfycat.com", "giphy.com", "streamable.com",
                    "instagram.com", "tiktok.com", "twitter.com", "x.com",
                    "facebook.com", "pinterest.com", "amazon.com", "flickr.com",
                    "reddit.com", "redditstatic.com", "redditmedia.com"]
        return junk.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    nonisolated static func looksLikeMediaFile(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return [".jpg", ".jpeg", ".png", ".gif", ".webp", ".mp4", ".webm", ".pdf",
                ".zip", ".xml", ".css", ".js"].contains { lower.hasSuffix($0) || lower.contains($0 + "?") }
    }

    // MARK: Extraction helpers

    /// Every same-scheme absolute link on a page, resolved against the page URL.
    nonisolated static func extractLinks(from html: String, base: URL) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"href\s*=\s*["']([^"'#\s]+)["']"#,
            options: .caseInsensitive
        ) else { return [] }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        var out: [String] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1 else { continue }
            let raw = nsHTML.substring(with: match.range(at: 1))
            guard !raw.hasPrefix("javascript:"), !raw.hasPrefix("mailto:") else { continue }
            guard let resolved = URL(string: raw, relativeTo: base)?.absoluteURL,
                  let scheme = resolved.scheme, scheme.hasPrefix("http") else { continue }
            let normalized = URLSafety.normalized(resolved).absoluteString
            if seen.insert(normalized).inserted { out.append(normalized) }
        }
        return out
    }

    /// Links out of an RSS/Atom document: <link>text</link>, <link href="…"/>, and any
    /// absolute URL inside entry bodies (how reddit carries the outbound article link).
    nonisolated static func extractFeedLinks(from xml: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ raw: String) {
            let cleaned = raw
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.hasPrefix("http"), seen.insert(cleaned).inserted else { return }
            out.append(cleaned)
        }
        for value in extractXMLTagContents(named: "link", from: xml) { add(value) }
        if let hrefRegex = try? NSRegularExpression(
            pattern: #"<link[^>]+href\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive
        ) {
            let ns = xml as NSString
            for match in hrefRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
            where match.numberOfRanges > 1 {
                add(ns.substring(with: match.range(at: 1)))
            }
        }
        // Absolute URLs inside encoded entry bodies (href=&quot;…&quot; and plain).
        if let urlRegex = try? NSRegularExpression(
            pattern: #"https?://[^\s"'<>&\\)\]]+"#, options: []
        ) {
            let ns = xml as NSString
            for match in urlRegex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
                add(ns.substring(with: match.range))
            }
        }
        return out
    }

    nonisolated static func extractXMLTagContents(named tag: String, from xml: String) -> [String] {
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
    
    /// Puts the full built-in catalog back while KEEPING every source that is not part
    /// of it (custom and file-imported entries survive). This is the self-heal for a
    /// sources.json that decoded to something empty, disabled, or unbrowsable.
    func repairCatalog() async throws -> [SourceProfile] {
        let builtin = builtInSources()
        guard !builtin.isEmpty else {
            throw CompanionError.parseFailed("The built-in catalog is unavailable")
        }
        let builtinIDs = Set(builtin.map(\.id))
        let custom = sources.filter { !builtinIDs.contains($0.id) }
        sources = builtin + custom
        try await persist()
        return sources
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
        // Build 96: hydration payloads (Next.js and friends) carry the identical
        // schema.org object inside plain <script> tags. Scan any script body that
        // mentions a Recipe type and pull the first balanced JSON object out of it.
        for candidate in extractRecipeScriptJSON(from: html) {
            if let dict = findRecipeDict(in: candidate) {
                return try buildResult(from: dict, url: url, html: html)
            }
        }
        throw CompanionError.parseFailed("No schema.org/Recipe JSON-LD found")
    }

    /// JSON slices from ordinary <script> bodies that look like they hold a Recipe.
    private func extractRecipeScriptJSON(from html: String) -> [String] {
        guard html.contains("Recipe") else { return [] }
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*>([\s\S]*?)</script>"#,
            options: .caseInsensitive
        ) else { return [] }
        let nsHTML = html as NSString
        let range = NSRange(location: 0, length: nsHTML.length)
        var out: [String] = []
        for match in regex.matches(in: html, range: range) where match.numberOfRanges > 1 {
            let body = nsHTML.substring(with: match.range(at: 1))
            guard body.contains("@type"), body.contains("Recipe") else { continue }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                out.append(trimmed)
            } else if let slice = Self.balancedJSONObject(in: body) {
                out.append(slice)
            }
            if out.count >= 6 { break }
        }
        return out
    }

    /// The first balanced `{ … }` in the text, ignoring braces inside string literals.
    static func balancedJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
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

    /// A page that is really a bot wall, not content. Short bodies and challenge
    /// phrases; used to decide the WebKit-rendered retry and to say something more
    /// useful than "No JSON-LD found".
    static func looksBlocked(_ html: String) -> Bool {
        if html.count < 2500 { return true }
        let lower = html.lowercased()
        let markers = ["captcha", "access denied", "are you a robot", "unusual traffic",
                       "just a moment", "cf-challenge", "cf-browser-verification",
                       "request blocked", "pardon our interruption", "px-captcha",
                       "bot detection", "enable javascript and cookies"]
        return markers.contains { lower.contains($0) }
    }

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


// MARK: - Microdata parser (Build 95)
//
// Second engine: schema.org via itemprop attributes, for sites that mark recipes up
// in HTML instead of JSON-LD. Regex-scoped, deliberately forgiving.

nonisolated struct MicrodataRecipeParser {

    func parse(html: String, url: URL) throws -> ParserResult {
        let ingredients = Self.itempropValues(["recipeIngredient", "ingredients"], in: html)
        let steps = Self.itempropValues(["recipeInstructions"], in: html)
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 3 }
        guard ingredients.count >= 2, !steps.isEmpty else {
            throw CompanionError.parseFailed("No schema.org microdata recipe found")
        }
        let title = Self.itempropValues(["name"], in: html).first
            ?? HeuristicRecipeParser.metaContent("og:title", in: html)
            ?? ""
        guard !title.isEmpty else {
            throw CompanionError.parseFailed("Microdata recipe has no name")
        }
        let image = Self.itempropAttribute(["image"], attributes: ["content", "src", "href"], in: html)
            ?? HeuristicRecipeParser.metaContent("og:image", in: html)

        return ParserResult(
            title: title,
            summary: Self.itempropValues(["description"], in: html).first
                ?? HeuristicRecipeParser.metaContent("og:description", in: html),
            author: Self.itempropValues(["author"], in: html).first,
            imageURL: image,
            ingredientSections: [IngredientSection(name: nil, items: ingredients.map { IngredientItem(raw: $0) })],
            instructionSections: [InstructionSection(name: nil, steps: steps)],
            yield: Self.itempropValues(["recipeYield"], in: html).first,
            servings: nil,
            times: RecipeTimes(),
            nutrition: [:],
            cuisines: Self.itempropValues(["recipeCuisine"], in: html),
            categories: Self.itempropValues(["recipeCategory"], in: html),
            keywords: [],
            diets: [],
            canonicalURL: nil,
            confidence: 0.7,
            warnings: ["Parsed from HTML microdata; check the details."],
            parser: "native-microdata"
        )
    }

    /// Text content of elements carrying one of these itemprops.
    static func itempropValues(_ names: [String], in html: String) -> [String] {
        var out: [String] = []
        for name in names {
            guard let regex = try? NSRegularExpression(
                pattern: "<([a-z0-9]+)[^>]*itemprop\\s*=\\s*[\"']" + name + "[\"'][^>]*>([\\s\\S]*?)</\\1>",
                options: .caseInsensitive
            ) else { continue }
            let ns = html as NSString
            for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            where match.numberOfRanges > 2 {
                let text = HeuristicRecipeParser.plainText(ns.substring(with: match.range(at: 2)))
                if !text.isEmpty { out.append(text) }
            }
            // Meta-style: <meta itemprop="name" content="...">
            if out.isEmpty, let value = itempropAttribute([name], attributes: ["content"], in: html) {
                out.append(value)
            }
        }
        return out.cleanedUnique()
    }

    static func itempropAttribute(_ names: [String], attributes: [String], in html: String) -> String? {
        for name in names {
            for attribute in attributes {
                let patterns = [
                    "itemprop\\s*=\\s*[\"']" + name + "[\"'][^>]*" + attribute + "\\s*=\\s*[\"']([^\"']+)[\"']",
                    attribute + "\\s*=\\s*[\"']([^\"']+)[\"'][^>]*itemprop\\s*=\\s*[\"']" + name + "[\"']",
                ]
                for pattern in patterns {
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                    let ns = html as NSString
                    if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
                       match.numberOfRanges > 1 {
                        return ns.substring(with: match.range(at: 1))
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Heuristic parser (Build 95)
//
// Last local resort: og: tags for identity, class-name scraping for the body. Its
// confidence is capped low so nothing it produces can auto-approve — a human reads it.

nonisolated struct HeuristicRecipeParser {

    func parse(html: String, url: URL) throws -> ParserResult {
        let ingredients = Self.listItems(classContaining: "ingredient", in: html)
        let steps = Self.listItems(classContaining: "instruction", in: html)
            + Self.listItems(classContaining: "direction", in: html)
            + Self.listItems(classContaining: "step", in: html)
        let uniqueSteps = steps.cleanedUnique().filter { $0.count > 8 }
        guard ingredients.count >= 3, uniqueSteps.count >= 2 else {
            throw CompanionError.parseFailed("No recognizable recipe structure in the HTML")
        }
        let title = Self.metaContent("og:title", in: html)
            ?? Self.tagText("title", in: html)
            ?? ""
        guard !title.isEmpty else {
            throw CompanionError.parseFailed("The page has no title")
        }

        return ParserResult(
            title: title,
            summary: Self.metaContent("og:description", in: html),
            author: nil,
            imageURL: Self.metaContent("og:image", in: html),
            ingredientSections: [IngredientSection(name: nil, items: ingredients.map { IngredientItem(raw: $0) })],
            instructionSections: [InstructionSection(name: nil, steps: uniqueSteps)],
            yield: nil,
            servings: nil,
            times: RecipeTimes(),
            nutrition: [:],
            cuisines: [],
            categories: [],
            keywords: [],
            diets: [],
            canonicalURL: nil,
            confidence: 0.55,
            warnings: ["Reconstructed from the page layout, not structured data — review before approving."],
            parser: "heuristic-html"
        )
    }

    /// <li>/<p> text where the element's class mentions the marker.
    static func listItems(classContaining marker: String, in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "<(li|p)[^>]*class\\s*=\\s*[\"'][^\"']*" + marker + "[^\"']*[\"'][^>]*>([\\s\\S]*?)</\\1>",
            options: .caseInsensitive
        ) else { return [] }
        let ns = html as NSString
        var out: [String] = []
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        where match.numberOfRanges > 2 {
            let text = plainText(ns.substring(with: match.range(at: 2)))
            if text.count > 2, text.count < 500 { out.append(text) }
        }
        return out
    }

    static func metaContent(_ property: String, in html: String) -> String? {
        let patterns = [
            "<meta[^>]+(?:property|name)\\s*=\\s*[\"']" + property + "[\"'][^>]+content\\s*=\\s*[\"']([^\"']+)[\"']",
            "<meta[^>]+content\\s*=\\s*[\"']([^\"']+)[\"'][^>]+(?:property|name)\\s*=\\s*[\"']" + property + "[\"']",
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = html as NSString
            if let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1 {
                let value = plainText(ns.substring(with: match.range(at: 1)))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func tagText(_ tag: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<" + tag + "[^>]*>([\\s\\S]*?)</" + tag + ">", options: .caseInsensitive
        ) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let value = plainText(ns.substring(with: match.range(at: 1)))
        return value.isEmpty ? nil : value
    }

    /// Tags stripped, entities decoded, whitespace collapsed.
    static func plainText(_ fragment: String) -> String {
        var text = fragment.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
                        "&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&#8217;": "'", "&#8211;": "-"]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
