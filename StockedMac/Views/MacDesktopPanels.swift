import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacCommandPalette: View {
    @Environment(MacNavigation.self) private var navigation
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacDesktopExperience.self) private var desktop
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Action: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let perform: () -> Void
    }

    private var actions: [Action] {
        var values = MacSection.recipeManagerSections.map { section in
            Action(id: "open-\(section.id)", title: "Open \(section.rawValue)",
                   subtitle: "Go to the \(section.rawValue.lowercased()) workspace",
                   symbol: section.systemImage) {
                navigation.section = section
                dismiss()
            }
        }
        values.append(contentsOf: [
            Action(id: "new-recipe", title: "New recipe", subtitle: "Create an image-backed recipe", symbol: "plus") {
                navigation.section = .recipes; navigation.isAddingItem = true; dismiss()
            },
            Action(id: "import", title: "Open Import Center", subtitle: "URLs, backups, CSV, and drag-and-drop", symbol: "square.and.arrow.down") {
                dismiss(); desktop.isImportCenterPresented = true
            },
            Action(id: "sync", title: "Sync recipes now", subtitle: sync.status.message, symbol: "arrow.triangle.2.circlepath") {
                dismiss(); Task { await sync.syncNow(store: store); harvest.syncKitchenToCloud(store.recipes) }
            },
            Action(id: "find", title: "Find recipes", subtitle: "Open the bounded discovery pipeline", symbol: "globe") {
                navigation.section = .browse; dismiss()
            },
            Action(id: "toggle-inspector", title: desktop.isInspectorPresented ? "Hide inspector" : "Show inspector",
                   subtitle: "Toggle recipe metadata", symbol: "sidebar.right") {
                desktop.isInspectorPresented.toggle(); dismiss()
            }
        ])
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return values }
        return values.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.subtitle.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(MacTheme.gold)
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                Text("esc").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if actions.isEmpty {
                MacEmpty(title: "No matching command", message: "Try a screen name or action.", systemImage: "command")
            } else {
                List(actions) { action in
                    Button(action: action.perform) {
                        HStack(spacing: 12) {
                            Image(systemName: action.symbol)
                                .frame(width: 24)
                                .foregroundStyle(MacTheme.gold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                Text(action.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 380, idealHeight: 460)
        .background(.regularMaterial)
        .onAppear { focused = true }
    }
}

struct MacImportCenter: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(HarvestModel.self) private var harvest
    @Environment(MacNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var urls = ""
    @State private var mergeBackup = true
    @State private var message = "Drop recipe links or a Stocked JSON/CSV file anywhere in this window."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Import Center", systemImage: "square.and.arrow.down")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            MacCard(title: "Recipe URLs", systemImage: "link") {
                TextEditor(text: $urls)
                    .font(.body.monospaced())
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("Paste") { urls = NSPasteboard.general.string(forType: .string) ?? urls }
                    Button("Queue and import") { importURLs() }
                        .buttonStyle(.borderedProminent)
                        .disabled(parsedURLs.isEmpty)
                }
            }

            MacCard(title: "Files", systemImage: "doc") {
                HStack(spacing: 12) {
                    Button("Open Stocked backup…") { openBackup() }
                    Toggle("Merge with this Mac", isOn: $mergeBackup)
                    Spacer()
                    Button("Recipe removal CSV…") { MacRecipeMaintenance.removeFromCSV(store: store) }
                }
                Text("Backups preserve local-first data. CSV removal always previews matches and creates a recovery copy before deleting.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(message, systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 500)
        .dropDestination(for: URL.self) { urls, _ in
            handleDropped(urls); return true
        }
    }

    private var parsedURLs: [String] {
        urls.components(separatedBy: .whitespacesAndNewlines).filter {
            guard let value = URL(string: $0) else { return false }
            return value.scheme == "https" || value.scheme == "http"
        }
    }

    private func importURLs() {
        harvest.appendImportURLs(parsedURLs)
        harvest.importURLs()
        navigation.section = .browse
        message = "Queued \(parsedURLs.count) link\(parsedURLs.count == 1 ? "" : "s") through the normal validation pipeline."
        urls = ""
    }

    private func openBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importData(Data(contentsOf: url), replace: !mergeBackup)
            message = mergeBackup ? "Backup merged successfully." : "Backup replaced this Mac's local data successfully."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    private func handleDropped(_ dropped: [URL]) {
        let web = dropped.filter { $0.scheme == "https" || $0.scheme == "http" }.map(\.absoluteString)
        if !web.isEmpty {
            harvest.appendImportURLs(web); harvest.importURLs(); navigation.section = .browse
        }
        for file in dropped where file.isFileURL {
            switch file.pathExtension.lowercased() {
            case "json":
                do { try store.importData(Data(contentsOf: file), replace: false); message = "Dropped backup merged successfully." }
                catch { message = "Dropped backup failed: \(error.localizedDescription)" }
            case "csv":
                message = "CSV files use the preview-first Recipe removal CSV action."
            default: break
            }
        }
    }
}

struct MacDetachedRecipeView: View {
    let recipeID: UUID
    @Environment(MacKitchenStore.self) private var store
    @State private var editing = false

    private var recipe: UserRecipe? { store.recipes.first { $0.id == recipeID } }

    var body: some View {
        Group {
            if let recipe {
                MacRecipeDetail(recipe: recipe, onEdit: { editing = true })
                    .navigationTitle(recipe.title)
                    .sheet(isPresented: $editing) {
                        MacRecipeEditor(recipe: recipe) { updated in
                            store.updateRecipe(id: recipe.id) { $0 = updated }
                        }
                        .macThemedSurface()
                    }
            } else {
                MacEmpty(title: "Recipe unavailable", message: "It may have been removed or has not synced to this Mac yet.", systemImage: "book.closed")
            }
        }
        .macThemedSurface()
    }
}
