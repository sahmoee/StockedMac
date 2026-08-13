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
                .frame(minWidth: MacTheme.minWindowWidth,
                       minHeight: MacTheme.minWindowHeight)
                // A gentle fade rather than a hard swap, so signing in doesn't feel like
                // the window was replaced underneath you.
                .animation(.easeInOut(duration: 0.22), value: auth.isSignedIn)
                .task {
                    // `.task` on the root view can run again if the window is recreated,
                    // so this is guarded — loading twice would be harmless but pulling
                    // twice is a wasted round trip.
                    guard !didStart else { return }
                    didStart = true
                    store.sync = sync
                    store.writerID = sync.memberID
                    store.load()
                    // The Harvester needs to know where the kitchen is, or an approved
                    // recipe stays in the Harvester's own library until somebody presses
                    // "Add to Stocked". Handing it the store here is what makes a
                    // harvested recipe appear on the phone by itself.
                    harvest.kitchen = store
                    harvest.start()
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
                    harvest.syncKitchenToCloud(store.recipes)
                }
        }
        .defaultSize(width: 1140, height: 760)
        // The sidebar plus a detail pane needs a floor; below it the layout stops being
        // useful rather than merely tight.
        .windowResizability(.contentMinSize)
        .commands { MacCommands(store: store, sync: sync, navigation: navigation, harvest: harvest) }

        Settings {
            MacSettingsView()
                .environment(store)
                .environment(sync)
                .environment(auth)
                .frame(width: 560, height: 520)
        }

        // A glanceable summary that doesn't require the window. The whole reason to have
        // a Mac app open all day is that the answer to "what do I need to use up?" should
        // cost one click, not a window switch.
        MenuBarExtra {
            MacMenuBarView()
                .environment(store)
                .environment(sync)
                .frame(width: 300)
        } label: {
            Image(systemName: "refrigerator")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar panel

struct MacMenuBarView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync

    private var soon: [LocalInventoryItem] { Array(store.expiringSoon.prefix(6)) }
    private var low:  [LocalInventoryItem] { Array(store.lowStock.prefix(4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let metrics = store.metrics

            HStack {
                Text("Stocked").font(.headline)
                Spacer()
                Text("\(metrics.stockPercent)% stocked")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if store.inventory.isEmpty {
                Text("Nothing in the kitchen yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                if !soon.isEmpty {
                    MacSectionHeader(title: "Use soon")
                    ForEach(soon) { item in
                        HStack {
                            Circle()
                                .fill(MacTheme.expiryColor(daysLeft: item.daysUntilExpiry))
                                .frame(width: 6, height: 6)
                            Text(item.name).font(.callout).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(expiryLabel(item)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !low.isEmpty {
                    MacSectionHeader(title: "Running low")
                    ForEach(low) { item in
                        HStack {
                            Text(item.name).font(.callout).lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int(item.effectiveLevel * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if soon.isEmpty && low.isEmpty {
                    Text("Nothing needs attention. \(metrics.stockStatusSentence).")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func expiryLabel(_ item: LocalInventoryItem) -> String {
        guard let days = item.daysUntilExpiry else { return "" }
        if days < 0  { return "expired" }
        if days == 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "\(days) days"
    }
}
