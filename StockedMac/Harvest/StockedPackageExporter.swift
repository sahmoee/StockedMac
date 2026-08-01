import Foundation

nonisolated struct StockedPackageExporter {
    static let fileExtension = "stockedrecipe"

    static func safeFilename(_ title: String) -> String {
        let value = title.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return value.isEmpty ? "Recipe" : String(value.prefix(80))
    }

    func export(_ recipe: RecipeDraft, to destination: URL) throws {
        let data = try JSONCoding.encoder().encode(recipe)
        try data.write(to: destination, options: .atomic)
    }

    func exportAll(
        _ recipes: [RecipeDraft],
        toDirectory directory: URL
    ) throws -> (written: [URL], failures: [(title: String, reason: String)]) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        var failures: [(title: String, reason: String)] = []

        for recipe in recipes {
            let destination = directory
                .appendingPathComponent(Self.safeFilename(recipe.title))
                .appendingPathExtension(Self.fileExtension)
            do {
                try export(recipe, to: destination)
                written.append(destination)
            } catch {
                failures.append((recipe.title, error.localizedDescription))
            }
        }
        return (written, failures)
    }
}
