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

@MainActor
enum MacHarvestBridge {

    /// Copies drafts into the shared recipe library. Source URLs are the identity for web
    /// recipes, so two genuinely different recipes may share a title; title matching is
    /// only the fallback for personal recipes without a source.
    @discardableResult
    static func add(_ drafts: [RecipeDraft], to store: MacKitchenStore) -> Int {
        var existingSources: [String: UUID] = Dictionary(uniqueKeysWithValues: store.recipes.compactMap { recipe in
            guard let key = recipe.sourceURL.flatMap({ try? URLSafety.validatedRemoteURL($0) })
                .map({ URLSafety.normalized($0).absoluteString }) else { return nil }
            return (key, recipe.id)
        })
        var personalTitles = Set(store.recipes.filter { $0.sourceURL?.nilIfBlank == nil }
            .map { normalizedTitle($0.title) })
        var added = 0
        for draft in drafts {
            let titleKey = normalizedTitle(draft.title)
            guard !titleKey.isEmpty else { continue }
            // A recipe does not cross into either app until its image bytes are usable.
            guard draft.image?.hasLocalFile == true else { continue }
            let source = draft.source.canonicalURL?.nilIfBlank ?? draft.source.url.nilIfBlank
            let sourceKey = source.flatMap { try? URLSafety.validatedRemoteURL($0) }
                .map { URLSafety.normalized($0).absoluteString }
            if let sourceKey {
                if let existingID = existingSources[sourceKey] {
                    let incoming = userRecipe(from: draft)
                    store.updateRecipe(id: existingID) { current in
                        current.title = incoming.title
                        current.description = incoming.description
                        current.cookTime = incoming.cookTime
                        current.prepTime = incoming.prepTime
                        current.servings = incoming.servings
                        current.difficulty = incoming.difficulty
                        current.cuisine = incoming.cuisine
                        current.tags = incoming.tags
                        current.categories = incoming.categories
                        current.ingredients = incoming.ingredients
                        current.instructions = incoming.instructions
                        current.notes = incoming.notes
                        current.sourceURL = incoming.sourceURL
                        current.sourceName = incoming.sourceName
                        current.imageURL = incoming.imageURL
                        current.imageData = incoming.imageData
                    }
                    continue
                }
            } else {
                guard !personalTitles.contains(titleKey) else { continue }
                personalTitles.insert(titleKey)
            }
            store.addRecipe(userRecipe(from: draft))
            if let sourceKey { existingSources[sourceKey] = store.recipes.last?.id }
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

        recipe.cuisine = draft.cuisines.first
            ?? RecipeCuisineClassifier.infer(for: draft)
            ?? ""
        recipe.tags = tags(for: draft)
        recipe.categories = (draft.categories + draft.cuisines + draft.diets).cleanedUnique()
        recipe.ingredients = ingredients(from: draft.ingredientSections)
        recipe.instructions = instructions(from: draft.instructionSections)
        recipe.notes = notes(for: draft)
        recipe.imageURL = draft.image?.originalURL
        recipe.sourceURL = draft.source.canonicalURL?.nilIfBlank ?? draft.source.url.nilIfBlank
        recipe.sourceName = SourceAttribution.displayName(
            host: draft.source.host,
            sourceName: draft.source.attribution,
            author: draft.source.author
        )
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

    /// Preserve original bytes in the Mac library. Household transport may omit an
    /// oversized embedded copy, but local display and validation never accept a URL-only
    /// promise as though it were an image.
    private static func imageData(from image: RecipeImage?) -> Data? {
        guard let path = image?.localPath?.nilIfBlank,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else { return nil }
        return MacRecipeImagePolicy.isUsable(data) ? data : nil
    }
}
