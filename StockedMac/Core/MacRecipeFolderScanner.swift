import Foundation
import CryptoKit
import Darwin

nonisolated struct MacRecipeInboxItem: Identifiable, Codable, Sendable, Equatable {
    var id: String { fingerprint }
    var filename: String
    var fingerprint: String
    var byteCount: Int
    var modifiedAt: Date
    var detectedAt: Date
    var replacesEarlierFile: Bool
    var fileIdentity: String? = nil
}

nonisolated struct MacRecipeFileObservation: Codable, Sendable, Equatable {
    var byteCount: Int
    var modifiedAt: Date
    var firstSeenAt: Date
    var fingerprint: String? = nil
    var fileIdentity: String? = nil
}

nonisolated struct MacRecipeFolderScan: Sendable {
    var observations: [String: MacRecipeFileObservation] = [:]
    var candidates: [MacRecipeInboxItem] = []
    var warning: String?
}

/// Watches file metadata, not recipe content. Files are never moved, deleted, parsed,
/// approved, or published by this scanner. Review rechecks the exact fingerprint.
nonisolated enum MacRecipeFolderScanner {
    static let maximumFileBytes = 32 * 1_024 * 1_024
    static let maximumEntries = 500
    static let maximumHashes = 12
    static let supportedExtensions: Set<String> = ["cook", "json", "jsonld", "zip", "gz", "paprikarecipe", "paprikarecipes"]

    enum ScanError: LocalizedError {
        case unavailable, changed, unsafeFile
        var errorDescription: String? {
            switch self {
            case .unavailable: "The watched folder is unavailable. Choose it again if access has changed."
            case .changed: "This file has changed since it was queued. Scan the folder again to review its latest version."
            case .unsafeFile: "Only regular files directly inside the selected folder can be reviewed. Links and subfolders are skipped."
            }
        }
    }

    static func scan(folder: URL, previous: [String: MacRecipeFileObservation],
                     seen: Set<String>, queued: [MacRecipeInboxItem], now: Date = Date()) throws -> MacRecipeFolderScan {
        let root = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw ScanError.unavailable }
        guard let enumerator = FileManager.default.enumerator(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]) else { throw ScanError.unavailable }
        var result = MacRecipeFolderScan()
        var entries = 0, hashes = 0, hashedBytes = 0
        let queuedByName = Dictionary(queued.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })
        var known = seen.union(queued.map(\.fingerprint))
        while let file = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            entries += 1
            if entries > maximumEntries { result.warning = "This folder contains more than 500 entries. Use a smaller recipe-only folder so every file can be checked."; break }
            guard supportedExtensions.contains(file.pathExtension.lowercased()) else { continue }
            guard let value = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
                  value.isRegularFile == true, value.isSymbolicLink != true,
                  let size = value.fileSize, size > 0, size <= maximumFileBytes,
                  let modified = value.contentModificationDate else { continue }
            let name = file.lastPathComponent
            let old = previous[name]
            let identity = try fileIdentity(file)
            let stable = old?.byteCount == size && old?.modifiedAt == modified && old?.fileIdentity == identity
            let observation = MacRecipeFileObservation(byteCount: size, modifiedAt: modified,
                firstSeenAt: stable ? old?.firstSeenAt ?? now : now, fingerprint: stable ? old?.fingerprint : nil,
                fileIdentity: identity)
            result.observations[name] = observation
            guard stable, now.timeIntervalSince(observation.firstSeenAt) >= 2,
                  now.timeIntervalSince(modified) >= 2 else { continue }
            if let queued = queuedByName[name], queued.byteCount == size && queued.modifiedAt == modified && queued.fileIdentity == identity { continue }
            if let fingerprint = observation.fingerprint, known.contains(fingerprint) { continue }
            guard hashes < maximumHashes, hashedBytes + size <= maximumFileBytes else { continue }
            hashes += 1
            hashedBytes += size
            let data = try readRegularFile(file, in: folder)
            let after = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard after.fileSize == size, after.contentModificationDate == modified, try fileIdentity(file) == identity else { continue }
            let fingerprint = digest(data)
            result.observations[name]?.fingerprint = fingerprint
            guard known.insert(fingerprint).inserted else { continue }
            result.candidates.append(MacRecipeInboxItem(filename: name, fingerprint: fingerprint,
                byteCount: data.count, modifiedAt: modified, detectedAt: now,
                replacesEarlierFile: queuedByName[name] != nil, fileIdentity: identity))
        }
        return result
    }

    static func reviewedData(_ item: MacRecipeInboxItem, folder: URL) throws -> Data {
        let data = try readRegularFile(folder.appendingPathComponent(item.filename), in: folder)
        guard digest(data) == item.fingerprint else { throw ScanError.changed }
        return data
    }

    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func fileIdentity(_ file: URL) throws -> String {
        var value = stat()
        guard lstat(file.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG else { throw ScanError.unsafeFile }
        // Inode and change time catch atomic replacement or preserved-mtime copies.
        return "\(value.st_dev):\(value.st_ino):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }

    private static func readRegularFile(_ file: URL, in folder: URL) throws -> Data {
        guard file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { throw ScanError.unsafeFile }
        let value = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard value.isRegularFile == true, value.isSymbolicLink != true,
              file.resolvingSymlinksInPath().deletingLastPathComponent() == folder.resolvingSymlinksInPath() else { throw ScanError.unsafeFile }
        let directoryFD = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw ScanError.unsafeFile }
        defer { close(directoryFD) }
        let descriptor = openat(directoryFD, file.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ScanError.unsafeFile }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw ScanError.unsafeFile
        }
        let fileHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? fileHandle.close() }
        let data = try fileHandle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumFileBytes else { throw ScanError.unsafeFile }
        return data
    }
}
