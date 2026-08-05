// MacRecipesView.swift — the recipe book, list on the left, the recipe on the right.
//
// A recipe is the one thing in this app that is genuinely nicer to read on a Mac than on a
// phone: the ingredients and the method fit side by side, so you never scroll back up to
// check how much butter. That's the layout here — a narrow index, then two columns.
//
// Every ingredient line says whether it's in the kitchen. That check is the reason to keep
// an inventory at all, so it should be visible without pressing anything.

import AppKit
import SwiftUI

struct MacRecipesView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.colorScheme) private var scheme

    @State private var selection: UUID?
    @State private var search = ""
    @State private var sort: Sort = .name
    @State private var availability: Availability = .all
    @State private var favoritesOnly = false
    @State private var selectedCuisine = ""
    @State private var selectedTag = ""
    @State private var selectedDifficulty = ""
    @State private var selectedRole = ""
    @State private var editingID: UUID?
    @State private var planning: UserRecipe?
    @FocusState private var searchFocused: Bool

    private enum Sort: String, CaseIterable, Identifiable {
        case name     = "Name"
        case recent   = "Recently added"
        case cookable = "Fewest missing"
        case favorites = "Favorites first"
        case cooked = "Most cooked"
        var id: String { rawValue }
    }

    private enum Availability: String, CaseIterable, Identifiable {
        case all = "Any availability"
        case ready = "Ready to cook"
        case close = "Missing 1–2"
        case shopping = "Needs shopping"
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

        let tokens = searchTokens(search)
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
        switch availability {
        case .all: break
        case .ready: items = items.filter { store.missingIngredients(for: $0).isEmpty }
        case .close: items = items.filter { (1...2).contains(store.missingIngredients(for: $0).count) }
        case .shopping: items = items.filter { !store.missingIngredients(for: $0).isEmpty }
        }

        switch sort {
        case .name:   items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recent: items.sort { $0.dateCreated > $1.dateCreated }
        case .cookable:
            items.sort {
                let left  = store.missingIngredients(for: $0).count
                let right = store.missingIngredients(for: $1).count
                if left != right { return left < right }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .favorites:
            items.sort {
                if $0.isFavorited != $1.isFavorited { return $0.isFavorited }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .cooked:
            items.sort {
                if $0.cookCount != $1.cookCount { return $0.cookCount > $1.cookCount }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
        return items
    }

    private var current: UserRecipe? {
        guard let selection else { return rows.first }
        return rows.first { $0.id == selection } ?? rows.first
    }

    private var activeFilterCount: Int {
        (search.nilIfBlank == nil ? 0 : 1)
            + (availability == .all ? 0 : 1)
            + (favoritesOnly ? 1 : 0)
            + (selectedCuisine.isEmpty ? 0 : 1)
            + (selectedTag.isEmpty ? 0 : 1)
            + (selectedDifficulty.isEmpty ? 0 : 1)
            + (selectedRole.isEmpty ? 0 : 1)
    }

    // MARK: - Body

    var body: some View {
        @Bindable var navigation = navigation

        HStack(spacing: 0) {
            index
                .frame(width: 330)
            Divider()
            Group {
                if let recipe = current {
                    MacRecipeDetail(recipe: recipe,
                                    onEdit: { editingID = recipe.id },
                                    onPlan: { planning = recipe })
                } else if store.recipes.isEmpty {
                    MacEmpty(title: "No recipes yet",
                             message: "Add one with the + button, or join your household to bring "
                                    + "across everything already saved on your phone.",
                             systemImage: "book")
                } else {
                    MacEmpty(title: "Nothing matches",
                             message: "No recipe matches that search. Try a shorter word, or turn "
                                    + "off \"only what I can cook\".",
                             systemImage: "magnifyingglass")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $navigation.isAddingItem) {
            MacRecipeEditor(recipe: nil) { newRecipe in
                store.addRecipe(newRecipe)
                selection = newRecipe.id
            }
        }
        .sheet(item: Binding(get: { editingID.flatMap { id in store.recipes.first { $0.id == id } } },
                             set: { editingID = $0?.id })) { recipe in
            MacRecipeEditor(recipe: recipe) { updated in
                store.updateRecipe(id: recipe.id) { $0 = updated }
            }
        }
        .sheet(item: $planning) { recipe in
            MacPlanRecipeSheet(recipe: recipe)
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
                TextField("Search recipes", text: $search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .help("Use quotes for an exact phrase or prefix a word with - to exclude it")
                if !search.isEmpty {
                    Button {
                        search = ""
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

            Divider()

            List(rows, selection: $selection) { recipe in
                indexRow(recipe)
                    .tag(recipe.id)
                    .contextMenu {
                        Button("Edit…") { editingID = recipe.id }
                        Button(recipe.isFavorited ? "Remove from favourites" : "Add to favourites") {
                            store.toggleFavorite(recipeID: recipe.id)
                        }
                        Button("Plan this…") { planning = recipe }
                        Divider()
                        Button("Add what's missing to the list") {
                            store.addMissingIngredients(for: recipe)
                        }
                        Button("Copy ingredients") { copyIngredients(recipe) }
                        Divider()
                        Button("Delete", role: .destructive) {
                            store.deleteRecipe(ids: [recipe.id])
                            if selection == recipe.id { selection = nil }
                        }
                    }
            }
            .listStyle(.sidebar)

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
        let missing = store.missingIngredients(for: recipe)
        return HStack(spacing: 9) {
            recipeThumbnail(recipe, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if recipe.isFavorited {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(MacTheme.gold)
                    }
                    Text(recipe.title).font(.callout.weight(.medium)).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if missing.isEmpty {
                        Label("ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(MacTheme.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text("needs \(missing.count)")
                            .font(.caption)
                            .foregroundStyle(missing.count <= 2 ? MacTheme.low : .secondary)
                    }
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
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(recipe.title), \(missing.isEmpty ? "ready to cook" : "missing \(missing.count) ingredients")")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Availability", selection: $availability) {
                ForEach(Availability.allCases) { Text($0.rawValue).tag($0) }
            }
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
        search = ""
        availability = .all
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
    let onPlan: () -> Void

    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.colorScheme) private var scheme

    private var missing: [String] { store.missingIngredients(for: recipe) }

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
                }
                header
                if !recipe.description.isEmpty {
                    Text(recipe.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statusCard

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
                Button("Plan this…", action: onPlan)
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

    private var statusCard: some View {
        MacCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: missing.isEmpty ? "checkmark.circle.fill" : "cart.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(missing.isEmpty ? MacTheme.green : MacTheme.low)
                VStack(alignment: .leading, spacing: 2) {
                    Text(missing.isEmpty
                         ? "You can cook this right now."
                         : "You're missing \(missing.count) ingredient\(missing.count == 1 ? "" : "s").")
                        .font(.callout.weight(.medium))
                    if !missing.isEmpty {
                        Text(missing.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if !missing.isEmpty {
                    Button("Add \(missing.count) to the list") {
                        store.addMissingIngredients(for: recipe)
                        navigation.section = .grocery
                    }
                }
            }
        }
    }

    private var ingredientsCard: some View {
        MacCard(title: "Ingredients", systemImage: "list.bullet",
                footnote: "\(recipe.ingredients.count)") {
            if recipe.ingredients.isEmpty {
                Text("None listed.").font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recipe.ingredients) { ingredient in
                        let onHand = store.hasOnHand(ingredient.name)
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: onHand ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(onHand ? MacTheme.green : Color.secondary.opacity(0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ingredient.name)
                                    .font(.callout)
                                    .foregroundStyle(onHand ? .primary : .secondary)
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
    @State private var loaded = false

    private let difficulties = ["Easy", "Medium", "Hard"]

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Button(recipe == nil ? "Add" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(14)
        }
        .frame(width: 560, height: 700)
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
        ingredientsText = recipe.ingredients
            .map { $0.amount.isEmpty ? $0.name : "\($0.name), \($0.amount)" }
            .joined(separator: "\n")
        stepsText = recipe.instructions.joined(separator: "\n")
    }

    private func commit() {
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
