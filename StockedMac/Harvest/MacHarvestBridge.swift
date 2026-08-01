// MacHarvestBridge.swift — the seam between the Harvester and the kitchen.
//
// The Harvester keeps its own library of RecipeDrafts: raw imports with per-section
// ingredients, confidence scores and review state. The kitchen keeps UserRecipes: the
// household-synced records the phone sees. This file is the one place a draft becomes a
// recipe, so the two models can evolve without either learning the other's internals.
//
// Adding here goes straight into MacKitchenStore.addRecipe, which stamps updatedAt and
// lastWriterID — so a harvested recipe syncs to the household exactly like one typed in
// by hand. No `.stockedrecipe` file round-trip is required any more; export remains for
// sharing packages with other devices out-of-band.

import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum MacHarvestBridge {

    /// Copies drafts into the kitchen's recipe library. Skips a draft when a recipe with
    /// the same title (case-insensitive) already exists, so pressing the button twice
    /// cannot fill the library with duplicates. Returns how many were actually added.
    @discardableResult
    static func add(_ drafts: [RecipeDraft], to store: MacKitchenStore) -> Int {
        var existing = Set(store.recipes.map { normalizedTitle($0.title) })
        var added = 0
        for draft in drafts {
            let key = normalizedTitle(draft.title)
            guard !key.isEmpty, !existing.contains(key) else { continue }
            // Skip recipes without an image — the iOS app shows a blank placeholder
            // for imageless recipes and they look out of place in the library.
            guard draft.image != nil else { continue }
            store.addRecipe(userRecipe(from: draft))
            existing.insert(key)
            added += 1
        }
        return added
    }

    /// One sentence for the status line: what happened, and why the number may be lower
    /// than what was asked for.
    static func summary(added: Int, of requested: Int) -> String {
        if added == requested {
            return added == 1
                ? "Added 1 recipe to Stocked."
                : "Added \(added) recipes to Stocked."
        }
        // Approving now hands recipes over on its own, so the usual answer to this button
        // is "they are already there". That should read as reassurance, not as a failure.
        if added == 0 {
            return requested == 1
                ? "Already in Stocked."
                : "All \(requested) are already in Stocked."
        }
        return "Added \(added) of \(requested) — the rest were already in Stocked."
    }

    // MARK: - Conversion

    static func userRecipe(from draft: RecipeDraft) -> UserRecipe {
        var recipe = UserRecipe(title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines))
        recipe.description = draft.summary ?? ""

        let times = draft.times.normalized()
        if let prep = times.prepMinutes { recipe.prepTime = minutesLabel(prep) }
        if let cook = times.cookMinutes {
            recipe.cookTime = minutesLabel(cook)
        } else if let total = times.totalMinutes {
            recipe.cookTime = minutesLabel(total)
        }
        if let servings = draft.servings, servings > 0 {
            recipe.servings = max(1, Int(servings.rounded()))
        }

        recipe.cuisine = draft.cuisines.first ?? ""
        recipe.tags = tags(for: draft)
        recipe.ingredients = ingredients(from: draft.ingredientSections)
        recipe.instructions = instructions(from: draft.instructionSections)
        recipe.notes = notes(for: draft)
        recipe.imageURL = draft.image?.originalURL
        recipe.imageData = imageData(from: draft.image)
        return recipe
    }

    private static func minutesLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    private static func tags(for draft: RecipeDraft) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in draft.categories + draft.diets + draft.keywords {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            guard !clean.isEmpty, seen.insert(key).inserted else { continue }
            out.append(clean)
            if out.count == 12 { break }   // a recipe card, not a keyword dump
        }
        return out
    }

    private static func ingredients(from sections: [IngredientSection]) -> [RecipeIngredient] {
        sections.flatMap { section in
            section.items.map { item in
                var ingredient = RecipeIngredient(
                    name: item.name?.nilIfBlank ?? item.raw,
                    amount: amountLabel(for: item)
                )
                ingredient.quantity = item.quantity
                ingredient.unit = item.unit
                ingredient.prep = item.preparation
                ingredient.notes = item.notes
                return ingredient
            }
        }
    }

    private static func amountLabel(for item: IngredientItem) -> String {
        let quantity = item.quantityText?.nilIfBlank
            ?? item.quantity.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
        return [quantity, item.unit].compactMap(\.self).joined(separator: " ")
    }

    private static func instructions(from sections: [InstructionSection]) -> [String] {
        var steps: [String] = []
        let named = sections.filter { $0.name?.nilIfBlank != nil }.count > 0
        for section in sections {
            if named, let name = section.name?.nilIfBlank {
                steps.append("\(name):")
            }
            steps.append(contentsOf: section.steps.filter { !$0.isEmpty })
        }
        return steps
    }

    private static func notes(for draft: RecipeDraft) -> String {
        var lines: [String] = []
        // Build 93: the attribution the kitchen (and therefore the phone) shows is
        // decided by SourceAttribution — the site's real name, else the author, else
        // the plain host. "Sowens", "Stocked Companion", "custom-…" and other internal
        // handles never qualify, and the URL always travels alongside the name.
        let attribution = SourceAttribution.displayName(
            host: draft.source.host,
            sourceName: draft.source.attribution,
            author: draft.source.author
        )
        if let url = draft.source.url.nilIfBlank {
            lines.append("Source: \(attribution) \u{2014} \(url)")
        } else {
            lines.append("Source: \(attribution)")
        }
        if let note = draft.discoveryNote?.nilIfBlank { lines.append(note) }
        if let yield = draft.yield?.nilIfBlank { lines.append("Yield: \(yield)") }
        return lines.joined(separator: "\n")
    }

    /// Only a modest image travels with the recipe — imageData is synced to the whole
    /// household, and a 6 MB hero photo per recipe would make every pull pay for it.
    ///
    /// Previously anything over 2 MB was simply dropped, which meant nothing: household
    /// sync strips anything over `MacHouseholdSync.maxSyncedImageBytes` anyway, and a
    /// typical recipe hero JPEG is 250 KB–1.5 MB. So every harvested photo was admitted
    /// here and then silently destroyed one step later, and the phone got a recipe with
    /// no picture. Now the image is downsampled to fit the sync budget instead.
    private static func imageData(from image: RecipeImage?) -> Data? {
        guard let path = image?.localPath?.nilIfBlank,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else { return nil }
        if data.count <= MacHouseholdSync.maxSyncedImageBytes { return data }
        return downsampled(data, toAtMost: MacHouseholdSync.maxSyncedImageBytes)
    }

    /// Re-encodes to a JPEG small enough to sync. Tries progressively smaller edges and
    /// qualities; returns nil rather than a still-oversize blob, so the caller keeps the
    /// `imageURL` and the phone falls back to loading it from the web.
    private static func downsampled(_ data: Data, toAtMost limit: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        for edge in [1200, 900, 700, 500] as [Int] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: edge
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else { continue }

            for quality in [0.75, 0.6, 0.45] as [Double] {
                let out = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    out, "public.jpeg" as CFString, 1, nil
                ) else { return nil }
                CGImageDestinationAddImage(
                    destination,
                    cgImage,
                    [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
                )
                guard CGImageDestinationFinalize(destination) else { return nil }
                if out.length > 0, out.length <= limit { return out as Data }
            }
        }
        return nil
    }
}
