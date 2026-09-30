import SowensKit
// HarvestInfrastructure.swift — Infrastructure types for the Harvester

import Foundation

// MARK: - Pause Gate (Build 91)

/// One switch that pauses every network request the Harvester makes — discovery,
/// page fetches and image downloads all funnel through `HTTPClient`, which waits
/// here before each request. Pausing therefore stops new work immediately without
/// cancelling anything: Resume picks up exactly where the run left off.
actor PauseGate {
    private(set) var isPaused = false

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    func waitWhileParked() async {
        while isPaused && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

// MARK: - HTTP Client

actor HTTPClient {
    private let session: URLSession
    private let cacheDirectory: URL
    private var userAgent: String
    private let pauseGate: PauseGate?

    init(cacheDirectory: URL, userAgent: String, pauseGate: PauseGate? = nil) {
        self.cacheDirectory = cacheDirectory
        self.userAgent = userAgent
        self.pauseGate = pauseGate

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.requestCachePolicy = .returnCacheDataElseLoad
        // Build 94: a request that hangs must fail, not park the whole run. Every
        // "stuck on Reading sitemaps" report traced back to the default 60 s request
        // timeout compounding across a sitemap index with hundreds of children.
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45

        self.session = URLSession(configuration: config)

        // Create cache directory
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let pauseGate { await pauseGate.waitWhileParked() }
        try Task.checkCancellation()
        var modifiedRequest = request
        modifiedRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if modifiedRequest.timeoutInterval > 20 { modifiedRequest.timeoutInterval = 20 }
        return try await session.sowensData(for: modifiedRequest)
    }

    func updateUserAgent(_ newUserAgent: String) {
        userAgent = newUserAgent
    }

    func removeAllCache() async throws {
        session.configuration.urlCache?.removeAllCachedResponses()

        let files = try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        )
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }

    func pruneCache(maximumAgeHours: Int, maximumBytes: Int) async -> Int {
        let cutoff = Date().addingTimeInterval(-Double(maximumAgeHours) * 3600)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else { return 0 }

        var removed = 0
        var totalSize = 0
        var filesByDate: [(url: URL, date: Date, size: Int)] = []

        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
                  let date = values.creationDate,
                  let size = values.fileSize else { continue }

            // Remove files older than cutoff
            if date < cutoff {
                try? FileManager.default.removeItem(at: file)
                removed += 1
                continue
            }

            totalSize += size
            filesByDate.append((file, date, size))
        }

        // If still over limit, remove oldest files
        if totalSize > maximumBytes {
            filesByDate.sort { $0.date < $1.date }

            for item in filesByDate {
                if totalSize <= maximumBytes { break }
                try? FileManager.default.removeItem(at: item.url)
                totalSize -= item.size
                removed += 1
            }
        }

        return removed
    }
}

// MARK: - Robots Policy

