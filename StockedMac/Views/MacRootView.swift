// MacRootView.swift — the window shell.
//
// A source list on the left, one section at a time on the right. This is the layout Mail,
// Notes, Reminders and Finder all use, and it is the reason a Mac app can show far more
// than a phone can: the navigation is always visible, so the content never has to give up
// room to a tab bar.
//
// The sidebar carries live counts. On a phone those would be badge dots; here there is
// room to say "3 expiring" outright, which is the difference between a hint and an answer.

import SwiftUI
import AppKit
import Combine

/// The sections of the app. The order is the order of use: what needs attention, what you
/// have, what you need, what you could make, what you planned, who you share with.
nonisolated enum MacSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home      = "Kitchen"
    case inventory = "Inventory"
    case grocery   = "Grocery"
    case recipes   = "Recipes"
    case plan      = "Week"
    case cook      = "Cook"
    case insights  = "Insights"
    case tools     = "Tools"
    case household = "Household"
    /// Build 91: the full import pipeline — sources, queue, verification, image
    /// recovery, cloud cache. Build 100 folds the review library in too, so Browse
    /// is now the single place recipes are found, imported, AND approved.
    case browse    = "Browse"
    case sync = "Household Sync"
    case catalog = "Brands & Stores"

    /// Categories remain an internal discovery/cache concern. The dedicated browser is
    /// intentionally absent from the operator shell; Browse consumes the same background data.
    static let recipeManagerSections: [MacSection] = [.recipes, .browse, .catalog, .sync]

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .inventory: return "refrigerator"
        case .grocery:   return "cart"
        case .recipes:   return "book"
        case .plan:      return "calendar"
        case .cook:      return "frying.pan"
        case .insights:  return "chart.bar"
        case .tools:     return "wrench.and.screwdriver"
        case .household: return "person.2"
        case .browse:    return "globe"
        case .sync: return "arrow.triangle.2.circlepath"
        case .catalog: return "storefront"
        }
    }

    /// ⌘1 … ⌘6, wired up in MacCommands.
    var shortcut: KeyEquivalent {
        switch self {
        case .home:      return "1"
        case .inventory: return "2"
        case .grocery:   return "3"
        case .recipes:   return "1"
        case .plan:      return "5"
        case .cook:      return "6"
        case .insights:  return "7"
        case .tools:     return "8"
        case .household: return "9"
        case .browse:    return "2"
        case .sync: return "4"
        case .catalog: return "3"
        }
    }
}

nonisolated enum MacRecipeAIMode: Sendable {
    case ask
    case bring
}

/// Selection lives in one place so the menu bar commands and the sidebar can both drive it.
@MainActor
@Observable
final class MacNavigation {
    var section: MacSection = .recipes
    /// Raised by ⌘N and the toolbar's + button; each section decides what "new" means.
    var isAddingItem = false
    var searchText = ""
    var recipeAIMode: MacRecipeAIMode?
}

