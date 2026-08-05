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
    var section: MacSection = .home
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { navigation.section },
                                set: { navigation.section = $0 ?? .home })) {
            Section("Kitchen") {
                ForEach(MacSection.allCases) { section in
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
        switch navigation.section {
        case .home, .cook, .insights, .tools, .household, .browse: return false
        default: return true
        }
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
