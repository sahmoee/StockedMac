import Foundation
import Observation

/// Reads the same public recipe records used by iOS, without a household gate.
@MainActor @Observable
final class MacPublicRecipeSync {
    static let shared = MacPublicRecipeSync()
    private(set) var isSyncing = false
    private(set) var status = "Shared catalogue not yet refreshed"
    private(set) var lastCompleteCount: Int?
    @ObservationIgnored private var loop: Task<Void, Never>?

    func start(store: MacKitchenStore) {
        guard loop == nil else { return }
        loop = Task { [weak self, weak store] in
            while !Task.isCancelled {
                guard let self, let store else { return }
                await self.refresh(store: store)
                do { try await Task.sleep(for: .seconds(900)) } catch { return }
            }
        }
    }

    func refresh(store: MacKitchenStore) async {
        guard !isSyncing else { return }
        guard MacWorkerClient.isConfigured else {
            status = "Configure the Worker to load the shared catalogue"
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        var cursor: String?
        var seenCursors = Set<String>()
        var identities = Set<String>()
        do {
            repeat {
                try Task.checkCancellation()
                var query = ["pageSize": "100"]
                if let cursor { query["cursor"] = cursor }
                let data = try await MacWorkerClient.getData(path: "harvest/recipes", query: query, timeout: 45)
                let base = MacBuildConfig.receiptWorkerURL
                let page = try await Task.detached(priority: .utility) {
                    try MacPublicRecipePage.decode(data, baseURL: base)
                }.value
                // Merge text/URLs only. Artwork is fetched by visible rows, never by a
                // whole-library image download that delays browsing or spikes memory.
                store.mergePublicRecipes(page.recipes)
                for recipe in page.recipes { identities.insert(MacPublicRecipePage.identity(recipe)) }
                status = "Loading shared catalogue · \(identities.count) recipes"
                guard let complete = page.complete else {
                    status = "Loaded legacy catalogue; server update needed for all recipes"
                    return
                }
                if complete {
                    lastCompleteCount = identities.count
                    status = "\(identities.count) shared recipes · catalogue up to date"
                    return
                }
                guard let next = page.nextCursor, !next.isEmpty, seenCursors.insert(next).inserted else {
                    throw MacServiceError.malformedResponse("Catalogue pagination did not advance")
                }
                cursor = next
                await Task.yield()
            } while !Task.isCancelled
        } catch {
            status = "Catalogue refresh incomplete · \(error.localizedDescription)"
        }
    }
}

nonisolated struct MacPublicRecipePage: Sendable {
    var recipes: [UserRecipe]
    var complete: Bool?
    var nextCursor: String?

    static func identity(_ recipe: UserRecipe) -> String {
        guard let raw = recipe.sourceURL, var url = URLComponents(string: raw) else { return recipe.id.uuidString }
        url.fragment = nil
        url.queryItems = url.queryItems?.filter {
            !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid", "ref"].contains($0.name.lowercased())
        }
        if url.queryItems?.isEmpty == true { url.queryItems = nil }
        return (url.string ?? raw).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    static func decode(_ data: Data, baseURL: String) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["recipes"] as? [[String: Any]] else {
            throw MacServiceError.malformedResponse("Missing catalogue recipes")
        }
        let formatter = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? {
            guard let text = value as? String else { return nil }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: text) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: text)
        }
        let recipes = rows.compactMap { row -> UserRecipe? in
            guard let rawID = row["id"] as? String, !rawID.isEmpty,
                  let title = row["title"] as? String, !title.isEmpty,
                  let source = row["sourceURL"] as? String,
                  let sourceURL = URL(string: source), sourceURL.scheme?.lowercased() == "https", sourceURL.host != nil,
                  let steps = row["instructions"] as? [String], !steps.isEmpty else { return nil }
            let rawImage = (row["imageURL"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? row["image"] as? String ?? ""
            guard !rawImage.isEmpty,
                  let image = URL(string: rawImage, relativeTo: URL(string: baseURL))?.absoluteURL,
                  image.scheme?.lowercased() == "https", image.host != nil else { return nil }
            var recipe = UserRecipe(title: title)
            if let uuid = UUID(uuidString: rawID) { recipe.id = uuid }
            else {
                // Match iOS HarvestWireRecipe's stable UUID for historical non-UUID ids.
                func hash(_ input: String) -> UInt64 {
                    input.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
                }
                let bytes = [hash(rawID), hash("harvest-salt::" + rawID)].flatMap { value in
                    (0..<8).map { UInt8((value >> (8 * UInt64(7 - $0))) & 0xff) }
                }
                recipe.id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
            }
            recipe.description = row["description"] as? String ?? ""
            recipe.instructions = steps
            recipe.ingredients = (row["ingredients"] as? [[String: Any]] ?? []).compactMap {
                guard let name = $0["name"] as? String, !name.isEmpty else { return nil }
                return RecipeIngredient(name: name, amount: $0["amount"] as? String ?? "")
            }
            recipe.imageURL = image.absoluteString
            recipe.sourceURL = source
            recipe.sourceName = row["attribution"] as? String ?? sourceURL.host
            recipe.tags = row["tags"] as? [String] ?? []
            recipe.categories = row["categories"] as? [String]
            recipe.cuisine = row["cuisine"] as? String ?? ""
            recipe.servings = max(1, row["servings"] as? Int ?? 4)
            recipe.prepTime = row["prepTime"] as? String ?? ""
            recipe.cookTime = row["cookTime"] as? String ?? ""
            recipe.dateCreated = date(row["importedAt"]) ?? date(row["storedAt"]) ?? .distantPast
            recipe.updatedAt = row["updatedAt"] as? Double ?? (date(row["storedAt"]) ?? recipe.dateCreated).timeIntervalSince1970 * 1000
            recipe.lastWriterID = "shared-catalogue"
            return recipe
        }
        return Self(recipes: recipes, complete: object["complete"] as? Bool, nextCursor: object["nextCursor"] as? String)
    }
}
