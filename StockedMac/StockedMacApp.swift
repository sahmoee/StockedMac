// StockedMacApp.swift — the entry point for Stocked for Mac.
//
// This is a standalone macOS app, not the iPhone app running in a window. It has its own
// project, its own bundle identifier (com.sowens.StockedMac) and its own version line.
// What it shares with the phone is the data: join the same household code and the two
// stay in step over the same Worker endpoints.
//
// Scenes:
//   • the main window   — the kitchen, in a source-list layout
//   • Settings          — the standard ⌘, panel, because Mac users look there
//   • a menu bar item   — what's expiring, without bringing the window forward
//
// Deployment target is macOS 14. That is deliberate: nothing here needs an API newer
// than Sonoma, so the app runs on the Macs people actually have rather than only the
// newest one.

import SwiftUI
import AppKit

@main
struct StockedMacApp: App {

    @State private var store = MacKitchenStore()
    @State private var sync  = MacHouseholdSync()
    /// Owned here, not in the window, so the menu bar commands and the sidebar share one
    /// selection. ⌘3 has to move the same highlight the user can see.
    @State private var navigation = MacNavigation()
    @State private var auth = MacAppleAuth()
    /// The recipe Harvester (formerly the separate Stocked Companion app). Owned here so
    /// the menu bar commands, the sidebar badge and the Harvester screen share one model.
    @State private var harvest = HarvestModel()
    @State private var catalog = CatalogModel()
    @State private var desktop = MacDesktopExperience()
    @State private var didStart = false

    var body: some Scene {

        WindowGroup {
            Group {
                if auth.isSignedIn {
                    MacRootView()
                } else {
                    MacWelcomeView()
                }
            }
                .environment(store)
                .environment(sync)
                .environment(navigation)
                .environment(auth)
                .environment(harvest)
                .environment(catalog)
                .environment(desktop)
                .frame(minWidth: MacTheme.minWindowWidth,
                       minHeight: MacTheme.minWindowHeight)
                // A gentle fade rather than a hard swap, so signing in doesn't feel like
                // the window was replaced underneath you.
                .animation(.easeInOut(duration: 0.22), value: auth.isSignedIn)
                .onReceive(NotificationCenter.default.publisher(for: .macInventoryNeedsCatalogEnrichment)) { note in
                    guard let id = note.object as? UUID else { return }
                    Task { await catalog.enrichInventoryItem(id: id, store: store) }
                }
                .task {
                    // `.task` on the root view can run again if the window is recreated,
                    // so this is guarded — loading twice would be harmless but pulling
                    // twice is a wasted round trip.
                    guard !didStart else { return }
                    didStart = true
                    store.sync = sync
                    store.writerID = sync.memberID
                    store.load()
                    MacPublicRecipeSync.shared.start(store: store)
                    // StockedMac is recipe-only. Keep household transport compatible
                    // with iOS while excluding every non-recipe collection.
                    sync.syncInventory = false
                    sync.syncGrocery = false
                    sync.syncPlan = false
                    sync.syncRecipes = true
                    sync.persistPreferences()
                    // The Harvester needs to know where the kitchen is, or an approved
                    // recipe stays in the Harvester's own library until somebody presses
                    // "Add to Stocked". Handing it the store here is what makes a
                    // harvested recipe appear on the phone by itself.
                    harvest.kitchen = store
                    harvest.start()
                    catalog.startServerInboxConsumer()
                    // The session is only needed by the AI routes, and getting it wrong
                    // must never block the kitchen from opening — so it is fired off
                    // rather than awaited in line with the pull.
                    Task { await auth.refreshSessionIfNeeded() }
                    if sync.isJoined {
                        // Not a plain pull. If this Mac is joined and holding nothing, the
                        // launch pull asks for the entire household with both watermarks at
                        // zero — the only question the server cannot answer "nothing new"
                        // to. That makes an empty joined Mac self-correcting on every
                        // launch, whatever an earlier build left on disk.
                        await sync.pullAtLaunch(into: store)
                        await sync.refreshPresence()
                        // Keeps this Mac within a few seconds of the phones for as long as
                        // the app is open, which is the whole point of a desktop app that
                        // lives in the corner of the screen all day.
                        sync.startAutoSync(store: store)
                    }
                    // Build 89 — clear out the retired recipe sources (the bundled Kaggle
                    // dataset and the "Sowens" curated feed). Deliberately AFTER the
                    // launch pull rather than before it: a joined Mac pulls the phone's
                    // whole library on launch, and sweeping first would just tidy up
                    // immediately ahead of the arrival of the very rows being swept.
                    // Outside the `isJoined` branch so an unjoined Mac still gets swept.
                    MacRecipePurge.run(store: store)
                    // Backfill the full Recipes-sidebar library after pull/purge. Previous
                    // builds only published newly approved Harvester drafts, and the Worker
                    // also capped its index at 500, so an 882-recipe kitchen could never be
                    // fully available to iPhone/iPad. Upserts are idempotent by recipe UUID.
                    // Let the window become interactive before starting maintenance.
                    // These jobs used to stack during launch and briefly pushed the app
                    // above a gigabyte while full catalog snapshots were also encoding.
                    Task {
                        try? await Task.sleep(for: .seconds(8))
                        harvest.syncKitchenToCloud(store.recipes, force: false)
                        if catalog.isBulkImportEnabled {
                            // The continuous importer already enriches as it walks sources;
                            // do only a small rotating retroactive pass alongside it.
                            await catalog.enrichAllExisting(batchSize: 3)
                        } else {
                            await catalog.enrichAllExisting(batchSize: 8)
                        }
                        await catalog.enrichInventoryBatch(store: store, limit: 5)
                        catalog.resumeBulkImportIfEnabled()
                    }
                }
        }
        .defaultSize(width: 1140, height: 760)
        // The sidebar plus a detail pane needs a floor; below it the layout stops being
        // useful rather than merely tight.
        .windowResizability(.contentMinSize)
        .commands { MacCommands(store: store, sync: sync, navigation: navigation, harvest: harvest, desktop: desktop) }

        WindowGroup("Recipe", id: "recipe", for: UUID.self) { $recipeID in
            if let recipeID {
                MacDetachedRecipeView(recipeID: recipeID)
                    .environment(store)
                    .environment(sync)
                    .environment(navigation)
                    .environment(harvest)
                    .environment(desktop)
                    .frame(minWidth: 560, minHeight: 460)
            } else {
                MacEmpty(title: "Recipe unavailable", message: "Choose a recipe from the main window.", systemImage: "book")
            }
        }
        .defaultSize(width: 820, height: 720)

        Settings {
            MacSettingsView()
                .environment(store)
                .environment(sync)
                .environment(auth)
                .environment(desktop)
                .frame(minWidth: 560, idealWidth: 680, minHeight: 520, idealHeight: 620)
        }

        MenuBarExtra("Stocked", systemImage: "refrigerator.fill") {
            MacMenuBarView()
                .environment(store)
                .environment(sync)
                .environment(harvest)
                .frame(width: 330)
        }
        .menuBarExtraStyle(.window)

    }
}

