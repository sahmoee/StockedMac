import Foundation

@main struct RecipeFolderChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stocked-watch-check-" + UUID().uuidString)
        let folder = root.appendingPathComponent("inbox")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        func write(_ name: String, _ text: String) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: url.path)
            return url
        }
        let first = try write("one.json", "first")
        _ = try write("copy.json", "first")
        let outside = root.appendingPathComponent("outside.json")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked.json"), withDestinationURL: outside)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: folder.appendingPathComponent("nested/ignored.json"))
        let initial = try MacRecipeFolderScanner.scan(folder: folder, previous: [:], seen: [], queued: [], now: now)
        precondition(initial.candidates.isEmpty, "New files need two stable observations")
        precondition(initial.observations.count == 2, "Links and subdirectories must not enter observations")
        let stable = try MacRecipeFolderScanner.scan(folder: folder, previous: initial.observations, seen: [], queued: [], now: now.addingTimeInterval(3))
        precondition(stable.candidates.count == 1, "Exact copies are queued only once")
        let item = stable.candidates[0]
        let reviewed = try MacRecipeFolderScanner.reviewedData(item, folder: folder)
        precondition(reviewed == Data("first".utf8))
        let acknowledged = try MacRecipeFolderScanner.scan(folder: folder, previous: stable.observations,
            seen: [item.fingerprint], queued: [], now: now.addingTimeInterval(6))
        precondition(acknowledged.candidates.isEmpty)
        let replaced = folder.appendingPathComponent(item.filename)
        try Data("other".utf8).write(to: replaced, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: replaced.path)
        let replacedWarm = try MacRecipeFolderScanner.scan(folder: folder, previous: acknowledged.observations,
            seen: [item.fingerprint], queued: [], now: now.addingTimeInterval(7))
        let replacement = try MacRecipeFolderScanner.scan(folder: folder, previous: replacedWarm.observations,
            seen: [item.fingerprint], queued: [], now: now.addingTimeInterval(10))
        precondition(replacement.candidates.contains { $0.filename == item.filename && $0.fingerprint != item.fingerprint }, "Same-size preserved-mtime replacements must be detected")
        try Data("changed".utf8).write(to: folder.appendingPathComponent(item.filename))
        do { _ = try MacRecipeFolderScanner.reviewedData(item, folder: folder); preconditionFailure("Changed queued file accepted") }
        catch {}
        var traversal = item
        traversal.filename = "../outside.json"
        do { _ = try MacRecipeFolderScanner.reviewedData(traversal, folder: folder); preconditionFailure("Traversal accepted") }
        catch {}
        var link = item
        link.filename = "linked.json"
        do { _ = try MacRecipeFolderScanner.reviewedData(link, folder: folder); preconditionFailure("Symlink accepted") }
        catch {}
        for index in 0..<30 { _ = try write("batch-\(index).json", "unique-\(index)") }
        let warming = try MacRecipeFolderScanner.scan(folder: folder, previous: [:], seen: [], queued: [], now: now.addingTimeInterval(10))
        let batch = try MacRecipeFolderScanner.scan(folder: folder, previous: warming.observations, seen: [], queued: [], now: now.addingTimeInterval(13))
        precondition(batch.candidates.count <= 12)
        let continuation = try MacRecipeFolderScanner.scan(folder: folder, previous: batch.observations, seen: [], queued: batch.candidates, now: now.addingTimeInterval(16))
        precondition(!continuation.candidates.isEmpty)
        precondition(Set(batch.candidates.map(\.fingerprint)).isDisjoint(with: continuation.candidates.map(\.fingerprint)))
        precondition(FileManager.default.fileExists(atPath: first.path), "Scanning never removes files")
        print("Folder inbox: stable observations, content deduplication, changed-file review, traversal/link rejection and bounded progress passed")
    }
}
