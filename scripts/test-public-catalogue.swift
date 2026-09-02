// Standalone smoke harness: compile with the production Models.swift,
// MacSharedTypes.swift, KitchenMetrics.swift, MacBuildConfig.swift and
// MacPublicRecipeSync.swift. Only transport/store are fakes.
import Foundation

@MainActor final class MacKitchenStore {
    var recipes: [UserRecipe] = []
    func mergePublicRecipes(_ rows: [UserRecipe]) { recipes.append(contentsOf: rows) }
}

@MainActor enum MacWorkerClient {
    static var isConfigured = true
    static var responses: [Data] = []
    static var cursors: [String?] = []
    static func getData(path: String, query: [String: String], timeout: TimeInterval) async throws -> Data {
        precondition(path == "harvest/recipes" && query["pageSize"] == "100")
        cursors.append(query["cursor"])
        guard !responses.isEmpty else { throw MacServiceError.offline }
        return responses.removeFirst()
    }
}

@main @MainActor struct CatalogueSmokeTests {
    static func main() async throws {
        let row: [String: Any] = ["id": "legacy-slug", "title": "Soup", "sourceURL": "https://publisher.example/soup",
            "image": "/harvest/img/soup.jpg", "attribution": "Original publisher", "instructions": ["Simmer"],
            "ingredients": [["name": "Water", "amount": "1 cup"]], "storedAt": "2026-09-02T00:00:00.000Z"]
        func page(_ rows: [[String: Any]], complete: Bool? = true, cursor: String? = nil) throws -> Data {
            var object: [String: Any] = ["recipes": rows]
            if let complete { object["complete"] = complete }
            if let cursor { object["nextCursor"] = cursor }
            return try JSONSerialization.data(withJSONObject: object)
        }
        let data = try page([row])
        let a = try MacPublicRecipePage.decode(data, baseURL: "https://worker.example")
        let b = try MacPublicRecipePage.decode(data, baseURL: "https://worker.example")
        precondition(a.recipes.count == 1 && a.recipes[0].id == b.recipes[0].id)
        precondition(a.recipes[0].imageURL == "https://worker.example/harvest/img/soup.jpg")
        precondition(a.recipes[0].sourceName == "Original publisher" && a.recipes[0].imageData == nil)
        var privateRow = row
        privateRow["sourceURL"] = ""
        let privatePage = try MacPublicRecipePage.decode(page([privateRow]), baseURL: "https://worker.example")
        precondition(privatePage.recipes.isEmpty)
        var tracked = a.recipes[0]
        tracked.sourceURL = "https://publisher.example/soup/?utm_source=test#section"
        precondition(MacPublicRecipePage.identity(tracked) == MacPublicRecipePage.identity(a.recipes[0]))

        MacWorkerClient.responses = [try page([], complete: false, cursor: "next"), data]
        let store = MacKitchenStore()
        let sync = MacPublicRecipeSync()
        await sync.refresh(store: store)
        precondition(MacWorkerClient.cursors.count == 2 && MacWorkerClient.cursors[1] == "next")
        precondition(store.recipes.count == 1 && sync.lastCompleteCount == 1 && !sync.isSyncing)

        MacWorkerClient.responses = [try page([row], complete: nil)]
        await sync.refresh(store: store)
        precondition(sync.status.contains("server update needed"))
        MacWorkerClient.responses = [try page([], complete: false, cursor: "repeat"), try page([], complete: false, cursor: "repeat")]
        await sync.refresh(store: store)
        precondition(sync.status.contains("incomplete") && !sync.isSyncing)
        print("Public catalogue decoder/pagination smoke tests passed")
    }
}
