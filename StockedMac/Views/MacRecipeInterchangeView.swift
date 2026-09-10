import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A review surface over the existing Mac library. Importing never updates a matching
/// recipe, and validation completes before any selected record enters the shared store.
struct MacRecipeInterchangeView: View {
    var inboxReview: MacRecipeInboxReview? = nil
    var connectedRecipe: CooklangFederationRecipe? = nil
    @Environment(MacKitchenStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [MacInterchangeRecipe] = []
    @State private var selected = Set<UUID>()
    @State private var duplicates = Set<UUID>()
    @State private var added: [UUID: UserRecipe] = [:]
    @State private var mayPublish = false
    @State private var busy = false
    @State private var message = "Choose recipe files or an exported archive to preview. Nothing changes until you import."
    @State private var importTask: Task<Void, Never>?
    @State private var confirmUndo = false
    @State private var importWarnings: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Portable recipes", systemImage: "doc.badge.arrow.up").font(.title2.weight(.semibold))
                Spacer()
                Button(busy ? "Cancel import" : "Done") {
                    importTask?.cancel()
                    if !busy { dismiss() }
                }.keyboardShortcut(.cancelAction)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading) {
                Button("Choose files or archives…") { openFile() }.disabled(busy)
                Button("Export library as JSON-LD…") { exportLibrary() }.disabled(busy || store.recipes.isEmpty)
                Button("Export original files…") { exportOriginalFiles() }.disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !importWarnings.isEmpty {
                DisclosureGroup("Import notes (\(importWarnings.count))") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(importWarnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption) }
                        }
                    }.frame(maxHeight: 130)
                }
            }
            if !rows.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(rows) { row in
                            MacCard(title: row.title.isEmpty ? "Untitled recipe" : row.title, systemImage: "book") {
                                HStack {
                                    Toggle("Import this recipe", isOn: Binding(get: { selected.contains(row.id) }, set: {
                                        if $0 { selected.insert(row.id) } else { selected.remove(row.id) }
                                    }))
                                    .disabled(busy || duplicates.contains(row.id) || !problems(row).isEmpty)
                                    Spacer()
                                    Text(duplicates.contains(row.id) ? "Already here · skipped" : problems(row).isEmpty ? "Ready for photo check" : "Needs attention")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text("\(row.ingredients.count) ingredients · \(row.instructions.count) steps\(row.yield.isEmpty ? "" : " · Yield: " + row.yield)")
                                    .font(.caption)
                                if let source = MacRecipeInterchange.secureURL(row.sourceURL) {
                                    Link(row.sourceName.isEmpty ? source.host ?? "Original source" : row.sourceName, destination: source)
                                }
                                ForEach(problems(row) + row.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                                DisclosureGroup("Preview ingredients, steps and credits") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if !row.summary.isEmpty { Text(row.summary) }
                                        if !row.privateNotes.isEmpty { Text("Imported notes: " + row.privateNotes) }
                                        Text(row.ingredients.joined(separator: "\n"))
                                        Divider()
                                        Text(row.instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n"))
                                        if !row.author.isEmpty { Text("Author: " + row.author) }
                                        if !row.license.isEmpty { Text("Recipe license: " + row.license) }
                                        if !row.imageCredit.isEmpty { Text("Photo credit: " + row.imageCredit) }
                                        if !row.nutrition.isEmpty {
                                            Text("Source nutrition: " + row.nutrition.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "; "))
                                        }
                                    }.font(.callout).textSelection(.enabled).padding(.top, 8)
                                }
                                Button(row.originalCooklang == nil ? "Save as Cooklang…" : "Save original Cooklang…") { exportCooklang(row) }
                                    .disabled(busy)
                            }
                        }
                    }
                }
                if connectedRecipe == nil {
                    Toggle("Also share publicly — I have permission to publish these recipes and photos.", isOn: $mayPublish)
                        .disabled(busy)
                }
                Text(mayPublish ? "Public sharing needs an original source URL and a valid photo for every selected recipe." : "Recipes stay in your household. Original source details and notes remain private.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Existing recipes stay as they are. Photo downloads happen only after you choose Import.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !added.isEmpty {
                        Button("Undo this import…") { confirmUndo = true }.disabled(busy)
                    }
                    Button("Import \(selected.count) recipes") { beginImport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || selected.isEmpty)
                }
            } else { Spacer() }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Link("Schema.org Recipe format", destination: URL(string: "https://schema.org/Recipe")!)
                    Link("Cooklang contributors", destination: URL(string: "https://cooklang.org/docs/spec/")!)
                }
                HStack {
                    Link("ZIP format: PKWARE", destination: URL(string: "https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT")!)
                    Link("System zlib: Gailly & Adler", destination: URL(string: "https://zlib.net/zlib_license.html")!)
                }
                Text("Recipes and photos keep their original owners and credits.")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 760, minHeight: 540, idealHeight: 740)
        .macThemedSurface()
        .onDisappear { importTask?.cancel() }
        .task {
            if let connectedRecipe { openConnection(connectedRecipe) }
            else if let request = inboxReview { openInbox(request) }
        }
        .onChange(of: mayPublish) { _, _ in selected.formIntersection(rows.filter { problems($0).isEmpty }.map(\.id)) }
        .confirmationDialog("Remove recipes added by this import?", isPresented: $confirmUndo) {
            Button("Remove unchanged imported recipes", role: .destructive) { undoImport() }
        } message: {
            Text("Only recipes still identical to this import are removed. Later edits are kept. Deletions use normal household syncing.")
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = true
        panel.message = "Choose Cooklang, JSON-LD, Mealie, Tandoor, Paprika or Recipya exports. Archives are inspected locally, without AI."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        guard panel.urls.count <= 50 else { message = "Choose at most 50 files per preview."; return }
        let files = panel.urls
        busy = true
        mayPublish = false
        importTask = Task {
            do {
                let result = try await MacRecipeInterchangeAdapter.offMain { try MacRecipeInterchangeAdapter.readFiles(files) }
                try Task.checkCancellation()
                installPreview(result.rows, warnings: result.warnings)
            } catch is CancellationError { message = "Import cancelled. Your library is unchanged." }
            catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func openInbox(_ request: MacRecipeInboxReview) {
        busy = true
        mayPublish = false
        importTask = Task {
            do {
                let result = try await MacRecipeInterchangeAdapter.offMain {
                    try MacRecipeInterchangeAdapter.migration(request.read(), filename: request.item.filename)
                }
                try Task.checkCancellation()
                installPreview(result.rows, warnings: result.warnings)
            } catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func openConnection(_ recipe: CooklangFederationRecipe) {
        busy = true; mayPublish = false
        importTask = Task {
            do {
                let result = try await MacRecipeInterchangeAdapter.offMain { try MacCooklangConnectionImport.preview(recipe) }
                try Task.checkCancellation()
                installPreview(result.rows, warnings: result.warnings)
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
            busy = false
        }
    }

    private func installPreview(_ parsed: [MacInterchangeRecipe], warnings: [String]) {
        rows = parsed
        duplicates = duplicateIDs(in: parsed)
        selected = Set(parsed.filter { problems($0).isEmpty && !duplicates.contains($0.id) }.map(\.id))
        added = [:]
        importWarnings = warnings
        message = "\(parsed.count) recipes found. \(duplicates.count) duplicates skipped. Review before importing."
        if !warnings.isEmpty { message += " \(warnings.count) import notes: " + warnings.prefix(3).joined(separator: " · ") }
    }

    private func problems(_ row: MacInterchangeRecipe) -> [String] { row.contentProblems + (mayPublish ? row.publicationProblems : []) }

    private func duplicateIDs(in candidates: [MacInterchangeRecipe]) -> Set<UUID> {
        MacRecipeInterchangeAdapter.duplicateIDs(in: candidates, existing: store.recipes)
    }

    private func beginImport() {
        let candidates = rows.filter { selected.contains($0.id) && problems($0).isEmpty }
        let sharePublicly = connectedRecipe == nil && mayPublish
        busy = true
        importTask = Task {
            var failures: [String] = []
            var count = 0
            do {
                for row in candidates {
                    try Task.checkCancellation()
                    if duplicateIDs(in: [row]).contains(row.id) { continue }
                    message = "Checking photo \(count + failures.count + 1) of \(candidates.count): \(row.title)"
                    do {
                        let bytes: Data
                        if let original = row.localImageData { bytes = original }
                        else { bytes = try await MacRecipeInterchangeAdapter.imageData(row.imageURL) }
                        guard MacRecipeImagePolicy.isUsable(bytes) else { throw MacRecipeInterchange.ImportError.malformed }
                        try Task.checkCancellation()
                        guard !duplicateIDs(in: [row]).contains(row.id) else { continue }
                        let recipe = MacRecipeInterchangeAdapter.userRecipe(row, image: bytes, catalogueSharingApproved: sharePublicly)
                        store.addRecipe(recipe)
                        if let saved = store.recipes.first(where: { $0.id == recipe.id }) {
                            added[saved.id] = saved
                            selected.remove(row.id)
                            count += 1
                        } else { failures.append("\(row.title): photo validation failed") }
                    } catch is CancellationError { throw CancellationError() }
                    catch { failures.append("\(row.title): \(error.localizedDescription)") }
                }
                message = "Added \(count) recipes. Existing recipes were kept."
                if !failures.isEmpty { message += " \(failures.count) could not import: " + failures.prefix(3).joined(separator: " · ") }
            } catch { message = "Import stopped. \(count) completed recipes were kept; use Undo to remove unchanged additions." }
            duplicates = duplicateIDs(in: rows)
            busy = false
        }
    }

    private func undoImport() {
        let ids = Set(store.recipes.filter { added[$0.id] == $0 }.map(\.id))
        store.deleteRecipe(ids: ids)
        let kept = added.count - ids.count
        added = [:]
        duplicates = duplicateIDs(in: rows)
        selected = []
        message = "Removed \(ids.count) unchanged imported recipes. \(kept) edited or already removed recipes were left alone."
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Stocked Recipes.json"
        panel.message = "Export \(store.recipes.count) recipes in the open Schema.org format. Photo URLs and source credits are included; use Stocked Backup for photos stored only on this Mac and personal history."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = store.recipes
        busy = true
        importTask = Task {
            do {
                try await MacRecipeInterchangeAdapter.offMain {
                    let data = try MacRecipeInterchange.encode(snapshot.map(MacRecipeInterchangeAdapter.document))
                    try Task.checkCancellation()
                    try data.write(to: url, options: .atomic)
                }
                message = "Exported \(snapshot.count) recipes with source and photo credits."
            } catch { message = "Export failed: \(error.localizedDescription)" }
            busy = false
        }
    }

    private func exportCooklang(_ row: MacInterchangeRecipe) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cook") ?? .plainText]
        panel.nameFieldStringValue = "Stocked Recipe.cook"
        panel.message = row.originalCooklang == nil
            ? "Save a basic Cooklang recipe. Ingredients and steps are kept; use JSON-LD or Stocked Backup for nutrition and the complete library record."
            : "Save the complete original Cooklang text, including metadata and extensions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = row.originalCooklang ?? PortableCooklang.export(MacRecipeInterchangeAdapter.cooklang(row))
            try Data(text.utf8).write(to: url, options: .atomic)
            message = row.originalCooklang == nil ? "Saved the recipe in basic Cooklang format." : "Saved the original Cooklang file unchanged."
        } catch { message = error.localizedDescription }
    }

    private func exportOriginalFiles() {
        let originals = store.recipes.compactMap { recipe -> (UUID, PortableRecipeSource)? in
            guard let original = recipe.portableSource, !original.originalText.isEmpty else { return nil }
            return (recipe.id, original)
        }
        guard !originals.isEmpty else { message = "There are no original recipe files in this library yet."; return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export originals"
        panel.message = "Save \(originals.count) complete original files in a new folder. Original files may include your personal recipe notes."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        importTask = Task {
            do {
                try await MacRecipeInterchangeAdapter.offMain {
                    let access = destination.startAccessingSecurityScopedResource()
                    defer { if access { destination.stopAccessingSecurityScopedResource() } }
                    let folder = destination.appendingPathComponent("Stocked Originals-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                    for (id, original) in originals {
                        try Task.checkCancellation()
                        let name = URL(fileURLWithPath: original.filename).lastPathComponent
                        let file = folder.appendingPathComponent(id.uuidString + "-" + name)
                        try Data(original.originalText.utf8).write(to: file, options: .atomic)
                    }
                }
                message = "Exported \(originals.count) original files into a new Stocked Originals folder."
            } catch { message = "Export failed: \(error.localizedDescription)" }
            busy = false
        }
    }
}