// MARK: - Menu bar panel

struct MacMenuBarView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync
    @Environment(HarvestModel.self) private var harvest

    private var recent: [UserRecipe] {
        Array(store.recipes.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }
    private var needsReview: Int {
        harvest.recipes.filter { $0.reviewState == .needsReview }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stocked").font(.headline)
                Spacer()
                Text("\(store.recipes.count) recipes")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                MacPill(text: "\(harvest.queuedURLCount) queued", tint: .secondary, systemImage: "link")
                MacPill(text: "\(needsReview) review", tint: needsReview > 0 ? .orange : .secondary,
                        systemImage: "checklist")
            }

            if recent.isEmpty {
                Text("No recipes on this Mac yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                MacSectionHeader(title: "Recently updated")
                ForEach(recent) { recipe in
                    HStack(spacing: 8) {
                        Image(systemName: recipe.isFavorited ? "star.fill" : "book.closed")
                            .foregroundStyle(recipe.isFavorited ? MacTheme.gold : .secondary)
                            .frame(width: 14)
                        Text(recipe.title).font(.callout).lineLimit(1)
                        Spacer(minLength: 8)
                        if !recipe.cuisine.isEmpty {
                            Text(recipe.cuisine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Stocked") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.canBecomeMain {
                        window.makeKeyAndOrderFront(nil)
                        break
                    }
                }
                Spacer()
                if sync.isJoined {
                    Button("Sync") {
                        Task { await sync.syncNow(store: store) }
                    }
                    .disabled(sync.status.isBusy)
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(14)
    }

}
