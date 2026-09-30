// MacRecipeDetailTools.swift — reading, sharing and printing tools for one recipe.
//
// Build 114. Serving scale and unit conversion are display-only: they rewrite what the
// ingredient card shows, never the stored amounts. Private notes are edited through the
// normal MacKitchenStore.updateRecipe path so household sync and last-write stamping stay
// intact. Printing and PDF export use AppKit's own print system (Save as PDF included).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Serving + unit bar

struct MacRecipeServingBar: View {
    let baseServings: Int
    @Binding var servings: Int
    @Binding var system: MacMeasurementSystem

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { servingControl; Spacer(minLength: 0); unitControl }
            VStack(alignment: .leading, spacing: 8) { servingControl; unitControl }
        }
        .font(.callout)
    }

    private var servingControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2").foregroundStyle(.secondary)
            Stepper(value: $servings, in: 1...200) {
                Text("Serves \(servings)").monospacedDigit()
            }
            .fixedSize()
            .accessibilityLabel("Servings shown")
            .accessibilityValue("\(servings)")
            if servings != baseServings {
                Button("Reset to \(baseServings)") { servings = baseServings }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .help("Scale ingredient amounts for reading. The saved recipe is unchanged.")
    }

    private var unitControl: some View {
        Picker("Units", selection: $system) {
            ForEach(MacMeasurementSystem.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 300)
        .help("Show amounts as written, in US customary units, or in metric units")
    }
}

// MARK: - Inline private notes

struct MacRecipeNotesEditor: View {
    let recipe: UserRecipe
    @Environment(MacKitchenStore.self) private var store
    @State private var isEditing = false
    @State private var draft = ""
    @State private var problem: String?

    var body: some View {
        MacCard(title: "Notes", systemImage: "note.text",
                footnote: isEditing ? "Private to your household" : nil) {
            if isEditing {
                TextEditor(text: $draft)
                    .font(.callout)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Recipe notes")
                if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel") { isEditing = false; problem = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Save Notes") { save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == recipe.notes)
                }
            } else if let notes = recipe.notes.nilIfBlank {
                Text(notes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Edit Notes") { begin() }.buttonStyle(.link).font(.caption)
            } else {
                HStack {
                    Text("No notes yet. Notes stay with your household and are never published.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Add Notes") { begin() }
                }
            }
        }
        .onChange(of: recipe.id) { _, _ in isEditing = false; problem = nil }
    }

    private func begin() {
        draft = recipe.notes
        problem = nil
        isEditing = true
    }

    private func save() {
        let value = draft
        let before = store.recipes.first { $0.id == recipe.id }?.updatedAt
        store.updateRecipe(id: recipe.id) { $0.notes = value }
        let after = store.recipes.first { $0.id == recipe.id }?.updatedAt
        if before == after, value != recipe.notes {
            problem = "These notes couldn't be saved because the recipe is missing its required image. Repair the image in Edit first."
            return
        }
        isEditing = false
    }
}

// MARK: - Clipboard + sharing

@MainActor
enum MacRecipeClipboard {
    static func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    static func copyMarkdown(_ recipe: UserRecipe, factor: Double = 1, system: MacMeasurementSystem = .asWritten) {
        copy(MacRecipeTextExport.markdown(recipe, factor: factor, system: system))
    }

    static func copyCooklang(_ recipe: UserRecipe) {
        copy(MacRecipeTextExport.cooklang(recipe))
    }
}

// MARK: - Printing and PDF

@MainActor
enum MacRecipePrinter {
    static func print(_ recipe: UserRecipe, factor: Double = 1, system: MacMeasurementSystem = .asWritten) {
        let operation = NSPrintOperation(view: textView(for: recipe, factor: factor, system: system),
                                         printInfo: printInfo())
        operation.jobTitle = recipe.title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    static func exportPDF(_ recipe: UserRecipe, factor: Double = 1, system: MacMeasurementSystem = .asWritten) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = MacRecipeTextExport.safeFilename(recipe.title, id: recipe.id) + ".pdf"
        panel.message = "Save a printable PDF of this recipe. The original source and credits are included."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary().setObject(url, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)
        let operation = NSPrintOperation(view: textView(for: recipe, factor: factor, system: system), printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        if operation.run() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "The PDF couldn't be saved"
            alert.informativeText = "Check that the destination folder is writable and try again."
            alert.runModal()
        }
    }

