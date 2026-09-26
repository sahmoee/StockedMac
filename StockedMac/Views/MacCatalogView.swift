import SwiftUI

struct MacCatalogView: View {
    @Environment(CatalogModel.self) private var catalog
    @State private var mode = Mode.discover
    @State private var selection: Set<UUID> = []
    @State private var filter: CatalogRecordKind?
    @State private var editingRecord: CatalogRecord?
    @State private var sourcePendingDeletion: CatalogSource?

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
        .macThemedSurface()
        .sheet(item: $editingRecord) { record in
            CatalogRecordEditor(record: record) { catalog.update($0) }
                .macThemedSurface()
        }
        .confirmationDialog("Delete all records from this source?", isPresented: Binding(
            get: { sourcePendingDeletion != nil }, set: { if !$0 { sourcePendingDeletion = nil } }
        ), titleVisibility: .visible) {
            if let source = sourcePendingDeletion {
                Button("Delete all \(source.rawValue) records", role: .destructive) {
                    catalog.deleteLibrary(source: source)
                    selection.removeAll()
                    sourcePendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { sourcePendingDeletion = nil }
        } message: {
            Text("This removes imported and queued records from the selected source and sends a durable deletion to the other Mac.")
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
                GroupBox("Server Mac enrichment") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(catalog.serverBatchStatus, systemImage: "server.rack")
                            .font(.caption)
                        LabeledContent("Imported this session", value: "\(catalog.serverImportedCount)")
                        Text("Server batches use the same grocery-only provenance, duplicate merge, aisle, and source rules as local discovery.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(6)
                }
                GroupBox("Automatic bulk import") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(bulkStateTitle,
                                  systemImage: catalog.isBulkImportRunning
                                    ? "arrow.triangle.2.circlepath.circle.fill"
                                    : (catalog.isBulkImportPaused ? "pause.circle.fill" : "stop.circle"))
                                .foregroundStyle(catalog.isBulkImportRunning ? MacTheme.green : .secondary)
                            Spacer()
                            if catalog.isBulkImportRunning {
                                Button { catalog.pauseBulkImport() } label: {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    catalog.isBulkImportPaused
                                        ? catalog.resumeBulkImport()
                                        : catalog.startBulkImport()
                                } label: {
                                    Label(catalog.isBulkImportPaused ? "Resume" : "Start", systemImage: "play.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Button(role: .destructive) { catalog.stopBulkImport() } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .disabled(!catalog.isBulkImportRunning && !catalog.isBulkImportPaused)
                        }
                        Text("No names are required. Stocked rotates through grocery categories, stores, providers, and result pages; imports immediately; skips duplicates; and resumes from its saved position after relaunch.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(catalog.bulkStatus).font(.caption)
                        LabeledContent("Catalog", value: "\(catalog.library.count) records")
                        LabeledContent("Provider requests", value: "\(catalog.bulkRequestCount) this run")
                    }.padding(6)
                }
                GroupBox("What to find") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Optional brand, product, or category", text: $catalog.query)
                        TextField("Optional city, ZIP code, or region", text: $catalog.location)
                        Stepper("Up to \(catalog.resultLimit) per run", value: $catalog.resultLimit, in: 10...500, step: 10)
                        Text("Products receive an aisle automatically. Existing records are enriched with better images and metadata instead of duplicated. Kroger uses a five-digit ZIP for store-specific price, availability and aisle data.")
                            .font(.caption).foregroundStyle(.secondary)
                        if isTexasLocation(catalog.location) {
                            Label("Texas detected — H-E-B stores, own brands and matching live provider results are prioritized.",
                                  systemImage: "location.fill")
                                .font(.caption).foregroundStyle(MacTheme.green)
                        }
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
                }.buttonStyle(.borderedProminent).disabled(
                    catalog.isDiscovering || catalog.isBulkImportEnabled || catalog.selectedSources.isEmpty
                )
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

    private var bulkStateTitle: String {
        if catalog.isBulkImportRunning { return "Running" }
        if catalog.isBulkImportPaused { return "Paused" }
        return "Stopped"
    }

    private func isTexasLocation(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "tx" || normalized.contains("texas") { return true }
        guard let range = normalized.range(of: #"\b\d{5}\b"#, options: .regularExpression),
              let zip = Int(normalized[range]) else { return false }
        return (75001...79999).contains(zip) || (73301...73399).contains(zip) || (88510...88589).contains(zip)
    }

    private var sourcesView: some View {
        @Bindable var catalog = catalog
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(CatalogSource.allCases) { source in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(source.rawValue, systemImage: source.icon)
                                .font(.headline)
                            Text(source.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Label(source.capabilities, systemImage: "checkmark.seal")
                                .font(.caption).foregroundStyle(MacTheme.green)
                            if source == .stockedReference {
                                Text("\(CatalogReferenceData.storeNames.count) store chains · \(CatalogReferenceData.brandNames.count) brands included")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if source == .wikidataCommons {
                                Text("Enter a specific brand or store above. Image files retain the Commons source and attribution requirement.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if source == .kroger {
                                Text("Requires KROGER_CLIENT_ID and KROGER_CLIENT_SECRET on the Unified Worker. No Kroger credential is stored in this app.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if source == .rapidAPIGrocery {
                                Text("Uses the Worker's allowlisted grocery adapter. RapidAPI remains an optional fallback, not a source of truth for store aisles.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
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
                if mode == .library {
                    Menu("Delete by Source") {
                        ForEach(CatalogSource.allCases) { source in
                            let count = catalog.library.lazy.filter { $0.source == source }.count
                            Button("\(source.rawValue) (\(count))", role: .destructive) {
                                sourcePendingDeletion = source
                            }
                            .disabled(count == 0)
                        }
                    }
                }
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
                TableColumn("Image") { row in
                    CatalogImageThumbnail(record: row)
                }.width(54)
                TableColumn("Name") { row in Label(row.name, systemImage: row.kind.icon).lineLimit(2) }.width(min: 180, ideal: 260)
                TableColumn("Brand / Store") { row in Text(row.brand ?? row.store ?? "—").foregroundStyle(.secondary) }.width(min: 120, ideal: 180)
                TableColumn("Category") { row in Text(row.category ?? "—") }.width(min: 110, ideal: 160)
                TableColumn("Aisle") { row in Text(row.aisle ?? "—") }.width(min: 100, ideal: 140)
                TableColumn("Source") { row in Text(row.source.rawValue).font(.caption) }.width(min: 120, ideal: 160)
            }
            if records.isEmpty {
                ContentUnavailableView(mode == .library ? "No imported catalog records" : "Queue is empty",
                                       systemImage: "tag", description: Text(mode == .library
                                        ? "Automatic and manual imports will appear here."
                                        : "Automatic bulk imports go straight to Library. Manual discoveries appear here before import."))
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
                if record.hasImage {
                    CatalogImageThumbnail(record: record, size: 150)
                        .frame(maxWidth: .infinity)
                    if let source = record.imageSourceURL.flatMap(URL.init(string:)) {
                        Link("Open image source and attribution", destination: source)
                    }
                }
                TextField("Name", text: $record.name)
                TextField("Brand", text: optional(\.brand))
                TextField("Store", text: optional(\.store))
                TextField("Category", text: optional(\.category))
                TextField("Aisle", text: optional(\.aisle))
                TextField("Address", text: optional(\.address), axis: .vertical)
                TextField("Original image URL", text: optional(\.imageURL), axis: .vertical)
                TextField("Image attribution", text: optional(\.imageAttribution), axis: .vertical)
                if let regular = record.regularPrice {
                    LabeledContent("Regular price", value: String(format: "$%.2f", regular))
                }
                if let promotional = record.promotionalPrice {
                    LabeledContent("Promotional price", value: String(format: "$%.2f", promotional))
                }
                if let inventory = record.inventoryLevel { LabeledContent("Availability", value: inventory) }
                if let location = record.retailerLocationID { LabeledContent("Store location ID", value: location) }
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

private struct CatalogImageThumbnail: View {
    let record: CatalogRecord
    var size: CGFloat = 42
    @State private var image: NSImage?
    @State private var isLoading = false

    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    private var imageURL: URL? {
        (record.imagePreviewURL ?? record.imageURL).flatMap(URL.init(string:))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if isLoading {
                ProgressView().controlSize(.small)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.35), lineWidth: 1))
        .help(record.imageAttribution ?? (record.hasImage ? "Original source image" : "No image found yet"))
        .task(id: imageURL) { await loadImage() }
    }

    private func loadImage() async {
        image = nil
        guard let url = imageURL else { isLoading = false; return }
        if let cached = Self.cache.object(forKey: url as NSURL) {
            image = cached
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        guard !Task.isCancelled,
              let (data, response) = try? await URLSession.shared.data(from: url),
              !Task.isCancelled,
              let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              let loaded = NSImage(data: data) else { return }
        Self.cache.setObject(loaded, forKey: url as NSURL, cost: data.count)
        image = loaded
    }

    private var placeholder: some View {
        Image(systemName: record.kind == .store ? "storefront" : "photo")
            .foregroundStyle(.secondary)
    }
}
