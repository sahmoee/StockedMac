import Foundation
import CryptoKit

/// Byte-compatible with Stocked iOS PortableRecipeSource. Kept in private household
/// records and backups; the public harvest payload deliberately omits original files.
nonisolated struct PortableRecipeSource: Codable, Equatable, Sendable {
    var format: String
    var filename: String
    var originalText: String
    var contentHash: String
    var catalogueSharingApproved: Bool? = nil
    var originalSourceURL: String? = nil

    init(format: String, filename: String, originalText: String) throws {
        guard originalText.utf8.count <= PortableCooklang.maximumBytes,
              let escaped = try? JSONEncoder().encode(originalText), escaped.count <= 60 * 1024 else {
            throw PortableCooklang.ParseError.tooLarge
        }
        self.format = format
        self.filename = String(URL(fileURLWithPath: filename).lastPathComponent.prefix(180))
        self.originalText = originalText
        self.contentHash = SHA256.hash(data: Data(originalText.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Older clients use top-level sourceURL as their catalogue eligibility signal.
/// Keep private provenance inside the additive envelope and neutralize old note repair
/// markers, even when an older editor omits the entire envelope in its newer payload.
nonisolated enum MacPortableRecipePolicy {
    static func allowsCatalogueSharing(_ recipe: UserRecipe) -> Bool {
        recipe.portableSource == nil || recipe.portableSource?.catalogueSharingApproved == true
    }

    static func repaired(_ incoming: UserRecipe, preserving existing: UserRecipe? = nil) -> UserRecipe {
        var recipe = incoming
        if recipe.portableSource == nil { recipe.portableSource = existing?.portableSource }
        guard var source = recipe.portableSource, source.catalogueSharingApproved != true else { return recipe }
        if source.originalSourceURL?.isEmpty != false { source.originalSourceURL = recipe.sourceURL }
        recipe.portableSource = source
        recipe.sourceURL = nil
        recipe.notes = recipe.notes.components(separatedBy: .newlines).map { line in
            line.lowercased().hasPrefix("source:") ? "Original reference:" + line.dropFirst("source:".count) : line
        }.joined(separator: "\n")
        return recipe
    }
}