    private static func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        info.topMargin = 42; info.bottomMargin = 42; info.leftMargin = 48; info.rightMargin = 48
        return info
    }

    private static func textView(for recipe: UserRecipe, factor: Double, system: MacMeasurementSystem) -> NSTextView {
        let width: CGFloat = 516
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        view.isEditable = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = true
        view.textStorage?.setAttributedString(document(for: recipe, factor: factor, system: system, width: width))
        if let container = view.textContainer, let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            let height = layout.usedRect(for: container).height + 20
            view.setFrameSize(NSSize(width: width, height: max(height, 200)))
        }
        return view
    }

    private static func document(for recipe: UserRecipe, factor: Double,
                                 system: MacMeasurementSystem, width: CGFloat) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 11)
        let ink = NSColor.black
        let muted = NSColor.darkGray
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        paragraph.lineSpacing = 1.5

        func append(_ text: String, font: NSFont = body, color: NSColor = ink, spacing: CGFloat = 4) {
            let style = (paragraph.mutableCopy() as? NSMutableParagraphStyle) ?? paragraph
            style.paragraphSpacing = spacing
            output.append(NSAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: style,
            ]))
        }

        if let data = recipe.imageData, let image = NSImage(data: data), image.size.width > 0 {
            let attachment = NSTextAttachment()
            let scale = min(1, width / image.size.width, 220 / max(1, image.size.height))
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
            output.append(NSAttributedString(attachment: attachment))
            output.append(NSAttributedString(string: "\n"))
        }

        append(recipe.title, font: .boldSystemFont(ofSize: 20), spacing: 6)
        if let description = recipe.description.nilIfBlank { append(description, color: muted, spacing: 8) }
        var facts = ["Serves \(max(1, Int((Double(recipe.servings) * factor).rounded())))"]
        if let prep = recipe.prepTime.nilIfBlank { facts.append("Prep \(prep)") }
        if let cook = recipe.cookTime.nilIfBlank { facts.append("Cook \(cook)") }
        if let cuisine = recipe.cuisine.nilIfBlank { facts.append(cuisine) }
        append(facts.joined(separator: "  ·  "), font: .systemFont(ofSize: 10, weight: .medium), color: muted, spacing: 12)

        append("Ingredients", font: .boldSystemFont(ofSize: 13), spacing: 6)
        for ingredient in recipe.ingredients {
            append("•  " + MacRecipeTextExport.ingredientLine(ingredient, factor: factor, system: system), spacing: 2)
        }
        append("", spacing: 6)
        append("Method", font: .boldSystemFont(ofSize: 13), spacing: 6)
        for (offset, step) in recipe.instructions.enumerated() {
            append("\(offset + 1).  \(step)", spacing: 6)
        }
        if let notes = recipe.notes.nilIfBlank {
            append("", spacing: 6)
            append("Notes", font: .boldSystemFont(ofSize: 13), spacing: 6)
            append(notes, spacing: 6)
        }
        var credits: [String] = []
        if let url = recipe.attributedSourceURL?.nilIfBlank {
            credits.append("Source: \(recipe.sourceName?.nilIfBlank ?? URL(string: url)?.host ?? "Original recipe") — \(url)")
        }
        if let author = recipe.author?.nilIfBlank { credits.append("Author: \(author)") }
        if let license = recipe.license?.nilIfBlank { credits.append("Recipe license: \(license)") }
        if let photo = recipe.imageAttribution?.nilIfBlank { credits.append("Photo credit: \(photo)") }
        if !credits.isEmpty {
            append("", spacing: 8)
            for line in credits { append(line, font: .systemFont(ofSize: 9), color: muted, spacing: 2) }
        }
        return output
    }
}

// MARK: - Keep window on top

/// Finds the hosting NSWindow and applies a floating level while enabled. Restores the
/// normal level when disabled or when the view leaves the window.
struct MacWindowLevelAccessor: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in apply(to: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in apply(to: nsView) }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Void) {
        nsView.window?.level = .normal
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.level = floating ? .floating : .normal
        window.collectionBehavior.insert(.fullScreenAuxiliary)
    }
}

// MARK: - Library actions shared by menus, toolbar and context menus

@MainActor
enum MacRecipeLibraryActions {
    /// Adds a personal, household-only copy and reveals it. Returns the new id.
    @discardableResult
    static func duplicateAsVariation(_ id: UUID, store: MacKitchenStore, desktop: MacDesktopExperience) -> UUID? {
        guard let original = store.recipes.first(where: { $0.id == id }) else { return nil }
        let copy = MacRecipeVariation.make(from: original)
        store.addRecipe(copy)
        guard store.recipes.contains(where: { $0.id == copy.id }) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "The variation couldn't be created"
            alert.informativeText = "“\(original.title)” is missing its required image. Repair the image in Edit, then try again."
            alert.runModal()
            return nil
        }
        desktop.reveal(copy.id)
        desktop.pendingEditRecipeID = copy.id
        return copy.id
    }

    /// Writes the given recipes as Markdown files into a new folder the user chooses.
    static func exportMarkdown(_ recipes: [UserRecipe]) {
        guard !recipes.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Export \(recipes.count) recipe\(recipes.count == 1 ? "" : "s") as Markdown into a new folder."
        let includeNotes = NSButton(checkboxWithTitle: "Include private notes", target: nil, action: nil)
        includeNotes.state = .off
        panel.accessoryView = includeNotes
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let withNotes = includeNotes.state == .on
        let snapshot = recipes
        Task {
            let outcome = await Task.detached(priority: .utility) { () -> (folder: URL?, failure: String?) in
                let access = destination.startAccessingSecurityScopedResource()
                defer { if access { destination.stopAccessingSecurityScopedResource() } }
                do { return (try MacRecipeTextExport.writeMarkdownFolder(snapshot, into: destination, includeNotes: withNotes), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value
            if let folder = outcome.folder {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } else {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "The export didn't finish"
                alert.informativeText = outcome.failure ?? "The folder couldn't be written."
                alert.runModal()
            }
        }
    }
}
