import SwiftUI

struct MacCatalogView: View {
    @Environment(CatalogModel.self) private var catalog
    @State private var mode = Mode.discover
    @State private var selection: Set<UUID> = []
    @State private var filter: CatalogRecordKind?
    @State private var editingRecord: CatalogRecord?

    private enum Mode: String, CaseIterable, Identifiable { case discover = "Find & Import", library = "Library", sources = "Sources"; var id: String { rawValue } }
    private var rows: [CatalogRecord] {
        let base = mode == .library ? catalog.library : catalog.queue
        return filter.map { kind in base.filter { $0.kind == kind } } ?? base
    }

    var body: some View {
        @Bindable var catalog = catalog
        VStack(spacing: 0) {
            Picker("Workspace", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(maxWidth: 520).padding()
            Divider()
            if mode == .sources { sourcesView }
            else if mode == .discover { discoverView }
            else { libraryView }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingRecord) { record in
            CatalogRecordEditor(record: record) { catalog.update($0) }
        }
    }

    private var discoverView: some View {
        HSplitView {
            discoveryControls.frame(minWidth: 280, idealWidth: 330, maxWidth: 420)
            recordTable(title: "Import queue", records: rows)
        }
    }

    private var libraryView: some View {
        recordTable(title: "Imported catalog", records: rows)
    }

    private var discoveryControls: some View {
        @Bindable var catalog = catalog
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("What to find") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Brand, product, or category", text: $catalog.query)
                        TextField("City, ZIP code, or region", text: $catalog.location)
                        Stepper("Up to \(catalog.resultLimit) per run", value: $catalog.resultLimit, in: 10...500, step: 10)
                        Text("Products receive an aisle automatically. Store discovery uses the location field.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("Sources") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(CatalogSource.allCases) { source in
                            Toggle(source.rawValue, isOn: sourceBinding(source))
                        }
                    }.padding(6)
                }
                Button { Task { await catalog.discover() } } label: {
                    Label(catalog.isDiscovering ? "Searching…" : "Find and Queue", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(catalog.isDiscovering || catalog.selectedSources.isEmpty)
                if catalog.isDiscovering { ProgressView().frame(maxWidth: .infinity) }
                Text(catalog.lastError ?? catalog.status).font(.caption)
                    .foregroundStyle(catalog.lastError == nil ? Color.secondary : Color.red)
                if !catalog.queue.isEmpty {
                    Button("Import Next \(min(200, catalog.queue.count))") { catalog.importQueued(limit: 200) }
                        .buttonStyle(.borderedProminent).tint(MacTheme.green)
                    Text("\(catalog.queue.count) queued. Importing advances through the queue and preserves the remainder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18)
        }
    }

    private var sourcesView: some View {
        @Bindable var catalog = catalog
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(CatalogSource.allCases) { source in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(source.rawValue, systemImage: source == .openStreetMap ? "map" : "externaldrive.connected.to.line.below")
                                .font(.headline)
                            Text(source.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Toggle("Use for discovery", isOn: sourceBinding(source))
                            if source == .usda {
                                SecureField("data.gov API key (optional)", text: $catalog.usdaAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                Link("Get a free key", destination: URL(string: "https://api.data.gov/signup/")!)
                            }
                        }.padding(8)
                    }
                }
            }.padding(20)
        }
    }

    private func recordTable(title: String, records: [CatalogRecord]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Text("\(records.count)").foregroundStyle(.secondary)
                Spacer()
                Picker("Type", selection: $filter) {
                    Text("All types").tag(CatalogRecordKind?.none)
                    ForEach(CatalogRecordKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.frame(width: 150)
                if !selection.isEmpty {
                    if selection.count == 1,
                       let id = selection.first,
                       let record = records.first(where: { $0.id == id }) {
                        Button("Edit") { editingRecord = record }
                    }
                    Button("Delete \(selection.count)", role: .destructive) {
                        mode == .library ? catalog.deleteLibrary(selection) : catalog.removeFromQueue(selection)
                        selection.removeAll()
                    }
                }
            }.padding(16)
            Table(records, selection: $selection) {
                TableColumn("Name") { row in Label(row.name, systemImage: row.kind.icon).lineLimit(2) }.width(min: 180, ideal: 260)
                TableColumn("Brand / Store") { row in Text(row.brand ?? row.store ?? "—").foregroundStyle(.secondary) }.width(min: 120, ideal: 180)
                TableColumn("Category") { row in Text(row.category ?? "—") }.width(min: 110, ideal: 160)
                TableColumn("Aisle") { row in Text(row.aisle ?? "—") }.width(min: 100, ideal: 140)
                TableColumn("Source") { row in Text(row.source.rawValue).font(.caption) }.width(min: 120, ideal: 160)
            }
            if records.isEmpty {
                ContentUnavailableView(mode == .library ? "No imported catalog records" : "Queue is empty",
                                       systemImage: "tag", description: Text("Select sources and run discovery to begin."))
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func sourceBinding(_ source: CatalogSource) -> Binding<Bool> {
        Binding(get: { catalog.selectedSources.contains(source) }, set: { enabled in
            if enabled { catalog.selectedSources.insert(source) } else { catalog.selectedSources.remove(source) }
        })
    }
}

private struct CatalogRecordEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var record: CatalogRecord
    let onSave: (CatalogRecord) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $record.name)
                TextField("Brand", text: optional(\.brand))
                TextField("Store", text: optional(\.store))
                TextField("Category", text: optional(\.category))
                TextField("Aisle", text: optional(\.aisle))
                TextField("Address", text: optional(\.address), axis: .vertical)
                LabeledContent("Source", value: record.source.rawValue)
                LabeledContent("Confidence", value: "\(Int(record.confidence * 100))%")
            }
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 390)
            .navigationTitle("Edit Catalog Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { record.updatedAt = Date(); onSave(record); dismiss() }
                        .disabled(record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func optional(_ path: WritableKeyPath<CatalogRecord, String?>) -> Binding<String> {
        Binding(get: { record[keyPath: path] ?? "" }, set: { record[keyPath: path] = $0.nilIfBlank })
    }
}
