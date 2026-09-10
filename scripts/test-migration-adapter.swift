import Foundation
import CoreGraphics
import ImageIO

// Isolate network/sync configuration; production parsing, image validation, models,
// privacy policy and the Mac adapter are compiled unchanged into this native harness.
nonisolated enum MacHouseholdSync { static let maxSyncedImageBytes = 180_000 }
nonisolated enum CompanionError: Error { case invalidURL(String), parseFailed(String) }
nonisolated enum MacServiceError: Error { case invalidRequest(String), malformedResponse(String) }
nonisolated final class MacWorkerRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@main struct MacMigrationAdapterChecks {
    static func main() throws {
        let raw = """
        {"@type":"Recipe","name":"Synthetic family meal","recipeIngredient":["1 cup rice"],"recipeInstructions":["Cook the rice."],"url":"https://example.org/Recipe","author":"Fixture cook","license":"Fixture license","imageAttribution":"Fixture photographer","comment":{"text":"Private family note"}}
        """
        let json = Data(raw.utf8)
        var seed: UInt32 = 7
        var pixels = [UInt8](repeating: 255, count: 160 * 160 * 4)
        for index in pixels.indices where index % 4 != 3 {
            seed = 1664525 &* seed &+ 1013904223
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 16)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(width: 160, height: 160, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 640, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        precondition(CGImageDestinationFinalize(destination))
        let photo = output as Data
        precondition(MacRecipeImagePolicy.isUsable(photo))
        let item = KitchenMigrationItem(id: UUID(), filename: "family.json", recipeJSON: json, localImage: photo,
                                        originalText: raw, warnings: [])
        let preview = try MacRecipeInterchangeAdapter.migration(KitchenMigrationBatch(items: [item], warnings: []))
        let row = preview.rows[0]
        precondition(row.localImageData == photo)
        precondition(row.originalHash == MacRecipeFolderScanner.digest(Data(raw.utf8)))
        precondition(row.privateNotes == "Private family note")
        precondition(row.contentProblems.isEmpty)
        let privateRecipe = MacRecipeInterchangeAdapter.userRecipe(row, image: photo, catalogueSharingApproved: false)
        precondition(privateRecipe.sourceURL == nil)
        precondition(privateRecipe.portableSource?.originalSourceURL == "https://example.org/Recipe")
        precondition(privateRecipe.portableSource?.originalText == raw)
        precondition(privateRecipe.imageData == photo && privateRecipe.notes.contains("Private family note"))
        var insecurePhotoURL = row
        insecurePhotoURL.imageURL = "http://example.org/photo.png"
        let originalPhotoOnly = MacRecipeInterchangeAdapter.userRecipe(insecurePhotoURL, image: photo, catalogueSharingApproved: false)
        precondition(originalPhotoOnly.imageURL == nil && originalPhotoOnly.imageData == photo)
        precondition(!MacRecipeImagePolicy.isPublicImport(privateRecipe))
        let publicRecipe = MacRecipeInterchangeAdapter.userRecipe(row, image: photo, catalogueSharingApproved: true)
        precondition(publicRecipe.sourceURL == "https://example.org/Recipe" && MacRecipeImagePolicy.isPublicImport(publicRecipe))
        precondition(publicRecipe.author == "Fixture cook" && publicRecipe.license == "Fixture license" && publicRecipe.imageAttribution == "Fixture photographer")
        var edited = privateRecipe
        edited.title = "Renamed after import"
        edited.instructions = ["New instructions"]
        precondition(MacRecipeInterchangeAdapter.duplicateIDs(in: [row], existing: [edited]).contains(row.id))
        var repeated = row
        repeated.id = UUID()
        precondition(MacRecipeInterchangeAdapter.duplicateIDs(in: [row, repeated], existing: []).contains(repeated.id))
        let normalized = KitchenMigrationItem(id: UUID(), filename: "normalized.json", recipeJSON: json, localImage: photo,
                                              originalText: nil, warnings: [])
        let normalizedRow = try MacRecipeInterchangeAdapter.migration(KitchenMigrationBatch(items: [normalized], warnings: [])).rows[0]
        let normalizedRecipe = MacRecipeInterchangeAdapter.userRecipe(normalizedRow, image: photo, catalogueSharingApproved: false)
        precondition(normalizedRecipe.portableSource?.originalText == "")
        precondition(normalizedRecipe.portableSource?.contentHash == MacRecipeFolderScanner.digest(json))
        let exported = try MacRecipeInterchange.encode([MacRecipeInterchangeAdapter.document(privateRecipe)])
        let exportedRow = try MacRecipeInterchange.decode(exported)[0]
        precondition(exportedRow.privateNotes.contains("Private family note"))
        print("Mac migration adapter: original photos, private notes, author/license/credits, explicit publication, original hashes, edited-file duplicates and normalized-source export passed")
    }
}
