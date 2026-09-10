import Foundation

nonisolated enum MacCooklangConnectionImport {
    static func preview(_ recipe: CooklangFederationRecipe) throws -> MacRecipeInterchangeAdapter.Preview {
        try Task.checkCancellation()
        var preview = try MacRecipeInterchangeAdapter.migration(Data(recipe.content.utf8), filename: recipe.filename)
        guard !preview.rows.isEmpty else { throw MacRecipeInterchange.ImportError.noRecipes }
        var row = preview.rows[0]
        if row.title == URL(fileURLWithPath: recipe.filename).deletingPathExtension().lastPathComponent { row.title = recipe.title }
        // Recipe-declared attribution wins; feed curator is not inferred to be the recipe author.
        if row.sourceURL.isEmpty { row.sourceURL = (recipe.sourceURL ?? recipe.enclosureURL)?.absoluteString ?? "" }
        if row.sourceName.isEmpty { row.sourceName = URL(string: row.sourceURL)?.host ?? "Cooklang Federation" }
        if row.imageURL.isEmpty { row.imageURL = recipe.imageURL?.absoluteString ?? "" }
        row.privateNotes += (row.privateNotes.isEmpty ? "" : "\n\n") + recipe.attributionNote
        row.warnings.append("Cooklang Federation supplied this index copy. Review original credits and recipe amounts. This connection saves only to your household and never approves public catalogue sharing.")
        if row.imageURL.isEmpty {
            row.warnings.append("StockedMac requires a photo before importing. Save the Cooklang file below and add an image link before reimporting, or review this recipe on iOS where private text-only recipes are supported.")
        }
        preview.rows = [row]
        try Task.checkCancellation()
        return preview
    }
}
