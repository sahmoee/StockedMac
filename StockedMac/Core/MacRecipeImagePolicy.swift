import Foundation
import ImageIO

/// One image invariant for every recipe entry path. A URL is only a candidate; a recipe
/// has an image after the bytes have downloaded and ImageIO can decode a real photo.
nonisolated enum MacRecipeImagePolicy {
    static func isPublicImport(_ recipe: UserRecipe) -> Bool {
        guard let raw = recipe.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host != nil else { return false }
        return hasRequiredImage(recipe)
    }

    /// Imported images are validated before persistence. Once a recipe has a stable HTTPS
    /// source, keeping the same bytes base64-encoded inside recipes.json only duplicates
    /// hundreds of megabytes in memory. Local-only recipes still retain their bytes.
    static func hasRequiredImage(_ recipe: UserRecipe) -> Bool {
        if isUsable(recipe.imageData) { return true }
        guard let url = URL(string: recipe.imageURL ?? "") else { return false }
        return recipe.imageValidatedAt != nil
            && url.scheme?.lowercased() == "https"
            && url.host != nil
    }

    static func isUsable(_ data: Data?) -> Bool {
        guard let data, data.count > 4_096,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return min(width, height) >= 120
    }

    static func download(_ rawURL: String, referer: String? = nil) async throws -> Data {
        guard let url = URL(string: rawURL), url.scheme?.lowercased() == "https", url.host != nil else {
            throw CompanionError.invalidURL(rawURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("image/jpeg,image/png,image/heic,image/webp,image/avif,image/*;q=0.8", forHTTPHeaderField: "Accept")
        if let referer, !referer.isEmpty { request.setValue(referer, forHTTPHeaderField: "Referer") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), isUsable(data) else {
            throw CompanionError.parseFailed("The image URL did not return a usable recipe photo.")
        }
        return data
    }

    static func hydrate(_ recipes: [UserRecipe], maximumConcurrent: Int = 6) async -> [UserRecipe] {
        await withTaskGroup(of: (Int, UserRecipe?).self) { group in
            var iterator = recipes.enumerated().makeIterator()
            var results = Array<UserRecipe?>(repeating: nil, count: recipes.count)

            func submitNext() {
                guard let (index, recipe) = iterator.next() else { return }
                group.addTask {
                    if hasRequiredImage(recipe) { return (index, recipe) }
                    guard let imageURL = recipe.imageURL?.nilIfBlank else { return (index, nil) }
                    do {
                        var hydrated = recipe
                        hydrated.imageData = try await download(imageURL, referer: recipe.sourceURL)
                        hydrated.imageValidatedAt = Date()
                        return (index, hydrated)
                    } catch {
                        return (index, nil)
                    }
                }
            }

            for _ in 0..<min(maximumConcurrent, recipes.count) { submitNext() }
            while let (index, recipe) = await group.next() {
                results[index] = recipe
                submitNext()
            }
            return results.compactMap { $0 }
        }
    }
}
