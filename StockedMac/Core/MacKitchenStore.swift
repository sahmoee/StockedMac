// MacKitchenStore.swift — the Mac app's single source of truth.
//
// One @Observable object holding the whole kitchen: inventory, grocery list, recipes,
// week plan, cook history and the cooking profile. Every view reads from it; every
// mutation goes through it. That is deliberate — the iOS app learned the hard way that
// letting screens keep their own copies is how two views end up disagreeing about how
// many jars of peanut butter you own.
//
// Persistence is plain JSON in Application Support, one file per collection:
//
//   ~/Library/Application Support/com.sowens.StockedMac/
//       inventory.json  grocery.json  recipes.json  plan.json  history.json  profile.json
//
// Split by collection rather than one big blob so that saving a checkbox tick doesn't
// rewrite every recipe photo on disk. Writes are atomic (write to a sibling temp file,
// then rename) so a crash mid-save can never leave a half-written file — the previous
// good copy survives.
//
// The encoding is the SAME Codable shape the iOS app uses, because Models.swift is a
// byte-for-byte copy. That is what makes the JSON import path in Settings possible.
//
// Note on mutation: the collections do NOT use `didSet` to auto-save. The @Observable
// macro rewrites stored properties into accessors, which property observers cannot
// coexist with. Instead every mutating helper below calls `scheduleSave(_:)`, and
// anything writing a collection wholesale (household sync, import) calls `save()`.

import Foundation
import Observation
import os

/// A full backup of the kitchen. File scope rather than nested in the store, because a
/// type nested inside a `@MainActor` class inherits that isolation, which would collide
/// with Codable's non-isolated `init(from:)` requirement.
nonisolated struct MacKitchenSnapshot: Codable, Sendable {
    var inventory:    [LocalInventoryItem] = []
    var grocery:      [LocalGroceryItem]   = []
    var recipes:      [UserRecipe]         = []
    var savedRecipes: [GeneratedRecipe]    = []
    var plannedMeals: [PlannedMeal]        = []
    var pastMeals:    [LocalPastMeal]      = []
    var profile:      UserCookingProfile   = UserCookingProfile()
    var exportedAt:   Date                 = Date()
    var appVersion:   String               = ""

    init(
        inventory: [LocalInventoryItem] = [],
        grocery: [LocalGroceryItem] = [],
        recipes: [UserRecipe] = [],
        savedRecipes: [GeneratedRecipe] = [],
        plannedMeals: [PlannedMeal] = [],
        pastMeals: [LocalPastMeal] = [],
        profile: UserCookingProfile = UserCookingProfile(),
        exportedAt: Date = Date(),
        appVersion: String = ""
    ) {
        self.inventory = inventory
        self.grocery = grocery
        self.recipes = recipes
        self.savedRecipes = savedRecipes
        self.plannedMeals = plannedMeals
        self.pastMeals = pastMeals
        self.profile = profile
        self.exportedAt = exportedAt
        self.appVersion = appVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        inventory = try values.decodeIfPresent([LocalInventoryItem].self, forKey: .inventory) ?? []
        grocery = try values.decodeIfPresent([LocalGroceryItem].self, forKey: .grocery) ?? []
        recipes = try values.decodeIfPresent([UserRecipe].self, forKey: .recipes) ?? []
        savedRecipes = try values.decodeIfPresent([GeneratedRecipe].self, forKey: .savedRecipes) ?? []
        plannedMeals = try values.decodeIfPresent([PlannedMeal].self, forKey: .plannedMeals) ?? []
        pastMeals = try values.decodeIfPresent([LocalPastMeal].self, forKey: .pastMeals) ?? []
        profile = try values.decodeIfPresent(UserCookingProfile.self, forKey: .profile) ?? UserCookingProfile()
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        appVersion = try values.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
    }
}

@MainActor
@Observable
final class MacKitchenStore {

    // MARK: - Collections

    var inventory:    [LocalInventoryItem] = []
    var grocery:      [LocalGroceryItem]   = []
    var recipes:      [UserRecipe]         = []
    var savedRecipes: [GeneratedRecipe]    = []
    var plannedMeals: [PlannedMeal]        = []
    var pastMeals:    [LocalPastMeal]      = []
    var profile:      UserCookingProfile   = UserCookingProfile()