struct MacRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync
    @Environment(HarvestModel.self) private var harvest

    /// Owned by the App so the menu bar commands can drive the same selection the sidebar
    /// shows. A window-local @State here would leave ⌘2 doing nothing.
    @Environment(MacNavigation.self) private var navigation
    @Environment(MacDesktopExperience.self) private var desktop
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: MacTheme.sidebarMin,
                                                ideal: MacTheme.sidebarIdeal,
                                                max: MacTheme.sidebarMax)
        } detail: {
            detail
                // The window scene owns the usable minimum size. Giving the detail
                // column another hard minimum makes AppKit preserve two incompatible
                // widths while a split item is inserted, removed, or restored.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        // Prefer preserving the detail rather than asking both split items to retain
        // their width during sidebar transitions. This avoids transient mutually
        // exclusive NSSplitView safe-area constraints on macOS.
        .navigationSplitViewStyle(.prominentDetail)
        .navigationTitle(navigation.section.rawValue)
        .toolbar { toolbarContent }
        .sheet(isPresented: Binding(
            get: { desktop.isCommandPalettePresented },
            set: { desktop.isCommandPalettePresented = $0 }
        )) { MacCommandPalette().macThemedSurface() }
        .sheet(isPresented: Binding(
            get: { desktop.isImportCenterPresented },
            set: { desktop.isImportCenterPresented = $0 }
        )) { MacImportCenter().macThemedSurface() }
        // Pull whenever the window comes back to the front. A Mac app is left open for
        // hours, so "refresh on launch" alone would leave stale numbers on screen all day.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            guard sync.isJoined, !sync.status.isBusy else { return }
            Task { await sync.pull(into: store) }
        }
        .onAppear {
            sync.syncInventory = false
            sync.syncGrocery = false
            sync.syncPlan = false
            sync.syncRecipes = true
            sync.persistPreferences()
            if !MacSection.recipeManagerSections.contains(navigation.section) {
                navigation.section = .recipes
            }
        }
        .macThemedSurface()
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { navigation.section },
                                set: { navigation.section = $0 ?? .recipes })) {
            Section("Recipe Manager") {
                ForEach(MacSection.recipeManagerSections) { section in
                    Label {
                        HStack {
                            Text(section.rawValue)
                            Spacer(minLength: 6)
                            if let badge = badge(for: section) {
                                Text(badge)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: section.systemImage)
                    }
                    .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(MacTheme.sidebar(dark: colorScheme == .dark))
        .safeAreaInset(edge: .bottom) { syncFooter }
    }

    private func badge(for section: MacSection) -> String? {
        switch section {
        case .home:
            let urgent = store.metrics.expiringSoonCount + store.metrics.expiredCount
            return urgent > 0 ? "\(urgent)" : nil
        case .inventory:
            return store.inventory.isEmpty ? nil : "\(store.inventory.count)"
        case .grocery:
            let count = store.metrics.groceryToBuy
            return count > 0 ? "\(count)" : nil
        case .recipes:
            return store.recipes.isEmpty ? nil : "\(store.recipes.count)"
        case .plan:
            let upcoming = store.plannedMeals.filter { !$0.isCooked }.count
            return upcoming > 0 ? "\(upcoming)" : nil
        case .cook:
            let ready = store.recipes.filter { store.canCook($0) }.count
            return ready > 0 ? "\(ready)" : nil
        case .insights, .tools:
            return nil
        case .browse:
            // Build 100: Browse now owns review too. Surface what needs a decision first
            // (the actionable number), falling back to how many links are queued.
            let waiting = harvest.recipes.filter { $0.reviewState == .needsReview }.count
            if waiting > 0 { return "\(waiting)" }
            let queued = harvest.queuedURLCount
            return queued > 0 ? "\(queued)" : nil
        case .household:
            return sync.isJoined ? "\(max(1, sync.members.count))" : nil
        case .sync:
            return sync.isJoined ? "\(max(1, sync.members.count))" : nil
        case .catalog:
            return nil
        }
    }

    /// The sync state, parked at the bottom of the sidebar where it is visible but never
    /// in the way. A status line that has to be hunted for is a status line nobody trusts.
    private var syncFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if let health = harvest.serverCacheHealth {
                HStack(spacing: 6) {
                    Image(systemName: health.state == "healthy" ? "server.rack" : "exclamationmark.triangle")
                        .foregroundStyle(health.state == "healthy" ? MacTheme.green : .orange)
                    Text("Server: \(health.recipeBatchCount) recipe · \(health.catalogBatchCount) catalog")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .help("Updated \(health.updatedAt.formatted()) · \(health.candidateCount) recipe candidates · \(health.catalogRecordCount) catalog records · \(health.sitemapCacheCount) cached sitemaps" + (health.lastError.map { " · \($0)" } ?? ""))
            }
            Group {
                if sync.isJoined {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(footerTint)
                            .frame(width: 6, height: 6)
                        Text(sync.status.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            Task { await sync.syncNow(store: store) }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderless)
                        .disabled(sync.status.isBusy)
                        .help("Sync now")
                    }
                } else {
                    Button {
                        navigation.section = .sync
                    } label: {
                        Label("Enter household code", systemImage: "person.badge.key")
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MacTheme.gold)
                    .accessibilityHint("Opens Household Sync so you can join the household used by Stocked on iPhone.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var footerTint: Color {
        guard sync.isJoined else { return .secondary }
        switch sync.status {
        case .failed:  return .red
        case .syncing: return MacTheme.low
        default:       return MacTheme.green
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch navigation.section {
        case .home:      MacHomeView()
        case .inventory: MacInventoryView()
        case .grocery:   MacGroceryView()
        case .recipes:   MacRecipesView()
        case .plan:      MacPlanView()
        case .cook:      MacCookView()
        case .insights:  MacInsightsView()
        case .tools:     MacToolsView()
        case .household: MacHouseholdView()
        case .browse:    MacBrowseView()
        case .sync: MacHouseholdView()
        case .catalog: MacCatalogView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { desktop.isCommandPalettePresented = true } label: {
                Label("Commands", systemImage: "command")
            }
            .help("Command Palette (⌘K)")
            Button { desktop.isImportCenterPresented = true } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import Center (⇧⌘I)")
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            if navigation.section == .recipes {
                Picker("Recipe view", selection: Binding(
                    get: { desktop.recipeMode },
                    set: { desktop.recipeMode = $0 }
                )) {
                    ForEach(MacRecipeWorkspaceMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Recipe list presentation")
                Button { desktop.isInspectorPresented.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help(desktop.isInspectorPresented ? "Hide Inspector" : "Show Inspector")
            }
            if sync.isJoined {
                Button { Task { await sync.syncNow(store: store) } } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(sync.status.isBusy)
                .help(sync.status.message)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                navigation.isAddingItem = true
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .help(addLabel)
            .disabled(!supportsAdding)
        }
    }

    private var supportsAdding: Bool {
        navigation.section == .recipes
    }

    private var addLabel: String {
        switch navigation.section {
        case .inventory: return "Add an item"
        case .grocery:   return "Add to the list"
        case .recipes:   return "New recipe"
        case .plan:      return "Plan a meal"
        default:         return "Add"
        }
    }
}

private struct MacRecipeCategoriesView: View {
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacKitchenStore.self) private var store
    @State private var search = ""
    @State private var recipeSearch = ""
    @State private var selectedCategoryID: String?

    private static let cuisinePrefix = "cuisine:"

    private var cuisineCategories: [RecipeBrowseCategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return harvest.cuisineCategories }
        return harvest.cuisineCategories.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var categories: [SourceCategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return harvest.allCategories }
        return harvest.allCategories.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.sourceName.localizedCaseInsensitiveContains(query)
                || ($0.group?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedCategory: SourceCategory? {
        if let selectedCategoryID,
           let selected = categories.first(where: { $0.id == selectedCategoryID }) {
            return selected
        }
        return categories.first
    }

    private var selectedCuisine: RecipeBrowseCategory? {
        guard let selectedCategoryID, selectedCategoryID.hasPrefix(Self.cuisinePrefix) else { return nil }
        let id = String(selectedCategoryID.dropFirst(Self.cuisinePrefix.count))
        return harvest.cuisineCategories.first { $0.id == id }
    }

    private var importedSourceURLs: Set<String> {
        Set(store.recipes.compactMap(\.sourceURL).map(Self.normalizedURLKey))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search categories", text: $search).textFieldStyle(.roundedBorder)
                Spacer()
                Button("Import all cached") { harvest.importAllReadyCategories() }
                    .disabled(harvest.readyCategoryCount == 0 || harvest.isImporting)
            }.padding()
            Divider()
            if categories.isEmpty && cuisineCategories.isEmpty {
                MacEmpty(title: "No mined categories yet",
                         message: "Find recipes from a website. Categories discovered during that bounded scan are cached here automatically.",
                         systemImage: "square.grid.2x2")
            } else {
                HSplitView {
                    List(selection: $selectedCategoryID) {
                        Section("Cuisine collections") {
                            ForEach(cuisineCategories) { cuisine in
                                let count = harvest.cachedRecipes(forCuisine: cuisine).count
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cuisine.name).font(.headline).lineLimit(1)
                                    Text("Multiple recipe websites")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Label(count > 0 ? "\(count) cached recipes" : "Ready to discover",
                                          systemImage: count > 0 ? "checkmark.circle.fill" : "globe")
                                        .font(.caption2)
                                        .foregroundStyle(count > 0 ? MacTheme.green : MacTheme.gold)
                                }
                                .padding(.vertical, 5)
                                .tag(Self.cuisinePrefix + cuisine.id)
                            }
                        }
                        Section("Website categories") {
                            ForEach(categories) { category in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.name).font(.headline).lineLimit(2)
                                    Text("\(category.sourceName) · \(category.group ?? "Other")")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Label(category.isReady ? "\(category.recipeCount) cached recipes" : "Not scanned",
                                          systemImage: category.isReady ? "checkmark.circle.fill" : "magnifyingglass")
                                        .font(.caption2)
                                        .foregroundStyle(category.isReady ? MacTheme.green : Color.secondary)
                                }
                                .padding(.vertical, 5)
                                .tag(category.id)
                            }
                        }
                    }
                    .frame(minWidth: 220, idealWidth: 340)
                    .layoutPriority(0)

                    if let cuisine = selectedCuisine {
                        cuisineDetail(cuisine)
                            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                    } else if let category = selectedCategory {
                        categoryDetail(category)
                            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                    } else {
                        ContentUnavailableView("Select a category", systemImage: "square.grid.2x2",
                                               description: Text("Its cached recipes will appear here."))
                            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                    }
                }
            }
        }
        .onAppear { selectFirstVisibleCategory() }
        .onChange(of: search) { _, _ in selectFirstVisibleCategory() }
        .onChange(of: selectedCategoryID) { _, _ in recipeSearch = "" }
    }

    @ViewBuilder
    private func cuisineDetail(_ cuisine: RecipeBrowseCategory) -> some View {
        let cached = harvest.cachedRecipes(forCuisine: cuisine)
        let term = recipeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = term.isEmpty ? cached : cached.filter {
            Self.recipeTitle(for: $0).localizedCaseInsensitiveContains(term)
                || $0.localizedCaseInsensitiveContains(term)
        }
        let websiteCount = Set(cached.compactMap { URL(string: $0)?.host() }).count

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cuisine.name).font(.title2.bold())
                    Text("Cuisine collection · \(websiteCount) website\(websiteCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Text("\(cached.count) cached recipe\(cached.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Find & Import More") { harvest.findAndImportCuisine(cuisine) }
                    .disabled(harvest.isAutopilotRunning)
                Button(cached.isEmpty ? "Find & Import" : "Import Cached") {
                    harvest.importCachedCuisine(cuisine)
                }
                .buttonStyle(.borderedProminent)
                .disabled(harvest.isAutopilotRunning)
            }
            .padding()
            Divider()
            if cached.isEmpty {
                ContentUnavailableView(
                    "No cached \(cuisine.name) recipes yet",
                    systemImage: "globe.americas",
                    description: Text("Find & Import scans several recipe websites, keeps image-backed recipes, skips duplicates, and fills this category automatically.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("Search \(cuisine.name) recipes", text: $recipeSearch)
                    .textFieldStyle(.roundedBorder).padding()
                List(visible, id: \.self) { cachedRecipeRow($0) }
                    .overlay { if visible.isEmpty { ContentUnavailableView.search(text: recipeSearch) } }
            }
        }
        .background(.background.opacity(0.18))
    }

    @ViewBuilder
    private func categoryDetail(_ category: SourceCategory) -> some View {
        let cached = harvest.cachedRecipes(for: category)
        let term = recipeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = term.isEmpty ? cached : cached.filter {
            Self.recipeTitle(for: $0).localizedCaseInsensitiveContains(term)
                || $0.localizedCaseInsensitiveContains(term)
        }

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name).font(.title2.bold()).textSelection(.enabled)
                    Text("\(category.sourceName) · \(category.group ?? "Other")")
                        .foregroundStyle(.secondary)
                    Text("\(cached.count) cached recipe\(cached.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let page = URL(string: category.url) {
                    Link(destination: page) { Label("Open category", systemImage: "safari") }
                }
                Button(category.isReady ? "Import all" : "Scan category") {
                    harvest.importCategory(category)
                }
                .buttonStyle(.borderedProminent)
                .disabled(harvest.isImporting)
            }
            .padding()

            Divider()
            if cached.isEmpty {
                ContentUnavailableView("Category not scanned", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Scan this category to find and cache its recipes."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextField("Search recipes in this category", text: $recipeSearch)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                List(visible, id: \.self) { rawURL in
                    cachedRecipeRow(rawURL)
                }
                .overlay {
                    if visible.isEmpty {
                        ContentUnavailableView.search(text: recipeSearch)
                    }
                }
            }
        }
        .background(.background.opacity(0.18))
    }

    private func cachedRecipeRow(_ rawURL: String) -> some View {
        let imported = importedSourceURLs.contains(Self.normalizedURLKey(rawURL))
        return HStack(spacing: 12) {
            Image(systemName: imported ? "checkmark.circle.fill" : "fork.knife.circle")
                .font(.title3)
                .foregroundStyle(imported ? MacTheme.green : MacTheme.low)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.recipeTitle(for: rawURL)).font(.headline).lineLimit(2)
                Text(URL(string: rawURL)?.host(percentEncoded: false) ?? rawURL)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if imported {
                Text("In library").font(.caption).foregroundStyle(MacTheme.green)
            }
            if let url = URL(string: rawURL) {
                Link(destination: url) { Image(systemName: "safari") }.help("Open recipe page")
            }
            Button(imported ? "Re-import" : "Import") { harvest.importDirect([rawURL]) }
                .disabled(harvest.isImporting)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Import recipe") { harvest.importDirect([rawURL]) }
            if let url = URL(string: rawURL) { Link("Open recipe page", destination: url) }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rawURL, forType: .string)
            }
        }
    }

    private func selectFirstVisibleCategory() {
        let validCuisineIDs = Set(cuisineCategories.map { Self.cuisinePrefix + $0.id })
        let validSourceIDs = Set(categories.map(\.id))
        if selectedCategoryID == nil
            || (!validCuisineIDs.contains(selectedCategoryID ?? "") && !validSourceIDs.contains(selectedCategoryID ?? "")) {
            selectedCategoryID = cuisineCategories.first.map { Self.cuisinePrefix + $0.id } ?? categories.first?.id
            recipeSearch = ""
        }
    }

    private static func normalizedURLKey(_ raw: String) -> String {
        guard let url = URL(string: raw) else { return raw.lowercased() }
        return URLSafety.normalized(url).absoluteString.lowercased()
    }

    private static func recipeTitle(for rawURL: String) -> String {
        guard let url = URL(string: rawURL) else { return rawURL }
        let slug = url.pathComponents.last(where: { $0 != "/" && !$0.isEmpty }) ?? url.host() ?? rawURL
        let words = slug.removingPercentEncoding?.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ") ?? slug
        return words.split(separator: " ").map { word in
            let lower = word.lowercased()
            return lower == "and" || lower == "with" || lower == "of" ? lower : lower.capitalized
        }.joined(separator: " ")
    }
}
