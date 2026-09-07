import AppKit
import SwiftUI

struct MacRecipeFolderInboxView: View {
    @Environment(MacRecipeFolderInbox.self) private var inbox
    @State private var reviewing: MacRecipeInboxReview?
    @State private var message: String?
    @State private var confirmRemove = false

    var body: some View {
        MacCard(title: "Recipe drop folder", systemImage: "folder.badge.plus") {
            ViewThatFits(in: .horizontal) {
                HStack { controls }
                VStack(alignment: .leading) { controls }
            }
            Text(message ?? inbox.status).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if inbox.isConfigured {
                Text("Only direct files in \(inbox.folderName) are checked while Stocked is running. Linked files and subfolders are skipped. Every file still needs your review.")
                    .font(.caption).foregroundStyle(.secondary)
                if let date = inbox.lastScanAt { Text("Last checked \(date.formatted(date: .omitted, time: .shortened))").font(.caption) }
                if !inbox.queue.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(inbox.queue) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.filename).lineLimit(2)
                                        Text(item.replacesEarlierFile ? "Updated file · review the new version" : ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Review") { reviewing = inbox.review(item) }
                                    Button("Dismiss") { inbox.dismiss(item) }
                                }
                            }
                        }
                    }.frame(maxHeight: 180)
                }
            }
        }
        .sheet(item: $reviewing) { request in
            MacRecipeInterchangeView(inboxReview: request)
        }
        .confirmationDialog("Stop watching this folder?", isPresented: $confirmRemove) {
            Button("Remove folder access", role: .destructive) { inbox.removeFolder() }
        } message: { Text("The review queue is cleared. Your original files and saved recipes stay as they are.") }
    }

    @ViewBuilder private var controls: some View {
        Button(inbox.isConfigured ? "Change folder…" : "Choose folder…") { chooseFolder() }
        if inbox.isConfigured {
            Button(inbox.isPaused ? "Resume" : "Pause") { inbox.togglePause() }
            Button("Scan now") { Task { await inbox.scanNow() } }.disabled(inbox.isScanning)
            Button("Remove…") { confirmRemove = true }
        }
        if inbox.isScanning { ProgressView().controlSize(.small) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a small folder for recipe files or exported recipe archives. Files are queued for review, never imported automatically."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do { try inbox.choose(folder); message = nil }
        catch { message = error.localizedDescription }
    }
}
