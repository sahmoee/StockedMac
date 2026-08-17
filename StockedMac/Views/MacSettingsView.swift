// MacSettingsView.swift — the ⌘, panel.
//
// Mac users expect Settings to hold the things they set once and forget: where the data
// lives, what this build is, and the two destructive buttons that have to exist somewhere
// but must never sit next to a list you're editing.
//
// Anything you'd touch weekly lives in the main window instead. Household sharing is a
// screen, not a preference, because you actually read it.

import SwiftUI
import AppKit

struct MacSettingsView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync

    @State private var confirmErase = false
    @State private var confirmSample = false
    @State private var erasedNotice = false
    @State private var aiBackend = MacAIConfiguration.backend
    @State private var aiEndpoint = MacAIConfiguration.endpoint
    @State private var aiModel = MacAIConfiguration.model
    @State private var aiToken = MacAIConfiguration.token

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            data
                .tabItem { Label("Data", systemImage: "internaldrive") }
            ai
                .tabItem { Label("AI", systemImage: "sparkles") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 520)
    }

    private var ai: some View {
        Form {
            Section("Agent") {
                Picker("AI service", selection: $aiBackend) {
                    ForEach(MacAIBackend.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            if aiBackend == .custom {
                Section("Private Worker") {
                    TextField("https://example.workers.dev", text: $aiEndpoint)
                    SecureField("Worker access token (optional)", text: $aiToken)
                    Text("Deploy UnifiedWorker in your Cloudflare account and add your provider API key with Wrangler. The optional Worker token stays in StockedMac's Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Model") {
                TextField("Worker default", text: $aiModel)
                Text("Leave blank to keep the existing automatic model. A private Worker can honor the requested model or apply its own allowlist.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            MacAIConfiguration.backend = aiBackend
            MacAIConfiguration.endpoint = aiEndpoint
            MacAIConfiguration.model = aiModel
            MacAIConfiguration.saveToken(aiToken)
        }
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                LabeledContent("Household") {
                    if sync.isJoined {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sync.householdName.isEmpty ? "Joined" : sync.householdName)
                            Text(sync.code)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Not joined")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("This Mac") {
                    Text(sync.memberName.isEmpty ? "Unnamed" : sync.memberName)
                }
                LabeledContent("Status") {
                    Text(sync.status.message)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sharing")
            } footer: {
                Text("Joining, leaving and who's in the household all live in the Household "
                     + "screen of the main window — they're things you read, not settings.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("Sharing service") {
                    Label(MacBuildConfig.isWorkerConfigured ? "Configured" : "Not configured",
                          systemImage: MacBuildConfig.isWorkerConfigured
                                       ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(MacBuildConfig.isWorkerConfigured ? MacTheme.green : .orange)
                }
                LabeledContent("Endpoint") {
                    Text(MacBuildConfig.receiptWorkerURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Connection")
            } footer: {
                if !MacBuildConfig.isWorkerConfigured {
                    Text("This build has no sharing key, so household sync will fail. The "
                         + "README explains the single build setting that fixes it.")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var data: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(store.storageDirectory.path)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.storageDirectory])
                        }
                        .buttonStyle(.link)
                    }
                }
                LabeledContent("Last saved") {
                    Text(store.lastSavedAt.map { Self.stamp.string(from: $0) } ?? "Not yet")
                        .foregroundStyle(.secondary)
                }
                if let failure = store.lastSaveError {
                    LabeledContent("Last save problem") {
                        Text(failure)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                LabeledContent("Counts") {
                    Text("\(store.inventory.count) items · \(store.grocery.count) list lines · "
                         + "\(store.recipes.count) recipes · \(store.plannedMeals.count) planned")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("On this Mac")
            } footer: {
                Text("Everything is plain JSON in that folder. Back it up with the rest of "
                     + "your Mac and nothing special is needed — and File ▸ Export makes a "
                     + "single file you can keep anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Build 90 — recipe housekeeping, directly under the counts that prompt the
            // thought. Defined in MacRecipeMaintenanceSection.swift; the same three
            // actions are in the File menu.
            MacRecipeMaintenanceSection()

            Section {
                HStack {
                    Button("Load a sample kitchen…") { confirmSample = true }
                    Spacer()
                }
                HStack {
                    Button("Erase everything on this Mac…", role: .destructive) {
                        confirmErase = true
                    }
                    Spacer()
                }
                if erasedNotice {
                    Label("Erased. If you're in a household, the next sync will bring "
                        + "everything back down.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Starting over")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace what's here with a sample kitchen?",
                            isPresented: $confirmSample) {
            Button("Load the sample", role: .destructive) {
                store.loadSampleKitchen()
                erasedNotice = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This wipes the current lists and fills them with a demonstration kitchen, "
                 + "so you can see what a full app looks like. Export first if you'd rather "
                 + "not lose anything.")
        }
        .confirmationDialog("Erase everything stored on this Mac?",
                            isPresented: $confirmErase) {
            Button("Erase", role: .destructive) {
                store.eraseLocalData()
                erasedNotice = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears the kitchen, list, recipes and plan from this Mac only. Other "
                 + "devices in your household keep theirs, and the next sync will pull them "
                 + "back down here.")
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - About

    private var about: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(systemName: "refrigerator.fill")
                .font(.system(size: 46))
                .foregroundStyle(MacTheme.gold)

            VStack(spacing: 3) {
                Text(MacBuildConfig.appName)
                    .font(.system(size: 22, weight: .semibold))
                Text(MacBuildConfig.displayLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(MacBuildConfig.buildDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(MacBuildConfig.buildName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            Text(MacBuildConfig.sharedModelLineage)
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 14) {
                Link("Website", destination: URL(string: MacBuildConfig.websiteURL)!)
                Link("Support", destination: URL(string: MacBuildConfig.supportPageURL)!)
                Link("Privacy", destination: URL(string: MacBuildConfig.privacyURL)!)
                Link("Terms", destination: URL(string: MacBuildConfig.termsURL)!)
            }
            .font(.callout)

            Text(MacBuildConfig.supportEmail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("© \(MacBuildConfig.company)")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
