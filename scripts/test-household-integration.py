#!/usr/bin/env python3
"""Exercise the production merged sync transaction with isolated transport and stores."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'StockedMac/Core/MacHouseholdSync.swift').read_text()
start = source.index('    func syncNow(store:')
end = source.index('    func pullAtLaunch', start)
method = source[start:end]
harness = r'''
import Foundation
enum MacBuildConfig { static let isWorkerConfigured = true }
@MainActor final class MacKitchenStore {
 var inventory: [Int] = [], grocery: [Int] = [], recipes: [Int] = [1,2], plannedMeals: [Int] = []
}
@MainActor final class Fixture {
 enum Status { case syncing, failed(String), synced(Date), idle }
 enum Key { static let localStateVersion = "state" }
 let defaults = UserDefaults(suiteName: UUID().uuidString)!
 var isJoined = true, status = Status.idle, membershipEpoch: UInt64 = 0
 var code = "original", memberID = "fixture", householdName = "fixture"
 var syncInventory = true, syncGrocery = false, syncRecipes = true, syncPlan = false
 var pendingInventoryDeletes: Set<String> = ["sent"], pendingGroceryDeletes: Set<String> = ["disabled"]
 var pendingRecipeDeletes: Set<String> = ["recipe"], pendingMealDeletes: Set<String> = ["disabled"]
 var lastPulledAt = 0.0, applied = false, persisted = false, versioned: [Int] = []
 var requests: [[String: Any]] = [], failAt = 0, switchAt = 0
 var hook: ((Fixture) -> Void)?
 func localStateSignature(_ store: MacKitchenStore) -> String { "before" }
 func pull(into store: MacKitchenStore) async {}
 func inventoryDict(_ i: Int) -> [String: Any] { ["id": i] }
 func groceryDict(_ i: Int) -> [String: Any] { ["id": i] }
 func plannedMealDict(_ i: Int) -> [String: Any]? { ["id": i] }
 func recipePayloadBatches(_ store: MacKitchenStore) -> [[[String: Any]]] { [[ ["id": 1] ], [ ["id": 2] ]] }
 func post(_ path: String, _ body: [String: Any]) async -> [String: Any]? {
   requests.append(body)
   hook?(self)
   if requests.count == switchAt { membershipEpoch += 1; code = "new" }
   if requests.count == failAt { return nil }
   return ["household": ["fixture": true]]
 }
 func apply(_ payload: [String: Any], into store: MacKitchenStore) async { applied = true; store.recipes.append(3) }
 func persistRecipeVersions(_ rows: [Int]) { versioned = rows }
 func persistIdentity() { persisted = true }
''' + method + r'''
}
@main struct Checks {
 @MainActor static func main() async {
   let store = MacKitchenStore()
   let ok = Fixture()
   ok.hook = { f in f.pendingInventoryDeletes.insert("new") }
   await ok.syncNow(store: store)
   precondition(ok.requests.count == 2 && ok.applied && ok.persisted)
   precondition(ok.requests[0]["responseMode"] as? String == "ack")
   precondition(ok.requests[1]["responseMode"] as? String == "full")
   precondition(ok.requests[1]["code"] as? String == "original")
   precondition(ok.pendingInventoryDeletes == ["new"])
   precondition(ok.pendingGroceryDeletes == ["disabled"] && ok.pendingMealDeletes == ["disabled"])
   precondition(ok.pendingRecipeDeletes.isEmpty)
   precondition(ok.versioned == [1,2], "server merge must not acknowledge unsent recipe versions")
   for step in [1,2] {
     let stale = Fixture(); stale.switchAt = step
     await stale.syncNow(store: MacKitchenStore())
     precondition(!stale.applied && !stale.persisted && stale.lastPulledAt == 0)
     precondition(stale.pendingInventoryDeletes == ["sent"])
     precondition(stale.requests.count == step)
     let failed = Fixture(); failed.failAt = step
     await failed.syncNow(store: MacKitchenStore())
     precondition(!failed.applied && !failed.persisted)
     precondition(failed.pendingInventoryDeletes == ["sent"] && failed.pendingRecipeDeletes == ["recipe"])
   }
   print("PASS: production sequential batch modes, membership changes at each response, failure preservation, disabled category tombstones, concurrent deletion and sent recipe versions")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='stocked-household-check-') as temp:
    swift = Path(temp) / 'Checks.swift'
    swift.write_text(harness)
    binary = Path(temp) / 'checks'
    subprocess.run(['swiftc','-parse-as-library',str(swift),'-o',str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
