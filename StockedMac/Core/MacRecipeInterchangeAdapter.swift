import Foundation

nonisolated enum MacRecipeInterchangeAdapter {
    struct Preview: Sendable {
        var rows: [MacInterchangeRecipe] = []
        var warnings: [String] = []
        var retainedBytes = 0
    }

    static func readFiles(_ files: [URL]) throws -> Preview {
        var preview = Preview()
        for file in files.prefix(50) {
            try Task.checkCancellation()
            do {
                let next: Preview
                if file.pathExtension.lowercased() == "cook" {
                    next = try migration(MacRecipeInterchange.read(file), filename: file.lastPathComponent)
                } else { next = try migration(KitchenMigration.read(url: file)) }
                guard preview.rows.count + next.rows.count <= 250 else { throw MacRecipeInterchange.ImportError.tooMany }
                guard preview.retainedBytes + next.retainedBytes <= 32 * 1_024 * 1_024 else {
                    throw MacServiceError.invalidRequest("The recipe text and photos in this selection exceed 32 MB. Choose a smaller batch.")
                }
                preview.rows += next.rows
                preview.warnings += next.warnings
                preview.retainedBytes += next.retainedBytes
            } catch is CancellationError { throw CancellationError() }
            catch { preview.warnings.append("\(file.lastPathComponent): \(error.localizedDescription)") }
        }
        return preview
    }

    static func migration(_ data: Data, filename: String) throws -> Preview {
        if URL(fileURLWithPath: filename).pathExtension.lowercased() == "cook" {
            guard let text = String(data: data, encoding: .utf8) else { throw MacRecipeInterchange.ImportError.malformed }
            _ = try PortableRecipeSource(format: "cook", filename: filename, originalText: text)
            var row = document(try PortableCooklang.parse(text, fallbackTitle: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent))
            row.originalFilename = filename
            row.originalFormat = "cook"
            row.rawOriginalText = text
            row.originalHash = MacRecipeFolderScanner.digest(data)
            return Preview(rows: [row], retainedBytes: data.count * 3)
        }
        return try migration(KitchenMigration.decode(data, filename: filename))
    }

    static func migration(_ batch: KitchenMigrationBatch) throws -> Preview {
        var preview = Preview(warnings: batch.warnings)
        for item in batch.items {
            try Task.checkCancellation()
            guard var row = try MacRecipeInterchange.decode(item.recipeJSON).first else { continue }
            row.originalFilename = item.filename
            row.originalFormat = URL(fileURLWithPath: item.filename).pathExtension.lowercased()
            row.rawOriginalText = item.originalText
            row.originalHash = MacRecipeFolderScanner.digest(item.originalText.map { Data($0.utf8) } ?? item.recipeJSON)
            row.warnings += item.warnings
            if MacRecipeInterchange.secureURL(row.imageURL) == nil || !MacRecipeImagePolicy.isLikelyRecipeImageURL(row.imageURL, sourceURL: row.sourceURL) {
                row.imageURL = ""
            }
            preview.retainedBytes += item.recipeJSON.count + (item.originalText?.utf8.count ?? 0)
            if let bytes = item.localImage {
                if MacRecipeImagePolicy.isUsable(bytes) {
                    preview.retainedBytes += bytes.count
                    row.localImageData = bytes
                    if bytes.count > MacHouseholdSync.maxSyncedImageBytes && row.imageURL.isEmpty {
                        row.warnings.append("This original photo is kept on this Mac. It is larger than household sync supports; add a secure photo URL if you need the full photo on another device.")
                    }
                } else { row.warnings.append("The attached image could not be validated as a recipe photo. Add a secure photo URL before importing on this Mac.") }
            }
            guard preview.retainedBytes <= 32 * 1_024 * 1_024 else { throw MacServiceError.invalidRequest("The recipe text and photos in this archive exceed 32 MB. Export a smaller batch.") }
            if item.originalText == nil { row.warnings.append("This record was converted from an archive. An exact original text file is unavailable; keep your original archive for recovery.") }
            preview.rows.append(row)
        }
        return preview
    }

    static func offMain<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .utility, operation: work)
        return try await withTaskCancellationHandler(operation: {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        }, onCancel: { task.cancel() })
    }

    static func document(_ recipe: PortableCooklangRecipe) -> MacInterchangeRecipe {
        var row = MacInterchangeRecipe()
        row.title = recipe.title
        row.summary = recipe.description
        row.sourceURL = recipe.sourceURL
        row.sourceName = recipe.sourceName
        row.author = recipe.author
        row.license = recipe.license
        row.imageCredit = recipe.imageAttribution
        row.imageURL = recipe.imageURL
        row.yield = recipe.servings
        row.prepTime = recipe.prepTime
        row.cookTime = recipe.cookTime
        row.tags = recipe.tags
        row.ingredients = recipe.ingredients.map(\.displayLine)
        row.instructions = recipe.steps
        row.warnings = recipe.warnings + ["Cooklang files can contain advanced metadata. The original file is available unchanged; check source and photo sharing rights before importing."]
        row.originalCooklang = recipe.originalText
        row.privateNotes = recipe.notes.joined(separator: "\n")
        return row
    }

    static func cooklang(_ row: MacInterchangeRecipe) -> PortableCooklangRecipe {
        var recipe = PortableCooklangRecipe()
        recipe.title = row.title
        recipe.description = row.summary
        recipe.sourceURL = row.sourceURL
        recipe.author = row.author
        recipe.license = row.license
        recipe.imageAttribution = row.imageCredit
        recipe.sourceName = row.sourceName
        recipe.imageURL = row.imageURL
        recipe.servings = row.yield
        recipe.prepTime = row.prepTime
        recipe.cookTime = row.cookTime
        recipe.tags = row.tags
        recipe.ingredients = row.ingredients.map { PortableCooklangIngredient(name: $0) }
        recipe.steps = row.instructions
        recipe.notes = [("Author", row.author), ("Recipe license", row.license), ("Photo credit", row.imageCredit)]
            .filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }
        return recipe
    }

    static func signature(_ row: MacInterchangeRecipe) -> String {
        ([row.title] + row.ingredients + row.instructions).map {
            $0.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: "\u{1f}")
    }

    static func signature(_ recipe: UserRecipe) -> String { signature(document(recipe)) }

    static func duplicateIDs(in candidates: [MacInterchangeRecipe], existing: [UserRecipe]) -> Set<UUID> {
        var sources = Set(existing.compactMap { $0.attributedSourceURL.flatMap(MacRecipeInterchange.sourceKey) })
        var contents = Set(existing.map(signature))
        var originals = Set(existing.compactMap { $0.portableSource?.contentHash })
        var result = Set<UUID>()
        for row in candidates {
            let sourceDuplicate = row.sourceKey.map { !sources.insert($0).inserted } ?? false
            let contentDuplicate = !contents.insert(signature(row)).inserted
            let originalDuplicate = row.originalHash.map { !originals.insert($0).inserted } ?? false
            if sourceDuplicate || contentDuplicate || originalDuplicate { result.insert(row.id) }
        }
        return result
    }

    static func userRecipe(_ row: MacInterchangeRecipe, image: Data, catalogueSharingApproved: Bool) -> UserRecipe {
        var recipe = UserRecipe(title: row.title)
        recipe.description = row.summary
        recipe.ingredients = row.ingredients.map { RecipeIngredient(name: $0, amount: "") }
        recipe.instructions = row.instructions
        recipe.sourceURL = row.sourceURL
        recipe.author = row.author.isEmpty ? nil : row.author
        recipe.license = row.license.isEmpty ? nil : row.license
        recipe.imageAttribution = row.imageCredit.isEmpty ? nil : row.imageCredit
        recipe.sourceName = row.sourceName.isEmpty ? URL(string: row.sourceURL)?.host : row.sourceName
        recipe.imageURL = MacRecipeInterchange.secureURL(row.imageURL) != nil
            && MacRecipeImagePolicy.isLikelyRecipeImageURL(row.imageURL, sourceURL: row.sourceURL) ? row.imageURL : nil
        recipe.imageData = image
        recipe.imageValidatedAt = Date()
        recipe.prepTime = row.prepTime
        recipe.cookTime = row.cookTime.isEmpty ? row.totalTime : row.cookTime
        recipe.cuisine = row.cuisines.first ?? ""
        recipe.categories = row.categories
        recipe.tags = row.tags
        let numericYield = Double(row.yield)
        recipe.servings = numericYield.flatMap { $0.isFinite && $0 >= 1 && $0 <= 10000 && $0.rounded() == $0 ? Int($0) : nil } ?? 1
        var notes = [("Source", row.sourceURL), ("Author", row.author), ("Recipe license", row.license),
                     ("Photo credit", row.imageCredit), ("Original yield", row.yield), ("Original prep time", row.prepTime),
                     ("Original cook time", row.cookTime), ("Original total time", row.totalTime)]
            .filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }
        if numericYield == nil { notes.append("Serving count needs review before scaling this recipe.") }
        for (key, value) in row.nutrition.sorted(by: { $0.key < $1.key }) { notes.append("Source nutrition \(key): \(value)") }
        if !row.privateNotes.isEmpty { notes.append(row.privateNotes) }
        recipe.notes = notes.joined(separator: "\n")
        recipe.portableSource = try? PortableRecipeSource(format: row.originalFormat ?? "json", filename: row.originalFilename ?? "Recipe.json", originalText: row.rawOriginalText ?? row.originalCooklang ?? "")
        if recipe.portableSource == nil {
            recipe.portableSource = try? PortableRecipeSource(format: row.originalFormat ?? "json", filename: row.originalFilename ?? "Recipe.json", originalText: "")
        }
        if recipe.portableSource?.originalText.isEmpty == true, let hash = row.originalHash { recipe.portableSource?.contentHash = hash }
        recipe.portableSource?.originalSourceURL = row.sourceURL
        recipe.portableSource?.catalogueSharingApproved = catalogueSharingApproved
        return MacPortableRecipePolicy.repaired(recipe)
    }

    static func document(_ recipe: UserRecipe) -> MacInterchangeRecipe {
        var row = MacInterchangeRecipe()
        row.title = recipe.title
        row.summary = recipe.description
        row.privateNotes = recipe.notes
        // Display/export only. Publication must use the top-level URL and approval gate.
        row.sourceURL = recipe.attributedSourceURL ?? ""
        row.author = recipe.author ?? ""
        row.license = recipe.license ?? ""
        row.imageCredit = recipe.imageAttribution ?? ""
        row.sourceName = recipe.sourceName ?? ""
        row.imageURL = recipe.imageURL ?? ""
        row.ingredients = recipe.ingredients.map { [$0.amount, $0.name].filter { !$0.isEmpty }.joined(separator: " ") }
        row.instructions = recipe.instructions
        row.yield = String(recipe.servings)
        row.prepTime = recipe.prepTime.hasPrefix("P") ? recipe.prepTime : ""
        row.cookTime = recipe.cookTime.hasPrefix("P") ? recipe.cookTime : ""
        row.cuisines = recipe.cuisine.isEmpty ? [] : [recipe.cuisine]
        row.categories = recipe.categories ?? []
        row.tags = recipe.tags
        if let original = recipe.portableSource, ["cook", "cooklang"].contains(original.format) {
            row.originalCooklang = original.originalText
            row.originalFilename = original.filename
        }
        for line in recipe.notes.components(separatedBy: .newlines) {
            guard let separator = line.range(of: ": ") else { continue }
            let key = String(line[..<separator.lowerBound])
            let value = String(line[separator.upperBound...])
            switch key {
            case "Author": row.author = value
            case "Recipe license": row.license = value
            case "Photo credit": row.imageCredit = value
            case "Original yield": row.yield = value
            case "Original prep time": row.prepTime = value
            case "Original cook time": row.cookTime = value
            case "Original total time": row.totalTime = value
            default: if key.hasPrefix("Source nutrition ") { row.nutrition[String(key.dropFirst("Source nutrition ".count))] = value }
            }
        }
        return row
    }

    static func imageData(_ raw: String) async throws -> Data {
        guard let url = MacRecipeInterchange.secureURL(raw), MacRecipeImagePolicy.isLikelyRecipeImageURL(raw) else {
            throw MacRecipeInterchange.ImportError.malformed
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: MacWorkerRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
              response.expectedContentLength <= MacRecipeInterchange.byteLimit else {
            throw MacServiceError.malformedResponse("The original photo is unavailable or too large.")
        }
        var data = Data()
        for try await byte in bytes {
            if data.count % 16384 == 0 { try Task.checkCancellation() }
            guard data.count < MacRecipeInterchange.byteLimit else { throw MacRecipeInterchange.ImportError.tooLarge }
            data.append(byte)
        }
        guard MacRecipeImagePolicy.isUsable(data) else {
            throw MacServiceError.malformedResponse("The source did not provide a usable recipe photo.")
        }
        return data
    }
}
