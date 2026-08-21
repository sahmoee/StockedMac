// HarvestCloudSync.swift — pushes approved harvest recipes to the Stocked Worker cache.
//
// The old plan was "store recipes and images on the cPanel host". The Worker abandoned
// that origin (see worker/src/apps/stocked/src/content.js — cPanel is retired; content is
// served from KV / the site repo, edge-cached). So the Mac pushes to the Worker instead:
//
//   POST /harvest/cache   { schemaVersion: 1, recipes: [ … ] }     (chunks of 20)
//   POST /harvest/image   { id, imageBase64, mediaType }           (one per image)
//   POST /harvest/delete  { schemaVersion: 1, ids: [ … ] }         (chunks of 20)
//
// and every device reads back:
//
//   GET  /harvest/recipes            — the cached recipe JSON, edge-cached
//   GET  /harvest/img/<id>.jpg       — the cached image, 30-day edge cache
//
// Same endpoint, same `X-Stocked-Key` header as every other Worker call, so the iOS app
// needs no new credentials — only the two GET routes, which it can adopt whenever it is
// ready. Only recipes whose image bytes are on disk are pushed; the Worker cache carries
// the same guarantee the kitchen does: nothing without a picture.

import Foundation
import ImageIO

@MainActor
enum HarvestCloudSync {

    struct PushResult: Sendable {
        var recipes: Int
        var images: Int
    }

    /// Recipes per POST. The Worker caps bodies at 2 MB; twenty text-only recipes stay
    /// comfortably under it, and images travel separately.
    private static let chunkSize = 20
    /// Image budget per upload. Below the household-sync ceiling on purpose: this cache
    /// serves lists, not wallpaper.
    private static let maxImageBytes = 350_000

    static func push(_ drafts: [RecipeDraft]) async throws -> PushResult {
        guard let base = URL(string: MacBuildConfig.receiptWorkerURL) else {
            throw MacServiceError.notConfigured("The Stocked Worker URL")
        }
        let drafts = drafts.filter { $0.image?.hasLocalFile == true }
        var pushedRecipes = 0
        var pushedImages = 0

        // Recipes, in chunks.
        var index = 0
        while index < drafts.count {
            let chunk = Array(drafts[index..<min(index + chunkSize, drafts.count)])
            index += chunkSize
            let body: [String: Any] = [
                "schemaVersion": 1,
                "clientVersion": "mac-\(MacBuildConfig.version)",
                "recipes": chunk.map(payload(for:)),
            ]
            try await post(body, to: base.appendingPathComponent("harvest/cache"))
            pushedRecipes += chunk.count
        }

        // Images, one at a time, smallest risk of tripping the body cap.
        for draft in drafts {
            guard let path = draft.image?.localPath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  !data.isEmpty else { continue }
            let jpeg = data.count <= maxImageBytes
                ? data
                : downsampledJPEG(data, toAtMost: maxImageBytes)
            guard let jpeg else { continue }
            let body: [String: Any] = [
                "schemaVersion": 1,
                "id": draft.id.uuidString,
                "mediaType": "image/jpeg",
                "imageBase64": jpeg.base64EncodedString(),
            ]
            do {
                try await post(body, to: base.appendingPathComponent("harvest/image"))
                pushedImages += 1
            } catch {
                // One stubborn image must not sink the whole run; the recipe keeps its
                // original imageURL and the Worker's image proxy can fill in later.
                continue
            }
        }

        return PushResult(recipes: pushedRecipes, images: pushedImages)
    }

