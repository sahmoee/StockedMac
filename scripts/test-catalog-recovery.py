#!/usr/bin/env python3
"""Run production catalog persistence/settings fragments with isolated storage.
No app launch, networking, real credentials, or Xcode build is performed.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'StockedMac/Catalog/CatalogModel.swift').read_text()

def method(signature):
    start = source.index(signature)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

models = source[source.index('nonisolated enum CatalogRecordKind'):source.index('nonisolated private extension String')]
load = method('private func load()')
save_now = method('private func saveNow()')
url_body = method('private func fetchUSDA(limit: Int, page: Int) async throws -> [CatalogRecord]')
url_body = url_body[url_body.index('var components'):url_body.index('request.httpMethod')]
harness = r'''
import Foundation
extension String {
    var nilIfBlank: String? { let s = trimmingCharacters(in: .whitespacesAndNewlines); return s.isEmpty ? nil : s }
    var foldedCatalogKey: String { lowercased() }
}
enum UserDefaults { static let standard = Foundation.UserDefaults(suiteName: "catalog-recovery-test-\(UUID())")! }
enum CatalogAPIKeyStore { static func loadMigratingFromDefaults() -> String { "fixture-key" } }
enum MacServiceError: Error { case invalidRequest(String) }
''' + models + r'''
@MainActor final class Fixture {
    var library: [CatalogRecord] = [], queue: [CatalogRecord] = []
    var saveURL: URL
    var usdaAPIKey = "", bulkStatus = "", lastError: String?
    var storageWarning: String?
    var catalogSaveNeedsRetry = false
    var isBulkImportEnabled = false, isBulkImportPaused = false
    var bulkCursor = BulkCursor()
    struct BulkCursor: Codable { var sourceIndex = 0; var seedIndex = 0; var regionIndex = 0; var page = 0 }
    private let snapshotWriter = CatalogSnapshotWriter()
    var selectedSources = Set(CatalogSource.allCases)
    var saveGeneration: UInt = 0
    var pendingSaveTask: Task<Void, Never>?
    var providerOperationInFlight = false
    var requestQueryOverride: String?, requestLocationOverride: String?
    init(_ url: URL) { saveURL = url }
    func rebuildIdentityIndexes() {}
    func persistSmallSettings() {}
''' + load + '\n' + save_now + '\n' + method('private func clearSaveFailure()') + '\n' + method('private func acquireProviderOperation()') + '\n' + method('private func releaseProviderOperation()') + r'''
    func lease() async -> Bool { await acquireProviderOperation() }
    func release() { releaseProviderOperation() }
    func restore() { load() }
    func persist() { _ = saveNow() }
    func requestURL() throws -> URL {
''' + url_body + r'''
        return request.url!
    }
}
@main struct Checks {
    @MainActor static func main() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("catalog.json")
        UserDefaults.standard.set(true, forKey: "catalog.bulk.paused.v1")
        let fresh = Fixture(path); fresh.restore()
        precondition(fresh.usdaAPIKey == "fixture-key" && fresh.isBulkImportPaused && !fresh.isBulkImportEnabled)
        UserDefaults.standard.removeObject(forKey: "catalog.bulk.paused.v1")
        UserDefaults.standard.set(try JSONEncoder().encode([CatalogSource.usda]), forKey: "catalog.selectedSources.v1")
        UserDefaults.standard.set(try JSONEncoder().encode(Fixture.BulkCursor(sourceIndex: -5, seedIndex: -2, regionIndex: -1, page: 99)), forKey: "catalog.bulk.cursor.v1")
        let defaultEnabled = Fixture(path); defaultEnabled.restore()
        precondition(defaultEnabled.isBulkImportEnabled && defaultEnabled.selectedSources == [.usda])
        precondition(defaultEnabled.bulkCursor.sourceIndex == 0 && defaultEnabled.bulkCursor.seedIndex == 0 && defaultEnabled.bulkCursor.regionIndex == 0 && defaultEnabled.bulkCursor.page == 49)
        let corrupt = Data("unreadable-catalog".utf8)
        try corrupt.write(to: path)
        let broken = Fixture(path); broken.restore(); broken.persist()
        precondition(broken.storageWarning != nil && broken.usdaAPIKey == "fixture-key")
        precondition(try Data(contentsOf: path) == corrupt)
        let blocked = Fixture(dir.appendingPathComponent("missing/catalog.json")); blocked.persist()
        precondition(blocked.lastError != nil && blocked.bulkStatus.contains("could not be saved"))
        let writer = CatalogSnapshotWriter()
        let snapshot = CatalogSnapshot(library: [], queue: [])
        do { try writer.write(snapshot, to: blocked.saveURL); preconditionFailure("write error hidden") } catch {}
        try writer.write(snapshot, to: path)
        let newer = CatalogSnapshot(library: [CatalogRecord(kind: .brand, name: "New", source: .stockedReference)], queue: [])
        try writer.write(newer, to: path, generation: 2)
        try writer.write(snapshot, to: path, generation: 1)
        let ordered = try JSONDecoder().decode(CatalogSnapshot.self, from: Data(contentsOf: path))
        precondition(ordered.library.first?.name == "New")
        try writer.write(snapshot, to: path, generation: 3)
        let decoded = try JSONDecoder().decode(CatalogSnapshot.self, from: Data(contentsOf: path))
        precondition(decoded.library.isEmpty && decoded.queue.isEmpty)
        let acquired = await fresh.lease(); precondition(acquired)
        let waiting = Task { await fresh.lease() }
        waiting.cancel()
        let cancelledLease = await waiting.value; precondition(!cancelledLease)
        fresh.requestLocationOverride = "Texas"
        fresh.release(); precondition(fresh.requestLocationOverride == nil)
        let reacquired = await fresh.lease(); precondition(reacquired); fresh.release()
        for key in ["abc&other=value", "abc#fragment", "a b?x", "abc+def"] {
            fresh.usdaAPIKey = key
            let url = try fresh.requestURL()
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(items.count == 1 && items[0].name == "api_key" && items[0].value == key && url.fragment == nil)
        }
        fresh.usdaAPIKey = "  "
        precondition(URLComponents(url: try fresh.requestURL(), resolvingAgainstBaseURL: false)!.queryItems!.first!.value == "DEMO_KEY")
        print("PASS: fresh/default/paused settings, corrupt preservation, synchronous/asynchronous write errors, successful/latest-generation write, cancellation-aware provider lease, USDA delimiter keys/default")
    }
}
'''
harness = harness.replace('precondition(try Data(contentsOf: path) == corrupt)', 'let preserved = try Data(contentsOf: path); precondition(preserved == corrupt)\n        precondition(FileManager.default.fileExists(atPath: broken.saveURL.path))\n        let resumed = Fixture(path); resumed.restore(); precondition(resumed.storageWarning != nil)')
harness = harness.replace('precondition(URLComponents(url: try fresh.requestURL(),', 'let defaultURL = try fresh.requestURL(); precondition(URLComponents(url: defaultURL,')
with tempfile.TemporaryDirectory(prefix='catalog-recovery-') as temp:
    path = Path(temp) / 'Checks.swift'; path.write_text(harness)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path), '-o', str(Path(temp) / 'checks')], check=True)
    subprocess.run([str(Path(temp) / 'checks')], check=True)
