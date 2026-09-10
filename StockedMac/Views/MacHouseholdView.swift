// MacHouseholdView.swift — the Mac's connection to the kitchen everyone else is using.
//
// This is the screen that makes the Mac app worth having. On its own it is a tidy pantry
// list; joined to a household it is the same kitchen the phones see, on a big screen with
// a keyboard. So this view has exactly one job to do well: get the code in, show that it
// worked, and then get out of the way.
//
// There is no separate "sign in". A household is a code and a name. That's deliberate —
// the iOS app made the same choice, and the two have to agree.

import SwiftUI
import AppKit

struct MacHouseholdView: View {
    @Environment(MacKitchenStore.self) private var store
    @Environment(MacHouseholdSync.self) private var sync
    @Environment(\.colorScheme) private var scheme

    @State private var joinCode = ""
    @State private var joinName = ""
    @State private var createName = ""
    @State private var nameDraft = ""
    @State private var working = false
    @State private var problem: String?
    @State private var confirmLeave = false
    @State private var confirmRegenerate = false
    @State private var justCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if sync.isJoined {
                    joinedCard
                    membersCard
                    whatSyncsCard
                    dangerCard
                } else {
                    joinCard
                    createCard
                    explainCard
                }
            }
            .padding(18)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macThemedSurface()
        .onAppear {
            nameDraft = sync.memberName
            if joinName.isEmpty { joinName = defaultName }
            if createName.isEmpty { createName = defaultName }
        }
        .alert("That didn't work", isPresented: Binding(get: { problem != nil },
                                                        set: { if !$0 { problem = nil } })) {
            Button("OK", role: .cancel) { problem = nil }
        } message: {
            Text(problem ?? "")
        }
    }

    /// macOS knows the person's name already. Asking for it again is a small rudeness.
    private var defaultName: String {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty { return full }
        return NSUserName()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sync.isJoined ? (sync.householdName.isEmpty ? "Your household" : sync.householdName)
                               : "Household")
                .font(.system(size: 22, weight: .semibold))
            Text(sync.isJoined
                 ? "This Mac is part of the kitchen. Changes made here reach every other device, and theirs reach here."
                 : "Join the kitchen you already use on your phone, or start a new one here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Not joined

    private var joinCard: some View {
        MacCard(title: "Join with a code", systemImage: "person.badge.key") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Open Stocked on your phone, go to Household, and read off the code.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("Code", text: $joinCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .frame(width: 160)
                        .onSubmit(runJoin)
                    TextField("Your name on this Mac", text: $joinName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(runJoin)
                }

                HStack(spacing: 8) {
                    Button("Join", action: runJoin)
                        .keyboardShortcut(.defaultAction)
                        .disabled(working || !canJoin)
                    if working { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var canJoin: Bool {
        !joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !joinName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var createCard: some View {
        MacCard(title: "Start a new household", systemImage: "house") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Only do this if nobody in the house has a kitchen yet. If someone does, "
                     + "join theirs instead — two households don't merge later.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Your name", text: $createName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                HStack(spacing: 8) {
                    Button("Create a household", action: runCreate)
                        .disabled(working || createName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if working { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private var explainCard: some View {
        MacCard(title: "What sharing does", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 7) {
                bullet("Everyone sees the same kitchen, grocery list, recipes and week.")
                bullet("Edits win by whoever saved last, so two people editing the same "
                     + "item settle on one answer rather than fighting.")
                bullet("Nothing leaves this Mac until you join. Until then it's a local list.")
                if !MacBuildConfig.isWorkerConfigured {
                    Divider().padding(.vertical, 2)
                    Label("Sharing isn't configured in this build, so joining will fail. "
                        + "See the README for the one setting it needs.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                .padding(.top, 5)
            Text(text)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Joined

    private var joinedCard: some View {
        MacCard(title: "This kitchen", systemImage: "qrcode") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(sync.code)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MacTheme.accent(dark: scheme == .dark))
                        .textSelection(.enabled)
                    Button(justCopied ? "Copied" : "Copy") { copyCode() }
                        .buttonStyle(.link)
                    Spacer(minLength: 0)
                }
                Text("Read this out to anyone joining. They'll need it once.")
                    .font(.callout).foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Text("Your name here")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("Name", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                        .onSubmit(runRename)
                    Button("Save") { runRename() }
                        .disabled(working || nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || nameDraft == sync.memberName)
                    Spacer(minLength: 0)
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        Task { working = true; await sync.syncNow(store: store); working = false }
                    } label: {
                        Label("Sync now", systemImage: "arrow.clockwise")
                    }
                    .disabled(working || sync.status.isBusy)

                    Button {
                        Task { working = true; await sync.refreshPresence(); working = false }
                    } label: {
                        Label("Refresh people", systemImage: "person.2")
                    }
                    .disabled(working)

                    if sync.status.isBusy || working { ProgressView().controlSize(.small) }

                    Spacer(minLength: 8)

                    statusLabel
                }
            }
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusTint)
                .frame(width: 7, height: 7)
            Text(sync.status.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(lastPulledDescription)
    }

    private var statusTint: Color {
        switch sync.status {
        case .idle:     return .secondary
        case .syncing:  return MacTheme.gold
        case .repairing: return .orange
        case .synced:   return MacTheme.green
        case .failed:   return .red
        }
    }

    private var lastPulledDescription: String {
        guard sync.lastPulledAt > 0 else { return "Nothing pulled down yet." }
        let date = Date(timeIntervalSince1970: sync.lastPulledAt)
        return "Last pulled \(Self.stamp.string(from: date))."
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var membersCard: some View {
        MacCard(title: "Who's in", systemImage: "person.2.fill",
                footnote: sync.members.isEmpty ? nil : "\(sync.members.count)") {
            if sync.members.isEmpty {
                Text("Nobody's been listed yet. Hit Refresh people once everyone has opened "
                     + "the app at least once.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(sync.members) { member in
                        memberRow(member)
                        if member.id != sync.members.last?.id {
                            Divider().padding(.vertical, 5)
                        }
                    }
                }
            }
        }
    }

    private func memberRow(_ member: MacHouseholdMember) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(member.isOnline ? MacTheme.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .help(member.isOnline ? "Active recently" : "Not active recently")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(member.name.isEmpty ? "Someone" : member.name)
                        .font(.callout)
                    if member.isMe {
                        MacPill(text: "This Mac", tint: MacTheme.gold)
                    }
                }
                Text(member.displayLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if canManage && !member.isMe {
                Picker("", selection: Binding(
                    get: { member.role },
                    set: { newRole in
                        Task { await sync.setRole(newRole, for: member.id) }
                    })) {
                    ForEach(MacHouseholdMember.Role.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
            } else {
                Text(member.role.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// Only owners and managers get to change other people's roles — matching iOS.
    private var canManage: Bool {
        sync.members.first { $0.isMe }?.role.canManageMembers ?? false
    }

    private var whatSyncsCard: some View {
        @Bindable var sync = sync
        return MacCard(title: "What this Mac shares", systemImage: "slider.horizontal.3",
                       footnote: "Applies to this Mac only") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("The kitchen", isOn: $sync.syncInventory)
                Toggle("The grocery list", isOn: $sync.syncGrocery)
                Toggle("Recipes", isOn: $sync.syncRecipes)
                Toggle("The week's plan", isOn: $sync.syncPlan)
            }
            .toggleStyle(.checkbox)
            .onChange(of: sync.syncInventory) { _, _ in sync.persistPreferences() }
            .onChange(of: sync.syncGrocery)   { _, _ in sync.persistPreferences() }
            .onChange(of: sync.syncRecipes)   { _, _ in sync.persistPreferences() }
            .onChange(of: sync.syncPlan)      { _, _ in sync.persistPreferences() }

            Text("Turning one off stops this Mac sending or receiving it. Everyone else "
                 + "carries on as normal.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dangerCard: some View {
        MacCard(title: "Leaving and codes", systemImage: "exclamationmark.triangle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button("New code…") { confirmRegenerate = true }
                        .disabled(working || !canManage)
                    Text("Stops anyone with the old code getting back in. Everyone still in "
                         + "the household keeps working.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack(spacing: 10) {
                    Button("Leave household…", role: .destructive) { confirmLeave = true }
                        .disabled(working)
                    Text("This Mac keeps its own copy of everything, but stops sending and "
                         + "receiving.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .confirmationDialog("Give this household a new code?",
                            isPresented: $confirmRegenerate) {
            Button("Make a new code") { runRegenerate() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Anyone who hasn't already joined will need the new one.")
        }
        .confirmationDialog("Leave this household?", isPresented: $confirmLeave) {
            Button("Leave", role: .destructive) { runLeave() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Everything currently on this Mac stays on this Mac. You can rejoin later "
                 + "with the same code.")
        }
    }

    // MARK: - Actions

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sync.code, forType: .string)
        justCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            justCopied = false
        }
    }

    private func runJoin() {
        guard canJoin, !working else { return }
        let code = joinCode
        let name = joinName
        Task {
            working = true
            let ok = await sync.join(code: code, as: name)
            if ok {
                store.writerID = sync.memberID
                nameDraft = sync.memberName
                await sync.pull(into: store)
                await sync.refreshPresence()
                joinCode = ""
            } else {
                problem = joinFailureMessage
            }
            working = false
        }
    }

    private var joinFailureMessage: String {
        if case .failed(let why) = sync.status, !why.isEmpty { return why }
        return "That code didn't take. Check it on your phone — codes are short and easy to "
             + "mis-hear — and make sure this Mac is online."
    }

    private func runCreate() {
        guard !working else { return }
        let name = createName
        Task {
            working = true
            if let code = await sync.createHousehold(ownerName: name) {
                store.writerID = sync.memberID
                nameDraft = sync.memberName
                joinCode = code
                await sync.syncNow(store: store)
                await sync.refreshPresence()
            } else {
                problem = joinFailureMessage
            }
            working = false
        }
    }

    private func runRename() {
        let clean = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !working else { return }
        Task {
            working = true
            await sync.setDisplayName(clean)
            await sync.refreshPresence()
            working = false
        }
    }

    private func runRegenerate() {
        Task {
            working = true
            if await sync.regenerateCode() == nil { problem = joinFailureMessage }
            working = false
        }
    }

    private func runLeave() {
        Task {
            working = true
            await sync.leave()
            joinName = sync.memberName.isEmpty ? defaultName : sync.memberName
            createName = joinName
            working = false
        }
    }
}
