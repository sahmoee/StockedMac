// MacDesignVariantModel.swift — the optional design variants, as plain data.
//
// Foundation only, so `scripts/test-design-variants.swift` can compile it on its own.
// `current` is the shipped native Mac look (system appearance, system type, gold accent)
// and is always the default. The identifiers and the defaults key match Stocked iOS so a
// selection means the same thing on both platforms.

import Foundation

nonisolated enum MacDesignVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case current
    case pantryJournal
    case kitchenStandard
    case eveningTable

    static let defaultsKey = "stocked.designVariant"

    var id: String { rawValue }

    /// Missing, empty or unknown values (a newer build, a hand-edited file) fall back to
    /// the shipped design instead of failing.
    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .current
    }

    static func stored(in defaults: UserDefaults = .standard) -> MacDesignVariant {
        MacDesignVariant(storedValue: defaults.string(forKey: defaultsKey))
    }

    /// Backup export: only an explicit, known selection travels in a kitchen file.
    static func backupValue(from defaults: UserDefaults) -> String? {
        guard let raw = defaults.string(forKey: defaultsKey), MacDesignVariant(rawValue: raw) != nil else { return nil }
        return raw
    }

    /// Backup import: older files (nil) leave the selection alone; unknown values become Current.
    static func restoreBackupValue(_ value: String?, into defaults: UserDefaults) {
        guard let value else { return }
        defaults.set(MacDesignVariant(storedValue: value).rawValue, forKey: defaultsKey)
    }

    var title: String {
        switch self {
        case .current:         return "Current"
        case .pantryJournal:   return "Pantry Journal"
        case .kitchenStandard: return "Kitchen Standard"
        case .eveningTable:    return "Evening Table"
        }
    }

    var summary: String {
        switch self {
        case .current:         return "The standard Mac look. Follows your system Light or Dark appearance."
        case .pantryJournal:   return "Warm cream, forest-green actions, serif headings and roomy grouped sections."
        case .kitchenStandard: return "Crisp white and green, system type, compact section bars and squared controls."
        case .eveningTable:    return "Dark stone and brass with large serif recipe titles. Always dark."
        }
    }

    /// Evening Table is a dark composition. Every other design keeps the system appearance.
    var forcesDarkAppearance: Bool { self == .eveningTable }

    /// Component corner radius; nil keeps every existing Current value.
    var componentRadius: Double? {
        switch self {
        case .current: return nil
        case .pantryJournal: return 16
        case .kitchenStandard: return 8
        case .eveningTable: return 12
        }
    }

    var chipRadius: Double? {
        switch self {
        case .current: return nil
        case .pantryJournal: return 10
        case .kitchenStandard: return 4
        case .eveningTable: return 8
        }
    }

    /// Kitchen Standard draws section headings as compact bars and tightens rows.
    var compactSections: Bool { self == .kitchenStandard }

    /// Heading/body families. nil = the system font (unchanged from Current).
    var headingFamily: String? {
        switch self {
        case .pantryJournal, .eveningTable: return "Georgia"
        case .current, .kitchenStandard: return nil
        }
    }

    var bodyFamily: String? { self == .pantryJournal ? "AvenirNext-Regular" : nil }

    /// Recipe-first emphasis: hero photo and title scale for the recipe detail.
    var recipeHeroMaxHeight: Double {
        switch self {
        case .current: return 260
        case .pantryJournal: return 240
        case .kitchenStandard: return 200
        case .eveningTable: return 340
        }
    }

    var recipeTitleSize: Double {
        switch self {
        case .current: return 21
        case .pantryJournal: return 28
        case .kitchenStandard: return 22
        case .eveningTable: return 30
        }
    }

    func palette(dark: Bool) -> MacVariantPalette? {
        switch self {
        case .current: return nil
        case .pantryJournal: return dark ? .pantryJournalDark : .pantryJournal
        case .kitchenStandard: return dark ? .kitchenStandardDark : .kitchenStandard
        case .eveningTable: return .eveningTable
        }
    }
}

/// Hex values from the approved design contracts (StockedDesign-20261014/*/DESIGN.md);
/// dark Journal/Standard and the `success` role are derived, matching Stocked iOS.
nonisolated struct MacVariantPalette: Equatable, Sendable {
    let bg: UInt32, surface: UInt32, ink: UInt32, muted: UInt32, line: UInt32
    let accent: UInt32, onAccent: UInt32, soft: UInt32
    let warn: UInt32, danger: UInt32, success: UInt32

    static let pantryJournal = MacVariantPalette(
        bg: 0xF5F0E7, surface: 0xFFFCF6, ink: 0x2B3028, muted: 0x626A5B, line: 0xDCDCCF,
        accent: 0x36533C, onAccent: 0xFFFCF6, soft: 0xE8EBDD,
        warn: 0x9A4C2E, danger: 0xA83736, success: 0x3D6B47)
    static let pantryJournalDark = MacVariantPalette(
        bg: 0x181C17, surface: 0x222821, ink: 0xF1EEE4, muted: 0xB7BEAD, line: 0x3D473B,
        accent: 0xA9C79F, onAccent: 0x181C17, soft: 0x2B3529,
        warn: 0xE8B08A, danger: 0xF2A6A0, success: 0x9FD0A0)
    static let kitchenStandard = MacVariantPalette(
        bg: 0xF2F5F1, surface: 0xFFFFFF, ink: 0x182C24, muted: 0x55675E, line: 0xCCD8D0,
        accent: 0x195A47, onAccent: 0xFFFFFF, soft: 0xE3EEE7,
        warn: 0x8B4E17, danger: 0xAD3438, success: 0x2E7D4F)
    static let kitchenStandardDark = MacVariantPalette(
        bg: 0x0F1714, surface: 0x18221E, ink: 0xEEF4F0, muted: 0xA6B8AF, line: 0x2F3F38,
        accent: 0x79C6A9, onAccent: 0x0F1714, soft: 0x1F2D27,
        warn: 0xE6B27A, danger: 0xF3A3A6, success: 0x8FD3A8)
    static let eveningTable = MacVariantPalette(
        bg: 0x1B211E, surface: 0x252D28, ink: 0xF4F0E6, muted: 0xB6C1B8, line: 0x445148,
        accent: 0xD9B990, onAccent: 0x1B211E, soft: 0x354338,
        warn: 0xE4B787, danger: 0xF2ADA6, success: 0xA9D3AE)

    /// WCAG relative-luminance contrast ratio between two sRGB hex colors.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ value: UInt32) -> Double {
                let c = Double(value) / 255
                return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel((hex >> 16) & 0xFF)
                + 0.7152 * channel((hex >> 8) & 0xFF)
                + 0.0722 * channel(hex & 0xFF)
        }
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
