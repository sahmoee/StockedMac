import AppKit
import SwiftUI

struct MacHomeView: View {
    @Environment(MacKitchenStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 14) {
                metric("Stocked", "\(store.metrics.stockPercent)%", "refrigerator")
                metric("Use soon", "\(store.metrics.expiringSoonCount)", "clock.badge.exclamationmark")
                metric("On the list", "\(store.metrics.groceryToBuy)", "cart")
                metric("Ready to cook", "\(store.metrics.mealsReady)", "fork.knife")
            }
            .padding()
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        MacCard(title: title, systemImage: icon) {
            Text(value).font(.system(size: 32, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MacInventoryView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @State private var newName = ""

    var body: some View {
        @Bindable var navigation = navigation
        VStack(spacing: 0) {
            if navigation.isAddingItem {
                quickAdd
                Divider()
            }
            if store.inventory.isEmpty {
                MacEmpty(title: "Nothing in the kitchen", message: "Use the + button to add your first item.", systemImage: "refrigerator")
            } else {
                List {
                    ForEach(store.inventory) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(item.zone).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Slider(
                                value: Binding(get: { item.level }, set: { store.setLevel(id: item.id, to: $0) }),
                                in: 0...1
                            )
                            .frame(width: 140)
                            Text("\(Int(item.level * 100))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    .onDelete { offsets in
                        store.deleteInventory(ids: Set(offsets.map { store.inventory[$0].id }))
                    }
                }
            }
        }
    }

    private var quickAdd: some View {
        HStack {
            TextField("Item name", text: $newName)
                .onSubmit(add)
            Button("Add", action: add).disabled(newName.nilIfBlank == nil)
            Button("Cancel") { navigation.isAddingItem = false; newName = "" }
        }
        .padding(12)
    }

    private func add() {
        guard let name = newName.nilIfBlank else { return }
        store.addInventory(name: name)
        newName = ""
        navigation.isAddingItem = false
    }
}

struct MacGroceryView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            if navigation.isAddingItem {
                HStack {
                    TextField("Grocery item", text: $newName).onSubmit(add)
                    Button("Add", action: add).disabled(newName.nilIfBlank == nil)
                    Button("Cancel") { navigation.isAddingItem = false; newName = "" }
                }
                .padding(12)
                Divider()
            }
            if store.grocery.isEmpty {
                MacEmpty(title: "The list is clear", message: "Use the + button to add something.", systemImage: "cart")
            } else {
                List(store.grocery) { item in
                    HStack {
                        Button { store.toggleGrocery(id: item.id) } label: {
                            Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.borderless)
                        Text(item.name).strikethrough(item.isChecked)
                        Spacer()
                        if item.quantity > 1 { Text("×\(item.quantity)").foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private func add() {
        guard let name = newName.nilIfBlank else { return }
        store.addGrocery(name: name)
        newName = ""
        navigation.isAddingItem = false
    }
}

struct MacPlanView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @State private var title = ""
    @State private var day = 0

    var body: some View {
        VStack(spacing: 0) {
            if navigation.isAddingItem {
                HStack {
                    TextField("Meal", text: $title).onSubmit(add)
                    Picker("Day", selection: $day) {
                        ForEach(0..<MacWeek.dayCount, id: \.self) { Text(MacWeek.label(for: $0)).tag($0) }
                    }
                    .frame(width: 150)
                    Button("Add", action: add).disabled(title.nilIfBlank == nil)
                    Button("Cancel") { navigation.isAddingItem = false; title = "" }
                }
                .padding(12)
                Divider()
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(0..<MacWeek.dayCount, id: \.self) { offset in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(MacWeek.label(for: offset)).font(.headline)
                            ForEach(store.plannedMeals.filter { $0.dayIndex == offset }) { meal in
                                MacCard {
                                    Text(meal.title).font(.callout.weight(.medium))
                                    Button(meal.isCooked ? "Cooked" : "Mark cooked") {
                                        store.markCooked(mealID: meal.id)
                                    }
                                    .disabled(meal.isCooked)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(width: 180, alignment: .topLeading)
                    }
                }
                .padding()
            }
        }
    }

    private func add() {
        guard let title = title.nilIfBlank else { return }
        store.addPlannedMeal(PlannedMeal(dayIndex: day, title: title, servings: 2, ingredients: [], mealType: "Dinner"))
        self.title = ""
        navigation.isAddingItem = false
    }
}

struct MacCookView: View {
    @Environment(MacKitchenStore.self) private var store

    var body: some View {
        List(store.recipes.filter { store.canCook($0) }) { recipe in
            Label(recipe.title, systemImage: "checkmark.circle.fill")
                .foregroundStyle(MacTheme.green)
        }
        .overlay {
            if store.recipes.filter({ store.canCook($0) }).isEmpty {
                MacEmpty(title: "Nothing is ready yet", message: "Add missing ingredients to your grocery list from Recipes.", systemImage: "fork.knife")
            }
        }
    }
}

struct MacInsightsView: View {
    @Environment(MacKitchenStore.self) private var store

    var body: some View {
        Form {
            LabeledContent("Inventory items", value: "\(store.inventory.count)")
            LabeledContent("Expired", value: "\(store.metrics.expiredCount)")
            LabeledContent("Expiring soon", value: "\(store.metrics.expiringSoonCount)")
            LabeledContent("Recipes", value: "\(store.recipes.count)")
        }
        .formStyle(.grouped)
    }
}

struct MacToolsView: View {
    @Environment(MacKitchenStore.self) private var store

    var body: some View {
        Form {
            Button("Show data folder") { NSWorkspace.shared.activateFileViewerSelecting([store.storageDirectory]) }
            Button("Load sample kitchen") { store.loadSampleKitchen() }
        }
        .formStyle(.grouped)
    }
}

struct MacHarvestView: View {
    @Environment(HarvestModel.self) private var harvest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recipe Harvester").font(.title2.bold())
            Text(harvest.statusMessage).foregroundStyle(.secondary)
            HStack {
                Button("Paste URLs") { harvest.pasteURLsFromClipboard() }
                Button("Import queued URLs") { harvest.importURLs() }.disabled(harvest.isImporting)
                Button("Browse next source") { harvest.browseNextSource() }.disabled(harvest.isDiscovering)
            }
            List(harvest.recipes) { recipe in
                HStack {
                    Text(recipe.title)
                    Spacer()
                    Text(recipe.reviewState.label).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}
