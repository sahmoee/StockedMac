// MacCommands.swift — the menu bar.
//
// The menu bar is the single biggest thing that separates a Mac app from a phone app in a
// window. Everything the app can do should be reachable here, discoverable by reading,
// and keyboard-driven. A user who never touches the sidebar should still be able to run
// the whole app from the menus.
//
// Conventions honoured deliberately:
//   • ⌘N makes a new thing in whatever section you're in
//   • ⌘1…⌘9 jump between sections, like tabs in Safari
//   • ⌘R refreshes, like every other app that syncs
//   • Import/Export sit under File, not in Settings, because that's where Mac users look
//   • destructive items are last in their group and never adjacent to a common action

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacCommands: Commands {
    let store: MacKitchenStore
    let sync: MacHouseholdSync
    let navigation: MacNavigation
    let harvest: HarvestModel

    var body: some Commands {

        // Replace the default "New Item" so ⌘N does something meaningful per section.
        CommandGroup(replacing: .newItem) {
            Button(newLabel) { navigation.isAddingItem = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!supportsAdding)

            Divider()

            Button("Import from a Stocked backup…") { runImport() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Export a backup…") { runExport() }
                .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            // Recipes as a spreadsheet, and the same spreadsheet back again as a removal
            // list. No shortcut on the removal item: it is destructive, and every
            // convenient chord is already spoken for.
            Button("Export recipes as CSV…") { runRecipeCSVExport() }
            Button("Remove recipes from a CSV…") { runRecipeCSVRemoval() }
            Button("Remove Kaggle and Sowens recipes…") { runRetiredSourceRemoval() }
        }

        // Section switching, in the order the sidebar shows them.
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(MacSection.allCases) { section in
                Button(section.rawValue) { navigation.section = section }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
            }
        }

        // Everything kitchen-shaped, in its own top-level menu. A Mac app is allowed a
        // domain menu, and burying "Sync now" under View would be worse than adding one.
        CommandMenu("Kitchen") {
            Button("Sync now") {
                Task { await sync.syncNow(store: store) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!sync.isJoined || sync.status.isBusy)

            Button("Refresh household") {
                Task { await sync.refreshPresence() }
            }
            .disabled(!sync.isJoined)

            // The escape hatch, mirrored from the Household screen. Someone who has just
            // joined on this Mac and can't see the phone's food will look in the menus
            // before they look for a button.
            Button("Pull everything down again") {
                Task { await sync.resyncEverything(into: store) }
            }
            .disabled(!sync.isJoined || sync.status.isBusy)

            Divider()

            Button("What can I cook right now?") { navigation.section = .cook }
                .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button("Ask for a recipe…") { navigation.recipeAIMode = .ask }
                .keyboardShortcut("g", modifiers: .command)

            Button("Bring a recipe in…") { navigation.recipeAIMode = .bring }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Divider()

            Button("Put checked groceries away") {
                store.stockCheckedGrocery()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!store.grocery.contains { $0.isChecked })

            Button("Clear checked items") { store.clearCheckedGrocery() }
                .disabled(!store.grocery.contains { $0.isChecked })

            Divider()

            Button("Add everything I'm low on to the list") { addLowStockToList() }
                .disabled(store.lowStock.isEmpty)
        }

        // The Harvester's own actions, kept under one menu the way the standalone
        // Companion app had them. Shortcuts avoid every combination the Kitchen menu and
        // File menu already claim.
        CommandMenu("Harvest") {
            Button("Import Queued URLs") {
                navigation.section = .harvest
                harvest.importURLs()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            .disabled(harvest.isImporting)

            Button("Paste URLs from Clipboard") {
                navigation.section = .harvest
                harvest.pasteURLsFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Browse Next Source") {
                navigation.section = .harvest
                harvest.browseNextSource()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(harvest.isDiscovering)

            Divider()

            Button("Add Approved to Recipe Library") {
                let approved = harvest.approvedRecipes
                let added = MacHarvestBridge.add(approved, to: store)
                harvest.statusMessage = MacHarvestBridge.summary(added: added,
                                                                 of: approved.count)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(harvest.approvedRecipes.isEmpty)

            Button("Export Approved Recipes…") { harvest.exportBatch(harvest.approvedRecipes) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(harvest.approvedRecipes.isEmpty)

            Divider()

            Button("Open Harvest Data Folder") { harvest.openDataFolder() }
        }

        CommandGroup(replacing: .help) {
            Button("Stocked Help") { open(MacBuildConfig.supportPageURL) }
            Button("Email Support") {
                open("mailto:\(MacBuildConfig.supportEmail)?subject=Stocked%20for%20Mac%20\(MacBuildConfig.version)")
            }
            Divider()
            Button("Privacy Policy") { open(MacBuildConfig.privacyURL) }
            Button("Terms of Use")   { open(MacBuildConfig.termsURL) }
        }
    }

    // MARK: - Labels

    private var supportsAdding: Bool {
        // Kept in step with MacRootView's toolbar + button: the sections that read rather
        // than hold things have nothing for ⌘N to make.
        switch navigation.section {
        case .home, .household, .insights, .tools, .cook, .harvest: return false
        default: return true
        }
    }

    private var newLabel: String {
        switch navigation.section {
        case .inventory: return "New Inventory Item"
        case .grocery:   return "New Grocery Item"
        case .recipes:   return "New Recipe"
        case .plan:      return "New Planned Meal"
        default:         return "New Item"
        }
    }

    // MARK: - Actions

    private func addLowStockToList() {
        for item in store.lowStock {
            let alreadyListed = store.grocery.contains {
                $0.name.compare(item.name, options: .caseInsensitive) == .orderedSame
            }
            guard !alreadyListed else { continue }
            store.addGrocery(name: item.name)
        }
    }

    /// Standard save panel. Sandboxed apps get write access to whatever the user picks
    /// here — that grant is the entire reason `files.user-selected.read-write` is in the
    /// entitlements file.
    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Stocked Backup.json"
        panel.message = "Save a copy of your inventory, list, recipes and week plan."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: [.atomic])
        } catch {
            present(error: "The backup couldn't be saved. \(error.localizedDescription)")
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Stocked backup to bring in."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Default to merging, not replacing. Replacing is the choice that can lose data,
        // so it should never be the one a distracted user gets by pressing Return.
        let alert = NSAlert()
        alert.messageText = "Bring this backup in?"
        alert.informativeText = """
            Merge keeps everything you already have and adds what's missing, preferring \
            whichever copy of a shared item was edited most recently.

            Replace discards this Mac's data first.
            """
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        let choice = alert.runModal()
        guard choice != .alertThirdButtonReturn else { return }

        do {
            let data = try Data(contentsOf: url)
            try store.importData(data, replace: choice == .alertSecondButtonReturn)
        } catch {
            present(error: (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription)
        }
    }

    // MARK: - Recipes by spreadsheet
    //
    // Build 90 moved the bodies of these into MacRecipeMaintenance so Settings ▸ Data can
    // offer the same three actions. The menu items stay exactly where they were — anyone
    // who has learned them keeps them — they just no longer own the code.

    private func runRecipeCSVExport() {
        MacRecipeMaintenance.exportCSV(store: store)
    }

    private func runRecipeCSVRemoval() {
        MacRecipeMaintenance.removeFromCSV(store: store)
    }

    /// The manual form of the launch sweep. Named after the two sources rather than
    /// "retired sources" because in a menu you are scanning for the word you remember,
    /// and the word people remember is Kaggle.
    private func runRetiredSourceRemoval() {
        MacRecipeMaintenance.removeRetiredSources(store: store)
    }

    private func present(error message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That didn't work"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
