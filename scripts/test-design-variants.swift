// Native checks for the optional Mac design variants.
// Run: swiftc -parse-as-library StockedMac/Core/MacDesignVariantModel.swift scripts/test-design-variants.swift -o /tmp/stocked-design-variant-checks && /tmp/stocked-design-variant-checks
import Foundation
import AppKit

@main struct DesignVariantChecks {
    static var count = 0
    static func check(_ result: Bool, _ message: String) {
        guard result else { fatalError("FAILED: \(message)") }
        count += 1
    }

    static func main() {
        let suite = "stocked.design-variant-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Stable identifiers shared with Stocked iOS.
        check(MacDesignVariant.allCases.map(\.rawValue) == ["current", "pantryJournal", "kitchenStandard", "eveningTable"], "identifiers")
        check(MacDesignVariant.defaultsKey == "stocked.designVariant", "defaults key")

        // Default for new and existing users, and safe fallback.
        check(MacDesignVariant.stored(in: defaults) == .current, "missing value is Current")
        for bad in ["", "neon", "PantryJournal", "current "] {
            check(MacDesignVariant(storedValue: bad) == .current, "unknown '\(bad)' falls back to Current")
        }
        defaults.set("kitchenStandard", forKey: MacDesignVariant.defaultsKey)
        check(MacDesignVariant.stored(in: defaults) == .kitchenStandard, "persisted selection reads back")

        // Current preserves the shipped geometry, type and appearance.
        let current = MacDesignVariant.current
        check(current.palette(dark: false) == nil && current.palette(dark: true) == nil, "Current has no palette override")
        check(current.componentRadius == nil && current.chipRadius == nil, "Current keeps legacy radii")
        check(current.headingFamily == nil && current.bodyFamily == nil, "Current keeps system type")
        check(!current.forcesDarkAppearance, "Current follows system appearance")
        check(current.recipeHeroMaxHeight == 260 && current.recipeTitleSize == 21, "Current recipe detail sizes unchanged")

        // Variant mapping.
        check(MacDesignVariant.pantryJournal.componentRadius == 16, "Journal 16")
        check(MacDesignVariant.kitchenStandard.componentRadius == 8, "Standard 8")
        check(MacDesignVariant.eveningTable.componentRadius == 12, "Evening 12")
        check(MacDesignVariant.kitchenStandard.compactSections, "Standard compact sections")
        check(MacDesignVariant.eveningTable.forcesDarkAppearance, "Evening is dark")
        check(MacDesignVariant.pantryJournal.headingFamily == "Georgia" && MacDesignVariant.pantryJournal.bodyFamily == "AvenirNext-Regular", "Journal type")
        check(MacDesignVariant.kitchenStandard.headingFamily == nil, "Standard system type")
        check(MacDesignVariant.eveningTable.recipeHeroMaxHeight > MacDesignVariant.current.recipeHeroMaxHeight, "Evening recipe-first hero")
        check(MacDesignVariant.pantryJournal.palette(dark: false)?.accent == 0x36533C, "Journal accent contract")
        check(MacDesignVariant.kitchenStandard.palette(dark: false)?.bg == 0xF2F5F1, "Standard bg contract")
        check(MacDesignVariant.eveningTable.palette(dark: false) == MacDesignVariant.eveningTable.palette(dark: true), "Evening single palette")
        check(MacDesignVariant.eveningTable.palette(dark: true)?.accent == 0xD9B990, "Evening accent contract")

        // Contrast for text/action/status pairs in every variant and appearance.
        for variant in MacDesignVariant.allCases {
            for dark in [false, true] {
                guard let p = variant.palette(dark: dark) else { continue }
                let label = "\(variant.rawValue) dark=\(dark)"
                check(MacVariantPalette.contrast(p.ink, p.bg) >= 7, "\(label) ink/bg")
                check(MacVariantPalette.contrast(p.ink, p.surface) >= 7, "\(label) ink/surface")
                check(MacVariantPalette.contrast(p.muted, p.surface) >= 4.5, "\(label) muted/surface")
                check(MacVariantPalette.contrast(p.muted, p.bg) >= 4.5, "\(label) muted/bg")
                check(MacVariantPalette.contrast(p.onAccent, p.accent) >= 4.5, "\(label) primary action label")
                check(MacVariantPalette.contrast(p.accent, p.surface) >= 4.5, "\(label) accent text on surface")
                check(MacVariantPalette.contrast(p.accent, p.bg) >= 4.5, "\(label) accent text on bg")
                check(MacVariantPalette.contrast(p.warn, p.surface) >= 4.5, "\(label) warn label")
                check(MacVariantPalette.contrast(p.danger, p.surface) >= 4.5, "\(label) danger label")
                check(MacVariantPalette.contrast(p.success, p.surface) >= 4.5, "\(label) success label")
                check(MacVariantPalette.contrast(p.ink, p.soft) >= 7, "\(label) section bar text")
            }
        }

        // Backup format: optional, explicit, tolerant.
        defaults.removeObject(forKey: MacDesignVariant.defaultsKey)
        check(MacDesignVariant.backupValue(from: defaults) == nil, "untouched users export no design key")
        defaults.set("eveningTable", forKey: MacDesignVariant.defaultsKey)
        check(MacDesignVariant.backupValue(from: defaults) == "eveningTable", "explicit selection exported")
        defaults.set("futureDesign", forKey: MacDesignVariant.defaultsKey)
        check(MacDesignVariant.backupValue(from: defaults) == nil, "unknown stored value is not exported")
        defaults.set("pantryJournal", forKey: MacDesignVariant.defaultsKey)
        MacDesignVariant.restoreBackupValue(nil, into: defaults)
        check(MacDesignVariant.stored(in: defaults) == .pantryJournal, "older backup keeps the current selection")
        MacDesignVariant.restoreBackupValue("kitchenStandard", into: defaults)
        check(MacDesignVariant.stored(in: defaults) == .kitchenStandard, "backup restores selection")
        MacDesignVariant.restoreBackupValue("somethingNewer", into: defaults)
        check(defaults.string(forKey: MacDesignVariant.defaultsKey) == "current", "unknown backup value restores Current")

        // Variant identifiers survive a JSON round trip.
        let data = try! JSONEncoder().encode(MacDesignVariant.allCases)
        check(try! JSONDecoder().decode([MacDesignVariant].self, from: data) == MacDesignVariant.allCases, "Codable round trip")

        check(NSFont(name: "AvenirNext-Regular", size: 13) != nil, "Journal body face resolves on macOS")
        print("Design variant checks passed: \(count)")
    }
}
