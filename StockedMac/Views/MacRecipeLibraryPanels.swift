// MacRecipeLibraryPanels.swift — library-wide recipe management sheets.
//
// Build 114: Library Health, Duplicate Finder, Tag Manager and Bulk Edit. Every change
// goes through MacKitchenStore (updateRecipes / deleteRecipe) so household tombstones,
// last-write stamping, portable-source privacy repair and the required-image gate keep
// working exactly as they do for single-recipe edits. Destructive actions always confirm.

import SwiftUI

// MARK: - Shared chrome

private struct MacPanelHeader: View {
    let title: String
    let systemImage: String
    let subtitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(MacTheme.gold)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }
}

// MARK: - Library health

struct MacLibraryHealthView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacDesktopExperience.self) private var desktop
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var report = MacRecipeHealth.Report()
    @State private var selectedIssue: MacRecipeHealthIssue?
    @State private var isScanning = false

    private var titles: [UUID: UserRecipe] {
        Dictionary(store.recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(spacing: 0) {
            MacPanelHeader(title: "Library Health", systemImage: "stethoscope",
                           subtitle: "Finds recipes with missing details so they sort, filter and publish well. Nothing is changed until you edit a recipe.")
            Divider()
            if isScanning {
                ProgressView("Checking \(store.recipes.count) recipes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MacAdjustableSplit(initialLeadingWidth: 280, minimumLeadingWidth: 220,
                                   maximumLeadingWidth: 380, minimumTrailingWidth: 300) {
                    issueList
                } trailing: {
                    recipeList
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 520, idealHeight: 640)
        .task(id: store.recipes.count) { await scan() }
    }

    private var issueList: some View {
        List(selection: $selectedIssue) {
            Section {
                HStack {
                    Gauge(value: Double(report.healthyPercent), in: 0...100) {
                        Text("Healthy")
                    } currentValueLabel: {
                        Text("\(report.healthyPercent)%")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(report.healthyPercent >= 80 ? MacTheme.green : MacTheme.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(report.total - report.affectedCount) of \(report.total) complete")
                            .font(.callout.weight(.medium))
                        Text("\(report.affectedCount) need attention").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Issues") {
                ForEach(MacRecipeHealthIssue.allCases) { issue in
                    let count = report.byIssue[issue]?.count ?? 0
                    Label {
                        HStack {
                            Text(issue.rawValue)
                            Spacer()
                            Text("\(count)").font(.caption.monospacedDigit())
                                .foregroundStyle(count == 0 ? MacTheme.green : .secondary)
                        }
                    } icon: {
                        Image(systemName: count == 0 ? "checkmark.circle.fill" : issue.systemImage)
                            .foregroundStyle(count == 0 ? MacTheme.green : MacTheme.gold)
                    }
                    .tag(issue)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var recipeList: some View {
        if let issue = selectedIssue {
            let ids = report.byIssue[issue] ?? []
            let lookup = titles
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.rawValue).font(.headline)
                    Text(issue.advice).font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                Divider()
                if ids.isEmpty {
                    MacEmpty(title: "All clear", message: "No recipe has this issue.", systemImage: "checkmark.seal")
                } else {
                    List(ids.prefix(500), id: \.self) { id in
                        if let recipe = lookup[id] {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title).lineLimit(2)
                                    Text(recipe.sourceName?.nilIfBlank ?? "Personal recipe")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Show") { reveal(id) }.buttonStyle(.borderless)
                                Button("Edit…") { edit(id) }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if ids.count > 500 {
                        Text("Showing the first 500 of \(ids.count). Use the Recipes scope filter “Needs attention” for the complete list.")
                            .font(.caption).foregroundStyle(.secondary).padding(10)
                    }
                }
            }
        } else {
            MacEmpty(title: "Choose an issue", message: "Select an issue to see the recipes it affects.", systemImage: "list.bullet.clipboard")
        }
    }

    private func scan() async {
        isScanning = true
        let snapshot = store.recipes
        let result = await Task.detached(priority: .utility) { MacRecipeHealth.report(snapshot) }.value
        report = result
        if selectedIssue == nil {
            selectedIssue = MacRecipeHealthIssue.allCases.first { !(result.byIssue[$0] ?? []).isEmpty }
        }
        isScanning = false
    }

    private func reveal(_ id: UUID) {
        navigation.section = .recipes
        desktop.reveal(id)
        dismiss()
    }

    private func edit(_ id: UUID) {
        navigation.section = .recipes
        desktop.reveal(id)
        desktop.pendingEditRecipeID = id
        dismiss()
    }
}

// MARK: - Duplicate finder

struct MacDuplicateFinderView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacDesktopExperience.self) private var desktop
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var groups: [MacDuplicateGroup] = []
    @State private var isScanning = false
    @State private var pendingRemoval: Set<UUID> = []
    @State private var message: String?

    var body: some View {
        let lookup = Dictionary(store.recipes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(spacing: 0) {
            MacPanelHeader(title: "Find Duplicates", systemImage: "square.on.square",
                           subtitle: "Groups recipes that share an original source, or the same title and ingredients. The recipe with your notes, favourite or cook history is kept first.")
            Divider()
            if isScanning {
                ProgressView("Comparing recipes…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if groups.isEmpty {
                MacEmpty(title: "No duplicates found", message: "Every recipe in the library is distinct.", systemImage: "checkmark.seal")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(groups.count) group\(groups.count == 1 ? "" : "s") · \(groups.reduce(0) { $0 + $1.ids.count - 1 }) extra copies")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Remove All Extra Copies…") {
                        pendingRemoval = Set(groups.flatMap { $0.ids.dropFirst() })
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                List(groups) { group in
                    Section {
                        ForEach(Array(group.ids.enumerated()), id: \.element) { offset, id in
                            if let recipe = lookup[id] {
                                duplicateRow(recipe, keeper: offset == 0)
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.reason)
                            Spacer()
                            Button("Keep First, Remove \(group.ids.count - 1)…") {
                                pendingRemoval = Set(group.ids.dropFirst())
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
                .listStyle(.inset)
            }
            if let message {
                Label(message, systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(MacTheme.green)
                    .padding(10)
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 500, idealHeight: 640)
        .task { await scan() }
        .confirmationDialog("Remove \(pendingRemoval.count) duplicate recipe\(pendingRemoval.count == 1 ? "" : "s")?",
                            isPresented: Binding(get: { !pendingRemoval.isEmpty }, set: { if !$0 { pendingRemoval = [] } }),
                            titleVisibility: .visible) {
            Button("Remove \(pendingRemoval.count)", role: .destructive) { removePending() }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("The kept copy is unchanged. Removals sync to your household like any other deletion. Shared-catalogue copies may return on the next catalogue refresh if the catalogue still holds them.")
        }
    }

    private func duplicateRow(_ recipe: UserRecipe, keeper: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: keeper ? "star.circle.fill" : "doc.on.doc")
                .foregroundStyle(keeper ? MacTheme.gold : .secondary)
                .help(keeper ? "Recommended copy to keep" : "Extra copy")
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title).lineLimit(2)
                HStack(spacing: 6) {
                    Text(recipe.sourceName?.nilIfBlank ?? "Personal recipe")
                    Text("· \(recipe.ingredients.count) ingredients · \(recipe.instructions.count) steps")
                    if recipe.isFavorited { Image(systemName: "star.fill").foregroundStyle(MacTheme.gold) }
                    if recipe.notes.nilIfBlank != nil { Image(systemName: "note.text") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Show") {
                navigation.section = .recipes
                desktop.reveal(recipe.id)
                dismiss()
            }
            .buttonStyle(.borderless)
            if !keeper {
                Button("Remove…", role: .destructive) { pendingRemoval = [recipe.id] }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }

    private func scan() async {
        isScanning = true
        let snapshot = store.recipes
        groups = await Task.detached(priority: .utility) { MacRecipeDuplicates.groups(snapshot) }.value
        isScanning = false
    }

    private func removePending() {
        let ids = pendingRemoval
        pendingRemoval = []
        store.deleteRecipe(ids: ids)
        message = "Removed \(ids.count) duplicate\(ids.count == 1 ? "" : "s")."
        Task { await scan() }
    }
}

// MARK: - Tag manager

struct MacTagManagerView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacNavigation.self) private var navigation

    @State private var search = ""
    @State private var selection: String?
    @State private var renameText = ""
    @State private var pendingDelete: MacRecipeTags.Usage?
    @State private var message: String?

    private var usage: [MacRecipeTags.Usage] {
        let all = MacRecipeTags.usage(store.recipes)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.display.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let rows = usage
        let selected = rows.first { $0.key == selection }
        VStack(spacing: 0) {
            MacPanelHeader(title: "Tag Manager", systemImage: "tag",
                           subtitle: "Rename, merge or remove recipe tags across the whole library. Changes sync to your household.")
            Divider()
            MacAdjustableSplit(initialLeadingWidth: 300, minimumLeadingWidth: 220,
                               maximumLeadingWidth: 420, minimumTrailingWidth: 280) {
                VStack(spacing: 0) {
                    TextField("Filter tags", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .padding(10)
                    List(rows, selection: $selection) { tag in
                        HStack {
                            Text(tag.display).lineLimit(1)
                            if tag.variants.count > 1 {
                                MacPill(text: "\(tag.variants.count) spellings", tint: .orange)
                            }
                            Spacer()
                            Text("\(tag.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .tag(tag.key)
                    }
                    .listStyle(.sidebar)
                    .overlay {
                        if rows.isEmpty {
                            MacEmpty(title: "No tags", message: search.isEmpty ? "Recipes have no tags yet." : "No tag matches that filter.", systemImage: "tag.slash")
                        }
                    }
                }
            } trailing: {
                if let tag = selected {
                    Form {
                        Section("Tag") {
                            LabeledContent("Used by", value: "\(tag.count) recipe\(tag.count == 1 ? "" : "s")")
                            if tag.variants.count > 1 {
                                LabeledContent("Spellings", value: tag.variants.joined(separator: ", "))
                            }
                            Button("Show These Recipes") {
                                navigation.section = .recipes
                                navigation.searchText = "\"\(tag.display)\""
                            }
                        }
                        Section {
                            TextField("New name", text: $renameText)
                                .onSubmit { rename(tag) }
                            Button(existingTarget(for: tag) ? "Merge Into “\(renameText.trimmingCharacters(in: .whitespaces))”" : "Rename") {
                                rename(tag)
                            }
                            .disabled(renameText.nilIfBlank == nil || renameText.trimmingCharacters(in: .whitespaces) == tag.display && tag.variants.count == 1)
                        } header: {
                            Text("Rename or merge")
                        } footer: {
                            Text("Renaming to an existing tag merges them. Different capitalisations are unified into the new name.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section {
                            Button("Remove Tag From \(tag.count) Recipe\(tag.count == 1 ? "" : "s")…", role: .destructive) {
                                pendingDelete = tag
                            }
                        }
                        if let message {
                            Label(message, systemImage: "checkmark.circle").foregroundStyle(MacTheme.green)
                        }
                    }
                    .formStyle(.grouped)
                    .onAppear { renameText = tag.display }
                    .onChange(of: tag.key) { _, _ in renameText = tag.display; message = nil }
                } else {
                    MacEmpty(title: "Select a tag", message: "Choose a tag to rename, merge or remove it.", systemImage: "tag")
                }
            }
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 480, idealHeight: 600)
        .confirmationDialog("Remove “\(pendingDelete?.display ?? "")” from every recipe?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Tag", role: .destructive) { removePending() }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Only the tag is removed; the recipes themselves stay in your library.")
        }
    }

    private func existingTarget(for tag: MacRecipeTags.Usage) -> Bool {
        let target = MacRecipeTags.key(renameText)
        return !target.isEmpty && target != tag.key && usage.contains { $0.key == target }
    }

    private func rename(_ tag: MacRecipeTags.Usage) {
        guard let newName = renameText.nilIfBlank else { return }
        let ids = Set(store.recipes.filter { recipe in recipe.tags.contains { MacRecipeTags.key($0) == tag.key } }.map(\.id))
        let changed = store.updateRecipes(ids: ids) { recipe in
            if let renamed = MacRecipeTags.renamed(recipe.tags, from: tag.display, to: newName) { recipe.tags = renamed }
        }
        selection = MacRecipeTags.key(newName)
        message = "Updated \(changed) recipe\(changed == 1 ? "" : "s")."
    }

    private func removePending() {
        guard let tag = pendingDelete else { return }
        pendingDelete = nil
        let ids = Set(store.recipes.filter { recipe in recipe.tags.contains { MacRecipeTags.key($0) == tag.key } }.map(\.id))
        let changed = store.updateRecipes(ids: ids) { recipe in
            if let remaining = MacRecipeTags.removing(recipe.tags, tag.display) { recipe.tags = remaining }
        }
        selection = nil
        message = "Removed the tag from \(changed) recipe\(changed == 1 ? "" : "s")."
    }
}

// MARK: - Bulk edit

struct MacBulkEditView: View {
    let recipeIDs: [UUID]
    @Environment(MacKitchenStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var addTagsText = ""
    @State private var removeTagsText = ""
    @State private var changeCuisine = false
    @State private var cuisine = ""
    @State private var changeDifficulty = false
    @State private var difficulty = "Medium"
    @State private var changeRole = false
    @State private var role: DishRole = .unspecified
    @State private var favoriteChoice = 0   // 0 unchanged, 1 add, 2 remove
    @State private var confirming = false
    @State private var result: String?

    private var edit: MacRecipeBulkEdit {
        var value = MacRecipeBulkEdit()
        value.addTags = MacRecipeTags.parse(addTagsText)
        value.removeTags = MacRecipeTags.parse(removeTagsText)
        if changeCuisine {
            if let text = cuisine.nilIfBlank { value.cuisine = text } else { value.clearCuisine = true }
        }
        if changeDifficulty { value.difficulty = difficulty }
        if changeRole { value.role = role }
        if favoriteChoice == 1 { value.favorite = true }
        if favoriteChoice == 2 { value.favorite = false }
        return value
    }

    private var knownCuisines: [String] {
        Array(Set(store.recipes.compactMap { $0.cuisine.nilIfBlank })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            MacPanelHeader(title: "Edit \(recipeIDs.count) Recipe\(recipeIDs.count == 1 ? "" : "s")", systemImage: "square.stack.3d.up",
                           subtitle: "Applies to the recipes currently shown in the Recipes list. Only the fields you turn on are changed.")
            Divider()
            Form {
                Section("Tags") {
                    TextField("Add tags (comma separated)", text: $addTagsText)
                    TextField("Remove tags (comma separated)", text: $removeTagsText)
                }
                Section("Details") {
                    Toggle("Set cuisine", isOn: $changeCuisine)
                    if changeCuisine {
                        HStack {
                            TextField("Cuisine (leave empty to clear)", text: $cuisine)
                            Menu("Known") {
                                ForEach(knownCuisines, id: \.self) { value in Button(value) { cuisine = value } }
                            }
                            .fixedSize()
                        }
                    }
                    Toggle("Set difficulty", isOn: $changeDifficulty)
                    if changeDifficulty {
                        Picker("Difficulty", selection: $difficulty) {
                            ForEach(["Easy", "Medium", "Hard"], id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("Set recipe role", isOn: $changeRole)
                    if changeRole {
                        Picker("Role", selection: $role) {
                            ForEach(DishRole.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                    }
                    Picker("Favourites", selection: $favoriteChoice) {
                        Text("Leave unchanged").tag(0)
                        Text("Add to favourites").tag(1)
                        Text("Remove from favourites").tag(2)
                    }
                }
                if let result {
                    Label(result, systemImage: "checkmark.circle").foregroundStyle(MacTheme.green)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Recipes missing their required image are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply to \(recipeIDs.count)…") { confirming = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(edit.isEmpty || recipeIDs.isEmpty)
            }
            .padding(14)
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 520, idealHeight: 600)
        .confirmationDialog("Apply these changes to \(recipeIDs.count) recipe\(recipeIDs.count == 1 ? "" : "s")?",
                            isPresented: $confirming, titleVisibility: .visible) {
            Button("Apply") { apply() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Edited recipes sync to your household. This can't be undone automatically.")
        }
    }

    private func apply() {
        let change = edit
        let changed = store.updateRecipes(ids: Set(recipeIDs)) { change.apply(to: &$0) }
        result = "Updated \(changed) of \(recipeIDs.count) recipe\(recipeIDs.count == 1 ? "" : "s")."
    }
}
