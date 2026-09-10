import Foundation

@main struct PortableModelChecks {
    static func main() throws {
        var recipe = UserRecipe(title: "Compatibility fixture")
        let raw = "---\ntitle: Compatibility fixture\ncustom: keep this\n---\nCook @rice{1%cup}.\n"
        recipe.portableSource = try PortableRecipeSource(format: "cook", filename: "../fixture.cook", originalText: raw)
        recipe.author = "Example author"
        recipe.license = "https://example.org/license"
        recipe.imageAttribution = "Example photographer"
        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(UserRecipe.self, from: data)
        precondition(decoded.portableSource?.originalText == raw)
        precondition(decoded.portableSource?.filename == "fixture.cook")
        precondition(decoded.portableSource?.contentHash.count == 64)
        precondition(decoded.author == recipe.author && decoded.license == recipe.license && decoded.imageAttribution == recipe.imageAttribution)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["portableSource", "author", "license", "imageAttribution"] { legacy.removeValue(forKey: key) }
        let old = try JSONDecoder().decode(UserRecipe.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(old.title == recipe.title && old.portableSource == nil)
        precondition(old.author == nil && old.license == nil && old.imageAttribution == nil)
        recipe.sourceURL = "https://example.org/recipe"
        recipe.notes = "Source: https://example.org/recipe\nPrivate family note"
        precondition(!MacPortableRecipePolicy.allowsCatalogueSharing(recipe))
        let privateRecipe = MacPortableRecipePolicy.repaired(recipe)
        precondition(privateRecipe.sourceURL == nil)
        precondition(privateRecipe.portableSource?.originalSourceURL == "https://example.org/recipe")
        precondition(privateRecipe.notes.hasPrefix("Original reference:"))
        precondition(privateRecipe.notes.contains("Private family note"))
        var legacyEdit = recipe
        legacyEdit.portableSource = nil
        legacyEdit.title = "An edit from an older client"
        let retained = MacPortableRecipePolicy.repaired(legacyEdit, preserving: privateRecipe)
        precondition(retained.title == legacyEdit.title && retained.sourceURL == nil)
        precondition(retained.portableSource?.originalText == raw)
        precondition(!MacPortableRecipePolicy.allowsCatalogueSharing(retained))
        var approved = privateRecipe
        approved.portableSource?.catalogueSharingApproved = true
        approved.sourceURL = approved.portableSource?.originalSourceURL
        precondition(MacPortableRecipePolicy.allowsCatalogueSharing(approved))
        precondition(MacPortableRecipePolicy.repaired(approved).sourceURL == "https://example.org/recipe")
        approved.portableSource?.catalogueSharingApproved = false
        precondition(!MacPortableRecipePolicy.allowsCatalogueSharing(approved))
        precondition(MacPortableRecipePolicy.repaired(approved).sourceURL == nil)
        precondition(MacPortableRecipePolicy.allowsCatalogueSharing(old))
        do {
            _ = try PortableRecipeSource(format: "cook", filename: "big.cook", originalText: String(repeating: "x", count: PortableCooklang.maximumBytes + 1))
            preconditionFailure("Oversized original accepted")
        } catch {}
        do {
            _ = try PortableRecipeSource(format: "cook", filename: "escaped.cook", originalText: String(repeating: "\t", count: PortableCooklang.maximumBytes))
            preconditionFailure("Oversized escaped original accepted")
        } catch {}
        print("Portable recipe model: original text, sanitized filename, stable hash, credits, legacy decoding and size guards passed")
    }
}
