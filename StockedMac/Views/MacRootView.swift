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
    case categories = "Categories"
    case sync = "Recipe Sync"

    static let recipeManagerSections: [MacSection] = [.recipes, .browse, .categories, .sync]

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
        case .categories: return "square.grid.2x2"
        case .sync: return "arrow.triangle.2.circlepath"
        }
    }

    /// ⌘1 … ⌘6, wired up in MacCommands.
    var shortcut: KeyEquivalent {
        switch self {
        case .home:      return "1"
        case .inventory: return "2"
        case .grocery:   return "3"
        case .recipes:   return "4"
        case .plan:      return "5"
        case .cook:      return "6"
        case .insights:  return "7"
        case .tools:     return "8"
        case .household: return "9"
        case .browse:    return "b"
        case .categories: return "3"
        case .sync: return "4"
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
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync
    @Environment(HarvestModel.self) private var harvest

    /// Owned by the App so the menu bar commands can drive the same selection the sidebar
    /// shows. A window-local @State here would leave ⌘2 doing nothing.
    @Environment(MacNavigation.self) private var navigation
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: MacTheme.sidebarMin,
                                                ideal: MacTheme.sidebarIdeal,
                                                max: MacTheme.sidebarMax)
        } detail: {
            detail
                .frame(minWidth: 640, minHeight: 420)
        }
        .navigationTitle(navigation.section.rawValue)
        .toolbar { toolbarContent }
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
        case .categories:
            return harvest.allCategories.isEmpty ? nil : "\(harvest.allCategories.count)"
        case .sync:
            return sync.isJoined ? "\(max(1, sync.members.count))" : nil
        }
    }

    /// The sync state, parked at the bottom of the sidebar where it is visible but never
    /// in the way. A status line that has to be hunted for is a status line nobody trusts.
    private var syncFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(footerTint)
                    .frame(width: 6, height: 6)
                Text(sync.isJoined ? sync.status.message : "Not sharing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if sync.isJoined {
                    Button {
                        Task { await sync.syncNow(store: store) }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .disabled(sync.status.isBusy)
                    .help("Sync now")
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
        case .categories: MacRecipeCategoriesView()
        case .sync: MacRecipeSyncView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
    @State private var search = ""

    private var categories: [SourceCategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return harvest.allCategories }
        return harvest.allCategories.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.sourceName.localizedCaseInsensitiveContains(query)
                || ($0.group?.localizedCaseInsensitiveContains(query) ?? false)
        }
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
            if categories.isEmpty {
                MacEmpty(title: "No mined categories yet",
                         message: "Find recipes from a website. Categories discovered during that bounded scan are cached here automatically.",
                         systemImage: "square.grid.2x2")
            } else {
                List(categories) { category in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name).font(.headline)
                            Text("\(category.sourceName) · \(category.group ?? "Other")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(category.isReady ? "\(category.recipeCount) cached" : "Not scanned")
                            .font(.caption).foregroundStyle(.secondary)
                        Button(category.isReady ? "Import" : "Scan") {
                            harvest.importCategory(category)
                        }.disabled(harvest.isImporting)
                    }.padding(.vertical, 3)
                }
            }
        }
    }
}

private struct MacRecipeSyncView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync
    @Environment(HarvestModel.self) private var harvest
    @State private var code = ""
    @State private var name = ""

    var body: some View {
        Form {
            Section("Stocked iOS recipe sync") {
                Text("This Mac shares only recipes. Inventory, groceries, and meal plans stay out of this app.")
                    .foregroundStyle(.secondary)
                if sync.isJoined {
                    LabeledContent("Household", value: sync.householdName.nilIfBlank ?? sync.code)
                    LabeledContent("Status", value: sync.status.message)
                    LabeledContent("Recipes", value: "\(store.recipes.count)")
                    Button("Sync recipes now") {
                        Task {
                            await sync.syncNow(store: store)
                            harvest.syncKitchenToCloud(store.recipes)
                        }
                    }.disabled(sync.status.isBusy)
                    ForEach(sync.members) { member in
                        Label("\(member.name) · \(member.displayLabel)",
                              systemImage: member.isOnline ? "circle.fill" : "circle")
                    }
                } else {
                    TextField("Your name", text: $name)
                    TextField("Household code from Stocked iOS", text: $code)
                    Button("Join and sync recipes") {
                        Task {
                            if await sync.join(code: code, as: name) {
                                await sync.resyncEverything(into: store)
                                harvest.syncKitchenToCloud(store.recipes)
                            }
                        }
                    }
                }
            }
            Section("Historical repairs") {
                LabeledContent("Sources remaining", value: "\(harvest.retroactiveRefreshRemaining)")
                Stepper(value: Binding(
                    get: { harvest.settings.retroactiveRefreshBatchSize },
                    set: { harvest.settings.retroactiveRefreshBatchSize = $0; harvest.scheduleSettingsSave() }
                ), in: 1...100, step: 5) {
                    Text("Refresh \(harvest.settings.retroactiveRefreshBatchSize) per batch")
                }
                Button("Retry historical refresh") { harvest.restartHistoricalRefresh() }
                    .disabled(harvest.retroactiveRefreshRemaining == 0 || harvest.isImporting)
                Text("Future repair revisions normalize every saved recipe and reparse old source pages in a durable, shrinking queue. Recipes without recovered images remain excluded from sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding()
    }
}
