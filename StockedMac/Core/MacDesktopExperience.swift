import Foundation
import Observation

nonisolated enum MacRecipeWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case list = "List"
    case table = "Table"

    var id: String { rawValue }
    var systemImage: String { self == .list ? "list.bullet" : "tablecells" }
}

nonisolated enum MacContentDensity: String, CaseIterable, Identifiable, Sendable {
    case compact = "Compact"
    case comfortable = "Comfortable"

    var id: String { rawValue }
    var rowPadding: CGFloat { self == .compact ? 1 : 5 }
    var thumbnailSize: CGFloat { self == .compact ? 34 : 44 }
}

/// Window-wide desktop preferences and transient presentation state. Keeping these in
/// one environment model makes the menu bar, command palette, toolbar, and recipe
/// workspace agree instead of maintaining parallel AppStorage and sheet flags.
@MainActor
@Observable
final class MacDesktopExperience {
    private enum Key {
        static let recipeMode = "mac_recipe_workspace_mode_v1"
        static let density = "mac_content_density_v1"
        static let inspector = "mac_recipe_inspector_visible_v1"
    }

    var isCommandPalettePresented = false
    var isImportCenterPresented = false
    var isInspectorPresented: Bool {
        didSet { defaults.set(isInspectorPresented, forKey: Key.inspector) }
    }
    var recipeMode: MacRecipeWorkspaceMode {
        didSet { defaults.set(recipeMode.rawValue, forKey: Key.recipeMode) }
    }
    var density: MacContentDensity {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recipeMode = MacRecipeWorkspaceMode(
            rawValue: defaults.string(forKey: Key.recipeMode) ?? ""
        ) ?? .list
        density = MacContentDensity(
            rawValue: defaults.string(forKey: Key.density) ?? ""
        ) ?? .comfortable
        isInspectorPresented = defaults.object(forKey: Key.inspector) as? Bool ?? true
    }
}
