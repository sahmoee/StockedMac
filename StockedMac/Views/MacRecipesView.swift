// MacRecipesView.swift — the recipe book, list on the left, the recipe on the right.
//
// A recipe is the one thing in this app that is genuinely nicer to read on a Mac than on a
// phone: the ingredients and the method fit side by side, so you never scroll back up to
// check how much butter. That's the layout here — a narrow index, then two columns.
//
// Every ingredient line says whether it's in the kitchen. That check is the reason to keep
// an inventory at all, so it should be visible without pressing anything.

import AppKit
import QuickLook
import SwiftUI

struct MacRecipesView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacDesktopExperience.self) private var desktop
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    @State private var selection: UUID?
    @State private var sort: Sort = .name
    @State private var favoritesOnly = false
    @State private var selectedCuisine = ""
    @State private var selectedTag = ""
    @State private var selectedDifficulty = ""
    @State private var selectedRole = ""
    @State private var editingID: UUID?
    @State private var previewURL: URL?
    @State private var pendingDeletion: UserRecipe?
    @State private var previewError: String?
    @FocusState private var searchFocused: Bool

    private enum Sort: String, CaseIterable, Identifiable {
        case name     = "Name"
        case recent   = "Recently added"
        case favorites = "Favorites first"
        case oldest = "Oldest added"
        case updated = "Recently updated"
        case source = "Source"
        case ingredients = "Fewest ingredients"
        var id: String { rawValue }
    }

    private var cuisines: [String] {
        uniqueSorted(store.recipes.compactMap { $0.cuisine.nilIfBlank })
    }

    private var tags: [String] {
        uniqueSorted(store.recipes.flatMap(\.tags).compactMap(\.nilIfBlank))
    }

    private var difficulties: [String] {
        uniqueSorted(store.recipes.compactMap { $0.difficulty.nilIfBlank })
    }

    private var roles: [DishRole] {
        DishRole.allCases.filter { role in
            store.recipes.contains { $0.dishRole == role }
        }
    }

    private var rows: [UserRecipe] {
        var items = store.recipes

        let tokens = searchTokens(navigation.searchText)
        if !tokens.isEmpty { items = items.filter { matchesSearch($0, tokens: tokens) } }
        if favoritesOnly { items = items.filter(\.isFavorited) }
        if !selectedCuisine.isEmpty {
            items = items.filter { $0.cuisine.compare(selectedCuisine, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
        if !selectedTag.isEmpty {
            items = items.filter { recipe in
                recipe.tags.contains { $0.compare(selectedTag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            }
        }
        if !selectedDifficulty.isEmpty {
            items = items.filter { $0.difficulty == selectedDifficulty }
        }
        if !selectedRole.isEmpty {
            items = items.filter { $0.dishRole.rawValue == selectedRole }
        }
        switch sort {
        case .name:   items.sort(by: titleOrder)
        case .recent: items.sort { $0.dateCreated == $1.dateCreated ? titleOrder($0, $1) : $0.dateCreated > $1.dateCreated }
        case .oldest: items.sort { $0.dateCreated == $1.dateCreated ? titleOrder($0, $1) : $0.dateCreated < $1.dateCreated }
        case .updated: items.sort { $0.updatedAt == $1.updatedAt ? titleOrder($0, $1) : $0.updatedAt > $1.updatedAt }
        case .source:
            items.sort {
                let a = $0.sourceName ?? "", b = $1.sourceName ?? ""
                return a == b ? titleOrder($0, $1) : a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        case .ingredients:
            items.sort { $0.ingredients.count == $1.ingredients.count ? titleOrder($0, $1) : $0.ingredients.count < $1.ingredients.count }
        case .favorites:
            items.sort {
                if $0.isFavorited != $1.isFavorited { return $0.isFavorited }
                return titleOrder($0, $1)
            }
        }
        return items
    }

    private func titleOrder(_ a: UserRecipe, _ b: UserRecipe) -> Bool {
        let order = RecipeTitlePolicy.sortKey(a.title).localizedCaseInsensitiveCompare(RecipeTitlePolicy.sortKey(b.title))
        return order == .orderedSame ? a.id.uuidString < b.id.uuidString : order == .orderedAscending
    }

    private var current: UserRecipe? {
        guard let selection else { return rows.first }
        return rows.first { $0.id == selection } ?? rows.first
    }

    private var activeFilterCount: Int {
        (navigation.searchText.nilIfBlank == nil ? 0 : 1)
            + (favoritesOnly ? 1 : 0)
            + (selectedCuisine.isEmpty ? 0 : 1)
            + (selectedTag.isEmpty ? 0 : 1)
            + (selectedDifficulty.isEmpty ? 0 : 1)
            + (selectedRole.isEmpty ? 0 : 1)
    }

    // MARK: - Body

    var body: some View {
        @Bindable var navigation = navigation

        MacAdjustableSplit(
            initialLeadingWidth: 330,
            minimumLeadingWidth: 220,
            maximumLeadingWidth: 500,
            minimumTrailingWidth: 320
        ) {
            index
        } trailing: {
            Group {
                if let recipe = current {
                    MacRecipeDetail(recipe: recipe, onEdit: { editingID = recipe.id })
                } else if store.recipes.isEmpty {
                    MacEmpty(title: "No recipes yet",
                             message: "Add one with the + button, or join your household to bring "
                                    + "across everything already saved on your phone.",
                             systemImage: "book")
                } else {
                    VStack(spacing: 12) {
                        MacEmpty(title: "Nothing matches", message: "Try another search or reset your recipe filters.", systemImage: "magnifyingglass")
                        Button("Reset search and filters") { resetFilters() }
                    }.padding()
                }
            }
        }
        .macThemedSurface()
        .searchable(text: searchBinding, placement: .toolbar, prompt: "Search all recipe fields")
        .inspector(isPresented: Binding(
            get: { desktop.isInspectorPresented },
            set: { desktop.isInspectorPresented = $0 }
        )) { recipeInspector }
        .quickLookPreview($previewURL)
        .onDeleteCommand { deleteCurrentRecipe() }
        .confirmationDialog("Delete recipe?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let recipe = pendingDeletion else { return }
                store.deleteRecipe(ids: [recipe.id])
                if selection == recipe.id { selection = nil }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Remove “\(pendingDeletion?.title ?? "")” from your recipe library? This change also syncs to your household.")
        }
        .alert("Quick Look unavailable", isPresented: Binding(
            get: { previewError != nil }, set: { if !$0 { previewError = nil } }
        )) { Button("OK") { previewError = nil } } message: { Text(previewError ?? "") }
        .sheet(isPresented: $navigation.isAddingItem) {
            MacRecipeEditor(recipe: nil) { newRecipe in
                store.addRecipe(newRecipe)
                selection = newRecipe.id
            }
            .macThemedSurface()
        }
        .sheet(item: Binding(get: { editingID.flatMap { id in store.recipes.first { $0.id == id } } },
                             set: { editingID = $0?.id })) { recipe in
            MacRecipeEditor(recipe: recipe) { updated in
                store.updateRecipe(id: recipe.id) { $0 = updated }
            }
            .macThemedSurface()
        }
        .onChange(of: store.recipes.filter { $0.lastWriterID != "shared-catalogue" }.map { "\($0.id):\($0.updatedAt)" }) {
            harvest.syncKitchenToCloud(store.recipes)
        }
        .onChange(of: rows.map(\.id)) {
            let ids = Set(rows.map(\.id))
            if let selection, ids.contains(selection) { return }
            selection = rows.first?.id
        }
    }

    // MARK: - Index

    private var index: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search recipes", text: searchBinding)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .help("Use quotes for an exact phrase or prefix a word with - to exclude it")
                if !navigation.searchText.isEmpty {
                    Button {
                        navigation.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 7) {
                Button {
                    Task { await MacPublicRecipeSync.shared.refresh(store: store, maxPages: 8) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(MacPublicRecipeSync.shared.isSyncing)
                .help(MacPublicRecipeSync.shared.status)
                Text(rows.count == store.recipes.count
                     ? "\(rows.count) recipes"
                     : "\(rows.count) of \(store.recipes.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if activeFilterCount > 0 {
                    MacPill(text: "\(activeFilterCount) filter\(activeFilterCount == 1 ? "" : "s")",
                            tint: MacTheme.gold)
                }
                Spacer(minLength: 0)
                Button {
                    guard let pick = rows.randomElement() else { return }
                    selection = pick.id
                } label: {
                    Image(systemName: "dice")
                }
                .buttonStyle(.borderless)
                .disabled(rows.isEmpty)
                .help("Surprise me from these results")
                if activeFilterCount > 0 {
                    Button("Reset") { resetFilters() }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Text(MacPublicRecipeSync.shared.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            if MacPublicRecipeSync.shared.isSyncing {
                ProgressView().controlSize(.small).padding(.bottom, 6)
            } else if let date = MacPublicRecipeSync.shared.lastCompletedAt {
                Text("Last complete refresh: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }

            Divider()

            recipeCollection

            Divider()

            HStack(spacing: 8) {
                Picker("", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 155)
                Spacer(minLength: 0)
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .foregroundStyle(favoritesOnly ? MacTheme.gold : .secondary)
                }
                .buttonStyle(.borderless)
                .help(favoritesOnly ? "Show all recipes" : "Favorites only")
                filterMenu
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }

    private func indexRow(_ recipe: UserRecipe) -> some View {
        HStack(spacing: 9) {
            recipeThumbnail(recipe, size: desktop.density.thumbnailSize)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if recipe.isFavorited {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(MacTheme.gold)
                    }
                    Text(recipe.title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text(recipe.sourceName?.nilIfBlank ?? "Personal recipe")
                        .font(.caption).foregroundStyle(.secondary)
                    if !recipe.cookTime.isEmpty {
                        Text("· \(recipe.cookTime)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    if !recipe.cuisine.isEmpty {
                        Text(recipe.cuisine).lineLimit(1)
                    }
                    if let tag = recipe.tags.first?.nilIfBlank {
                        Text("· \(tag)").lineLimit(1)
                    }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, desktop.density.rowPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recipe.title)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openWindow(id: "recipe", value: recipe.id) }
        .draggable(recipe.id.uuidString)
    }

    @ViewBuilder
    private var recipeCollection: some View {
        switch desktop.recipeMode {
        case .list:
            List(rows, selection: $selection) { recipe in
                indexRow(recipe)
                    .tag(recipe.id)
                    .contextMenu { recipeMenu(recipe) }
            }
            .listStyle(.sidebar)
        case .table:
            Table(rows, selection: $selection) {
                TableColumn("Recipe") { recipe in
                    HStack(spacing: 7) {
                        recipeThumbnail(recipe, size: desktop.density.thumbnailSize)
                        Text(recipe.title).lineLimit(2)
                    }
                    .contextMenu { recipeMenu(recipe) }
                }
                TableColumn("Cuisine") { recipe in Text(recipe.cuisine.nilIfBlank ?? "—") }
                    .width(min: 80, ideal: 110)
                TableColumn("Source") { recipe in Text(recipe.sourceName?.nilIfBlank ?? "Personal") }
                    .width(min: 90, ideal: 130)
                TableColumn("Added") { recipe in Text(recipe.dateCreated, style: .date) }
                    .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    @ViewBuilder
    private func recipeMenu(_ recipe: UserRecipe) -> some View {
        Button("Open in New Window") { openWindow(id: "recipe", value: recipe.id) }
        Button("Quick Look") { preview(recipe) }
        Button("Edit…") { editingID = recipe.id }
        Button(recipe.isFavorited ? "Remove from favourites" : "Add to favourites") {
            store.toggleFavorite(recipeID: recipe.id)
        }
        Button("Copy ingredients") { copyIngredients(recipe) }
        if let raw = recipe.sourceURL, let url = URL(string: raw), url.scheme == "https" {
            Link("Open original source", destination: url)
            Button("Copy source link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            pendingDeletion = recipe
        }
    }

    @ViewBuilder
    private var recipeInspector: some View {
        if let recipe = current {
            Form {
                Section("Recipe") {
                    LabeledContent("Cuisine", value: recipe.cuisine.nilIfBlank ?? "Not set")
                    LabeledContent("Role", value: recipe.dishRole.label)
                    LabeledContent("Difficulty", value: recipe.difficulty)
                    LabeledContent("Servings", value: "\(recipe.servings)")
                    LabeledContent("Ingredients", value: "\(recipe.ingredients.count)")
                    LabeledContent("Steps", value: "\(recipe.instructions.count)")
                }
                Section("Provenance") {
                    LabeledContent("Source", value: recipe.sourceName?.nilIfBlank ?? "Personal recipe")
                    if let raw = recipe.sourceURL?.nilIfBlank, let url = URL(string: raw) {
                        Link("Open original", destination: url)
                    }
                    LabeledContent("Added") { Text(recipe.dateCreated, style: .date) }
                }
                Section {
                    Button("Open in New Window") { openWindow(id: "recipe", value: recipe.id) }
                    Button("Quick Look") { preview(recipe) }
                    Button("Edit…") { editingID = recipe.id }
                }
            }
            .formStyle(.grouped)
            .inspectorColumnWidth(min: 220, ideal: 270, max: 360)
        } else {
            MacEmpty(title: "No recipe selected", message: "Select a recipe to inspect its details.", systemImage: "sidebar.right")
                .inspectorColumnWidth(min: 220, ideal: 270, max: 360)
        }
    }

    private func deleteCurrentRecipe() {
        guard let selection, let recipe = store.recipes.first(where: { $0.id == selection }) else { return }
        pendingDeletion = recipe
    }

    private func preview(_ recipe: UserRecipe) {
        let ingredients = recipe.ingredients.map {
            "• " + ($0.amount.isEmpty ? $0.name : "\($0.amount) \($0.name)")
        }.joined(separator: "\n")
        let method = recipe.instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let value = "\(recipe.title)\n\n\(recipe.description)\n\nINGREDIENTS\n\(ingredients)\n\nMETHOD\n\(method)\n"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Stocked-QuickLook", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Recipe-\(recipe.id.uuidString).txt")
        do { try value.write(to: url, atomically: true, encoding: .utf8); previewURL = url }
        catch { previewError = "The preview could not be saved. Check available disk space and try again." }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("Favorites only", isOn: $favoritesOnly)
            Divider()
            facetMenu("Cuisine", values: cuisines, selection: $selectedCuisine)
            facetMenu("Tag", values: tags, selection: $selectedTag)
            facetMenu("Difficulty", values: difficulties, selection: $selectedDifficulty)
            Menu("Recipe role") {
                Button("Any role") { selectedRole = "" }
                Divider()
                ForEach(roles, id: \.rawValue) { role in
                    Button {
                        selectedRole = role.rawValue
                    } label: {
                        if selectedRole == role.rawValue {
                            Label(role.label, systemImage: "checkmark")
                        } else {
                            Text(role.label)
                        }
                    }
                }
            }
            if activeFilterCount > 0 {
                Divider()
                Button("Reset all filters") { resetFilters() }
            }
        } label: {
            Label(activeFilterCount > 0 ? "Filters \(activeFilterCount)" : "Filters",
                  systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
    }

    private func facetMenu(
        _ title: String,
        values: [String],
        selection: Binding<String>
    ) -> some View {
        Menu(title) {
            Button("Any \(title.lowercased())") { selection.wrappedValue = "" }
            Divider()
            ForEach(values, id: \.self) { value in
                Button {
                    selection.wrappedValue = value
                } label: {
                    if selection.wrappedValue == value {
                        Label(value, systemImage: "checkmark")
                    } else {
                        Text(value)
                    }
                }
            }
        }
    }

    private func recipeThumbnail(_ recipe: UserRecipe, size: CGFloat) -> some View {
        Group {
            if let data = recipe.imageData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let rawURL = recipe.imageURL, let url = URL(string: rawURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.10)
                }
            } else {
                ZStack {
                    Color.secondary.opacity(0.10)
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        var originalsByKey: [String: String] = [:]
        for value in values {
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            originalsByKey[key] = originalsByKey[key] ?? value
        }
        return originalsByKey.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func resetFilters() {
        navigation.searchText = ""
        favoritesOnly = false
        selectedCuisine = ""
        selectedTag = ""
        selectedDifficulty = ""
        selectedRole = ""
    }

    private func copyIngredients(_ recipe: UserRecipe) {
        let value = recipe.ingredients.map { ingredient in
            ingredient.amount.isEmpty ? ingredient.name : "\(ingredient.amount) \(ingredient.name)"
        }.joined(separator: "\n")
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var searchBinding: Binding<String> {
        Binding(get: { navigation.searchText }, set: { navigation.searchText = $0 })
    }

    private struct SearchToken {
        let value: String
        let excluded: Bool
    }

    private func searchTokens(_ query: String) -> [SearchToken] {
        var rawTerms: [String] = []
        var current = ""
        var inQuotes = false
        for character in query {
            if character == "\"" {
                inQuotes.toggle()
            } else if character.isWhitespace && !inQuotes {
                if !current.isEmpty { rawTerms.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { rawTerms.append(current) }
        return rawTerms.compactMap { term in
            let excluded = term.hasPrefix("-")
            let raw = excluded ? String(term.dropFirst()) : term
            let normalized = normalizedSearchText(raw)
            return normalized.isEmpty ? nil : SearchToken(value: normalized, excluded: excluded)
        }
    }

    private func matchesSearch(_ recipe: UserRecipe, tokens: [SearchToken]) -> Bool {
        let corpus = normalizedSearchText([
            recipe.title, recipe.description, recipe.cuisine, recipe.difficulty,
            recipe.dishRole.label, recipe.tags.joined(separator: " "),
            recipe.ingredientNames.joined(separator: " "),
            recipe.instructions.joined(separator: " "), recipe.notes
        ].joined(separator: " "))
        return tokens.allSatisfy { token in
            token.excluded ? !corpus.contains(token.value) : corpus.contains(token.value)
        }
    }

    private func normalizedSearchText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

// MARK: - Detail

struct MacRecipeDetail: View {
    let recipe: UserRecipe
    let onEdit: () -> Void

    @Environment(MacKitchenStore.self) private var store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let data = recipe.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .clipped()
                        .accessibilityLabel("Photo of \(recipe.title)")
                } else if let rawURL = recipe.imageURL, let url = URL(string: rawURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .clipped()
                    .accessibilityLabel("Photo of \(recipe.title)")
                }
                header
                if !recipe.description.isEmpty {
                    Text(recipe.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recipe.sourceName?.nilIfBlank != nil || recipe.attributedSourceURL?.nilIfBlank != nil || recipe.author?.nilIfBlank != nil || recipe.license?.nilIfBlank != nil || recipe.imageAttribution?.nilIfBlank != nil {
                    MacCard(title: "Source", systemImage: "link") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.sourceName?.nilIfBlank ?? "Original source")
                            if let source = recipe.attributedSourceURL?.nilIfBlank,
                               let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                                Link(source, destination: url).font(.caption).lineLimit(1)
                            }
                            if let author = recipe.author?.nilIfBlank { Text("Author: " + author).font(.caption) }
                            if let license = recipe.license?.nilIfBlank { Text("Recipe license: " + license).font(.caption) }
                            if let credit = recipe.imageAttribution?.nilIfBlank { Text("Photo credit: " + credit).font(.caption) }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ingredientsCard.frame(maxWidth: 340)
                        methodCard
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ingredientsCard
                        methodCard
                    }
                }

                if !recipe.notes.isEmpty {
                    MacCard(title: "Notes", systemImage: "note.text") {
                        Text(recipe.notes)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(recipe.title).font(.system(size: 21, weight: .semibold))
                Spacer(minLength: 8)
                Button {
                    store.toggleFavorite(recipeID: recipe.id)
                } label: {
                    Image(systemName: recipe.isFavorited ? "star.fill" : "star")
                        .foregroundStyle(MacTheme.gold)
                }
                .buttonStyle(.borderless)
                .help(recipe.isFavorited ? "Remove from favourites" : "Add to favourites")
                Button("Edit…", action: onEdit)
                Menu {
                    Button("Copy full recipe") { copyRecipe() }
                    Button("Copy ingredients") { copyIngredients() }
                    Button("Copy method") { copyMethod() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .help("Copy recipe")
            }
            HStack(spacing: 6) {
                if !recipe.cookTime.isEmpty {
                    MacPill(text: recipe.cookTime, tint: .secondary, systemImage: "clock")
                }
                if !recipe.prepTime.isEmpty {
                    MacPill(text: "\(recipe.prepTime) prep", tint: .secondary, systemImage: "timer")
                }
                MacPill(text: "serves \(recipe.servings)", tint: .secondary, systemImage: "person.2")
                MacPill(text: recipe.difficulty, tint: .secondary)
                if !recipe.cuisine.isEmpty {
                    MacPill(text: recipe.cuisine, tint: MacTheme.gold)
                }
                if recipe.dishRole != .unspecified {
                    MacPill(text: recipe.dishRole.label, tint: MacTheme.gold)
                }
                if recipe.cookCount > 0 {
                    MacPill(text: "cooked \(recipe.cookCount)×", tint: MacTheme.green)
                }
            }
            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            MacPill(text: tag, tint: .secondary, systemImage: "tag")
                        }
                    }
                }
            }
        }
    }

    private func copyRecipe() {
        let ingredients = recipe.ingredients.map { ingredient in
            "• " + (ingredient.amount.isEmpty
                     ? ingredient.name
                     : "\(ingredient.amount) \(ingredient.name)")
        }.joined(separator: "\n")
        let method = recipe.instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        copy("\(recipe.title)\n\nIngredients\n\(ingredients)\n\nMethod\n\(method)")
    }

    private func copyIngredients() {
        copy(recipe.ingredients.map {
            $0.amount.isEmpty ? $0.name : "\($0.amount) \($0.name)"
        }.joined(separator: "\n"))
    }

    private func copyMethod() {
        copy(recipe.instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n"))
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var ingredientsCard: some View {
        MacCard(title: "Ingredients", systemImage: "list.bullet",
                footnote: "\(recipe.ingredients.count)") {
            if recipe.ingredients.isEmpty {
                Text("None listed.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipe.ingredients) { ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ingredient.name)
                                    .font(.callout)
                                if let prep = ingredient.prep, !prep.isEmpty {
                                    Text(prep).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 6)
                            if ingredient.isOptional {
                                MacPill(text: "optional", tint: .secondary)
                            }
                            if !ingredient.amount.isEmpty {
                                Text(ingredient.amount)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var methodCard: some View {
        MacCard(title: "Method", systemImage: "text.book.closed",
                footnote: recipe.instructions.isEmpty ? nil : "\(recipe.instructions.count) steps") {
            if recipe.instructions.isEmpty {
                Text("No steps written down yet. Use Edit to add them.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text("\(pair.offset + 1)")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(MacTheme.accent(dark: scheme == .dark))
                                .frame(width: 16, alignment: .trailing)
                            Text(pair.element)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Plan sheet

/// Small sheet for "put this on a day". Kept separate from the week view so a recipe can
/// be planned without leaving the book.
struct MacPlanRecipeSheet: View {
    let recipe: UserRecipe

    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var dayIndex = 0
    @State private var mealType = "Dinner"
    @State private var alsoAddMissing = true

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    var body: some View {
        VStack(spacing: 0) {
            Text("Plan \(recipe.title)")
                .font(.headline)
                .padding(.top, 16).padding(.bottom, 10)
                .padding(.horizontal, 16)
                .multilineTextAlignment(.center)

            Form {
                Picker("Day", selection: $dayIndex) {
                    ForEach(0..<7, id: \.self) { offset in
                        Text(MacWeek.label(for: offset)).tag(offset)
                    }
                }
                Picker("Meal", selection: $mealType) {
                    ForEach(mealTypes, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Also add what's missing to the grocery list", isOn: $alsoAddMissing)
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Plan it") {
                    store.planMeal(recipe: recipe, dayIndex: dayIndex, mealType: mealType)
                    if alsoAddMissing { store.addMissingIngredients(for: recipe) }
                    dismiss()
                    navigation.section = .plan
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 400, height: 300)
    }
}

// MARK: - Editor

/// Ingredients and steps are edited as plain text, one per line. A row-by-row editor looks
/// tidier in a screenshot and is slower to use for anyone who has the recipe in front of
/// them: pasting eleven lines should be one paste, not eleven Add buttons.
struct MacRecipeEditor: View {
    let recipe: UserRecipe?
    let onSave: (UserRecipe) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var summary = ""
    @State private var cookTime = ""
    @State private var prepTime = ""
    @State private var servings = 4
    @State private var difficulty = "Medium"
    @State private var cuisine = ""
    @State private var role: DishRole = .unspecified
    @State private var ingredientsText = ""
    @State private var stepsText = ""
    @State private var notes = ""
    @State private var sourceName = ""
    @State private var sourceURL = ""
    @State private var categoriesText = ""
    @State private var tagsText = ""
    @State private var imageURL = ""
    @State private var loaded = false
    @State private var isResolvingImage = false
    @State private var imageError: String?

    private let difficulties = ["Easy", "Medium", "Hard"]

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (MacRecipeImagePolicy.isUsable(recipe?.imageData) || URL(string: imageURL)?.scheme == "https")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(recipe == nil ? "New recipe" : "Edit recipe")
                .font(.headline)
                .padding(.top, 16).padding(.bottom, 10)

            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("One-line description", text: $summary)
                }

                Section("Details") {
                    HStack {
                        TextField("Cook time", text: $cookTime)
                        TextField("Prep time", text: $prepTime)
                    }
                    Stepper("Serves \(servings)", value: $servings, in: 1...24)
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(difficulties, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Cuisine", text: $cuisine)
                    Picker("Role", selection: $role) {
                        ForEach(DishRole.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Categories (comma separated)", text: $categoriesText)
                    TextField("Tags (comma separated)", text: $tagsText)
                }

                Section("Original source") {
                    TextField("Publisher or author", text: $sourceName)
                    TextField("Recipe URL", text: $sourceURL)
                }

                Section("Required image") {
                    TextField("HTTPS image URL", text: $imageURL)
                    if let imageError {
                        Text(imageError).font(.caption).foregroundStyle(.red)
                    } else {
                        Text("The image is downloaded and decoded before this recipe can be saved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Ingredients — one per line, \"name, amount\"") {
                    TextEditor(text: $ingredientsText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 110)
                }

                Section("Method — one step per line") {
                    TextEditor(text: $stepsText)
                        .font(.system(size: 12))
                        .frame(minHeight: 110)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .font(.system(size: 12))
                        .frame(minHeight: 60)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { await commit() }
                } label: {
                    if isResolvingImage { ProgressView().controlSize(.small) }
                    else { Text(recipe == nil ? "Add" : "Save") }
                }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isResolvingImage)
            }
            .padding(14)
        }
        .frame(width: 580, height: 780)
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let recipe else { return }
        title      = recipe.title
        summary    = recipe.description
        cookTime   = recipe.cookTime
        prepTime   = recipe.prepTime
        servings   = recipe.servings
        difficulty = difficulties.contains(recipe.difficulty) ? recipe.difficulty : "Medium"
        cuisine    = recipe.cuisine
        role       = recipe.dishRole
        notes      = recipe.notes
        sourceName = recipe.sourceName ?? ""
        sourceURL = recipe.attributedSourceURL ?? ""
        categoriesText = (recipe.categories ?? []).joined(separator: ", ")
        tagsText = recipe.tags.joined(separator: ", ")
        imageURL = recipe.imageURL ?? ""
        ingredientsText = recipe.ingredients
            .map { $0.amount.isEmpty ? $0.name : "\($0.name), \($0.amount)" }
            .joined(separator: "\n")
        stepsText = recipe.instructions.joined(separator: "\n")
    }

    private func commit() async {
        isResolvingImage = true
        imageError = nil
        defer { isResolvingImage = false }
        var result = recipe ?? UserRecipe(title: "")
        result.title       = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.description = summary
        result.cookTime    = cookTime
        result.prepTime    = prepTime
        result.servings    = servings
        result.difficulty  = difficulty
        result.cuisine     = cuisine
        result.dishRole    = role
        result.notes       = notes
        result.sourceName  = sourceName.nilIfBlank
        result.sourceURL   = sourceURL.nilIfBlank
        if let original = result.portableSource, original.catalogueSharingApproved != true {
            result.portableSource?.originalSourceURL = sourceURL.nilIfBlank
            result.sourceURL = nil
        }
        result.categories  = Self.parseList(categoriesText)
        result.tags        = Self.parseList(tagsText)
        result.imageURL    = imageURL.nilIfBlank
        if !MacRecipeImagePolicy.isUsable(result.imageData) || result.imageURL != recipe?.imageURL {
            guard let imageURL = result.imageURL else {
                imageError = "Add an HTTPS image URL."
                return
            }
            do {
                result.imageData = try await MacRecipeImagePolicy.download(imageURL, referer: result.sourceURL)
            } catch {
                imageError = error.localizedDescription
                return
            }
        }
        guard MacRecipeImagePolicy.isUsable(result.imageData) else {
            imageError = "This recipe needs a usable image before it can be saved."
            return
        }
        result.ingredients = Self.parseIngredients(ingredientsText)
        result.instructions = stepsText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        onSave(result)
        dismiss()
    }

    /// "flour, 2 cups" → name "flour", amount "2 cups". A line with no comma is all name,
    /// which is the common case when someone is jotting things down quickly.
    static func parseIngredients(_ text: String) -> [RecipeIngredient] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            guard let comma = trimmed.firstIndex(of: ",") else {
                return RecipeIngredient(name: trimmed, amount: "")
            }
            let name = String(trimmed[trimmed.startIndex..<comma])
                .trimmingCharacters(in: .whitespaces)
            let amount = String(trimmed[trimmed.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
            return RecipeIngredient(name: name.isEmpty ? trimmed : name, amount: amount)
        }
    }

    private static func parseList(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return seen.insert(key).inserted ? value : nil
        }
    }
}

// MARK: - Week labels

/// Shared between the recipe plan sheet and the week view so "Wednesday" means the same
/// day in both places.
nonisolated enum MacWeek {
    static let dayCount = 7

    static func date(for offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    static func label(for offset: Int) -> String {
        switch offset {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        default: return weekday.string(from: date(for: offset))
        }
    }

    static func shortLabel(for offset: Int) -> String {
        weekdayShort.string(from: date(for: offset))
    }

    static func dayNumber(for offset: Int) -> String {
        String(Calendar.current.component(.day, from: date(for: offset)))
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let weekdayShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
