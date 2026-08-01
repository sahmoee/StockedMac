// MacRecipeMaintenanceSection.swift — the Recipes block in Settings ▸ Data.
//
// Deliberately its own file rather than more lines inside MacSettingsView, for one
// practical reason: MacSettingsView has drifted between trees (the Account tab exists in
// some and not others), so a whole-file replacement of it is a risky way to add three
// buttons. This is a self-contained `View` that reads only the store, so it can be
// dropped into whatever version of the Data form you happen to have with a single line:
//
//     MacRecipeMaintenanceSection()
//
// It renders a `Section`, so it must go inside a `Form` — directly alongside the other
// sections in `data`, not nested in one.
//
// Placement within that form is a judgement call worth writing down: it sits *after* the
// counts and *before* "Starting over". The counts are what make someone think "why do I
// have 102 recipes"; the answer belongs immediately underneath. Putting it below the
// erase button instead would file recipe housekeeping under nuclear options, which is
// both wrong and a good way to get someone to press the wrong thing.

import SwiftUI

struct MacRecipeMaintenanceSection: View {
    @Environment(MacKitchenStore.self) private var store

    var body: some View {
        Section {
            HStack {
                Button("Export recipes as a spreadsheet…") {
                    MacRecipeMaintenance.exportCSV(store: store)
                }
                Spacer()
            }
            HStack {
                Button("Remove recipes from a spreadsheet…") {
                    MacRecipeMaintenance.removeFromCSV(store: store)
                }
                Spacer()
            }
            HStack {
                Button(retiredLabel) {
                    MacRecipeMaintenance.removeRetiredSources(store: store)
                }
                .disabled(retiredCount == 0)
                Spacer()
            }
        } header: {
            Text("Recipes")
        } footer: {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Derived

    /// Recomputed on redraw rather than cached in `@State`. A cached count goes stale the
    /// moment a household sync brings more down, and this view is not on screen often
    /// enough for two array passes to be worth a staleness bug.
    private var retiredCount: Int {
        let counts = MacRecipeMaintenance.retiredSourceCounts(store: store)
        return counts.recipes + counts.saved
    }

    /// The number goes in the button title. A bare "Remove retired sources…" that does
    /// nothing when pressed is how you get someone convinced the feature is broken — and
    /// on a Mac where the launch sweep has already run, doing nothing is the normal case.
    private var retiredLabel: String {
        switch retiredCount {
        case 0:  return "No retired-source recipes to remove"
        case 1:  return "Remove 1 retired-source recipe…"
        default: return "Remove \(retiredCount) retired-source recipes…"
        }
    }

    private var footerText: String {
        let spreadsheet = "Export writes one row per recipe. Tick the remove column, hand "
                        + "the file back, and Stocked shows you the matches before anything "
                        + "goes."
        guard retiredCount > 0 else {
            return spreadsheet
                 + " Nothing in your library came from the two retired sources — Stocked "
                 + "checks each time it opens, so anything that arrives later from another "
                 + "device is cleared out on its own."
        }
        return spreadsheet
             + " The retired sources are the bulk food dataset and the small curated feed "
             + "early versions shipped with. These are cleared out automatically each time "
             + "Stocked opens, so the button is only for when you'd rather not wait."
    }
}