    /// Backfills the Mac kitchen's complete recipe collection. This is intentionally
    /// separate from `RecipeDraft`: the Recipes sidebar is backed by `UserRecipe`, and
    /// using only the Harvester review library left existing kitchen recipes unpublished.
    static func pushKitchenRecipes(_ recipes: [UserRecipe]) async throws -> PushResult {
        guard let base = URL(string: MacBuildConfig.receiptWorkerURL) else {
            throw MacServiceError.notConfigured("The Stocked Worker URL")
        }
        let recipes = recipes.filter(MacRecipeImagePolicy.hasRequiredImage)
        var pushedRecipes = 0
        var pushedImages = 0

        var index = 0
        while index < recipes.count {
            let chunk = Array(recipes[index..<min(index + chunkSize, recipes.count)])
            index += chunkSize
            let body: [String: Any] = [
                "schemaVersion": 1,
                "clientVersion": "mac-\(MacBuildConfig.version)",
                "recipes": chunk.map(kitchenPayload(for:)),
            ]
            try await post(body, to: base.appendingPathComponent("harvest/cache"))
            pushedRecipes += chunk.count
        }

        for recipe in recipes {
            // Imported recipes retain their original full-quality URL. Re-encoding and
            // uploading hundreds of those images on launch was both redundant and the
            // largest source of StockedMac's memory spike. Only personal/local-only
            // images need a Worker-hosted copy.
            guard recipe.imageURL?.nilIfBlank == nil,
                  let data = recipe.imageData, !data.isEmpty else { continue }
            let jpeg = autoreleasepool {
                data.count <= maxImageBytes ? data : downsampledJPEG(data, toAtMost: maxImageBytes)
            }
            guard let jpeg else { continue }
            do {
                try await post([
                    "schemaVersion": 1,
                    "id": recipe.id.uuidString,
                    "mediaType": "image/jpeg",
                    "imageBase64": jpeg.base64EncodedString(),
                ], to: base.appendingPathComponent("harvest/image"))
                pushedImages += 1
            } catch {
                continue
            }
        }
        return PushResult(recipes: pushedRecipes, images: pushedImages)
    }

    static func delete(recipeIDs: Set<UUID>) async throws {
        guard let base = URL(string: MacBuildConfig.receiptWorkerURL) else {
            throw MacServiceError.notConfigured("The Stocked Worker URL")
        }
        let ids = recipeIDs.map(\.uuidString).sorted()
        var index = 0
        while index < ids.count {
            let chunk = Array(ids[index..<min(index + chunkSize, ids.count)])
            index += chunkSize
            try await post([
                "schemaVersion": 1,
                "ids": chunk,
            ], to: base.appendingPathComponent("harvest/delete"))
        }
    }

    // MARK: - Transport

    private static func post(_ body: [String: Any], to url: URL) async throws {
        guard JSONSerialization.isValidJSONObject(body) else {
            throw MacServiceError.invalidRequest("The upload contains unsupported values.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        MacBuildConfig.authorizeWorkerRequest(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MacServiceError.malformedResponse("The Worker returned no HTTP response.")
        }
        if http.statusCode == 429 {
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw MacServiceError.rateLimited(retryAfter: retry)
        }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw MacServiceError.httpStatus(http.statusCode, object?["error"] as? String)
        }
    }

    // MARK: - Payload