    /// Set at launch so mutations can record who made them. Matches the household sync
    /// engine's member id, which is what the last-write-wins tie-breaker compares.
    var writerID: String = ""

    /// Wired up by the app so deletions can leave tombstones for the next push. Weak, and
    /// ignored by observation: the sync engine holds no claim on the store's lifetime.
    @ObservationIgnored weak var sync: MacHouseholdSync?

    /// True while a load or import is in flight. Views show a spinner instead of an empty
    /// state, so a slow first launch doesn't look like data loss.
    private(set) var isLoading = false
    /// Last persistence failure, surfaced in Settings rather than swallowed.
    private(set) var lastSaveError: String?
    /// When the last successful write completed. Shown in Settings so "is it saving?" has
    /// an answer that isn't a shrug.
    private(set) var lastSavedAt: Date?

    // MARK: - Internals

    @ObservationIgnored
    private static let log = Logger(subsystem: "com.sowens.StockedMac", category: "store")

    private nonisolated enum Collection: String, CaseIterable, Sendable {
        case inventory, grocery, recipes, savedRecipes = "saved-recipes", plan, history, profile
        var filename: String { "\(rawValue).json" }
    }

    /// Collections changed since the last flush. Coalesced so a burst of edits — dragging
    /// a slider, typing in a field — costs one write, not one per keystroke.
    @ObservationIgnored private var dirty: Set<Collection> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// Suppresses saving while a bulk load is populating the arrays.
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private let directory: URL

