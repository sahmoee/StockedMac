// MacRecipeSourceBlocklist.swift — the Mac's copy of the retired-source rules.
//
// The twin of `RecipeSourceBlocklist.swift` on iOS. Two sources are retired: the bundled
// Kaggle food dataset and the "Sowens" curated feed. The Mac never ingested either
// directly — it has no bundled seed and no Discover feed — but it holds the same recipes,
// because household sync copies the phone's library onto it. So it needs the same sweep,
// or a Mac joined to the household becomes the place they survive and the source they
// push back from at the next pull.
//
// This is a deliberate copy rather than a shared file: the two apps are separate Xcode
// projects with separate model isolation rules. **Change one, change both** — the two
// blocklists must agree, or one app removes a recipe and the other pushes it back.
//
// THE THING NOT TO REFACTOR: the sweep goes through `MacKitchenStore.deleteRecipe(ids:)`
// and `deleteSavedRecipes(ids:)`, never `store.recipes` / `store.savedRecipes` directly.
// The Mac has no `didSet` observers — `@Observable` rewrites stored properties into
// accessors, which property observers cannot coexist with — so the household tombstone
// bookkeeping lives inside those two methods. Filtering the arrays in place would remove
// the recipes locally and leave no tombstone, and the very next household pull would put
// every one of them back.

import Foundation
import os

nonisolated enum MacRecipeSourceBlocklist {

    /// Matched as a substring of a lowercased source name or image URL.
    static let blockedSourceFragments: [String] = ["kaggle", "sowens"]

    /// Matched as a substring of a lowercased URL.
    static let blockedURLFragments: [String] = ["kaggle.com", "kaggle.io"]

    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isBlocked(sourceName: String, sourceURL: String = "", tags: [String] = []) -> Bool {
        let name = norm(sourceName)
        if !name.isEmpty, blockedSourceFragments.contains(where: { name.contains($0) }) { return true }

        let url = norm(sourceURL)
        if !url.isEmpty, blockedURLFragments.contains(where: { url.contains($0) }) { return true }

        // Whole-tag equality, not substring. A recipe browsed on the phone and saved
        // carries its source name as a tag, which is the only provenance that survives
        // into `UserRecipe` — but tags are user-visible free text, so "kaggle-style"
        // should not condemn a recipe somebody typed by hand.
        if tags.contains(where: { blockedSourceFragments.contains(norm($0)) }) { return true }
        return false
    }

    static func isBlocked(_ recipe: UserRecipe) -> Bool {
        isBlocked(sourceName: "", sourceURL: recipe.imageURL ?? "", tags: recipe.tags)
    }

    static func isBlocked(_ recipe: GeneratedRecipe) -> Bool {
        isBlocked(sourceName: "", sourceURL: recipe.imageURL ?? "",
                  tags: recipe.mealCategory.isEmpty ? [] : [recipe.mealCategory])
    }
}

// MARK: - The sweep

nonisolated struct MacRecipePurgeReport: Sendable {
    var recipes = 0
    var saved   = 0

    var total: Int { recipes + saved }
    var isEmpty: Bool { total == 0 }

    var summary: String {
        guard !isEmpty else { return "Nothing to remove." }
        var parts: [String] = []
        if recipes > 0 { parts.append("\(recipes) recipe\(recipes == 1 ? "" : "s")") }
        if saved > 0   { parts.append("\(saved) saved recipe\(saved == 1 ? "" : "s")") }
        return parts.joined(separator: " and ") + " removed."
    }
}

@MainActor
enum MacRecipePurge {

    private static let logger = Logger(subsystem: "com.sowens.StockedMac", category: "recipe-purge")

    /// Sweeps both recipe collections. Called at launch, after the store has loaded and
    /// after the household pull, so anything that came down in that pull is caught in the
    /// same pass rather than a launch later.
    @discardableResult
    static func run(store: MacKitchenStore) -> MacRecipePurgeReport {
        var report = MacRecipePurgeReport()

        let doomedRecipes = Set(store.recipes.filter { MacRecipeSourceBlocklist.isBlocked($0) }
                                             .map(\.id))
        if !doomedRecipes.isEmpty {
            report.recipes = doomedRecipes.count
            store.deleteRecipe(ids: doomedRecipes)   // records the tombstones
        }

        let doomedSaved = Set(store.savedRecipes.filter { MacRecipeSourceBlocklist.isBlocked($0) }
                                                .map(\.id))
        if !doomedSaved.isEmpty {
            report.saved = doomedSaved.count
            store.deleteSavedRecipes(ids: doomedSaved)
        }

        if !report.isEmpty {
            logger.notice("Retired recipe sources: \(report.summary, privacy: .public)")
        }
        return report
    }
}