    /// Built from the draft directly (not through MacHarvestBridge) so the cache schema
    /// is explicit here and cannot drift silently when the bridge's kitchen conversion
    /// changes. Field names follow the curated content feed the iOS app already parses.
    private static func payload(for draft: RecipeDraft) -> [String: Any] {
        let times = draft.times.normalized()
        var tags: [String] = []
        var seen = Set<String>()
        for value in draft.categories + draft.diets + draft.keywords {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { continue }
            tags.append(clean)
            if tags.count == 12 { break }
        }

        var dict: [String: Any] = [
            "id": draft.id.uuidString,
            "title": draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            "description": draft.summary ?? "",
            "cuisine": draft.cuisines.first ?? "",
            "tags": tags,
            "categories": (draft.categories + draft.cuisines + draft.diets).cleanedUnique(),
            "ingredients": draft.ingredientSections.flatMap(\.items).map { item -> [String: Any] in
                let quantity = item.quantityText?.nilIfBlank
                    ?? item.quantity.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }
                let amount = [quantity, item.unit].compactMap(\.self).joined(separator: " ")
                return ["name": item.name?.nilIfBlank ?? item.raw, "amount": amount]
            },
            "instructions": draft.instructionSections.flatMap(\.steps).filter { !$0.isEmpty },
            "sourceURL": draft.source.canonicalURL?.nilIfBlank ?? draft.source.url,
            "importedBy": "recipe-manager",
            "importedAt": ISO8601DateFormatter().string(from: draft.updatedAt),
            "attribution": SourceAttribution.displayName(
                host: draft.source.host,
                sourceName: draft.source.attribution,
                author: draft.source.author
            ),
            "confidence": draft.confidence,
        ]
        if draft.image?.hasLocalFile == true { dict["image"] = "/harvest/img/\(draft.id.uuidString).jpg" }
        if let url = draft.image?.originalURL.nilIfBlank { dict["imageURL"] = url }
        if let servings = draft.servings, servings > 0 { dict["servings"] = max(1, Int(servings.rounded())) }
        if let prep = times.prepMinutes { dict["prepTime"] = minutesLabel(prep) }
        if let cook = times.cookMinutes {
            dict["cookTime"] = minutesLabel(cook)
        } else if let total = times.totalMinutes {
            dict["cookTime"] = minutesLabel(total)
        }
        return dict
    }

    private static func kitchenPayload(for recipe: UserRecipe) -> [String: Any] {
        let source = recipe.sourceName?.nilIfBlank
            ?? sourceMetadata(from: recipe.notes).name
            ?? URL(string: recipe.sourceURL ?? "")?.host
            ?? "Personal recipe"
        let sourceURL = recipe.sourceURL?.nilIfBlank ?? sourceMetadata(from: recipe.notes).url
        let categories = (recipe.categories ?? recipe.tags).cleanedUnique()
        var dict: [String: Any] = [
            "id": recipe.id.uuidString,
            "title": recipe.title,
            "description": recipe.description,
            "cuisine": recipe.cuisine,
            "tags": Array((recipe.tags + categories).cleanedUnique().prefix(12)),
            "categories": categories,
            "ingredients": recipe.ingredients.map { ["name": $0.name, "amount": $0.amount] },
            "instructions": recipe.instructions,
            "importedBy": "recipe-manager",
            "importedAt": ISO8601DateFormatter().string(from: recipe.dateCreated),
            "attribution": source,
            "servings": max(1, recipe.servings),
            "prepTime": recipe.prepTime,
            "cookTime": recipe.cookTime,
        ]
        if let sourceURL { dict["sourceURL"] = sourceURL }
        if let imageURL = recipe.imageURL?.nilIfBlank {
            dict["imageURL"] = imageURL
        } else if recipe.imageData != nil {
            dict["image"] = "/harvest/img/\(recipe.id.uuidString).jpg"
        }
        return dict
    }

    private static func sourceMetadata(from notes: String) -> (name: String?, url: String?) {
        guard let line = notes.components(separatedBy: .newlines)
            .first(where: { $0.lowercased().hasPrefix("source:") }) else { return (nil, nil) }
        let value = line.dropFirst("Source:".count).trimmingCharacters(in: .whitespaces)
        let parts = value.components(separatedBy: " — ")
        if parts.count > 1 { return (parts[0].nilIfBlank, parts.dropFirst().joined(separator: " — ").nilIfBlank) }
        if value.hasPrefix("http") { return (URL(string: value)?.host, value) }
        return (value.nilIfBlank, nil)
    }

    private static func minutesLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    // MARK: - Image downsampling

    /// Same approach as MacHarvestBridge.downsampled, tuned to this cache's budget.
    private static func downsampledJPEG(_ data: Data, toAtMost limit: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        for edge in [1000, 800, 600, 450] as [Int] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: edge,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else { continue }
            for quality in [0.7, 0.55, 0.4] as [Double] {
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
