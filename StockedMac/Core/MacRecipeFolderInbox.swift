import Foundation
import Observation

nonisolated struct MacRecipeInboxReview: Identifiable, Sendable {
    var id: String { item.id }
    var bookmark: Data
    var item: MacRecipeInboxItem

    func read() throws -> Data {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                             relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        return try MacRecipeFolderScanner.reviewedData(item, folder: folder)
    }
}

/// One app-owned watch service. The durable queue contains names, sizes and hashes;
/// recipe data remains in the user's selected folder until a reviewed import succeeds.
@MainActor @Observable final class MacRecipeFolderInbox {
    private struct State: Codable {
        var bookmark: Data?
        var folderName = ""
        var paused = true
        var queue: [MacRecipeInboxItem] = []
        var seen: [String] = []
    }
    private var state: State
    private let defaults: UserDefaults
    private let preferenceKey = "mac.recipeFolderInbox.v1"
    private var observations: [String: MacRecipeFileObservation] = [:]
    private var configurationRevision = 0
    private var loop: Task<Void, Never>?
    private var activeScan: Task<MacRecipeFolderScan, Error>?
    private(set) var isScanning = false
    private(set) var status = "Choose a folder to collect recipe files for review."
    private(set) var lastScanAt: Date?

    var folderName: String { state.folderName }
    var isConfigured: Bool { state.bookmark != nil }
    var isPaused: Bool { state.paused }
    var queue: [MacRecipeInboxItem] { state.queue }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: "mac.recipeFolderInbox.v1")
            .flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
        state.queue = Array(state.queue.prefix(100))
        state.seen = Array(state.seen.suffix(2_000))
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isPaused { await self.scanNow() }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func choose(_ folder: URL) throws {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw MacRecipeFolderScanner.ScanError.unavailable }
        let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
        activeScan?.cancel()
        configurationRevision += 1
        state = State(bookmark: bookmark, folderName: folder.lastPathComponent, paused: false)
        observations = [:]
        status = "Watching this folder while Stocked is running. New files need two stable checks before review."
        persist()
        Task { await scanNow() }
    }

    func togglePause() {
        state.paused.toggle()
        if state.paused { activeScan?.cancel(); status = "Folder watching is paused. You can still scan manually." }
        else { status = "Folder watching resumed."; Task { await scanNow() } }
        persist()
    }

    func removeFolder() {
        activeScan?.cancel()
        configurationRevision += 1
        state = State()
        observations = [:]
        lastScanAt = nil
        status = "Folder access removed. The original files are unchanged."
        persist()
    }

    func review(_ item: MacRecipeInboxItem) -> MacRecipeInboxReview? {
        guard let bookmark = state.bookmark else { return nil }
        return MacRecipeInboxReview(bookmark: bookmark, item: item)
    }

    func dismiss(_ item: MacRecipeInboxItem) {
        state.queue.removeAll { $0.id == item.id }
        state.seen.removeAll { $0 == item.fingerprint }
        state.seen.append(item.fingerprint)
        state.seen = Array(state.seen.suffix(2_000))
        persist()
    }

    func scanNow() async {
        guard !isScanning, let bookmark = state.bookmark else { return }
        isScanning = true
        defer { isScanning = false; activeScan = nil }
        let revision = configurationRevision
        let previous = observations, seen = Set(state.seen), queued = state.queue
        let task = Task.detached(priority: .utility) {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            return try MacRecipeFolderScanner.scan(folder: folder, previous: previous, seen: seen, queued: queued)
        }
        activeScan = task
        do {
            let result = try await task.value
            guard !task.isCancelled else { return }
            guard revision == configurationRevision else { return }
            observations = result.observations
            for item in result.candidates {
                state.queue.removeAll { $0.filename == item.filename && $0.id != item.id }
                if state.queue.count < 100, !state.queue.contains(where: { $0.id == item.id }) { state.queue.append(item) }
            }
            lastScanAt = Date()
            status = result.warning ?? (state.queue.count >= 100
                ? "The review queue has 100 files. Review or dismiss some to make room."
                : "\(state.queue.count) files waiting for review. Nothing has been imported or published.")
            persist()
        } catch is CancellationError { }
        catch { if revision == configurationRevision { status = error.localizedDescription } }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: preferenceKey) }
    }
}
