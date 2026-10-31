#!/usr/bin/env python3
"""Exercise actual Recipes row materialization and CSV matching with legacy duplicate IDs."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
view = (root/'StockedMac/Views/MacRecipesView.swift').read_text()
csv = (root/'StockedMac/Core/MacRecipeCSV.swift').read_text()
def extract(source, signature):
    start = source.index(signature); brace = source.index('{', start); end = brace+1; depth=1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}'); end+=1
    return source[start:end].replace('private func ', 'func ').replace('private enum ', 'enum ')
sort = extract(view,'private enum Sort:')
rebuild = extract(view,'private func rebuildRows()')
models = csv[csv.index('nonisolated enum MacRecipeCSVLibrary'):csv.index('// MARK: - The machinery')]
match = extract(csv,'static func match(')
norm = extract(csv,'static func normKey(')
harness = r'''
import Foundation
@MainActor final class MacKitchenStore { var recipes: [UserRecipe] = []; var savedRecipes: [GeneratedRecipe] = [] }
@MainActor final class Navigation { var searchText = "" }
@MainActor final class Desktop { var visibleRecipeIDs: [UUID] = [] }
enum MacRecipeImagePolicy { static func isKnownPublisherPlaceholder(_ value: String) -> Bool { false } }
enum MacRecipeScope { case all, other; func includes(_ recipe: UserRecipe) -> Bool { true } }
enum MacRecipeTiming { static func totalMinutes(_ recipe: UserRecipe) -> Int? { Int(recipe.cookTime) } }
@MainActor final class ViewFixture {
 let store = MacKitchenStore(), navigation = Navigation(), desktop = Desktop()
 var materializedRows: [UserRecipe] = [], selection: UUID?, scope = MacRecipeScope.all
 var favoritesOnly = false, selectedCuisine = "", selectedTag = "", selectedDifficulty = "", selectedRole = ""
 var sort = Sort.name
 func searchTokens(_ text: String) -> [String] { [] }
 func matchesSearch(_ recipe: UserRecipe, tokens: [String]) -> Bool { true }
''' + sort + '\n' + rebuild + r'''
}
''' + models + '\nenum MacRecipeCSV {\n' + norm + '\n@MainActor\n' + match + '\n}\n' + r'''
@main struct Checks {
 @MainActor static func main() {
   var first = UserRecipe(title: "First duplicate"); first.cookTime = "20"
   var duplicate = first; duplicate.title = "Later duplicate"; duplicate.cookTime = "1"
   var other = UserRecipe(title: "Other recipe"); other.cookTime = "10"
   let fixture = ViewFixture(); fixture.store.recipes = [first,duplicate,other]
   for sort in ViewFixture.Sort.allCases {
      fixture.sort = sort; fixture.rebuildRows()
      precondition(fixture.materializedRows.count == 3)
      precondition(Set(fixture.desktop.visibleRecipeIDs) == [first.id,other.id])
      precondition(fixture.selection != nil)
      if sort == .quickest {
        precondition(fixture.materializedRows.first?.id == other.id, "time lookup must keep first stored duplicate, matching selection semantics")
      }
   }
   fixture.store.recipes = []; fixture.rebuildRows(); precondition(fixture.materializedRows.isEmpty && fixture.selection == nil)
   let store = MacKitchenStore(); store.recipes = [first,duplicate]
   var saved = GeneratedRecipe(title: "First saved", cookTime: "10", servings: 2, difficulty: "Easy", ingredients: [], steps: [], tips: "")
   var savedDuplicate = saved; savedDuplicate.title = "Later saved"
   store.savedRecipes = [saved,savedDuplicate]
   let mineRow = MacRecipeCSVRow(library: .mine, recipeID: first.id, title: "", markedForRemoval: true, lineNumber: 2)
   let savedRow = MacRecipeCSVRow(library: .saved, recipeID: saved.id, title: "", markedForRemoval: true, lineNumber: 3)
   let matches = MacRecipeCSV.match([mineRow,savedRow,mineRow], store: store)
   precondition(matches.count == 2)
   precondition(matches.allSatisfy { $0.matchedByID && $0.candidates.count == 1 })
   precondition(matches[0].candidates[0].title == first.title)
   precondition(matches[1].candidates[0].title == saved.title)
   print("PASS: actual Recipes materializer all eight sorts (including quickest), empty rows, CSV mine/saved duplicate-ID first-winner matching and duplicate input-row collapse")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='stocked-duplicate-consumers-') as temp:
    p=Path(temp)/'Checks.swift'; p.write_text(harness); binary=Path(temp)/'checks'
    files=['Models','MacSharedTypes','KitchenMetrics','PortableRecipeSource','PortableCooklang']
    subprocess.run(['swiftc','-parse-as-library',*[str(root/f'StockedMac/Core/{f}.swift') for f in files],str(root/'StockedMac/Harvest/RecipeTitlePolicy.swift'),str(p),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
