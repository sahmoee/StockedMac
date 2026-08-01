// MacHouseholdSync.swift — the Mac joins your existing kitchen.
//
// This is the seam that makes the Mac app useful without coupling it to the iOS project.
// The two apps share no code and no bundle identifier; what they share is the household
// wire protocol on the Stocked Worker. The Mac joins with the same six-character code the
// phone uses, becomes another member device, and pushes and pulls the same JSON.
//
// Every route, body key and merge rule below is matched to Stocked/HouseholdSync.swift on
// iOS. Rename a key here and the two stop agreeing — the phone will quietly ignore what
// the Mac sends. When the iOS protocol changes, change it here in the same commit.
//
//   POST /household/create      ["ownerName", "memberId"]                 → ["code", "household"]
//   POST /household/join        ["code", "memberName", "memberId"]        → ["ok", "household"]
//   POST /household/pull        ["code", "since"]                         → ["household"]
//   POST /household/push        ["code", "actorId", …payload]             → ["household"]
//   POST /household/leave       ["code", "memberName", "memberId"]        → ["ok"]
//   POST /household/setname     ["code", "actorId", "memberId", "name"]   → ["ok"]
//   POST /household/setrole     ["code", "actorId", "memberId", "role"]   → ["ok"]
//   POST /household/regenerate  ["code"]                                  → ["code"]
//   POST /household/presence    ["code"]                                  → ["members"]

import Foundation
import Observation
import os

// MARK: - Merge policy
//
// Copied verbatim from Stocked/HouseholdMergePolicy.swift. Last-write-wins with a
// deterministic tie-break, so two devices that edit the same item in the same millisecond
// converge on the same answer instead of ping-ponging forever.

nonisolated enum HouseholdMergePolicy {
    static func remoteWins(remoteUpdatedAt: Double, remoteWriterID: String,
                           localUpdatedAt: Double, localWriterID: String) -> Bool {
        if remoteUpdatedAt != localUpdatedAt { return remoteUpdatedAt > localUpdatedAt }
        guard remoteWriterID != localWriterID else { return false }
        return remoteWriterID > localWriterID
    }
    static func advancedRevision(local: Int, remote: Int) -> Int { max(local, remote) }
}

// MARK: - Member

nonisolated struct MacHouseholdMember: Identifiable, Hashable, Sendable {
    nonisolated enum Role: String, CaseIterable, Sendable {
        case owner, manager, adult, teen, kid, member

        var label: String {
            switch self {
            case .owner:   return "Owner"
            case .manager: return "Manager"
            case .adult:   return "Adult"
            case .teen:    return "Teen"
            case .kid:     return "Kid"
            case .member:  return "Member"
            }
        }
        var canAdd: Bool    { self != .kid }
        var canEdit: Bool   { self != .kid }
        var canRemove: Bool { self == .owner || self == .manager || self == .adult }
        var canManageMembers: Bool { self == .owner || self == .manager }
    }

    var id: String
    var name: String
    var role: Role = .member
    var customLabel: String? = nil
    var isOnline: Bool = false
    var isMe: Bool = false

    var displayLabel: String {
        if let customLabel, !customLabel.isEmpty { return customLabel }
        return role.label
    }
}

// MARK: - Sync engine

@MainActor
@Observable
final class MacHouseholdSync {

