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
///
/// Build 114: also carries the recipe-manager tools' shared state (focused and visible
/// recipes, recently viewed, saved filters, display units and tool panels). All of it is
/// presentation state for this Mac — none of it is written into recipe records.
@MainActor
@Observable
final class MacDesktopExperience {
    private enum Key {
        static let recipeMode = "mac_recipe_workspace_mode_v1"
        static let density = "mac_content_density_v1"
        static let inspector = "mac_recipe_inspector_visible_v1"
        static let recent = "mac_recent_recipe_ids_v1"
        static let savedFilters = "mac_saved_recipe_filters_v1"
        static let measurement = "mac_measurement_system_v1"
    }

    static let recentLimit = 15

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

    // MARK: Recipe-manager tools (Build 114)

    /// The recipe currently selected in the main library, so menu commands (Print,
    /// Duplicate, Edit) act on what the user can see.
    var focusedRecipeID: UUID?
    /// The current filtered/sorted Recipes rows, used by Bulk Edit and Markdown export.
    var visibleRecipeIDs: [UUID] = []
    /// Asks the Recipes workspace to select (and scroll to) a recipe.
    var pendingRecipeSelection: UUID?
    /// Asks the Recipes workspace to open its editor for a recipe.
    var pendingEditRecipeID: UUID?
    /// Asks the Recipes workspace to apply a saved filter.
    var pendingSavedFilter: MacSavedRecipeFilter?

    var isLibraryHealthPresented = false
    var isDuplicateFinderPresented = false
    var isTagManagerPresented = false
    var isBulkEditPresented = false
    var isActivityLogPresented = false

    private(set) var recentRecipeIDs: [UUID] {
        didSet { defaults.set(recentRecipeIDs.map(\.uuidString), forKey: Key.recent) }
    }
    private(set) var savedFilters: [MacSavedRecipeFilter] {
        didSet {
            if let data = try? JSONEncoder().encode(savedFilters) { defaults.set(data, forKey: Key.savedFilters) }
        }
    }
    var measurementSystem: MacMeasurementSystem {
        didSet { defaults.set(measurementSystem.rawValue, forKey: Key.measurement) }
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
        recentRecipeIDs = (defaults.stringArray(forKey: Key.recent) ?? [])
            .compactMap(UUID.init(uuidString:))
        savedFilters = defaults.data(forKey: Key.savedFilters)
            .flatMap { try? JSONDecoder().decode([MacSavedRecipeFilter].self, from: $0) } ?? []
        measurementSystem = MacMeasurementSystem(
            rawValue: defaults.string(forKey: Key.measurement) ?? ""
        ) ?? .asWritten
    }

    // MARK: Recently viewed

    func noteViewed(_ id: UUID) {
        guard recentRecipeIDs.first != id else { return }
        var next = recentRecipeIDs.filter { $0 != id }
        next.insert(id, at: 0)
        recentRecipeIDs = Array(next.prefix(Self.recentLimit))
    }

    func clearRecent() { recentRecipeIDs = [] }

    /// Drops recipes that no longer exist so the menu never offers a dead entry.
    func recentRecipes(in recipes: [UserRecipe]) -> [UserRecipe] {
        let byID = Dictionary(recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return recentRecipeIDs.compactMap { byID[$0] }
    }

    // MARK: Saved filters

    func saveFilter(_ filter: MacSavedRecipeFilter) {
        var next = savedFilters.filter {
            $0.name.compare(filter.name, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        next.append(filter)
        savedFilters = next.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func removeFilter(id: UUID) {
        savedFilters.removeAll { $0.id == id }
    }

    // MARK: Library navigation helpers

    func reveal(_ id: UUID) {
        pendingRecipeSelection = id
        noteViewed(id)
    }
}
