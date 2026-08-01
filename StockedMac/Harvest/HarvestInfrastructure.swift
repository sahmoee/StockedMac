// HarvestInfrastructure.swift — Infrastructure types for the Harvester

import Foundation

// MARK: - HTTP Client

actor HTTPClient {
    private let session: URLSession
    private let cacheDirectory: URL
    private var userAgent: String
    
    init(cacheDirectory: URL, userAgent: String) {
        self.cacheDirectory = cacheDirectory
        self.userAgent = userAgent
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.requestCachePolicy = .returnCacheDataElseLoad
        
        self.session = URLSession(configuration: config)
        
        // Create cache directory
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var modifiedRequest = request
        modifiedRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
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
    
    func waitIfNeeded(for domain: String) async {
        // Check if paused
        if let pausedUntil = pausedUntil[domain], pausedUntil > Date() {
            let delay = pausedUntil.timeIntervalSinceNow
            try? await Task.sleep(for: .seconds(delay))
        }
        
        // Apply minimum delay between requests
        if let last = lastRequest[domain] {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 2.0 {
                try? await Task.sleep(for: .seconds(2.0 - elapsed))
            }
        }
        
        lastRequest[domain] = Date()
        requestCounts[domain, default: 0] += 1
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
        
        // Create subdirectories
        for directory in [httpCache, imageCache, discoveryReports] {
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
        Bundle.main.url(forResource: name.replacingOccurrences(of: ".json", with: ""), withExtension: "json")
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
