// MacRecipeCSV.swift — export the recipe library as a spreadsheet, and remove recipes
// in bulk by handing that spreadsheet back with rows marked.
//
// ── This file is a deliberate twin ──────────────────────────────────────────────
// `Stocked/RecipeCSV.swift` on the phone carries the same parser, the same escaper, the
// same normaliser, the same column header and the same matching rules. It is copied
// rather than shared because the two apps are separate Xcode projects with no shared
// framework, and because the format has to be byte-identical: a spreadsheet exported on
// the Mac must be removable on the phone and the other way round. **Change one, change
// both.** If they drift, a file exported here stops being readable there and the user
// finds out by losing the wrong recipes.
//
// ── The one rule that matters ───────────────────────────────────────────────────
// Deletions must leave household tombstones or the next pull brings every recipe back.
// On this app the bookkeeping lives inside `MacKitchenStore.deleteRecipe(ids:)` and
// `deleteSavedRecipes(ids:)`, which call `sync?.noteRecipeDeleted(_:)` /
// `noteSavedRecipeDeleted(_:)` before touching the array. So removal here goes through
// those two methods with the whole set at once and **never** mutates `store.recipes` or
// `store.savedRecipes` directly. (The phone reaches the same end by a different road:
// there the tombstones are recorded in `didSet`, so the rule there is to assign the
// array exactly once.)
//
// Nothing is deleted without the confirmation window in this file saying so, and a JSON
// copy of everything about to go is written to disk first.

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os

// MARK: - Model

/// Which of the two recipe collections a spreadsheet row is talking about.
nonisolated enum MacRecipeCSVLibrary: String, Codable, Sendable {
    case mine       // store.recipes      — recipes you wrote or harvested
    case saved      // store.savedRecipes — recipes kept from the phone's generator
}

/// One data row, read loosely: a file the user has edited in Numbers or Excel will not
/// come back with the columns in the order it left in, and may not come back with all of
/// them.
nonisolated struct MacRecipeCSVRow: Identifiable, Sendable {
    let id = UUID()
    var library: MacRecipeCSVLibrary?   // nil = the file didn't say; search both
    var recipeID: UUID?
    var title: String
    var markedForRemoval: Bool
    var lineNumber: Int
}

/// A recipe a row could be pointing at.
nonisolated struct MacRecipeCSVCandidate: Identifiable, Sendable {
    let id: UUID
    var title: String
    var detail: String
    var library: MacRecipeCSVLibrary
}

nonisolated struct MacRecipeCSVMatch: Identifiable, Sendable {
    let id = UUID()
    var row: MacRecipeCSVRow
    var candidates: [MacRecipeCSVCandidate]
    var matchedByID: Bool

    var isAmbiguous: Bool { candidates.count > 1 }
    var isUnmatched: Bool { candidates.isEmpty }
    var isClean: Bool     { candidates.count == 1 }
}

/// Everything the confirmation window needs. A plan describes what *could* be removed;
/// it removes nothing by existing.
nonisolated struct MacRecipeCSVPlan: Sendable {
    var matches: [MacRecipeCSVMatch] = []
    var totalDataRows: Int = 0
    var hadRemoveColumn: Bool = false
    var parseError: String?

    var clean: [MacRecipeCSVMatch]     { matches.filter(\.isClean) }
    var ambiguous: [MacRecipeCSVMatch] { matches.filter(\.isAmbiguous) }
    var unmatched: [MacRecipeCSVMatch] { matches.filter(\.isUnmatched) }
}

// MARK: - The machinery

enum MacRecipeCSV {

    private static let log = Logger(subsystem: "com.sowens.StockedMac", category: "recipe-csv")

    /// The shared column order. Identical to the phone's — see the note at the top.
    static let header = "library,id,title,cuisine,category,tags,source,created,remove"

    // MARK: Primitives

