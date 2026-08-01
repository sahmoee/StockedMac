import AppKit
import SwiftUI
import WebKit

struct MacHomeView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 14) {
                metric("Stocked", "\(store.metrics.stockPercent)%", "refrigerator")
                metric("Use soon", "\(store.metrics.expiringSoonCount)", "clock.badge.exclamationmark")
                metric("On the list", "\(store.metrics.groceryToBuy)", "cart")
                metric("Ready to cook", "\(store.metrics.mealsReady)", "fork.knife")
                Button { navigation.section = .browse } label: {
                    MacCard(title: "Browse recipes", systemImage: "globe") {
                        Text("Find & import")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(MacTheme.gold)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
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
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation

    @State private var stateFilter: ReviewState? = nil
    @State private var search = ""
    @State private var addStatus: String?
    /// Show only drafts missing their image — the ones the phone would reject.
    @State private var onlyImageless = false

    private var visible: [RecipeDraft] {
        var items = harvest.recipes
        if let f = stateFilter { items = items.filter { $0.reviewState == f } }
        if onlyImageless { items = items.filter { !($0.image?.hasLocalFile ?? false) } }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q) || $0.source.host.lowercased().contains(q)
            }
        }
        return items
    }

    var body: some View {
        @Bindable var harvest = harvest
        HStack(spacing: 0) {
            // ── Left: browse + queue + recipe list ───────────────────────
            VStack(spacing: 0) {
                harvestHeader
                Divider()
                filterRow
                Divider()
                bulkBar
                recipeList
                Divider()
                statusFooter
            }
            .frame(minWidth: 290, maxWidth: 390)

            Divider()

            // ── Right: recipe detail ──────────────────────────────────────
            Group {
                if let draft = harvest.recipes.first(where: { $0.id == harvest.selectedRecipeID }) {
                    HarvestDraftDetail(draft: draft, addStatus: $addStatus)
                } else if harvest.recipes.isEmpty {
                    MacEmpty(
                        title: "Nothing here yet",
                        message: "Browse a source or paste recipe URLs to get started.",
                        systemImage: "leaf"
                    )
                } else {
                    MacEmpty(
                        title: "Select a recipe",
                        message: "Choose a recipe from the list to review it.",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header
    //
    // Browsing and importing moved to the Browse section (Build 91). This header keeps
    // Harvest honest about being the review room, and puts the door to Browse where the
    // browse controls used to be.

    private var harvestHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf").font(.caption).foregroundStyle(.secondary)
            Text("Review imported recipes").font(.caption.weight(.medium))
            Spacer(minLength: 0)
            Button {
                navigation.section = .browse
            } label: {
                Label("Browse & import", systemImage: "globe").font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(MacTheme.gold)
            .help("Find and import recipes in the Browse section")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Bulk actions

    @ViewBuilder
    private var bulkBar: some View {
        let shown = visible
        let reviewable = shown.filter { $0.reviewState == .needsReview }
        if shown.count > 1 {
            HStack(spacing: 6) {
                Text("\(shown.count) shown").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !reviewable.isEmpty {
                    Button("Approve \(reviewable.count)") {
                        harvest.setReviewState(.approved, for: Set(reviewable.map(\.id)))
                    }
                    .font(.caption)
                    Button("Reject") {
                        harvest.setReviewState(.rejected, for: Set(reviewable.map(\.id)))
                    }
                    .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider()
        }
    }

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            TextField("Search recipes", text: $search).textFieldStyle(.plain).font(.callout)
            Picker("", selection: $stateFilter) {
                Text("All").tag(ReviewState?.none)
                Text("Review").tag(ReviewState?.some(.needsReview))
                Text("Approved").tag(ReviewState?.some(.approved))
                Text("Rejected").tag(ReviewState?.some(.rejected))
            }
            .labelsHidden()
            .frame(width: 100)
            Button {
                onlyImageless.toggle()
            } label: {
                Image(systemName: onlyImageless ? "photo.badge.exclamationmark.fill" : "photo.badge.exclamationmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(onlyImageless ? MacTheme.gold : .secondary)
            .help("Show only recipes missing an image")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Recipe list

    @ViewBuilder
    private var recipeList: some View {
        @Bindable var harvest = harvest
        if harvest.recipes.isEmpty {
            MacEmpty(
                title: "No recipes yet",
                message: "Browse a source to discover recipes.",
                systemImage: "leaf"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(visible, selection: $harvest.selectedRecipeID) { draft in
                HStack(spacing: 8) {
                    HarvestThumbnail(draft: draft)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.title).font(.callout).lineLimit(1)
                        HStack(spacing: 5) {
                            harvestStateBadge(draft.reviewState)
                            if !(draft.image?.hasLocalFile ?? false) {
                                Text("no image")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 3))
                            }
                            if !draft.source.host.isEmpty {
                                Text(draft.source.host)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("\(Int(draft.confidence * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(draft.confidence >= 0.85 ? MacTheme.green : .secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(draft.id)
                .contextMenu {
                    Button("Approve") { harvest.setReviewState(.approved, for: [draft.id]) }
                    Button("Reject") { harvest.setReviewState(.rejected, for: [draft.id]) }
                    Divider()
                    Button("Add to Stocked") {
                        addStatus = MacHarvestBridge.summary(
                            added: MacHarvestBridge.add([draft], to: store), of: 1
                        )
                    }
                    if !draft.source.url.isEmpty {
                        Divider()
                        Button("Open in Browser") { harvest.open(draft.source.url) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { harvest.deleteRecipe(draft) }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Status footer

    private var statusFooter: some View {
        HStack(spacing: 6) {
            Text(addStatus ?? harvest.statusMessage)
                .font(.caption)
                .foregroundStyle(addStatus != nil ? MacTheme.green : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if addStatus != nil {
                Button("Clear") { addStatus = nil }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func harvestStateBadge(_ state: ReviewState) -> some View {
        let label: String
        let color: Color
        switch state {
        case .needsReview: label = "review";   color = .secondary
        case .approved:    label = "approved"; color = MacTheme.green
        case .rejected:    label = "rejected"; color = .red
        }
        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - HarvestDraftDetail

private struct HarvestDraftDetail: View {
    let draft: RecipeDraft
    @Binding var addStatus: String?

    @Environment(HarvestModel.self) private var harvest
    @Environment(MacKitchenStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    @State private var showWebPreview = false

    var body: some View {
        VStack(spacing: 0) {
            if showWebPreview, let url = URL(string: draft.source.url) {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.caption2).foregroundStyle(.secondary)
                    Text(draft.source.url)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { showWebPreview = false } label: {
                        Image(systemName: "xmark.circle").font(.caption)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
                MacWebView(url: url)
            } else {
                recipeDetail
            }
        }
    }

    private var recipeDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title, summary, pills, action buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text(draft.title)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let summary = draft.summary?.nilIfBlank {
                        Text(summary)
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 6) {
                        let pct = Int(draft.confidence * 100)
                        MacPill(
                            text: "\(pct)% confidence",
                            tint: draft.confidence >= 0.85 ? MacTheme.green
                                : draft.confidence >= 0.60 ? .orange : .red
                        )
                        if let s = draft.servings, s > 0 {
                            MacPill(text: "serves \(Int(s))", tint: .secondary, systemImage: "person.2")
                        }
                        if let cuisine = draft.cuisines.first {
                            MacPill(text: cuisine, tint: MacTheme.gold)
                        }
                    }

                    HStack(spacing: 8) {
                        Button("Approve") {
                            harvest.setReviewState(.approved, for: [draft.id])
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MacTheme.green)
                        .disabled(draft.reviewState == .approved)

                        Button("Reject") {
                            harvest.setReviewState(.rejected, for: [draft.id])
                        }
                        .disabled(draft.reviewState == .rejected)

                        Button("Add to Stocked") {
                            addStatus = MacHarvestBridge.summary(
                                added: MacHarvestBridge.add([draft], to: store), of: 1
                            )
                        }

                        Spacer(minLength: 0)

                        if !draft.source.url.isEmpty {
                            Button {
                                showWebPreview = true
                            } label: {
                                Image(systemName: "eye")
                            }
                            .buttonStyle(.borderless)
                            .help("Preview in built-in browser")

                            Button("Open in Browser") { harvest.open(draft.source.url) }
                                .buttonStyle(.borderless)
                        }
                    }
                }

                // Source
                if !draft.source.url.isEmpty {
                    MacCard {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "globe").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                let attr = draft.source.attribution.nilIfBlank ?? draft.source.host
                                if !attr.isEmpty {
                                    Text(attr).font(.callout.weight(.medium))
                                }
                                Text(draft.source.url)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }

                // Ingredients
                let allIngredients = draft.ingredientSections.flatMap { $0.items }
                MacCard(
                    title: "Ingredients",
                    systemImage: "list.bullet",
                    footnote: allIngredients.isEmpty ? nil : "\(allIngredients.count)"
                ) {
                    if allIngredients.isEmpty {
                        Text("No ingredients found.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(draft.ingredientSections.indices, id: \.self) { si in
                                let section = draft.ingredientSections[si]
                                if let name = section.name?.nilIfBlank {
                                    Text(name)
                                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                        .padding(.top, si > 0 ? 4 : 0)
                                }
                                ForEach(section.items.indices, id: \.self) { ii in
                                    Text(section.items[ii].raw)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                // Instructions
                let steps = draft.instructionSections.flatMap { $0.steps }.filter { !$0.isEmpty }
                MacCard(
                    title: "Method",
                    systemImage: "text.book.closed",
                    footnote: steps.isEmpty ? nil : "\(steps.count) steps"
                ) {
                    if steps.isEmpty {
                        Text("No instructions found.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(idx + 1)")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(MacTheme.accent(dark: scheme == .dark))
                                        .frame(width: 18, alignment: .trailing)
                                    Text(step)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                // Warnings
                if !draft.warnings.isEmpty {
                    MacCard(title: "Warnings", systemImage: "exclamationmark.triangle") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(draft.warnings, id: \.self) { warning in
                                Text("• \(warning)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Built-in WebKit browser

struct MacWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Row thumbnail (Build 91)

/// A small, cached thumbnail for a harvested draft. Loads off the main thread the first
/// time; a static cache keeps scrolling cheap without holding full-size images.
struct HarvestThumbnail: View {
    let draft: RecipeDraft
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: draft.image?.localPath) {
            guard let path = draft.image?.localPath?.nilIfBlank else {
                image = nil
                return
            }
            let key = path as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
            }
            // Loaded on the main actor deliberately: a 34-pt thumbnail from a local
            // file is cheap, and NSImage is not Sendable, so hopping executors with it
            // would trade a non-problem for a concurrency error.
            await Task.yield()
            var loaded: NSImage?
            if let full = NSImage(contentsOfFile: path) {
                let side: CGFloat = 68
                let thumb = NSImage(size: NSSize(width: side, height: side))
                thumb.lockFocus()
                full.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                          from: .zero, operation: .copy, fraction: 1)
                thumb.unlockFocus()
                loaded = thumb
            }
            if let loaded {
                Self.cache.setObject(loaded, forKey: key)
                image = loaded
            }
        }
    }
}