    // MARK: - Init

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("com.sowens.StockedMac", isDirectory: true)
        }
        self.writerID = UserDefaults.standard.string(forKey: "mac_member_id_v1") ?? ""
        try? FileManager.default.createDirectory(at: self.directory,
                                                 withIntermediateDirectories: true)
    }

    /// Where the data lives, for the "Reveal in Finder" button in Settings.
    var storageDirectory: URL { directory }

    // MARK: - Load

    /// Reads every collection from disk. Safe to call more than once. A collection whose
    /// file is missing or unreadable is left at its default rather than aborting the load,
    /// so one corrupt file cannot cost you the other five.
    func load() {
        isLoading = true
        isRestoring = true
        var compactedRemoteRecipeImages = false
        defer {
            isRestoring = false
            isLoading = false
            if compactedRemoteRecipeImages {
                // Finish the one-time compaction before household work can re-enter the
                // store. The compact payload is small; writing it now also ensures the
                // next launch never has to decode the old 200+ MB base64 file again.
                dirty.insert(.recipes)
                flush()
            }
        }

        let decoder = JSONDecoder()

        if let data = read(.inventory),
           let value = try? decoder.decode([LocalInventoryItem].self, from: data) {
            inventory = value
        }
        if let data = read(.grocery),
           let value = try? decoder.decode([LocalGroceryItem].self, from: data) {
            grocery = value
        }
        if let data = read(.recipes),
           let value = try? decoder.decode([UserRecipe].self, from: data) {
            recipes = value.map { recipe in
                guard recipe.imageURL?.nilIfBlank != nil, recipe.imageData != nil else { return recipe }
                var compact = recipe
                compact.imageValidatedAt = compact.imageValidatedAt ?? Date()
                compact.imageData = nil
                compactedRemoteRecipeImages = true
                return compact
            }
        }
        if let data = read(.savedRecipes),
           let value = try? decoder.decode([GeneratedRecipe].self, from: data) {
            savedRecipes = value
        }
        if let data = read(.plan),
           let value = try? decoder.decode([PlannedMeal].self, from: data) {
            plannedMeals = value
        }
        if let data = read(.history),
           let value = try? decoder.decode([LocalPastMeal].self, from: data) {
            pastMeals = value
        }
        if let data = read(.profile),
           let value = try? decoder.decode(UserCookingProfile.self, from: data) {
            profile = value
        }
    }

    private func read(_ collection: Collection) -> Data? {
        let url = directory.appendingPathComponent(collection.filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            Self.log.error("read \(collection.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Save

    /// Marks everything dirty and flushes. This is the entry point the household sync
    /// engine calls after folding a remote payload in, and the one views call after
    /// editing a value through a binding.
    func save() {
        guard !isRestoring else { return }
        dirty.formUnion(Collection.allCases)
        scheduleFlush()
    }

    /// Writes pending changes immediately. Called on app termination and before an export,
    /// where "in about half a second" isn't good enough.
    func saveNow() {
        flushTask?.cancel()
        flushTask = nil
        flush()
    }

    private func scheduleSave(_ collection: Collection) {
        guard !isRestoring else { return }
        dirty.insert(collection)
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            // Long enough to coalesce a burst of edits, short enough that a force-quit a
            // second after typing still has the data.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.flushTask = nil
            self.flush()
        }
    }

    private func flush() {
        guard !dirty.isEmpty else { return }
        let pending = dirty
        dirty.removeAll()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var failure: String?
        for collection in pending {
            do {
                let data: Data
                switch collection {
                case .inventory: data = try encoder.encode(inventory)
                case .grocery:   data = try encoder.encode(grocery)
                case .recipes:   data = try encoder.encode(recipes)
                case .savedRecipes: data = try encoder.encode(savedRecipes)
                case .plan:      data = try encoder.encode(plannedMeals)
                case .history:   data = try encoder.encode(pastMeals)
                case .profile:   data = try encoder.encode(profile)
                }
                try write(data, to: collection)
            } catch {
                failure = error.localizedDescription
                Self.log.error("save \(collection.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        lastSaveError = failure
        if failure == nil { lastSavedAt = Date() }
    }

    private func write(_ data: Data, to collection: Collection) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `.atomic` writes to a temp file in the same directory and renames it into place.
        try data.write(to: directory.appendingPathComponent(collection.filename),
                       options: [.atomic])
    }

    // MARK: - Stamping
    //
    // Every mutation records when it happened and who did it. The household merge is
    // last-write-wins with the writer id as tie-breaker, so an edit that forgets to stamp
    // will silently lose to a stale copy on another device.

    private var nowMillis: Double { Date().timeIntervalSince1970 * 1000 }

    private func stampInventory(at index: Int) {
        inventory[index].updatedAt = nowMillis
        inventory[index].lastWriterID = writerID
        scheduleSave(.inventory)
    }
    private func stampGrocery(at index: Int) {
        grocery[index].updatedAt = nowMillis
        grocery[index].lastWriterID = writerID
        scheduleSave(.grocery)
    }
    private func stampRecipe(at index: Int) {
        recipes[index].updatedAt = nowMillis
        recipes[index].lastWriterID = writerID
        scheduleSave(.recipes)
    }
    private func stampMeal(at index: Int) {
        plannedMeals[index].updatedAt = nowMillis
        plannedMeals[index].lastWriterID = writerID
        scheduleSave(.plan)
    }

    // MARK: - Inventory

    func addInventory(_ item: LocalInventoryItem) {
        var copy = item
        copy.updatedAt = nowMillis
        copy.lastWriterID = writerID
        inventory.append(copy)
        scheduleSave(.inventory)
        NotificationCenter.default.post(name: .macInventoryNeedsCatalogEnrichment, object: copy.id)
    }

    @discardableResult
    func addInventory(name: String,
                      level: Double = 1.0,
                      zone: String = "Pantry",
                      quantity: Int = 1,
                      containerType: String = "item",
                      sizeAmount: Double? = nil,
                      sizeUnit: String? = nil) -> LocalInventoryItem {
        var item = LocalInventoryItem(name: name, level: level, zone: zone,
                                      quantity: quantity, containerType: containerType,
                                      sizeAmount: sizeAmount, sizeUnit: sizeUnit)
        item.updatedAt = nowMillis
        item.lastWriterID = writerID
        inventory.append(item)
        scheduleSave(.inventory)
        NotificationCenter.default.post(name: .macInventoryNeedsCatalogEnrichment, object: item.id)
        return item
    }

    /// Applies an edit and stamps it. Takes the change as a closure so callers can't
    /// forget the stamp — the only supported way to change an item in place.
    func updateInventory(id: UUID, requestEnrichment: Bool = true, _ change: (inout LocalInventoryItem) -> Void) {
        guard let index = inventory.firstIndex(where: { $0.id == id }) else { return }
        change(&inventory[index])
        stampInventory(at: index)
        if requestEnrichment {
            NotificationCenter.default.post(name: .macInventoryNeedsCatalogEnrichment, object: id)
        }
    }

    func deleteInventory(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { sync?.noteInventoryDeleted(id) }
        inventory.removeAll { ids.contains($0.id) }
        scheduleSave(.inventory)
    }

    func deleteInventory(_ item: LocalInventoryItem) { deleteInventory(ids: [item.id]) }

    /// Confirms an item is still there and still at the stated level. Clears the
    /// provisional state the AI import paths leave behind.
    func confirmInventory(id: UUID) {
        updateInventory(id: id) { item in
            item.lastConfirmedAt = Date()
            if item.sourceBadge == .needsReview || item.sourceBadge == .aiParsed {
                item.sourceBadge = .verified
            }
        }
    }

    /// Sets an item's remaining level. Separate from `updateInventory` because it is by
    /// far the most common edit and views drive it from a slider.
    func setLevel(id: UUID, to level: Double) {
        updateInventory(id: id) { $0.level = max(0, min(1, level)) }
    }

    // MARK: - Grocery

    @discardableResult
    func addGrocery(name: String,
                    quantity: Int = 1,
                    sizeText: String = "",
                    recipeSource: String = "",
                    recipeId: String = "") -> LocalGroceryItem {
        // LocalGroceryItem defaults every field and declares no custom init, so building
        // it by assignment is safer than relying on memberwise argument order.
        var item = LocalGroceryItem()
        item.name         = name
        item.quantity     = max(1, quantity)
        item.sizeText     = sizeText
        item.recipeSource = recipeSource
        item.recipeId     = recipeId
        item.updatedAt    = nowMillis
        item.lastWriterID = writerID
        grocery.append(item)
        scheduleSave(.grocery)
        return item
    }

    func updateGrocery(id: UUID, _ change: (inout LocalGroceryItem) -> Void) {
        guard let index = grocery.firstIndex(where: { $0.id == id }) else { return }
        change(&grocery[index])
        stampGrocery(at: index)
    }

    func toggleGrocery(id: UUID) {
        updateGrocery(id: id) { $0.isChecked.toggle() }
    }

    func deleteGrocery(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { sync?.noteGroceryDeleted(id) }
        grocery.removeAll { ids.contains($0.id) }
        scheduleSave(.grocery)
    }

    func clearCheckedGrocery() {
        deleteGrocery(ids: Set(grocery.filter { $0.isChecked }.map { $0.id }))
    }

    /// Moves everything ticked off onto the shelf. This is the "I got home from the shop"
    /// action: checked items become inventory at full level and leave the list.
    /// Returns how many items moved.
    @discardableResult
    func stockCheckedGrocery(into zone: String = "Pantry") -> Int {
        let checked = grocery.filter { $0.isChecked }
        guard !checked.isEmpty else { return 0 }
        for item in checked {
            if let index = inventory.firstIndex(where: {
                $0.name.compare(item.name, options: .caseInsensitive) == .orderedSame
            }) {
                // Already own it — top it back up rather than creating a duplicate row.
                inventory[index].level = 1.0
                inventory[index].quantity += max(1, item.quantity)
                stampInventory(at: index)
            } else {
                var fresh = LocalInventoryItem(name: item.name, level: 1.0, zone: zone,
                                               quantity: max(1, item.quantity))
                fresh.sourceBadge = .userAdded
                fresh.purchaseDate = Date()
                fresh.updatedAt = nowMillis
                fresh.lastWriterID = writerID
                inventory.append(fresh)
            }
        }
        scheduleSave(.inventory)
        deleteGrocery(ids: Set(checked.map { $0.id }))
        return checked.count
    }

    // MARK: - Recipes

    /// The authenticated public catalogue is already publisher/image gated by the
    /// Worker. Keep local annotations and newer edits; never delete private/local rows.
    func mergePublicRecipes(_ incoming: [UserRecipe]) {
        var merged = recipes
        var byID = Dictionary(merged.indices.map { (merged[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
        var bySource = Dictionary(merged.indices.map { (MacPublicRecipePage.identity(merged[$0]), $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for remote in incoming {
            let key = MacPublicRecipePage.identity(remote)
            if let index = byID[remote.id] ?? bySource[key] {
                let local = merged[index]
                guard remote.updatedAt > local.updatedAt else { continue }
                var next = remote
                next.id = local.id
                next.notes = local.notes
                next.isFavorited = local.isFavorited
                next.cookCount = local.cookCount
                next.lastCooked = local.lastCooked
                if next.imageURL == local.imageURL {
                    next.imageData = local.imageData
                    next.imageValidatedAt = local.imageValidatedAt
                }
                if next != local { merged[index] = next; changed = true }
                byID[remote.id] = index
                bySource[key] = index
            } else {
                byID[remote.id] = merged.count
                bySource[key] = merged.count
                merged.append(remote)
                changed = true
            }
        }
        if changed { recipes = merged; scheduleSave(.recipes) }
    }

    func addRecipe(_ recipe: UserRecipe) {
        guard MacRecipeImagePolicy.hasRequiredImage(recipe) else { return }
        var copy = recipe
        copy.title = RecipeTitlePolicy.cleaned(copy.title)
        copy.updatedAt = nowMillis
        copy.lastWriterID = writerID
        recipes.append(copy)
        scheduleSave(.recipes)
    }

    func updateRecipe(id: UUID, _ change: (inout UserRecipe) -> Void) {
        guard let index = recipes.firstIndex(where: { $0.id == id }) else { return }
        var updated = recipes[index]
        change(&updated)
        guard MacRecipeImagePolicy.hasRequiredImage(updated) else { return }
        updated.title = RecipeTitlePolicy.cleaned(updated.title)
        recipes[index] = updated
        stampRecipe(at: index)
    }

    func deleteRecipe(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { sync?.noteRecipeDeleted(id) }
        recipes.removeAll { ids.contains($0.id) }
        scheduleSave(.recipes)
    }

    func deleteSavedRecipes(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        savedRecipes.removeAll { ids.contains($0.id) }
        scheduleSave(.savedRecipes)
    }

    func toggleFavorite(recipeID: UUID) {
        updateRecipe(id: recipeID) { $0.isFavorited.toggle() }
    }

    /// Adds every non-optional ingredient of a recipe that isn't already on hand to the
    /// grocery list, tagged with the recipe so the list can group them.
    /// Returns the names actually added.
    @discardableResult
    func addMissingIngredients(for recipe: UserRecipe) -> [String] {
        var added: [String] = []
        for ingredient in recipe.ingredients where !ingredient.isOptional {
            guard !hasOnHand(ingredient.name) else { continue }
            guard !grocery.contains(where: {
                $0.name.compare(ingredient.name, options: .caseInsensitive) == .orderedSame
            }) else { continue }
            addGrocery(name: ingredient.name,
                       sizeText: ingredient.amount,
                       recipeSource: recipe.title,
                       recipeId: recipe.id.uuidString)
            added.append(ingredient.name)
        }
        return added
    }

    // MARK: - Plan

    func addPlannedMeal(_ meal: PlannedMeal) {
        var copy = meal
        copy.updatedAt = nowMillis
        copy.lastWriterID = writerID
        plannedMeals.append(copy)
        scheduleSave(.plan)
    }

    /// Puts a recipe on a day of the week plan.
    @discardableResult
    func planMeal(recipe: UserRecipe, dayIndex: Int, mealType: String = "Dinner") -> PlannedMeal {
        var meal = PlannedMeal(dayIndex: dayIndex,
                               title: recipe.title,
                               servings: recipe.servings,
                               ingredients: recipe.ingredientNames,
                               mealType: mealType)
        meal.updatedAt = nowMillis
        meal.lastWriterID = writerID
        plannedMeals.append(meal)
        scheduleSave(.plan)
        return meal
    }

    func updatePlannedMeal(id: UUID, _ change: (inout PlannedMeal) -> Void) {
        guard let index = plannedMeals.firstIndex(where: { $0.id == id }) else { return }
        change(&plannedMeals[index])
        stampMeal(at: index)
    }

    func deletePlannedMeal(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { sync?.noteMealDeleted(id) }
        plannedMeals.removeAll { ids.contains($0.id) }
        scheduleSave(.plan)
    }

    /// Marks a planned meal cooked, records it in history and draws down the inventory
    /// levels of the ingredients it used. Deliberately conservative: it lowers levels
    /// rather than deleting items, because "I used some of the rice" is far more common
    /// than "I used the entire bag."
    func markCooked(mealID: UUID, rating: Int = 0) {
        guard let meal = plannedMeals.first(where: { $0.id == mealID }) else { return }
        updatePlannedMeal(id: mealID) {
            $0.isCooked = true
            $0.cookAheadStatus = .served
        }
        for name in meal.ingredients {
            guard let index = inventory.firstIndex(where: { matches($0.name, name) }) else { continue }
            inventory[index].level = max(0, inventory[index].level - 0.25)
            inventory[index].quantityUsed = (inventory[index].quantityUsed ?? 0) + 1
            stampInventory(at: index)
        }
        pastMeals.append(LocalPastMeal(title: meal.title,
                                       date: Self.historyFormatter.string(from: Date()),
                                       recipeId: nil,
                                       rating: rating))
        scheduleSave(.history)
        if let index = recipes.firstIndex(where: { $0.title == meal.title }) {
            recipes[index].cookCount += 1
            recipes[index].lastCooked = Date()
            stampRecipe(at: index)
        }
    }

    @ObservationIgnored
    private static let historyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Lookups

    /// Loose name match. Inventory says "Olive oil, extra virgin" and a recipe says
    /// "olive oil"; both should count as the same thing. Case-insensitive containment in
    /// either direction, with a length floor so a three-letter word can't match half the
    /// pantry by accident.
    nonisolated func matches(_ a: String, _ b: String) -> Bool {
        let left  = a.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let right = b.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard left.count >= 4, right.count >= 4 else { return left == right }
        return left == right || left.contains(right) || right.contains(left)
    }

    func hasOnHand(_ name: String) -> Bool {
        inventory.contains { matches($0.name, name) && $0.effectiveLevel > 0.05 }
    }

    func inventoryItem(named name: String) -> LocalInventoryItem? {
        inventory.first { matches($0.name, name) }
    }

    /// Ingredients of a recipe that aren't in the kitchen right now.
    func missingIngredients(for recipe: UserRecipe) -> [String] {
        recipe.ingredients
            .filter { !$0.isOptional && !hasOnHand($0.name) }
            .map { $0.name }
    }

    func canCook(_ recipe: UserRecipe) -> Bool { missingIngredients(for: recipe).isEmpty }

    var expiringSoon: [LocalInventoryItem] {
        inventory.filter { $0.isExpiringSoon && !$0.isExpired }
                 .sorted { ($0.daysUntilExpiry ?? 999) < ($1.daysUntilExpiry ?? 999) }
    }

    var expired: [LocalInventoryItem] {
        inventory.filter { $0.isExpired }
    }

    var lowStock: [LocalInventoryItem] {
        inventory.filter { $0.isLow }.sorted { $0.effectiveLevel < $1.effectiveLevel }
    }

    func items(in category: StorageCategory) -> [LocalInventoryItem] {
        inventory.filter { $0.storageCategory == category }
                 .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Metrics

    /// The headline numbers. Computed from the same thresholds the iOS app uses, so a
    /// household looking at a phone and a Mac side by side sees the same figures.
    var metrics: KitchenMetrics {
        var value = KitchenMetrics()
        value.totalItems        = inventory.count
        value.expiredCount      = inventory.filter { $0.isExpired }.count
        value.expiringSoonCount = inventory.filter { $0.isExpiringSoon && !$0.isExpired }.count
        value.lowStockCount     = inventory.filter { $0.isLow }.count
        value.freshCount        = inventory.filter { !$0.isExpired && !$0.isExpiringSoon && !$0.isLow }.count
        value.groceryToBuy      = grocery.filter { !$0.isChecked }.count
        value.mealsReady        = recipes.filter { canCook($0) }.count

        if inventory.isEmpty {
            value.stockPercent = 0
        } else {
            let total = inventory.reduce(0.0) { $0 + max(0, min(1, $1.effectiveLevel)) }
            value.stockPercent = Int((total / Double(inventory.count) * 100).rounded())
        }

        // How long the current stock plausibly lasts. Not a prediction — a rough dial that
        // falls as the shelves empty, so "shop in 2 days" reads as pressure, not fact.
        value.groceryRunDays = max(0, Int((Double(value.stockPercent) / 100.0 * 7).rounded()))
        return value
    }

    // MARK: - Import / export
    //
    // The Mac's escape hatch. Household sync is the normal way data arrives, but a user
    // with no household — or one who wants a backup before a big edit — needs a file.

    func snapshot() -> MacKitchenSnapshot {
        MacKitchenSnapshot(inventory: inventory, grocery: grocery, recipes: recipes,
                           savedRecipes: savedRecipes,
                           plannedMeals: plannedMeals, pastMeals: pastMeals,
                           profile: profile, exportedAt: Date(),
                           appVersion: MacBuildConfig.displayLabel)
    }

    func exportData() throws -> Data {
        saveNow()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot())
    }

    /// Reads a snapshot back in. `replace: false` merges by id, keeping whichever copy of a
    /// clashing row was written more recently — the same rule household sync uses, so an
    /// import can't quietly undo a change made on the phone five minutes ago.
    func importData(_ data: Data, replace: Bool) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incoming: MacKitchenSnapshot
        do {
            incoming = try decoder.decode(MacKitchenSnapshot.self, from: data)
        } catch {
            throw MacServiceError.malformedResponse("That file isn't a Stocked backup.")
        }

        isRestoring = true
        if replace {
            inventory    = incoming.inventory
            grocery      = incoming.grocery
            recipes      = incoming.recipes
            savedRecipes = incoming.savedRecipes
            plannedMeals = incoming.plannedMeals
            pastMeals    = incoming.pastMeals
            profile      = incoming.profile
        } else {
            inventory    = Self.merge(inventory, incoming.inventory,
                                      id: \.id, at: \.updatedAt, writer: \.lastWriterID)
            grocery      = Self.merge(grocery, incoming.grocery,
                                      id: \.id, at: \.updatedAt, writer: \.lastWriterID)
            recipes      = Self.merge(recipes, incoming.recipes,
                                      id: \.id, at: \.updatedAt, writer: \.lastWriterID)
            savedRecipes = Self.merge(savedRecipes, incoming.savedRecipes,
                                      id: \.id, at: \.updatedAt, writer: \.lastWriterID)
            plannedMeals = Self.merge(plannedMeals, incoming.plannedMeals,
                                      id: \.id, at: \.updatedAt, writer: \.lastWriterID)
            let known = Set(pastMeals.map { $0.id })
            pastMeals += incoming.pastMeals.filter { !known.contains($0.id) }
            // Only take the imported profile if it was actually filled in — otherwise a
            // backup taken before onboarding would wipe a completed profile.
            if incoming.profile.completedSetup { profile = incoming.profile }
        }
        isRestoring = false
        save()
    }

    /// Last-write-wins merge shared by every collection. Same policy as the household
    /// engine: newer timestamp wins; on an exact tie the higher writer id wins, which is
    /// arbitrary but identical on every device, so copies converge instead of ping-ponging.
    private static func merge<T>(_ local: [T], _ remote: [T],
                                 id: KeyPath<T, UUID>,
                                 at: KeyPath<T, Double>,
                                 writer: KeyPath<T, String>) -> [T] {
        var result = local
        var index: [UUID: Int] = [:]
        for (offset, element) in result.enumerated() { index[element[keyPath: id]] = offset }

        for element in remote {
            let key = element[keyPath: id]
            guard let existing = index[key] else {
                index[key] = result.count
                result.append(element)
                continue
            }
            let takeRemote = HouseholdMergePolicy.remoteWins(
                remoteUpdatedAt: element[keyPath: at],
                remoteWriterID: element[keyPath: writer],
                localUpdatedAt: result[existing][keyPath: at],
                localWriterID: result[existing][keyPath: writer])
            if takeRemote { result[existing] = element }
        }
        return result
    }

    /// Wipes everything on this Mac. Does not touch the household — leaving is separate,
    /// and the confirmation copy in Settings says so.
    func eraseLocalData() {
        isRestoring = true
        inventory = []; grocery = []; recipes = []; savedRecipes = []
        plannedMeals = []; pastMeals = []; profile = UserCookingProfile()
        isRestoring = false
        save()
    }

    // MARK: - Sample data
    //
    // Used by SwiftUI previews and by the "Load a sample kitchen" button in Settings,
    // which exists so a new user can see what a full app looks like before committing to
    // typing their pantry in.

    static func sample() -> MacKitchenStore {
        let store = MacKitchenStore(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("stocked-mac-preview", isDirectory: true))
        store.loadSampleKitchen()
        return store
    }

    func loadSampleKitchen() {
        isRestoring = true

        let stamp = Date().timeIntervalSince1970 * 1000
        func item(_ name: String, _ level: Double, _ zone: String,
                  days: Int? = nil, brand: String? = nil) -> LocalInventoryItem {
            var value = LocalInventoryItem(name: name, level: level, zone: zone)
            value.brand = brand
            if let days {
                value.expirationDate = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }
            value.sourceBadge = .userAdded
            value.updatedAt = stamp
            return value
        }

        inventory = [
            item("Whole milk", 0.4, "Fridge", days: 3, brand: "Clover"),
            item("Large eggs", 0.75, "Fridge", days: 12),
            item("Baby spinach", 0.5, "Fridge", days: 2),
            item("Greek yogurt", 0.9, "Fridge", days: 9, brand: "Fage"),
            item("Chicken thighs", 1.0, "Freezer", days: 60),
            item("Frozen peas", 0.6, "Freezer"),
            item("Olive oil, extra virgin", 0.35, "Pantry"),
            item("Basmati rice", 0.8, "Pantry"),
            item("Canned chickpeas", 1.0, "Pantry", days: 400),
            item("Pasta, penne", 0.15, "Pantry"),
            item("Kosher salt", 0.9, "Staples"),
            item("Black peppercorns", 0.7, "Staples"),
            item("Garlic", 0.5, "Pantry", days: 14),
            item("Yellow onions", 0.6, "Pantry", days: 21),
        ]

        grocery = ["Lemons", "Parmesan", "Butter", "Sourdough"].map { name in
            var value = LocalGroceryItem()
            value.name = name
            value.updatedAt = stamp
            return value
        }

        recipes = [
            UserRecipe(title: "Lemon garlic chicken",
                       description: "Weeknight sheet-pan chicken with a bright pan sauce.",
                       cookTime: "35 min", prepTime: "10 min", servings: 4,
                       difficulty: "Easy", cuisine: "Mediterranean",
                       tags: ["weeknight", "one pan"],
                       ingredients: [
                        RecipeIngredient(name: "Chicken thighs", amount: "6"),
                        RecipeIngredient(name: "Garlic", amount: "4 cloves"),
                        RecipeIngredient(name: "Olive oil", amount: "2 tbsp"),
                        RecipeIngredient(name: "Lemons", amount: "2"),
                       ],
                       instructions: [
                        "Heat the oven to 425°F.",
                        "Toss the thighs with oil, sliced garlic, salt and pepper.",
                        "Roast 30–35 minutes, until the skin crackles.",
                        "Squeeze the lemon over the pan and spoon the juices back on top.",
                       ],
                       dishRole: .entree),
            UserRecipe(title: "Chickpea and spinach stew",
                       description: "Pantry dinner that comes together in one pot.",
                       cookTime: "25 min", prepTime: "5 min", servings: 3,
                       difficulty: "Easy", cuisine: "Mediterranean",
                       tags: ["vegetarian", "pantry"],
                       ingredients: [
                        RecipeIngredient(name: "Canned chickpeas", amount: "2 cans"),
                        RecipeIngredient(name: "Baby spinach", amount: "5 oz"),
                        RecipeIngredient(name: "Yellow onions", amount: "1"),
                        RecipeIngredient(name: "Olive oil", amount: "2 tbsp"),
                       ],
                       instructions: [
                        "Soften the onion in oil.",
                        "Add the chickpeas with their liquid and simmer 15 minutes.",
                        "Stir the spinach through until it wilts. Season well.",
                       ],
                       dishRole: .fullMeal),
        ]

        plannedMeals = [
            PlannedMeal(dayIndex: 0, title: "Lemon garlic chicken", servings: 4,
                        ingredients: ["Chicken thighs", "Garlic", "Lemons"], mealType: "Dinner"),
            PlannedMeal(dayIndex: 1, title: "Chickpea and spinach stew", servings: 3,
                        ingredients: ["Canned chickpeas", "Baby spinach"], mealType: "Dinner"),
        ]

        if profile.cookingGoal.isEmpty {
            profile.cookingGoal  = "Eat healthier"
            profile.dietaryStyle = "Omnivore"
            profile.householdSize = 2
        }

        isRestoring = false
        save()
    }
}