    /// Quotes a field only when it needs it, and doubles any quote inside.
    static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    /// Case- and punctuation-insensitive key for title matching. "Mum's Ragù" and
    /// "mums ragu" have to land in the same bucket or title matching is theatre.
    static func normKey(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// RFC-4180-ish reader: handles quoted fields, embedded commas, embedded newlines,
    /// doubled quotes, and CRLF. Tolerant of a trailing newline and of blank lines.
    static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.startIndex

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while iterator < text.endIndex {
            let ch = text[iterator]
            if inQuotes {
                if ch == "\"" {
                    let next = text.index(after: iterator)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        iterator = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",":  endField()
                case "\n": endRow()
                case "\r": break            // CRLF — the \n does the work
                default:   field.append(ch)
                }
            }
            iterator = text.index(after: iterator)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// What counts as "yes, remove this" in the remove column. Generous on purpose —
    /// people tick spreadsheets with whatever is at hand.
    private static let truthy: Set<String> = ["yes", "y", "true", "1", "x", "✓", "remove", "delete"]

    // MARK: Export

    /// The whole recipe library as CSV. The `remove` column ships empty: the file is a
    /// worksheet, and marking it is how you turn it into an instruction.
    @MainActor
    static func exportCSV(store: MacKitchenStore) -> String {
        var lines: [String] = [header]

        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"

        for r in store.recipes {
            let fields = [
                "mine",
                r.id.uuidString,
                r.title,
                r.cuisine,
                r.dishRole == .unspecified ? "" : r.dishRole.label,
                r.tags.joined(separator: "|"),
                r.imageURL ?? "",
                iso.string(from: r.dateCreated),
                ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        // Saved recipes have no cuisine, tags or created date — those columns stay blank
        // rather than being invented. They're ignored on the way back in anyway.
        for r in store.savedRecipes {
            let fields = [
                "saved",
                r.id.uuidString,
                r.title,
                "",
                r.mealCategory,
                "",
                r.imageURL ?? "",
                "",
                ""
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// Suggested filename for the save panel.
    static func exportFilename() -> String { "Stocked-Recipes-\(dateStamp()).csv" }

    // MARK: Reading a removal file

    /// Pulls rows out of an edited spreadsheet. Column order is discovered from the
    /// header, not assumed, and several spellings of each column are accepted because
    /// the file has been through someone else's spreadsheet app by the time it gets here.
    static func parseRemovalRows(_ text: String)
        -> (rows: [MacRecipeCSVRow], hadRemoveColumn: Bool, total: Int, error: String?) {

        let grid = parseCSVRows(text)
        guard let headerRow = grid.first else {
            return ([], false, 0, "That file is empty.")
        }

        var index: [String: Int] = [:]
        for (i, raw) in headerRow.enumerated() {
            let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "_", with: "")
            switch key {
            case "library", "section", "list":       index["library"] = i
            case "id", "uuid", "recipeid":           index["id"] = i
            case "title", "name", "recipe":          index["title"] = i
            case "remove", "delete":                 index["remove"] = i
            default: break
            }
        }

        guard let titleCol = index["title"] else {
            return ([], false, 0,
                    "That CSV needs a Title column. Export your recipes first to get the right shape.")
        }

        let removeCol = index["remove"]
        let hadRemove = removeCol != nil
        var rows: [MacRecipeCSVRow] = []
        var total = 0

        for (offset, cells) in grid.dropFirst().enumerated() {
            let lineNumber = offset + 2   // 1-based, and the header is line 1

            func cell(_ i: Int?) -> String {
                guard let i, i < cells.count else { return "" }
                return cells[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = cell(titleCol)
            let idText = cell(index["id"])
            if title.isEmpty && idText.isEmpty { continue }
            total += 1

            let libraryText = cell(index["library"]).lowercased()
                .replacingOccurrences(of: " ", with: "")
            let library: MacRecipeCSVLibrary?
            switch libraryText {
            case "mine", "user", "vault", "userrecipe":  library = .mine
            case "saved", "generated", "ai":             library = .saved
            default:                                     library = nil
            }

            let marked: Bool = {
                guard let removeCol else { return true }   // no column = every row is a candidate
                return truthy.contains(cell(removeCol).lowercased())
            }()

            rows.append(MacRecipeCSVRow(
                library: library,
                recipeID: UUID(uuidString: idText),
                title: title,
                markedForRemoval: marked,
                lineNumber: lineNumber
            ))
        }

        return (rows.filter(\.markedForRemoval), hadRemove, total, nil)
    }

    // MARK: Matching

    /// Turns rows into matches. ID first; falls back to normalised title when the ID
    /// isn't found, because a recipe that was exported and re-imported legitimately has
    /// a new ID. A title that hits two recipes is never resolved automatically.
    @MainActor
    static func match(_ rows: [MacRecipeCSVRow], store: MacKitchenStore) -> [MacRecipeCSVMatch] {

        func detail(_ r: UserRecipe) -> String {
            var bits: [String] = []
            if !r.cuisine.isEmpty { bits.append(r.cuisine) }
            if !r.cookTime.isEmpty { bits.append(r.cookTime) }
            bits.append("\(r.ingredients.count) ingredients")
            return bits.joined(separator: " · ")
        }
        func detail(_ r: GeneratedRecipe) -> String {
            var bits: [String] = []
            if !r.mealCategory.isEmpty { bits.append(r.mealCategory) }
            if !r.cookTime.isEmpty { bits.append(r.cookTime) }
            bits.append("\(r.ingredients.count) ingredients")
            return bits.joined(separator: " · ")
        }

        var byTitleMine: [String: [MacRecipeCSVCandidate]] = [:]
        for r in store.recipes {
            byTitleMine[normKey(r.title), default: []].append(
                MacRecipeCSVCandidate(id: r.id, title: r.title, detail: detail(r), library: .mine))
        }
        var byTitleSaved: [String: [MacRecipeCSVCandidate]] = [:]
        for r in store.savedRecipes {
            byTitleSaved[normKey(r.title), default: []].append(
                MacRecipeCSVCandidate(id: r.id, title: r.title, detail: detail(r), library: .saved))
        }
        let mineByID  = Dictionary(uniqueKeysWithValues: store.recipes.map { ($0.id, $0) })
        let savedByID = Dictionary(uniqueKeysWithValues: store.savedRecipes.map { ($0.id, $0) })

        var results: [MacRecipeCSVMatch] = []
        var seen: Set<UUID> = []      // two rows naming the same recipe collapse to one

        for row in rows {
            var candidates: [MacRecipeCSVCandidate] = []
            var byID = false

            if let rid = row.recipeID {
                if row.library != .saved, let r = mineByID[rid] {
                    candidates = [MacRecipeCSVCandidate(id: r.id, title: r.title, detail: detail(r), library: .mine)]
                    byID = true
                } else if row.library != .mine, let r = savedByID[rid] {
                    candidates = [MacRecipeCSVCandidate(id: r.id, title: r.title, detail: detail(r), library: .saved)]
                    byID = true
                }
            }

            if candidates.isEmpty, !row.title.isEmpty {
                let key = normKey(row.title)
                if row.library != .saved { candidates += byTitleMine[key] ?? [] }
                if row.library != .mine  { candidates += byTitleSaved[key] ?? [] }
            }

            if candidates.count == 1, seen.contains(candidates[0].id) { continue }
            if candidates.count == 1 { seen.insert(candidates[0].id) }

            results.append(MacRecipeCSVMatch(row: row, candidates: candidates, matchedByID: byID))
        }

        return results
    }

    @MainActor
    static func plan(from text: String, store: MacKitchenStore) -> MacRecipeCSVPlan {
        let parsed = parseRemovalRows(text)
        var plan = MacRecipeCSVPlan()
        plan.totalDataRows = parsed.total
        plan.hadRemoveColumn = parsed.hadRemoveColumn
        plan.parseError = parsed.error
        guard parsed.error == nil else { return plan }
        plan.matches = match(parsed.rows, store: store)
        return plan
    }

    // MARK: The backup

    private struct RemovalBackup: Codable {
        var exportedAt: Date
        var userRecipes: [UserRecipe]
        var generatedRecipes: [GeneratedRecipe]
    }

    /// Removes, and returns how many went plus where the safety copy landed.
    ///
    /// Both deletions go through `MacKitchenStore`, which is what records the household
    /// tombstones. Reaching into `store.recipes` here would delete them locally and then
    /// have the next pull put them straight back.
    @MainActor
    @discardableResult
    static func remove(recipeIDs: Set<UUID>,
                       savedRecipeIDs: Set<UUID>,
                       store: MacKitchenStore) -> (removed: Int, backupURL: URL?) {

        guard !recipeIDs.isEmpty || !savedRecipeIDs.isEmpty else { return (0, nil) }

        let doomedMine  = store.recipes.filter { recipeIDs.contains($0.id) }
        let doomedSaved = store.savedRecipes.filter { savedRecipeIDs.contains($0.id) }
        let backupURL = writeBackup(userRecipes: doomedMine, generated: doomedSaved)

        if !recipeIDs.isEmpty      { store.deleteRecipe(ids: recipeIDs) }
        if !savedRecipeIDs.isEmpty { store.deleteSavedRecipes(ids: savedRecipeIDs) }

        let total = doomedMine.count + doomedSaved.count
        log.notice("CSV removal: \(total, privacy: .public) recipes removed")
        return (total, backupURL)
    }

    /// Written before anything is deleted, so "undo" is a real file rather than a hope.
    ///
    /// Restoring it brings the recipes back as NEW recipes with new IDs, on purpose: the
    /// old IDs now carry tombstones that have been pushed to the household, and reusing
    /// them would mean every device deletes them again on the next pull.
    private static func writeBackup(userRecipes: [UserRecipe],
                                    generated: [GeneratedRecipe]) -> URL? {
        guard !userRecipes.isEmpty || !generated.isEmpty else { return nil }

        let payload = RemovalBackup(exportedAt: Date(),
                                    userRecipes: userRecipes,
                                    generatedRecipes: generated)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload) else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Stocked-Removed-Recipes-\(dateStamp()).json")
        do {
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            log.error("Removal backup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Confirmation window

/// `MacCommands` is a `Commands` struct — it has no view to hang a sheet on, and an
/// `NSAlert` can't show a scrolling list with checkboxes. So the confirmation is a real
/// modal window hosting a SwiftUI view, run with `NSApp.runModal(for:)`.
@MainActor
enum MacRecipeCSVWindow {

    /// Shows the plan and returns what the user chose to remove, or nil if they backed
    /// out. Blocks until the window closes, which is what a modal is for.
    static func confirm(plan: MacRecipeCSVPlan) -> (recipes: Set<UUID>, saved: Set<UUID>)? {

        final class Box { var result: (recipes: Set<UUID>, saved: Set<UUID>)? }
        let box = Box()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remove Recipes"
        window.isReleasedWhenClosed = false

        let root = MacRecipeCSVRemovalView(plan: plan) { choice in
            box.result = choice
            NSApp.stopModal()
            window.orderOut(nil)
        }
        window.contentViewController = NSHostingController(rootView: root)
        window.center()

        NSApp.runModal(for: window)
        return box.result
    }
}

/// Nothing is removed until this view says so.
///
/// Clean matches arrive ticked. A title that matches two recipes arrives unticked in its
/// own section with enough detail to tell them apart — guessing here is how you delete
/// the wrong dinner. Rows that matched nothing are listed at the bottom, so a typo reads
/// as a typo instead of as silence.
struct MacRecipeCSVRemovalView: View {

    let plan: MacRecipeCSVPlan
    /// nil = cancelled.
    let onFinish: ((recipes: Set<UUID>, saved: Set<UUID>)?) -> Void

    @State private var selected: Set<UUID> = []
    @State private var libraryOf: [UUID: MacRecipeCSVLibrary] = [:]
    @State private var confirming = false
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { MacTheme.accent(dark: scheme == .dark) }
    private var selectedCount: Int { selected.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let err = plan.parseError {
                errorState(err)
            } else if plan.matches.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 460)
        .onAppear(perform: prime)
        .alert("Remove \(selectedCount) recipe\(selectedCount == 1 ? "" : "s")?",
               isPresented: $confirming) {
            Button("Remove \(selectedCount)", role: .destructive) { commit() }
            Button("Keep everything", role: .cancel) { }
        } message: {
            Text("A copy of everything removed is saved first, so this is recoverable.")
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Remove recipes from a spreadsheet")
                .font(.system(size: 15, weight: .semibold))
            Text(summaryLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(MacTheme.pad)
    }

    private var summaryLine: String {
        if plan.parseError != nil { return "That file couldn't be read." }
        var bits: [String] = ["\(plan.totalDataRows) row\(plan.totalDataRows == 1 ? "" : "s") read"]
        if !plan.hadRemoveColumn {
            bits.append("no remove column, so every row is offered")
        }
        return bits.joined(separator: " · ")
    }

    private var list: some View {
        List {
            if !plan.clean.isEmpty {
                Section("Found — \(plan.clean.count)") {
                    ForEach(plan.clean) { match in
                        if let candidate = match.candidates.first {
                            row(candidate, matchedByID: match.matchedByID)
                        }
                    }
                }
            }

            if !plan.ambiguous.isEmpty {
                Section {
                    ForEach(plan.ambiguous) { match in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("“\(match.row.title)” — line \(match.row.lineNumber)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            ForEach(match.candidates) { candidate in
                                row(candidate, matchedByID: false)
                                    .padding(.leading, 12)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("More than one match — pick which")
                } footer: {
                    Text("These are unticked. Nothing here goes unless you tick it.")
                        .font(.system(size: 11))
                }
            }

            if !plan.unmatched.isEmpty {
                Section {
                    ForEach(plan.unmatched) { match in
                        HStack(spacing: 8) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.row.title.isEmpty ? "(no title)" : match.row.title)
                                    .font(.system(size: 13))
                                Text("Line \(match.row.lineNumber) — no recipe by that name")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Not found — nothing to remove")
                }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ candidate: MacRecipeCSVCandidate, matchedByID: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { selected.contains(candidate.id) },
            set: { on in
                if on { selected.insert(candidate.id) } else { selected.remove(candidate.id) }
                libraryOf[candidate.id] = candidate.library
            }
        )) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).font(.system(size: 13))
                    Text(candidate.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if candidate.library == .saved {
                    Text("Saved")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accent.opacity(0.16), in: Capsule())
                }
                if !matchedByID {
                    Image(systemName: "textformat")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("Matched by title, not by ID")
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.system(size: 28)).foregroundStyle(MacTheme.green)
            Text("Nothing in that file is marked for removal.")
                .font(.system(size: 13))
            Text("Put yes in the remove column next to the recipes you want gone, then try again.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundStyle(MacTheme.urgent)
            Text(message)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack {
            if !plan.matches.isEmpty {
                Text(selectedCount == 0
                     ? "Nothing selected"
                     : "\(selectedCount) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { onFinish(nil) }
                .keyboardShortcut(.cancelAction)
            Button("Remove…") { confirming = true }
                .disabled(selected.isEmpty)
        }
        .padding(MacTheme.pad)
    }

    // MARK: Behaviour

    /// Ticks the unambiguous matches only. An ambiguous row is a question, and a question
    /// shouldn't arrive pre-answered.
    private func prime() {
        var picks: Set<UUID> = []
        var libs: [UUID: MacRecipeCSVLibrary] = [:]
        for match in plan.matches {
            for candidate in match.candidates { libs[candidate.id] = candidate.library }
            if match.isClean, let one = match.candidates.first { picks.insert(one.id) }
        }
        selected = picks
        libraryOf = libs
    }

    private func commit() {
        var mine: Set<UUID> = []
        var saved: Set<UUID> = []
        for id in selected {
            if libraryOf[id] == .saved { saved.insert(id) } else { mine.insert(id) }
        }
        onFinish((recipes: mine, saved: saved))
    }
}
