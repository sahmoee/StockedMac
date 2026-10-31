#!/usr/bin/env python3
"""Compile production membership/cache/batch helpers with real models and isolated defaults.
Only transport and unrelated store persistence are fakes; no live household or Keychain.
"""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root / 'StockedMac/Core/MacHouseholdSync.swift').read_text()
def method(signature):
    start = s.index(signature); brace = s.index('{', start); depth = 1; end = brace + 1
    while depth:
        depth += (s[end] == '{') - (s[end] == '}'); end += 1
    return s[start:end].replace('private func ', 'func ')
methods = [method(x) for x in ['private func beginMembershipChange()', 'func createHousehold(', 'func join(', 'func leave()', 'func regenerateCode()', 'private func recipeVersion(', 'private func storedRecipeVersions()', 'private func persistRecipeVersions(', 'private func localStateSignature(', 'private func recipePayloadBatches(', 'private func userRecipeDict(', 'func syncNow(', 'private func inventoryDict(', 'private func groceryDict(', 'private func plannedMealDict(']]
policy = s[s.index('nonisolated enum HouseholdMergePolicy'):s.index('// MARK: - Member')]
invite = s[s.index('nonisolated enum MacHouseholdInvite'):]
harness = r'''
import Foundation
import CryptoKit
enum MacBuildConfig { static let isWorkerConfigured = true }
@MainActor final class MacKitchenStore {
 var inventory: [LocalInventoryItem] = [], grocery: [LocalGroceryItem] = [], recipes: [UserRecipe] = [], plannedMeals: [PlannedMeal] = []
}
struct SilentLog { func info(_ value: String) {} }
@MainActor final class Fixture {
 enum Status { case syncing, failed(String), synced(Date), idle }
 enum Key {
  static let recipeVersions = "versions", localStateVersion = "state"
 }
 let suite = "stocked-membership-check-" + UUID().uuidString
 lazy var defaults = UserDefaults(suiteName: suite)!
 var status = Status.idle, membershipEpoch: UInt64 = 0, code = "AAAAAAAA", memberID = "fixture", memberName = "fixture", householdName = ""
 var members: [String] = [], lastPulledAt = 0.0
 var isJoined: Bool { !code.isEmpty }
 var syncInventory = true, syncGrocery = true, syncRecipes = true, syncPlan = true
 var pendingInventoryDeletes: Set<String> = [], pendingGroceryDeletes: Set<String> = [], pendingRecipeDeletes: Set<String> = [], pendingMealDeletes: Set<String> = []
 static let maxSyncedImageBytes = 180_000, maxPushBodyBytes = 700_000
 let log = SilentLog()
 var staleResponse = false, failResponse = false
 var requests: [(String, [String: Any])] = []
 func post(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
   requests.append((path, body))
   if staleResponse { _ = beginMembershipChange(); code = "CCCCCCCC" }
   return failResponse ? nil : ["code": "BBBBBBBB", "ok": true]
 }
 func readMembers(from value: [String: Any]?) {}
 func persistIdentity() {}
 func pull(into store: MacKitchenStore) async {}
 func apply(_ payload: [String: Any], into store: MacKitchenStore) async {}
 func seed(_ recipes: [UserRecipe], _ signature: String) {
   persistRecipeVersions(recipes); defaults.set(signature, forKey: Key.localStateVersion)
 }
 func close() { defaults.removePersistentDomain(forName: suite) }
''' + '\n'.join(methods) + r'''
}
@main struct Checks {
 @MainActor static func main() async {
   var recipe = UserRecipe(title: "Fixture"); recipe.updatedAt = 10; recipe.lastWriterID = "a"; recipe.collectionSavedByUser = true
   let store = MacKitchenStore(); store.recipes = [recipe]
   for transition in 0..<4 {
     let f = Fixture(); defer { f.close() }
     let signature = f.localStateSignature(store)
     f.seed([recipe], signature)
     precondition(f.recipePayloadBatches(store).isEmpty)
     switch transition {
      case 0: _ = await f.createHousehold(ownerName: "fixture")
      case 1: _ = await f.join(code: "BBBBBBBB", as: "fixture")
      case 2: await f.leave()
      default: _ = await f.regenerateCode()
     }
     precondition(f.defaults.object(forKey: Fixture.Key.localStateVersion) == nil)
     precondition(f.storedRecipeVersions().isEmpty)
     precondition(f.recipePayloadBatches(store).flatMap { $0 }.count == 1, "same-named new household must receive unchanged recipes")
     precondition(f.localStateSignature(store) == signature, "identical state still needs invalidated acknowledgment")
     if transition != 2 {
       await f.syncNow(store: store)
       precondition(f.requests.last?.0 == "/household/push", "new household must push, never enter pull-only shortcut")
       precondition((f.requests.last?.1["userRecipes"] as? [[String: Any]])?.count == 1)
     }
   }
   // A transition's continuation must not overwrite a later membership, even when the
   // transport finishes successfully (or reports failure) after that later transition.
   for transition in 0..<4 {
     for fails in [false, true] {
       let f = Fixture(); defer { f.close() }; f.staleResponse = true; f.failResponse = fails
       switch transition {
        case 0: precondition(await f.createHousehold(ownerName: "fixture") == nil)
        case 1: precondition(await f.join(code: "BBBBBBBB", as: "fixture") == false)
        case 2: await f.leave()
        default: precondition(await f.regenerateCode() == nil)
       }
       precondition(f.code == "CCCCCCCC", "stale membership completion changed new identity")
       precondition(f.storedRecipeVersions().isEmpty)
     }
   }
   let f = Fixture(); defer { f.close() }
   let staleSync = Fixture(); defer { staleSync.close() }; staleSync.staleResponse = true
   await staleSync.syncNow(store: store)
   precondition(staleSync.defaults.object(forKey: Fixture.Key.localStateVersion) == nil)
   precondition(staleSync.storedRecipeVersions().isEmpty, "old sync completion must not repopulate new membership cache")
   var newer = recipe; newer.updatedAt = 20; newer.lastWriterID = "b"
   for duplicates in [[recipe,newer],[newer,recipe],[newer,newer]] {
      f.persistRecipeVersions(duplicates)
      precondition(f.storedRecipeVersions()[recipe.id.uuidString] == f.recipeVersion(newer))
      precondition(f.storedRecipeVersions().count == 1)
   }
   var tie = newer; tie.lastWriterID = "z"
   f.persistRecipeVersions([tie,newer]); precondition(f.storedRecipeVersions()[recipe.id.uuidString] == f.recipeVersion(tie))
   // Cache decoding is real, bounded recipe batching is real, models are production.
   f.defaults.set(Data("invalid".utf8), forKey: Fixture.Key.recipeVersions)
   precondition(f.storedRecipeVersions().isEmpty)
   print("PASS: actual create/join/leave/regenerate invalidation; unchanged new-household upload; stale membership completions; duplicate LWW cache order; corrupt cache fallback")
 }
}
'''
# Swift precondition autoclosures cannot suspend.
harness = harness.replace('precondition(await f.createHousehold(ownerName: "fixture") == nil)', 'let result = await f.createHousehold(ownerName: "fixture"); precondition(result == nil)').replace('precondition(await f.join(code: "BBBBBBBB", as: "fixture") == false)', 'let result = await f.join(code: "BBBBBBBB", as: "fixture"); precondition(result == false)').replace('precondition(await f.regenerateCode() == nil)', 'let result = await f.regenerateCode(); precondition(result == nil)')
with tempfile.TemporaryDirectory(prefix='stocked-membership-') as temp:
    p = Path(temp)/'Checks.swift'; p.write_text(harness + policy + invite)
    binary = Path(temp)/'checks'
    files = ['Models','MacSharedTypes','KitchenMetrics','PortableRecipeSource','PortableCooklang']
    subprocess.run(['swiftc','-parse-as-library',*[str(root/f'StockedMac/Core/{f}.swift') for f in files],str(p),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
