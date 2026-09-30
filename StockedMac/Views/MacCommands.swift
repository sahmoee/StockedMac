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
    let desktop: MacDesktopExperience

    var body: some Commands {

        // Replace the default "New Item" so ⌘N does something meaningful per section.
        CommandGroup(replacing: .newItem) {
            Button(newLabel) { navigation.isAddingItem = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!supportsAdding)

            Button("Duplicate as Personal Variation") {
                guard let id = desktop.focusedRecipeID else { return }
                navigation.section = .recipes
                MacRecipeLibraryActions.duplicateAsVariation(id, store: store, desktop: desktop)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(focusedRecipe == nil)

            Divider()

            Button("Import Center…") { desktop.isImportCenterPresented = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Import Stocked Backup…") { runImport() }
            Button("Export Stocked Backup…") { runExport() }

            Divider()

            // Recipes as a spreadsheet, and the same spreadsheet back again as a removal
            // list. No shortcut on the removal item: it is destructive, and every
            // convenient chord is already spoken for.
            Button("Export recipes as CSV…") { runRecipeCSVExport() }
            Button("Export Shown Recipes as Markdown…") {
                let ids = Set(desktop.visibleRecipeIDs)
                MacRecipeLibraryActions.exportMarkdown(store.recipes.filter { ids.contains($0.id) })
            }
            .disabled(desktop.visibleRecipeIDs.isEmpty)
            Button("Remove recipes from a CSV…") { runRecipeCSVRemoval() }
            Button("Remove Kaggle and Sowens recipes…") { runRetiredSourceRemoval() }
        }

        // Print and PDF act on the recipe selected in the library.
        CommandGroup(replacing: .printItem) {
            Button("Print Recipe…") {
                if let recipe = focusedRecipe { MacRecipePrinter.print(recipe, system: desktop.measurementSystem) }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(focusedRecipe == nil)
            Button("Export Recipe as PDF…") {
                if let recipe = focusedRecipe { MacRecipePrinter.exportPDF(recipe, system: desktop.measurementSystem) }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(focusedRecipe == nil)
        }

        // Section switching, in the order the sidebar shows them.
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(MacSection.recipeManagerSections) { section in
                Button(section.rawValue) { navigation.section = section }
                    .keyboardShortcut(section.shortcut, modifiers: .command)
            }
        }

        CommandMenu("Navigate") {
            Button("Command Palette…") { desktop.isCommandPalettePresented = true }
                .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("View") {
            Picker("Recipe view", selection: Binding(
                get: { desktop.recipeMode },
                set: { desktop.recipeMode = $0 }
            )) {
                ForEach(MacRecipeWorkspaceMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                }
            }
            Picker("Density", selection: Binding(
                get: { desktop.density },
                set: { desktop.density = $0 }
            )) {
                ForEach(MacContentDensity.allCases) { density in Text(density.rawValue).tag(density) }
            }
            Divider()
            Button(desktop.isInspectorPresented ? "Hide Inspector" : "Show Inspector") {
                desktop.isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Recipes") {
            Button("Sync recipes now") {
                Task {
                    await sync.syncNow(store: store)
                    harvest.syncKitchenToCloud(store.recipes)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!sync.isJoined || sync.status.isBusy)

            Button("Pull all recipes down again") {
                Task { await sync.resyncEverything(into: store) }
            }
            .disabled(!sync.isJoined || sync.status.isBusy)

            Divider()

            Button("Edit Selected Recipe…") {
                guard let id = desktop.focusedRecipeID else { return }
                navigation.section = .recipes
                desktop.pendingEditRecipeID = id
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(focusedRecipe == nil)

            Menu("Recently Viewed") {
                let recent = desktop.recentRecipes(in: store.recipes)
                if recent.isEmpty {
                    Text("No recently viewed recipes")
                } else {
                    ForEach(recent) { recipe in
                        Button(recipe.title) { reveal(recipe.id) }
                    }
                    Divider()
                    Button("Clear Recently Viewed") { desktop.clearRecent() }
                }
            }

            Menu("Saved Filters") {
                if desktop.savedFilters.isEmpty {
                    Text("Save filters from the Recipes list")
                } else {
                    ForEach(desktop.savedFilters) { filter in
                        Button(filter.name) {
                            navigation.section = .recipes
                            desktop.pendingSavedFilter = filter
                        }
                    }
                }
            }

            Divider()

            Button("Edit Shown Recipes…") {
                navigation.section = .recipes
                desktop.isBulkEditPresented = true
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(desktop.visibleRecipeIDs.isEmpty)
            Button("Library Health…") { desktop.isLibraryHealthPresented = true }
            Button("Find Duplicates…") { desktop.isDuplicateFinderPresented = true }
            Button("Tag Manager…") { desktop.isTagManagerPresented = true }

            Divider()

            Picker("Show Amounts", selection: Binding(
                get: { desktop.measurementSystem },
                set: { desktop.measurementSystem = $0 }
            )) {
                ForEach(MacMeasurementSystem.allCases) { Text($0.rawValue).tag($0) }
            }
        }

        // The Harvester's own actions, kept under one menu the way the standalone
        // Companion app had them. Shortcuts avoid every combination the Kitchen menu and
        // File menu already claim.
        CommandMenu("Harvest") {
            Button("Import Queued URLs") {
                navigation.section = .browse
                harvest.importURLs()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("Paste URLs from Clipboard") {
                navigation.section = .browse
                harvest.pasteURLsFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Browse Next Source") {
                navigation.section = .browse
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

            Button("Import Activity…") { desktop.isActivityLogPresented = true }
                .keyboardShortcut("l", modifiers: [.command, .option])
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
            Button("Cookies & Tracking") { open(MacBuildConfig.cookiesURL) }
            Button("Refund Policy") { open(MacBuildConfig.refundURL) }
            Button("Request Data Deletion…") { open(MacBuildConfig.deleteDataURL) }
            Divider()
            Button("About & Business Details") { open(MacBuildConfig.aboutURL) }
            Button("Open-Source Licenses") { open(MacBuildConfig.licensesURL) }
            Button("Accessibility Statement") { open(MacBuildConfig.accessibilityURL) }
        }
    }

    // MARK: - Labels

    private var focusedRecipe: UserRecipe? {
        guard let id = desktop.focusedRecipeID else { return nil }
        return store.recipes.first { $0.id == id }
    }

    /// Brings the main window forward and selects the recipe in the library.
    private func reveal(_ id: UUID) {
        navigation.section = .recipes
        desktop.reveal(id)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain && window.identifier?.rawValue.contains("recipe") != true {
            window.makeKeyAndOrderFront(nil)
            break
        }
    }

    private var supportsAdding: Bool {
        // Kept in step with MacRootView's toolbar + button: the sections that read rather
        // than hold things have nothing for ⌘N to make.
        navigation.section == .recipes
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
