// MacRecipeMaintenance.swift — the three recipe-tidying jobs, in one place.
//
// Build 88 put "Export recipes as CSV…" and "Remove recipes from a CSV…" in the File menu
// and nowhere else. Build 89 removed the two retired sources at launch and gave the user
// no way to ask for it. Both decisions were defensible on their own and wrong together:
// the File menu is where a Mac user looks for *import and export*, but "get these recipes
// out of my library" is housekeeping, and housekeeping is looked for in Settings ▸ Data,
// next to the counts that prompted the thought in the first place.
//
// So the work moves here and both surfaces call it. The menu keeps its items — removing
// them would be a regression for anyone who has learned them — and Settings gets the same
// three actions plus the one thing a menu cannot show: how many recipes match right now.
//
// Every one of these runs modal on the main actor. That is deliberate. They are all
// user-initiated, all destructive or file-touching, and all fast; an async version would
// buy nothing but a chance for the store to move underneath the confirmation.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
enum MacRecipeMaintenance {

    // MARK: - Counting

    /// How many recipes in each library came from a retired source, right now.
    ///
    /// Settings calls this on every redraw to label the button. It is two linear passes
    /// over arrays that are already in memory and hold hundreds of items, not thousands —
    /// cheaper than the layout pass that displays the result.
    static func retiredSourceCounts(store: MacKitchenStore) -> (recipes: Int, saved: Int) {
        let mine  = store.recipes.filter { MacRecipeSourceBlocklist.isBlocked($0) }.count
        let saved = store.savedRecipes.filter { MacRecipeSourceBlocklist.isBlocked($0) }.count
        return (mine, saved)
    }

    // MARK: - Export

    /// The file that comes out is the file `removeFromCSV` expects back — the `remove`
    /// column is what turns a worksheet into an instruction.
    static func exportCSV(store: MacKitchenStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = MacRecipeCSV.exportFilename()
        panel.message = "Save every recipe as a spreadsheet you can edit."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let csv = MacRecipeCSV.exportCSV(store: store)
            try Data(csv.utf8).write(to: url, options: [.atomic])
        } catch {
            present(error: "The spreadsheet couldn't be saved. \(error.localizedDescription)")
        }
    }

    // MARK: - Remove by spreadsheet

    /// Read the file, show what it would remove, remove only what was ticked. The
    /// confirmation window is not skippable — a CSV is too easy to edit by accident for
    /// this to be a one-click delete.
    static func removeFromCSV(store: MacKitchenStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the recipe spreadsheet with the rows you want removed."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            present(error: "That file couldn't be opened. \(error.localizedDescription)")
            return
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1), !text.isEmpty else {
            present(error: "That file looks empty.")
            return
        }

        let plan = MacRecipeCSV.plan(from: text, store: store)
        guard let choice = MacRecipeCSVWindow.confirm(plan: plan) else { return }

        let result = MacRecipeCSV.remove(recipeIDs: choice.recipes,
                                         savedRecipeIDs: choice.saved,
                                         store: store)
        guard result.removed > 0 else { return }
        reportRemoval(count: result.removed, backupURL: result.backupURL)
    }

    // MARK: - Remove the retired sources on demand

    /// The manual version of the Build 89 launch sweep.
    ///
    /// It deliberately does **not** call `MacRecipePurge.run`. That path is right for a
    /// silent launch sweep — no confirmation, no backup, no window — and wrong for a
    /// button somebody pressed. This one counts first, says out loud what it found, waits
    /// for a yes, and then goes through `MacRecipeCSV.remove`, which writes a restorable
    /// copy of everything it is about to take out. Same two `MacKitchenStore` deletion
    /// methods underneath, so the household tombstones are recorded either way.
    static func removeRetiredSources(store: MacKitchenStore) {
        let doomedMine  = Set(store.recipes.filter { MacRecipeSourceBlocklist.isBlocked($0) }
                                           .map(\.id))
        let doomedSaved = Set(store.savedRecipes.filter { MacRecipeSourceBlocklist.isBlocked($0) }
                                                .map(\.id))
        let total = doomedMine.count + doomedSaved.count

        guard total > 0 else {
            let none = NSAlert()
            none.messageText = "Nothing to remove."
            none.informativeText = """
                No recipe in your library came from the old food dataset or the retired \
                curated feed. Stocked also checks this every time it opens, so if some \
                arrive later from another device they will be cleared out on their own.
                """
            none.addButton(withTitle: "OK")
            none.runModal()
            return
        }

        let ask = NSAlert()
        ask.alertStyle = .warning
        ask.messageText = total == 1
            ? "Remove 1 recipe from a retired source?"
            : "Remove \(total) recipes from retired sources?"
        ask.informativeText = """
            \(breakdown(mine: doomedMine.count, saved: doomedSaved.count))

            These came from the bulk food dataset and the small curated feed that early \
            versions of Stocked shipped with. A recipe is judged only by where it came \
            from — never by its title or its contents — so anything you wrote yourself, \
            harvested from a website, or saved from elsewhere is left alone.

            A copy is saved first, and the removals carry across your household.
            """
        ask.addButton(withTitle: "Remove")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        let result = MacRecipeCSV.remove(recipeIDs: doomedMine,
                                         savedRecipeIDs: doomedSaved,
                                         store: store)
        guard result.removed > 0 else { return }
        reportRemoval(count: result.removed, backupURL: result.backupURL)
    }

    // MARK: - Shared reporting

    private static func breakdown(mine: Int, saved: Int) -> String {
        var parts: [String] = []
        if mine > 0  { parts.append("\(mine) in your recipes") }
        if saved > 0 { parts.append("\(saved) in your saved recipes") }
        return parts.joined(separator: ", ") + "."
    }

    /// Tell them where the safety copy went, and offer to reveal it. The path alone is
    /// useless in a sandbox; the button is the part that matters.
    private static func reportRemoval(count: Int, backupURL: URL?) {
        let done = NSAlert()
        done.messageText = count == 1 ? "1 recipe removed." : "\(count) recipes removed."
        if let backup = backupURL {
            done.informativeText = """
                A copy of what was removed was saved first, so you can bring them back \
                if this was a mistake.
                """
            done.addButton(withTitle: "OK")
            done.addButton(withTitle: "Show the Backup")
            if done.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([backup])
            }
        } else {
            done.addButton(withTitle: "OK")
            done.runModal()
        }
    }

    private static func present(error message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That didn't work"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