    nonisolated enum Status: Equatable, Sendable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)

        var isBusy: Bool { self == .syncing }
        var message: String {
            switch self {
            case .idle:            return "Not synced yet"
            case .syncing:         return "Syncing…"
            case .synced(let at):  return "Last synced \(Self.formatter.string(from: at))"
            case .failed(let why): return why
            }
        }
        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .none
            f.timeStyle = .short
            return f
        }()
    }

    // ── Identity ─────────────────────────────────────────────────────────────
    /// The household code. Empty = this Mac hasn't joined a kitchen.
    private(set) var code: String = ""
    /// Stable per-device id. Generated once and kept — it is this Mac's `lastWriterID`,
    /// which is what makes last-write-wins deterministic across devices.
    private(set) var memberID: String = ""
    /// This device's display name in the member list. Written through `setDisplayName(_:)`
    /// when the change should reach the household; assigning it directly only changes the
    /// local label until the next `persistIdentity()`. No `didSet` here on purpose — the
    /// @Observable macro rewrites stored properties into accessors, and a property
    /// observer cannot coexist with that.
    var memberName: String = ""
    private(set) var householdName: String = ""
    private(set) var members: [MacHouseholdMember] = []
    private(set) var status: Status = .idle
    private(set) var lastPulledAt: Double = 0

    /// Categories to sync. Off by default for none of them — the point of joining is to
    /// share — but each can be turned off in Settings if the Mac should stay out of one.
    var syncInventory = true
    var syncGrocery   = true
    var syncRecipes   = true
    var syncPlan      = true

    var isJoined: Bool { !code.isEmpty }

    /// Images larger than this are dropped from a synced recipe. The Worker's KV values
    /// have a hard ceiling; a single 4 MB plate photo would blow the whole payload and the
    /// push would fail for every item in it, not just that recipe.
    nonisolated static let maxSyncedImageBytes = 180_000

    @ObservationIgnored private var autoSyncTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.sowens.StockedMac", category: "household")
    private let defaults = UserDefaults.standard

    // Tombstones. A deletion has to be transmitted as a fact — otherwise the next pull
    // resurrects the item from another device's copy. These accumulate until a push
    // succeeds, then clear.
    private var pendingInventoryDeletes: Set<String> = []
    private var pendingGroceryDeletes:   Set<String> = []
    private var pendingRecipeDeletes:    Set<String> = []
    private var pendingMealDeletes:      Set<String> = []

    init() { loadIdentity() }

    // MARK: - Identity persistence

    private enum Key {
        static let code   = "mac_household_code_v1"
        static let member = "mac_member_id_v1"
        static let name   = "mac_member_name_v1"
        static let hname  = "mac_household_name_v1"
        static let since  = "mac_household_since_v1"
        static let syncInv = "mac_sync_inventory_v1"
        static let syncGro = "mac_sync_grocery_v1"
        static let syncRec = "mac_sync_recipes_v1"
        static let syncPln = "mac_sync_plan_v1"
    }

    private func loadIdentity() {
        code          = defaults.string(forKey: Key.code) ?? ""
        householdName = defaults.string(forKey: Key.hname) ?? ""
        lastPulledAt  = defaults.double(forKey: Key.since)

        if let existing = defaults.string(forKey: Key.member), !existing.isEmpty {
            memberID = existing
        } else {
            memberID = "mac-" + UUID().uuidString.prefix(12)
            defaults.set(memberID, forKey: Key.member)
        }
        memberName = defaults.string(forKey: Key.name) ?? (Host.current().localizedName ?? "Mac")

        if defaults.object(forKey: Key.syncInv) != nil {
            syncInventory = defaults.bool(forKey: Key.syncInv)
            syncGrocery   = defaults.bool(forKey: Key.syncGro)
            syncRecipes   = defaults.bool(forKey: Key.syncRec)
            syncPlan      = defaults.bool(forKey: Key.syncPln)
        }

        // Write the resolved identity straight back, so the generated member id and the
        // machine-name default are on disk from the very first launch rather than being
        // re-derived (and re-randomised) if the app is quit before anything else saves.
        persistIdentity()
    }

    private func persistIdentity() {
        defaults.set(code, forKey: Key.code)
        defaults.set(memberID, forKey: Key.member)
        defaults.set(memberName, forKey: Key.name)
        defaults.set(householdName, forKey: Key.hname)
        defaults.set(lastPulledAt, forKey: Key.since)
    }

    func persistPreferences() {
        defaults.set(syncInventory, forKey: Key.syncInv)
        defaults.set(syncGrocery,   forKey: Key.syncGro)
        defaults.set(syncRecipes,   forKey: Key.syncRec)
        defaults.set(syncPlan,      forKey: Key.syncPln)
    }

    // MARK: - Transport

    /// One POST helper for every household route. Kept byte-compatible with the iOS
    /// version, including the 12-second timeout and the 429 / kvQuota handling.
    private func post(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: MacBuildConfig.receiptWorkerURL + path) else { return nil }
        guard JSONSerialization.isValidJSONObject(body) else {
            status = .failed("Couldn't build that request.")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        MacBuildConfig.authorizeWorkerRequest(&request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 429 {
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
                status = .failed(retry.map { "Too many requests — try again in \($0)s." }
                                 ?? "Too many requests — try again shortly.")
                return nil
            }

            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

            guard (200..<300).contains(http.statusCode) else {
                let detail = object?["error"] as? String
                if (object?["code"] as? String) == "kvQuota" || http.statusCode == 503 {
                    status = .failed(detail ?? "Household storage is temporarily unavailable.")
                } else {
                    status = .failed(detail ?? "The server returned an error (\(http.statusCode)).")
                }
                return nil
            }
            return object
        } catch {
            log.error("household \(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            status = .failed("Couldn't reach Stocked. Check your connection.")
            return nil
        }
    }

    // MARK: - Membership

    /// Start a brand-new household from the Mac. Returns the code to share.
    @discardableResult
    func createHousehold(ownerName: String) async -> String? {
        status = .syncing
        let trimmed = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let response = await post("/household/create",
                                        ["ownerName": trimmed.isEmpty ? memberName : trimmed,
                                         "memberId": memberID]),
              let newCode = response["code"] as? String, !newCode.isEmpty else {
            if case .syncing = status { status = .failed("Couldn't create the household.") }
            return nil
        }
        code = newCode
        if !trimmed.isEmpty { memberName = trimmed }
        readMembers(from: response["household"] as? [String: Any])
        lastPulledAt = 0
        persistIdentity()
        status = .synced(Date())
        return newCode
    }

    /// Join the kitchen the phone already has. This is the normal path.
    func join(code newCode: String, as name: String) async -> Bool {
        let cleanCode = newCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else {
            status = .failed("Enter your household code.")
            return false
        }
        status = .syncing
        guard let response = await post("/household/join",
                                        ["code": cleanCode,
                                         "memberName": cleanName.isEmpty ? memberName : cleanName,
                                         "memberId": memberID]),
              (response["ok"] as? Bool) == true else {
            if case .syncing = status { status = .failed("That code didn't work. Check it and try again.") }
            return false
        }
        code = cleanCode
        if !cleanName.isEmpty { memberName = cleanName }
        readMembers(from: response["household"] as? [String: Any])
        lastPulledAt = 0          // force a full pull so the Mac starts with everything
        persistIdentity()
        status = .synced(Date())
        return true
    }

    /// Leave the household. Local data is left alone — leaving is about the shared copy,
    /// and silently wiping the user's kitchen because they unlinked a device would be
    /// unforgivable. Settings offers a separate explicit "remove local data".
    func leave() async {
        guard isJoined else { return }
        status = .syncing
        _ = await post("/household/leave",
                       ["code": code, "memberName": memberName, "memberId": memberID])
        code = ""
        householdName = ""
        members = []
        lastPulledAt = 0
        pendingInventoryDeletes.removeAll()
        pendingGroceryDeletes.removeAll()
        pendingRecipeDeletes.removeAll()
        pendingMealDeletes.removeAll()
        persistIdentity()
        status = .idle
    }

    /// Rename this device's member entry.
    func setDisplayName(_ name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isJoined, !clean.isEmpty else { return }
        memberName = clean
        _ = await post("/household/setname",
                       ["code": code, "actorId": memberID, "memberId": memberID, "name": clean])
        persistIdentity()
    }

    /// Owner/manager action: change someone's access level.
    func setRole(_ role: MacHouseholdMember.Role, for memberId: String) async {
        guard isJoined else { return }
        _ = await post("/household/setrole",
                       ["code": code, "actorId": memberID,
                        "memberId": memberId, "role": role.rawValue])
        await refreshPresence()
    }

    /// Issue a new join code, invalidating the old one.
    @discardableResult
    func regenerateCode() async -> String? {
        guard isJoined else { return nil }
        guard let response = await post("/household/regenerate", ["code": code]),
              let newCode = response["code"] as? String, !newCode.isEmpty else { return nil }
        code = newCode
        persistIdentity()
        return newCode
    }

    /// Who else is in the kitchen right now.
    func refreshPresence() async {
        guard isJoined else { return }
        guard let response = await post("/household/presence", ["code": code]) else { return }
        readMembers(from: response)
    }

    private func readMembers(from payload: [String: Any]?) {
        guard let payload else { return }
        if let name = payload["name"] as? String, !name.isEmpty { householdName = name }
        let raw = (payload["members"] as? [[String: Any]]) ?? []
        guard !raw.isEmpty else { return }
        members = raw.compactMap { entry in
            guard let id = entry["id"] as? String ?? entry["memberId"] as? String else { return nil }
            let role = MacHouseholdMember.Role(rawValue: (entry["role"] as? String) ?? "") ?? .member
            let custom = entry["customLabel"] as? String
            return MacHouseholdMember(id: id,
                                      name: (entry["name"] as? String) ?? "Member",
                                      role: role,
                                      customLabel: (custom?.isEmpty == false) ? custom : nil,
                                      isOnline: (entry["online"] as? Bool) ?? false,
                                      isMe: id == memberID)
        }
    }

    // MARK: - Deletion tracking
    //
    // The store calls these when the user removes something, so the next push carries the
    // tombstone. Without them a delete on the Mac is undone by the next pull.

    func noteInventoryDeleted(_ id: UUID) { pendingInventoryDeletes.insert(id.uuidString) }
    func noteGroceryDeleted(_ id: UUID)   { pendingGroceryDeletes.insert(id.uuidString) }
    func noteRecipeDeleted(_ id: UUID)    { pendingRecipeDeletes.insert(id.uuidString) }
    func noteMealDeleted(_ id: UUID)      { pendingMealDeletes.insert(id.uuidString) }

    // MARK: - Sync

    /// Push local state, then apply whatever comes back. One round trip; the Worker
    /// returns the merged household from a push, so a separate pull is only needed when
    /// there is nothing to send.
    func syncNow(store: MacKitchenStore) async {
        guard isJoined else { return }
        guard MacBuildConfig.isWorkerConfigured else {
            status = .failed("Add your Worker key in Secrets.xcconfig to enable sync.")
            return
        }
        status = .syncing

        var body: [String: Any] = ["code": code, "actorId": memberID]
        if !householdName.isEmpty { body["householdName"] = householdName }

        if syncInventory {
            body["inventory"]  = store.inventory.map(inventoryDict)
            body["invDeleted"] = Array(pendingInventoryDeletes)
        }
        if syncGrocery {
            body["grocery"]    = store.grocery.map(groceryDict)
            body["groDeleted"] = Array(pendingGroceryDeletes)
        }
        if syncRecipes {
            body["userRecipes"]       = store.recipes.compactMap(userRecipeDict)
            body["userRecipeDeleted"] = Array(pendingRecipeDeletes)
        }
        if syncPlan {
            body["plannedMeals"] = store.plannedMeals.compactMap(plannedMealDict)
            body["mealDeleted"]  = Array(pendingMealDeletes)
        }

        guard let response = await post("/household/push", body) else { return }

        // The push succeeded, so the tombstones have been recorded server-side and can go.
        pendingInventoryDeletes.removeAll()
        pendingGroceryDeletes.removeAll()
        pendingRecipeDeletes.removeAll()
        pendingMealDeletes.removeAll()

        apply(response["household"] as? [String: Any] ?? response, into: store)
        lastPulledAt = Date().timeIntervalSince1970 * 1000
        persistIdentity()
        status = .synced(Date())
    }

    func pullAtLaunch(into store: MacKitchenStore) async {
        let previous = lastPulledAt
        if store.inventory.isEmpty && store.grocery.isEmpty && store.recipes.isEmpty {
            lastPulledAt = 0
        }
        await pull(into: store)
        if lastPulledAt == 0 { lastPulledAt = previous }
    }

    func resyncEverything(into store: MacKitchenStore) async {
        lastPulledAt = 0
        persistIdentity()
        await pull(into: store)
    }

    func startAutoSync(store: MacKitchenStore) {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self, weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, let store, self.isJoined else { continue }
                await self.syncNow(store: store)
            }
        }
    }

    /// Read-only refresh — used on launch and by the menu bar's Refresh command.
    func pull(into store: MacKitchenStore) async {
        guard isJoined else { return }
        status = .syncing
        guard let response = await post("/household/pull",
                                        ["code": code, "since": lastPulledAt]) else { return }
        apply(response["household"] as? [String: Any] ?? response, into: store)
        lastPulledAt = Date().timeIntervalSince1970 * 1000
        persistIdentity()
        status = .synced(Date())
    }

    // MARK: - Wire encoders
    //
    // Field-for-field identical to HouseholdSync.swift on iOS. Do not "tidy" these.

    private func inventoryDict(_ item: LocalInventoryItem) -> [String: Any] {
        ["id": item.id.uuidString,
         "name": item.name,
         "quantity": item.quantity,
         "zone": item.zone,
         "level": item.effectiveLevel,
         "brand": item.brand ?? "",
         "updatedAt": item.updatedAt,
         "lastWriterID": item.lastWriterID]
    }

    private func groceryDict(_ item: LocalGroceryItem) -> [String: Any] {
        ["id": item.id.uuidString,
         "name": item.name,
         "quantity": item.quantity,
         "isChecked": item.isChecked,
         "recipeSource": item.recipeSource,
         "addedByName": item.addedByName,
         "updatedAt": item.updatedAt,
         "lastWriterID": item.lastWriterID,
         "assignedTo": item.assignedTo,
         "sizeText": item.sizeText]
    }

    /// Recipes and planned meals ride as the encoded struct with the sync fields overlaid,
    /// so a field added to the model syncs without a change here. Oversized images are
    /// dropped rather than failing the whole push.
    private func userRecipeDict(_ recipe: UserRecipe) -> [String: Any]? {
        var trimmed = recipe
        if let data = trimmed.imageData, data.count > Self.maxSyncedImageBytes { trimmed.imageData = nil }
        guard let data = try? JSONEncoder().encode(trimmed),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        object["updatedAt"]    = recipe.updatedAt
        object["lastWriterID"] = recipe.lastWriterID
        return object
    }

    private func plannedMealDict(_ meal: PlannedMeal) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(meal),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        object["updatedAt"]    = meal.updatedAt
        object["lastWriterID"] = meal.lastWriterID
        return object
    }

    // MARK: - Wire parsers

    private func parseInventory(_ d: [String: Any]) -> LocalInventoryItem? {
        guard let name = d["name"] as? String, !name.isEmpty else { return nil }
        let zone = (d["zone"] as? String) ?? "Pantry"
        var item = LocalInventoryItem(name: name,
                                      level: (d["level"] as? Double) ?? 1.0,
                                      zone: zone,
                                      quantity: (d["quantity"] as? Int) ?? 1)
        if let idStr = d["id"] as? String, let uuid = UUID(uuidString: idStr) { item.id = uuid }
        if let brand = d["brand"] as? String, !brand.isEmpty { item.brand = brand }
        item.storageCategory = StorageCategory(rawValue: zone) ?? .pantry
        item.updatedAt    = (d["updatedAt"] as? Double) ?? 0
        item.lastWriterID = (d["lastWriterID"] as? String) ?? ""
        return item
    }

    private func parseGrocery(_ d: [String: Any]) -> LocalGroceryItem? {
        guard let name = d["name"] as? String, !name.isEmpty else { return nil }
        var item = LocalGroceryItem()
        item.name      = name
        item.isChecked = (d["isChecked"] as? Bool) ?? false
        if let idStr = d["id"] as? String, let uuid = UUID(uuidString: idStr) { item.id = uuid }
        item.quantity     = (d["quantity"] as? Int) ?? 1
        item.recipeSource = (d["recipeSource"] as? String) ?? ""
        item.addedByName  = (d["addedByName"] as? String) ?? ""
        item.assignedTo   = (d["assignedTo"] as? String) ?? ""
        item.sizeText     = (d["sizeText"] as? String) ?? ""
        item.updatedAt    = (d["updatedAt"] as? Double) ?? 0
        item.lastWriterID = (d["lastWriterID"] as? String) ?? ""
        return item
    }

    private func decode<T: Decodable>(_ type: T.Type, from d: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Merge

    /// Fold a household payload into the local store. Merge by id, last-write-wins with the
    /// shared tie-break, tombstones applied last so a remote delete beats a stale remote add.
    private func apply(_ payload: [String: Any]?, into store: MacKitchenStore) {
        guard let payload else { return }

        if let name = payload["name"] as? String, !name.isEmpty { householdName = name }
        readMembers(from: payload)

        if syncInventory, let rows = payload["inventory"] as? [[String: Any]] {
            let remote = rows.compactMap(parseInventory)
            let deleted = Set((payload["invDeleted"] as? [String]) ?? [])
                .union(pendingInventoryDeletes)
            var merged = store.inventory
            for item in remote {
                if let index = merged.firstIndex(where: { $0.id == item.id }) {
                    let local = merged[index]
                    if HouseholdMergePolicy.remoteWins(remoteUpdatedAt: item.updatedAt,
                                                       remoteWriterID: item.lastWriterID,
                                                       localUpdatedAt: local.updatedAt,
                                                       localWriterID: local.lastWriterID) {
                        // Keep local-only detail the wire format doesn't carry (expiry,
                        // nutrition, photo) rather than blanking it on every merge.
                        var updated = local
                        updated.name            = item.name
                        updated.quantity        = item.quantity
                        updated.level           = item.level
                        updated.storageCategory = item.storageCategory
                        updated.brand           = item.brand ?? local.brand
                        updated.updatedAt       = item.updatedAt
                        updated.lastWriterID    = item.lastWriterID
                        merged[index] = updated
                    }
                } else {
                    merged.append(item)
                }
            }
            store.inventory = merged.filter { !deleted.contains($0.id.uuidString) }
        }

        if syncGrocery, let rows = payload["grocery"] as? [[String: Any]] {
            let remote = rows.compactMap(parseGrocery)
            let deleted = Set((payload["groDeleted"] as? [String]) ?? [])
                .union(pendingGroceryDeletes)
            var merged = store.grocery
            for item in remote {
                if let index = merged.firstIndex(where: { $0.id == item.id }) {
                    let local = merged[index]
                    if HouseholdMergePolicy.remoteWins(remoteUpdatedAt: item.updatedAt,
                                                       remoteWriterID: item.lastWriterID,
                                                       localUpdatedAt: local.updatedAt,
                                                       localWriterID: local.lastWriterID) {
                        merged[index] = item
                    }
                } else {
                    merged.append(item)
                }
            }
            store.grocery = merged.filter { !deleted.contains($0.id.uuidString) }
        }

        if syncRecipes, let rows = payload["userRecipes"] as? [[String: Any]] {
            let remote = rows.compactMap { decode(UserRecipe.self, from: $0) }
            let deleted = Set((payload["userRecipeDeleted"] as? [String]) ?? [])
                .union(pendingRecipeDeletes)
            var merged = store.recipes
            for recipe in remote {
                if let index = merged.firstIndex(where: { $0.id == recipe.id }) {
                    let local = merged[index]
                    if HouseholdMergePolicy.remoteWins(remoteUpdatedAt: recipe.updatedAt,
                                                       remoteWriterID: recipe.lastWriterID,
                                                       localUpdatedAt: local.updatedAt,
                                                       localWriterID: local.lastWriterID) {
                        merged[index] = recipe
                    }
                } else {
                    merged.append(recipe)
                }
            }
            store.recipes = merged.filter { !deleted.contains($0.id.uuidString) }
        }

        if syncPlan, let rows = payload["plannedMeals"] as? [[String: Any]] {
            let remote = rows.compactMap { decode(PlannedMeal.self, from: $0) }
            let deleted = Set((payload["mealDeleted"] as? [String]) ?? [])
                .union(pendingMealDeletes)
            var merged = store.plannedMeals
            for meal in remote {
                if let index = merged.firstIndex(where: { $0.id == meal.id }) {
                    let local = merged[index]
                    if HouseholdMergePolicy.remoteWins(remoteUpdatedAt: meal.updatedAt,
                                                       remoteWriterID: meal.lastWriterID,
                                                       localUpdatedAt: local.updatedAt,
                                                       localWriterID: local.lastWriterID) {
                        merged[index] = meal
                    }
                } else {
                    merged.append(meal)
                }
            }
            store.plannedMeals = merged.filter { !deleted.contains($0.id.uuidString) }
        }

        store.save()
    }
}