/// Fetches, caches and applies each origin's robots.txt (RFC 9309) for sources that
/// require robots compliance. Rules come from `RobotsRules`; this actor owns transport
/// and the failure policy:
/// - 2xx: parsed rules, cached for 24 hours.
/// - 4xx (including 404): no restrictions, cached for 24 hours (RFC 9309 §2.3.1.3).
/// - 5xx: treated as "disallow all" for 10 minutes, so an overloaded site is left alone
///   (RFC 9309 §2.3.1.4) without blocking it for the rest of the session.
/// - Transport errors (offline, DNS, TLS, timeout): allowed and retried after 10
///   minutes. Page fetches will fail on their own and the rate limiter still applies.
/// Concurrent lookups for one origin share a single request.
actor RobotsPolicy {
    private struct Entry {
        let rules: RobotsRules
        let expires: Date
    }

    private static let successTTL: TimeInterval = 24 * 60 * 60
    private static let failureTTL: TimeInterval = 10 * 60
    private static let maximumBytes = 500 * 1024

    private var userAgent: String
    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<Entry, Never>] = [:]
    private let session: URLSession

    init(userAgent: String) {
        self.userAgent = userAgent
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// A new user agent can select a different robots group, so cached rules are dropped.
    func updateUserAgent(_ userAgent: String) {
        guard userAgent != self.userAgent else { return }
        self.userAgent = userAgent
        cache.removeAll()
    }

    func isAllowed(_ url: URL) async -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        let origin = url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
        let rules = await rules(for: origin)
        return rules.isAllowed(path: Self.pathAndQuery(of: url))
    }

    /// Percent-encoded path plus query, the form robots.txt patterns are written against.
    static func pathAndQuery(of url: URL) -> String {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            if let query = components.percentEncodedQuery { return path + "?" + query }
            return path
        }
        return url.path.isEmpty ? "/" : url.path
    }

    private func rules(for origin: String) async -> RobotsRules {
        if let entry = cache[origin], entry.expires > Date() { return entry.rules }
        if let task = inFlight[origin] { return await task.value.rules }
        let session = self.session
        let agent = self.userAgent
        let task = Task { await Self.fetch(origin: origin, userAgent: agent, session: session) }
        inFlight[origin] = task
        let entry = await task.value
        inFlight[origin] = nil
        cache[origin] = entry
        return entry.rules
    }

    private static func fetch(origin: String, userAgent: String, session: URLSession) async -> Entry {
        guard let url = URL(string: origin + "/robots.txt") else {
            return Entry(rules: .allowAll, expires: Date().addingTimeInterval(failureTTL))
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, */*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200...299:
                let body = data.prefix(maximumBytes)
                let text = String(decoding: body, as: UTF8.self)
                return Entry(rules: RobotsRules.parse(text, userAgent: userAgent),
                             expires: Date().addingTimeInterval(successTTL))
            case 400...499:
                return Entry(rules: .allowAll, expires: Date().addingTimeInterval(successTTL))
            case 500...599:
                return Entry(rules: .disallowAll, expires: Date().addingTimeInterval(failureTTL))
            default:
                return Entry(rules: .allowAll, expires: Date().addingTimeInterval(failureTTL))
            }
        } catch {
            return Entry(rules: .allowAll, expires: Date().addingTimeInterval(failureTTL))
        }
    }
}

// MARK: - Domain Rate Limiter

actor DomainRateLimiter {
    private var lastRequest: [String: Date] = [:]
    private var requestCounts: [String: Int] = [:]
    private var pausedUntil: [String: Date] = [:]

    /// `minimumDelay` comes from the source profile, so a site that asked for a slower
    /// crawl actually gets one — Build 90 hardcoded two seconds for everybody.
    func waitIfNeeded(for domain: String, minimumDelay: Double = 2.0) async {
        // Check if paused
        if let pausedUntil = pausedUntil[domain], pausedUntil > Date() {
            let delay = pausedUntil.timeIntervalSinceNow
            try? await Task.sleep(for: .seconds(delay))
        }

        // Apply minimum delay between requests
        let floor = max(0.5, minimumDelay)
        if let last = lastRequest[domain] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < floor {
                try? await Task.sleep(for: .seconds(floor - elapsed))
            }
        }

        lastRequest[domain] = Date()
        requestCounts[domain, default: 0] += 1
    }

    /// How many requests this domain has answered since the counters were last reset.
    func requestCount(for domain: String) -> Int {
        requestCounts[domain, default: 0]
    }

    func clearPause(for domain: String) {
        pausedUntil.removeValue(forKey: domain)
    }

    func resetAll() {
        lastRequest.removeAll()
        requestCounts.removeAll()
        pausedUntil.removeAll()
    }
}

// MARK: - Stores

actor SettingsStore {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: AppSettings) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}

actor LogStore {
    private let fileURL: URL
    private var entries: [CrawlLogEntry] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        Task {
            await load()
        }
    }

    private func load() async {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([CrawlLogEntry].self, from: data) else {
            entries = []
            return
        }
        entries = loaded
    }

    func recent(limit: Int) async -> [CrawlLogEntry] {
        Array(entries.prefix(limit))
    }

    func append(_ entry: CrawlLogEntry) async {
        entries.insert(entry, at: 0)
        if entries.count > 1000 {
            entries = Array(entries.prefix(1000))
        }
        try? await persist()
    }

    func clear() async {
        entries.removeAll()
        try? await persist()
    }

    private func persist() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Log Entry

nonisolated struct CrawlLogEntry: Identifiable, Codable, Sendable {
    var id: UUID
    var timestamp: Date
    var level: Level
    var message: String
    var url: String?

    enum Level: String, Codable, Sendable {
        case info
        case success
        case warning
        case error
    }

    init(id: UUID = UUID(), timestamp: Date = Date(), level: Level, message: String, url: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.url = url
    }
}

// MARK: - Import Progress

nonisolated struct ImportProgress: Sendable {
    var completed: Int
    var total: Int
    var succeeded: Int
    var failed: Int
    var currentURL: String?

    static var idle: ImportProgress {
        ImportProgress(completed: 0, total: 0, succeeded: 0, failed: 0, currentURL: nil)
    }
}

// MARK: - Dashboard

nonisolated struct DashboardSnapshot: Sendable {
    var recipes: Int
    var needsReview: Int
    var approved: Int
    var rejected: Int
    var sourcesEnabled: Int
    var sourcesDiscovering: Int
    var averageConfidence: Double
    var duplicateGroups: Int
}

// MARK: - Crawl Presets

nonisolated enum CrawlPreset: String, CaseIterable {
    case respectful
    case balanced
    case aggressive

    var label: String {
        switch self {
        case .respectful: return "Respectful"
        case .balanced: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }

    func apply(to settings: inout AppSettings) {
        switch self {
        case .respectful:
            settings.maximumConcurrentJobs = 1
        case .balanced:
            settings.maximumConcurrentJobs = 3
        case .aggressive:
            settings.maximumConcurrentJobs = 8
        }
    }
}

// MARK: - App Paths

nonisolated struct AppPaths: Sendable {
    let root: URL
    let recipesFile: URL
    let settingsFile: URL
    let logFile: URL
    let sourcesFile: URL
    let httpCache: URL
    let imageCache: URL
    let discoveryReports: URL
    let sourceDiscoveryCache: URL
    let miningResultCache: URL
    let categoryCatalog: URL
    let serverInbox: URL
    let serverInboxReceipts: URL
    let serverHealthFile: URL
    let lastDiscoveryReport: URL
    let importQueueFile: URL
    let retroactiveRefreshFile: URL

    static func liveOrTemporary() -> (paths: AppPaths, warning: String?) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first

        guard let appSupport else {
            return (temporary(), "Could not access Application Support directory. Using temporary storage.")
        }

        let root = appSupport.appendingPathComponent("com.sowens.StockedMac", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return (live(root: root), nil)
        } catch {
            return (temporary(), "Could not create storage directory: \(error.localizedDescription)")
        }
    }

    static func live(root: URL) -> AppPaths {
        let httpCache = root.appendingPathComponent("HTTPCache", isDirectory: true)
        let imageCache = root.appendingPathComponent("Images", isDirectory: true)
        let discoveryReports = root.appendingPathComponent("DiscoveryReports", isDirectory: true)
        let sourceDiscoveryCache = root.appendingPathComponent("SourceDiscoveryCache", isDirectory: true)
        let miningResultCache = root.appendingPathComponent("MiningResultCache", isDirectory: true)
        let categoryCatalog = root.appendingPathComponent("CategoryCatalog", isDirectory: true)
        let serverInbox = root.appendingPathComponent("ServerInbox", isDirectory: true)
        let serverInboxReceipts = root.appendingPathComponent("ServerInboxReceipts", isDirectory: true)
        let serverStatus = root.appendingPathComponent("ServerStatus", isDirectory: true)

        // Create subdirectories
        for directory in [httpCache, imageCache, discoveryReports, sourceDiscoveryCache, miningResultCache, categoryCatalog, serverInbox, serverInboxReceipts, serverStatus] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return AppPaths(
            root: root,
            // Harvester drafts and the shared Stocked recipe library are different
            // Codable schemas. They previously collided at recipes.json, repeatedly
            // renaming the valid shared library as "corrupt". Keep them permanently
            // separate; MacKitchenStore remains the sole owner of recipes.json.
            recipesFile: root.appendingPathComponent("harvest-recipes.json"),
            settingsFile: root.appendingPathComponent("settings.json"),
            logFile: root.appendingPathComponent("log.json"),
            sourcesFile: root.appendingPathComponent("sources.json"),
            httpCache: httpCache,
            imageCache: imageCache,
            discoveryReports: discoveryReports,
            sourceDiscoveryCache: sourceDiscoveryCache,
            miningResultCache: miningResultCache,
            categoryCatalog: categoryCatalog,
            serverInbox: serverInbox,
            serverInboxReceipts: serverInboxReceipts,
            serverHealthFile: serverStatus.appendingPathComponent("health.json"),
            lastDiscoveryReport: root.appendingPathComponent("last-discovery.json"),
            importQueueFile: root.appendingPathComponent("import-queue.txt"),
            retroactiveRefreshFile: root.appendingPathComponent("retroactive-refresh.txt")
        )
    }

    static func temporary() -> AppPaths {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StockedMac-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        return live(root: temp)
    }

    static func bundledResource(_ name: String) -> URL? {
        let resource = URL(fileURLWithPath: name)
        let ext = resource.pathExtension.nilIfBlank
        let base = ext == nil
            ? resource.lastPathComponent
            : resource.deletingPathExtension().lastPathComponent
        return Bundle.main.url(forResource: base, withExtension: ext)
    }
}

// MARK: - JSON Coding

nonisolated enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
