// HarvestInfrastructure.swift — Infrastructure types for the Harvester

import Foundation

// MARK: - Pause Gate (Build 91)

/// One switch that pauses every network request the Harvester makes — discovery,
/// page fetches and image downloads all funnel through `HTTPClient`, which waits
/// here before each request. Pausing therefore stops new work immediately without
/// cancelling anything: Resume picks up exactly where the run left off.
actor PauseGate {
    private(set) var isPaused = false

    func pause()  { isPaused = true }
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
        return try await session.data(for: modifiedRequest)
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

actor RobotsPolicy {
    private let userAgent: String
    private var cache: [String: Bool] = [:]
    
    init(userAgent: String) {
        self.userAgent = userAgent
    }
    
    func isAllowed(_ url: URL) async -> Bool {
        guard let host = url.host else { return false }
        
        let key = "\(host)\(url.path)"
        if let cached = cache[key] {
            return cached
        }
        
        // For now, allow everything - a real implementation would fetch
        // and parse robots.txt
        let allowed = true
        cache[key] = allowed
        return allowed
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
    let lastDiscoveryReport: URL
    
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

        // Create subdirectories
        for directory in [httpCache, imageCache, discoveryReports, sourceDiscoveryCache, miningResultCache, categoryCatalog] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return AppPaths(
            root: root,
            recipesFile: root.appendingPathComponent("recipes.json"),
            settingsFile: root.appendingPathComponent("settings.json"),
            logFile: root.appendingPathComponent("log.json"),
            sourcesFile: root.appendingPathComponent("sources.json"),
            httpCache: httpCache,
            imageCache: imageCache,
            discoveryReports: discoveryReports,
            sourceDiscoveryCache: sourceDiscoveryCache,
            miningResultCache: miningResultCache,
            categoryCatalog: categoryCatalog,
            lastDiscoveryReport: root.appendingPathComponent("last-discovery.json")
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
