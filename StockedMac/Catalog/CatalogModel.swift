import Foundation
import Observation

extension Notification.Name {
    static let macInventoryNeedsCatalogEnrichment = Notification.Name("com.sowens.StockedMac.inventoryNeedsCatalogEnrichment")
}

nonisolated enum CatalogRecordKind: String, Codable, CaseIterable, Sendable {
    case brand = "Brand"
    case product = "Product"
    case store = "Store"
    case aisle = "Aisle"

    var icon: String {
        switch self {
        case .brand: "tag"
        case .product: "shippingbox"
        case .store: "storefront"
        case .aisle: "square.grid.3x3"
        }
    }
}

nonisolated enum CatalogImportState: String, Codable, Sendable {
    case queued, imported, skipped
}

nonisolated enum CatalogSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case openFoodFacts = "Open Food Facts"
    case usda = "USDA FoodData Central"
    case openStreetMap = "OpenStreetMap"
    case wikidataCommons = "Wikidata + Wikimedia Commons"
    case kroger = "Kroger Store Catalog"
    case rapidAPIGrocery = "RapidAPI Grocery Catalog"
    case fatSecret = "FatSecret Food & Nutrition"
    case stockedReference = "Stocked Brand & Store Reference"
    case builtIn = "Stocked Aisle Taxonomy"
    case legacyRemoved = "Removed non-grocery source"

    static let allCases: [CatalogSource] = [
        .kroger, .openFoodFacts, .usda, .openStreetMap, .wikidataCommons,
        .fatSecret, .rapidAPIGrocery, .stockedReference, .builtIn
    ]

    var id: String { rawValue }
    var detail: String {
        switch self {
        case .openFoodFacts: "Worldwide grocery products, barcodes, brands, stores, categories and original product images"
        case .usda: "U.S. Global Branded Foods; a free data.gov key is recommended"
        case .openStreetMap: "Nearby grocery stores and addresses by city, ZIP code or region"
        case .wikidataCommons: "Brand and retailer identities with reusable original images from Wikimedia Commons"
        case .kroger: "Official store locations and grocery products with store-specific prices, availability, aisles and original images"
        case .rapidAPIGrocery: "Optional Walmart and Amazon grocery catalog fallback through the key-protected Stocked Worker"
        case .fatSecret: "Branded and generic grocery foods with serving and nutrition data through the protected Stocked Worker"
        case .stockedReference: "Offline coverage for major grocery chains and consumer brands; no key or network required"
        case .builtIn: "Offline category-to-aisle rules used to normalize every source"
        case .legacyRemoved: "Retained only to migrate old saved catalogs safely"
        }
    }

    var capabilities: String {
        switch self {
        case .openFoodFacts: "Grocery products · Brands · Stores · Images"
        case .usda: "Products · Brands · Barcodes"
        case .openStreetMap: "Stores · Addresses · Coordinates"
        case .wikidataCommons: "Brands · Stores · Original images · Attribution"
        case .kroger: "Stores · Products · Brands · Prices · Availability · Aisles · Images"
        case .rapidAPIGrocery: "Products · Brands · Prices · Images"
        case .fatSecret: "Products · Brands · Nutrition"
        case .stockedReference: "Brands · Store chains · Offline"
        case .builtIn: "Categories · Aisles · Offline"
        case .legacyRemoved: "Unavailable"
        }
    }

    var icon: String {
        switch self {
        case .openStreetMap: "map"
        case .kroger: "cart.fill.badge.plus"
        case .rapidAPIGrocery, .fatSecret: "network"
        case .wikidataCommons: "photo.on.rectangle.angled"
        case .stockedReference, .builtIn: "internaldrive"
        case .legacyRemoved: "nosign"
        default: "externaldrive.connected.to.line.below"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if ["Open Beauty Facts", "Open Pet Food Facts", "Open Products Facts"].contains(value) {
            self = .legacyRemoved
        } else if let source = Self(rawValue: value) {
            self = source
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown catalog source: \(value)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct CatalogRecord: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var kind: CatalogRecordKind
    var name: String
    var brand: String? = nil
    var category: String? = nil
    var aisle: String? = nil
    var store: String? = nil
    var address: String? = nil
    var barcode: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var source: CatalogSource
    var sourceURL: String? = nil
    var imageURL: String? = nil
    var imagePreviewURL: String? = nil
    var imageSourceURL: String? = nil
    var imageAttribution: String? = nil
    var externalID: String? = nil
    var retailerLocationID: String? = nil
    var regularPrice: Double? = nil
    var promotionalPrice: Double? = nil
    var inventoryLevel: String? = nil
    var confidence: Double = 0.8
    var state: CatalogImportState = .queued
    var updatedAt = Date()

    var identityKey: String {
        [kind.rawValue, name, brand ?? "", store ?? "", barcode ?? "", address ?? ""]
            .joined(separator: "|").foldedCatalogKey
    }

    var hasImage: Bool { imageURL?.nilIfBlank != nil }

    private static func imageQualityScore(_ raw: String?) -> Int {
        guard let raw = raw?.nilIfBlank, let url = URL(string: raw), url.scheme == "https" else { return 0 }
        let value = raw.lowercased()
        var score = 10
        if value.contains("/full/") || value.contains("original") || value.contains("image_url") { score += 8 }
        if value.contains("small") || value.contains("thumb") || value.contains("preview") { score -= 7 }
        if value.contains(".400.") || value.contains("/400/") { score -= 3 }
        return score
    }

    mutating func mergeEnrichment(from incoming: CatalogRecord) -> Bool {
        let before = self
        brand = brand ?? incoming.brand
        category = category ?? incoming.category
        aisle = aisle ?? incoming.aisle
        store = store ?? incoming.store
        address = address ?? incoming.address
        barcode = barcode ?? incoming.barcode
        latitude = latitude ?? incoming.latitude
        longitude = longitude ?? incoming.longitude
        sourceURL = sourceURL ?? incoming.sourceURL
        // `imageURL` always tracks the best original asset. Small CDN previews stay in
        // imagePreviewURL and can never downgrade a previously imported full-size image.
        if Self.imageQualityScore(incoming.imageURL) > Self.imageQualityScore(imageURL) {
            imageURL = incoming.imageURL
            imageSourceURL = incoming.imageSourceURL ?? imageSourceURL
            imageAttribution = incoming.imageAttribution ?? imageAttribution
        }
        imagePreviewURL = imagePreviewURL ?? incoming.imagePreviewURL
        imageSourceURL = imageSourceURL ?? incoming.imageSourceURL
        imageAttribution = imageAttribution ?? incoming.imageAttribution
        externalID = externalID ?? incoming.externalID
        retailerLocationID = retailerLocationID ?? incoming.retailerLocationID
        regularPrice = incoming.regularPrice ?? regularPrice
        promotionalPrice = incoming.promotionalPrice ?? promotionalPrice
        inventoryLevel = incoming.inventoryLevel ?? inventoryLevel
        confidence = max(confidence, incoming.confidence)
        if self != before { updatedAt = Date(); return true }
        return false
    }
}

nonisolated struct ServerCatalogBatch: Codable, Sendable {
    var schemaVersion: Int
    var batchID: String
    var createdAt: Date
    var sourceName: String
    var records: [CatalogRecord]
}

nonisolated struct CatalogMutation: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case upsert, deleteIDs, deleteSource }
    var schemaVersion = 1
    var mutationID = UUID().uuidString
    var createdAt = Date()
    var actorID: String
    var operation: Operation
    var records: [CatalogRecord] = []
    var recordIDs: [UUID] = []
    var source: CatalogSource? = nil
}

nonisolated private struct CatalogSnapshot: Codable, Sendable {
    var library: [CatalogRecord]
    var queue: [CatalogRecord]
}

private actor CatalogSnapshotWriter {
    func write(_ snapshot: CatalogSnapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

nonisolated private extension String {
    var foldedCatalogKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().filter { $0.isLetter || $0.isNumber || $0 == "|" }
    }
}

nonisolated enum GroceryAisleClassifier {
    static func aisle(for raw: String) -> String {
        let value = raw.lowercased()
        let rules: [(String, [String])] = [
            ("Produce", ["fruit", "vegetable", "produce", "salad", "herb", "fresh"]),
            ("Bakery", ["bread", "bakery", "tortilla", "bun", "cake"]),
            ("Dairy & Eggs", ["milk", "cheese", "yogurt", "butter", "egg", "dairy"]),
            ("Meat & Seafood", ["meat", "beef", "pork", "chicken", "turkey", "fish", "seafood"]),
            ("Frozen", ["frozen", "ice cream"]),
            ("Canned & Jarred", ["canned", "preserved", "sauce", "pickle", "jar"]),
            ("Pasta, Rice & Grains", ["pasta", "rice", "grain", "cereal", "noodle"]),
            ("Baking", ["baking", "flour", "sugar", "yeast", "chocolate"]),
            ("Snacks", ["snack", "chip", "cracker", "popcorn", "candy"]),
            ("Beverages", ["beverage", "drink", "water", "coffee", "tea", "juice", "soda"]),
            ("Condiments & Spices", ["condiment", "spice", "seasoning", "oil", "vinegar"]),
            ("International", ["international", "asian", "mexican", "indian", "italian"]),
            ("Household", ["household", "cleaner", "paper", "laundry", "trash"]),
        ]
        return rules.first(where: { rule in rule.1.contains(where: value.contains) })?.0 ?? "Pantry"
    }
}

@MainActor @Observable
final class CatalogModel {
    var library: [CatalogRecord] = []
    var queue: [CatalogRecord] = []
    var selectedSources: Set<CatalogSource> = Set(CatalogSource.allCases)
    var query = ""
    var location = ""
    var resultLimit = 100
    var isDiscovering = false
    var status = "Ready"
    var lastError: String?
    var usdaAPIKey = ""
    var isBulkImportEnabled = false
    var isBulkImportPaused = false
    var bulkImportedCount = 0
    var bulkRequestCount = 0
    var bulkStatus = "Bulk import is off"
    var serverBatchStatus = "Waiting for Server Mac catalog batches"
    var serverImportedCount = 0
    var isBulkImportRunning: Bool {
        isBulkImportEnabled && !isBulkImportPaused && bulkRunID != nil
    }

    private let session: URLSession
    private let saveURL: URL
    private var bulkTask: Task<Void, Never>?
    private var bulkRunID: UUID?
    /// Catalog snapshots can be several megabytes. Coalescing nearby mutations avoids
    /// repeatedly encoding the complete library while a provider batch is merging.
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingWorkerPublishTask: Task<Void, Never>?
    private var saveGeneration: UInt = 0
    private var serverInboxTask: Task<Void, Never>?
    private let mutationActorID = Host.current().localizedName ?? UUID().uuidString
    private let snapshotWriter = CatalogSnapshotWriter()
    private var libraryIdentityIndex: [String: Int] = [:]
    private var queueIdentityIndex: [String: Int] = [:]
    private var bulkCursor = BulkCursor()
    private var requestQueryOverride: String?
    private var requestLocationOverride: String?
    private var requestQuery: String { requestQueryOverride ?? query }
    private var requestLocation: String { requestLocationOverride ?? location }
    private var isTexasRequest: Bool { Self.isTexasLocation(requestLocation) }

    /// Broad grocery terms intentionally live in the app so a fresh install can discover
    /// useful records without requiring the user to know or type product names. The cursor
    /// is persisted, so every pass advances instead of repeatedly mining the first terms.
    private static let bulkSeeds = [
        "fresh fruit", "fresh vegetables", "salad greens", "fresh herbs", "bread", "tortillas",
        "milk", "cheese", "yogurt", "butter", "eggs", "beef", "chicken", "pork", "turkey",
        "fish", "seafood", "frozen vegetables", "frozen meals", "ice cream", "canned beans",
        "canned vegetables", "pasta sauce", "pasta", "rice", "grains", "breakfast cereal",
        "oatmeal", "flour", "sugar", "baking", "chips", "crackers", "nuts", "popcorn",
        "chocolate", "coffee", "tea", "juice", "sparkling water", "soda", "spices",
        "seasoning", "cooking oil", "vinegar", "condiments", "international foods",
        "plant based", "gluten free", "organic food", "baby food", "household paper",
        "food storage", "dish soap", "laundry detergent"
    ]

    private static let storeRegions = [
        "77002", "78205", "75201", "78701", "73301", "76102", "79901", "78401", "76701", "79401",
        "90210", "94103", "98101", "80202",
        "60601", "10001", "02108", "30303", "33130", "20001", "37201", "85004", "97205"
    ]

    init(session: URLSession = .shared) {
        self.session = session
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("StockedMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        saveURL = root.appendingPathComponent("brand-store-catalog.json")
        load()
    }

    func startBulkImport() {
        guard bulkTask == nil else { return }
        let continuingPausedRun = isBulkImportPaused
        isBulkImportEnabled = true
        isBulkImportPaused = false
        UserDefaults.standard.set(true, forKey: "catalog.bulk.enabled.v1")
        UserDefaults.standard.set(false, forKey: "catalog.bulk.paused.v1")
        if !continuingPausedRun {
            bulkImportedCount = 0
            bulkRequestCount = 0
        }
        lastError = nil
        bulkStatus = continuingPausedRun
            ? "Resuming automatic import from the saved position…"
            : "Starting automatic grocery catalog import…"
        let runID = UUID()
        bulkRunID = runID
        bulkTask = Task { [weak self] in await self?.runBulkImport(runID: runID) }
    }

    func pauseBulkImport() {
        isBulkImportEnabled = false
        isBulkImportPaused = true
        UserDefaults.standard.set(false, forKey: "catalog.bulk.enabled.v1")
        UserDefaults.standard.set(true, forKey: "catalog.bulk.paused.v1")
        bulkTask?.cancel()
        bulkTask = nil
        bulkRunID = nil
        bulkStatus = "Paused safely — progress is saved"
        saveNow()
    }

    func stopBulkImport() {
        isBulkImportEnabled = false
        isBulkImportPaused = false
        UserDefaults.standard.set(false, forKey: "catalog.bulk.enabled.v1")
        UserDefaults.standard.set(false, forKey: "catalog.bulk.paused.v1")
        bulkTask?.cancel()
        bulkTask = nil
        bulkRunID = nil
        requestQueryOverride = nil
        requestLocationOverride = nil
        bulkStatus = "Stopped — saved position will be used the next time you start"
        saveNow()
    }

    func resumeBulkImport() {
        guard isBulkImportPaused else { startBulkImport(); return }
        startBulkImport()
    }

    func resumeBulkImportIfEnabled() {
        guard isBulkImportEnabled else { return }
        startBulkImport()
    }

    func startServerInboxConsumer() {
        guard serverInboxTask == nil else { return }
        serverInboxTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.consumeServerCatalogInbox()
                self?.consumeCatalogMutations()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func mutationRoot() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.sowens.StockedMac", isDirectory: true)
    }

    private func publishMutation(_ mutation: CatalogMutation) {
        guard let root = mutationRoot() else { return }
        let outbox = root.appendingPathComponent("CatalogMutationOutbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(mutation) else { return }
        try? data.write(to: outbox.appendingPathComponent(mutation.mutationID).appendingPathExtension("json"), options: .atomic)
    }

    private func consumeCatalogMutations() {
        guard let root = mutationRoot() else { return }
        let inbox = root.appendingPathComponent("CatalogMutationInbox", isDirectory: true)
        let receipts = root.appendingPathComponent("CatalogMutationReceipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for file in files.prefix(100) {
            let receipt = receipts.appendingPathComponent(file.deletingPathExtension().lastPathComponent).appendingPathExtension("receipt")
            guard !FileManager.default.fileExists(atPath: receipt.path),
                  let data = try? Data(contentsOf: file),
                  let mutation = try? decoder.decode(CatalogMutation.self, from: data),
                  mutation.schemaVersion == 1 else { continue }
            if mutation.actorID != mutationActorID {
                apply(mutation)
            }
            try? Data(Date().ISO8601Format().utf8).write(to: receipt, options: .atomic)
        }
    }

    private func apply(_ mutation: CatalogMutation) {
        switch mutation.operation {
        case .upsert:
            for record in mutation.records {
                if let index = library.firstIndex(where: { $0.id == record.id }) { library[index] = record }
                else if let index = libraryIdentityIndex[record.identityKey] { _ = mergeLibrary(at: index, from: record) }
                else { appendToLibrary(record) }
            }
        case .deleteIDs:
            let ids = Set(mutation.recordIDs)
            library.removeAll { ids.contains($0.id) }
            queue.removeAll { ids.contains($0.id) }
        case .deleteSource:
            guard let source = mutation.source else { return }
            library.removeAll { $0.source == source }
            queue.removeAll { $0.source == source }
        }
        rebuildIdentityIndexes()
        status = "Applied catalog changes from another Mac."
        save()
    }

    private func consumeServerCatalogInbox() {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let root = applicationSupport.appendingPathComponent("com.sowens.StockedMac", isDirectory: true)
        let inbox = root.appendingPathComponent("ServerCatalogInbox", isDirectory: true)
        let receipts = root.appendingPathComponent("ServerCatalogInboxReceipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
        let files = ((try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { file in
                guard file.pathExtension.lowercased() == "json" else { return false }
                return !FileManager.default.fileExists(atPath: receipts.appendingPathComponent(file.deletingPathExtension().lastPathComponent).appendingPathExtension("receipt").path)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for file in files.prefix(5) {
            guard let data = try? Data(contentsOf: file),
                  let batch = try? decoder.decode(ServerCatalogBatch.self, from: data),
                  batch.schemaVersion == 1, !batch.batchID.isEmpty else {
                serverBatchStatus = "Ignored invalid Server Mac catalog batch \(file.lastPathComponent)"
                continue
            }
            var added = 0, enriched = 0
            var queuedIDsToRemove = Set<UUID>()
            for var record in batch.records where record.source != .legacyRemoved && record.name.nilIfBlank != nil {
                record.state = .imported
                if let index = libraryIdentityIndex[record.identityKey] {
                    if mergeLibrary(at: index, from: record) { enriched += 1 }
                } else if let index = queueIdentityIndex[record.identityKey] {
                    var merged = queue[index]; _ = merged.mergeEnrichment(from: record)
                    merged.state = .imported
                    queuedIDsToRemove.insert(queue[index].id)
                    appendToLibrary(merged); added += 1
                } else {
                    appendToLibrary(record); added += 1
                }
            }
            if !queuedIDsToRemove.isEmpty {
                queue.removeAll { queuedIDsToRemove.contains($0.id) }
                rebuildQueueIdentityIndex()
            }
            let receipt = receipts.appendingPathComponent(batch.batchID).appendingPathExtension("receipt")
            do {
                try Data("\(Date().ISO8601Format()) added=\(added) enriched=\(enriched)\n".utf8).write(to: receipt, options: .atomic)
                serverImportedCount += added
                serverBatchStatus = "Server Mac: added \(added), enriched \(enriched) from \(batch.sourceName)"
                save()
            } catch {
                serverBatchStatus = "Could not acknowledge Server Mac catalog batch: \(error.localizedDescription)"
            }
        }
    }

    /// Runs one provider request at a time, imports successful partial results immediately,
    /// and persists after every step. A provider failure only cools that provider down; it
    /// never resets the global sweep or strands already-discovered data in a review queue.
    private func runBulkImport(runID: UUID) async {
        defer {
            requestQueryOverride = nil
            requestLocationOverride = nil
            if bulkRunID == runID {
                bulkTask = nil
                bulkRunID = nil
            }
        }
        while isBulkImportEnabled && !Task.isCancelled {
            requestLocationOverride = Self.storeRegions[bulkCursor.regionIndex % Self.storeRegions.count]
            let sources = orderedSources().filter { selectedSources.contains($0) }
            guard !sources.isEmpty else {
                bulkStatus = "Select at least one source to continue"
                try? await Task.sleep(for: .seconds(5))
                continue
            }

            let source = sources[bulkCursor.sourceIndex % sources.count]
            if let until = bulkCursor.cooldowns[source.rawValue], until > Date() {
                advanceBulkCursor(sourceCount: sources.count)
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            let seed = Self.bulkSeeds[bulkCursor.seedIndex % Self.bulkSeeds.count]
            requestQueryOverride = seed
            bulkStatus = "Importing \(source.rawValue) · \(seed) · page \(bulkCursor.page + 1)"

            do {
                let records = try await fetch(source: source, limit: 50, page: bulkCursor.page)
                bulkRequestCount += 1
                let merged = mergeDiscovered(records)
                let before = library.count
                importQueued(enrichAfterImport: false)
                bulkImportedCount += max(0, library.count - before)
                bulkStatus = "Added \(merged.added), enriched \(merged.enriched) · \(library.count) total"
                bulkCursor.consecutiveFailures[source.rawValue] = 0
                advanceBulkCursor(sourceCount: sources.count, received: records.count, source: source)
            } catch is CancellationError {
                break
            } catch MacServiceError.rateLimited(let retryAfter) {
                let delay = max(60, retryAfter ?? 300)
                bulkCursor.cooldowns[source.rawValue] = Date().addingTimeInterval(delay)
                bulkStatus = "\(source.rawValue) cooling down; continuing with other sources"
                advanceBulkCursor(sourceCount: sources.count)
            } catch {
                let failures = (bulkCursor.consecutiveFailures[source.rawValue] ?? 0) + 1
                bulkCursor.consecutiveFailures[source.rawValue] = failures
                let delay = min(3_600.0, pow(2, Double(min(failures, 8))) * 15)
                bulkCursor.cooldowns[source.rawValue] = Date().addingTimeInterval(delay)
                bulkStatus = "\(source.rawValue) deferred for \(Int(delay / 60)) min; continuing with other sources"
                advanceBulkCursor(sourceCount: sources.count)
            }

            requestQueryOverride = nil
            requestLocationOverride = nil
            save()
            try? await Task.sleep(for: .milliseconds(Self.delayMilliseconds(for: source)))
        }
    }

    private func advanceBulkCursor(sourceCount: Int, received: Int? = nil, source: CatalogSource? = nil) {
        let pagedSources: Set<CatalogSource> = [.openFoodFacts, .usda, .kroger, .rapidAPIGrocery, .fatSecret]
        if let received, let source, pagedSources.contains(source), received >= 20, bulkCursor.page < 49 {
            bulkCursor.page += 1
            return
        }
        bulkCursor.page = 0
        bulkCursor.sourceIndex += 1
        if bulkCursor.sourceIndex >= max(1, sourceCount) {
            bulkCursor.sourceIndex = 0
            bulkCursor.seedIndex = (bulkCursor.seedIndex + 1) % Self.bulkSeeds.count
            if bulkCursor.seedIndex == 0 {
                bulkCursor.regionIndex = (bulkCursor.regionIndex + 1) % Self.storeRegions.count
            }
        }
    }

    private static func delayMilliseconds(for source: CatalogSource) -> Int {
        switch source {
        case .openStreetMap: 1_200
        case .wikidataCommons, .openFoodFacts: 850
        case .usda: 450
        case .kroger, .fatSecret, .rapidAPIGrocery: 700
        case .stockedReference, .builtIn, .legacyRemoved: 100
        }
    }

    func discover() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        lastError = nil
        status = "Searching selected sources…"
        defer { isDiscovering = false; save() }
        var found: [CatalogRecord] = []
        var failures: [String] = []
        let perSource = max(10, resultLimit / max(1, selectedSources.count))

        for source in orderedSources() where selectedSources.contains(source) {
            do {
                found += try await fetch(source: source, limit: perSource, page: 0)
            } catch {
                failures.append("\(source.rawValue): \(error.localizedDescription)")
            }
        }

        let result = mergeDiscovered(found)
        if failures.isEmpty {
            status = "Queued \(result.added) new records and enriched \(result.enriched) existing records from \(selectedSources.count) sources."
        } else {
            lastError = failures.joined(separator: "\n")
            status = "Kept partial results: queued \(result.added), enriched \(result.enriched); \(failures.count) source(s) unavailable."
        }
    }

    func importQueued(limit: Int? = nil, enrichAfterImport: Bool = true) {
        let count = min(limit ?? queue.count, queue.count)
        guard count > 0 else { status = "Nothing is waiting to import."; return }
        var incoming = Array(queue.prefix(count))
        for index in incoming.indices { incoming[index].state = .imported; incoming[index].updatedAt = Date() }
        var added = 0
        var enriched = 0
        for record in incoming {
            if let index = libraryIdentityIndex[record.identityKey] {
                if mergeLibrary(at: index, from: record) { enriched += 1 }
            } else {
                appendToLibrary(record)
                added += 1
            }
        }
        queue.removeFirst(count)
        rebuildQueueIdentityIndex()
        status = "Imported \(added) records and enriched \(enriched) existing records; \(queue.count) remain queued."
        save()
        if enrichAfterImport {
            let importedIDs = incoming.map(\.id)
            Task { await enrichAllExisting(prioritizing: importedIDs) }
        }
    }

    func removeFromQueue(_ ids: Set<UUID>) {
        queue.removeAll { ids.contains($0.id) }
        rebuildQueueIdentityIndex()
        status = "Removed \(ids.count) queued records."
        save()
    }

    func deleteLibrary(_ ids: Set<UUID>) {
        library.removeAll { ids.contains($0.id) }
        rebuildLibraryIdentityIndex()
        status = "Deleted \(ids.count) catalog records."
        publishMutation(CatalogMutation(actorID: mutationActorID, operation: .deleteIDs, recordIDs: Array(ids)))
        save()
    }

    func deleteLibrary(source: CatalogSource) {
        let removed = library.filter { $0.source == source }.count
        library.removeAll { $0.source == source }
        queue.removeAll { $0.source == source }
        rebuildIdentityIndexes()
        status = "Deleted \(removed) records from \(source.rawValue)."
        publishMutation(CatalogMutation(actorID: mutationActorID, operation: .deleteSource, source: source))
        save()
    }

    func update(_ record: CatalogRecord) {
        if let index = queue.firstIndex(where: { $0.id == record.id }) { queue[index] = record }
        if let index = library.firstIndex(where: { $0.id == record.id }) { library[index] = record }
        rebuildIdentityIndexes()
        publishMutation(CatalogMutation(actorID: mutationActorID, operation: .upsert, records: [record]))
        save()
    }

    private func mergeDiscovered(_ records: [CatalogRecord]) -> (added: Int, enriched: Int) {
        var added = 0
        var enriched = 0
        for record in records {
            if let index = libraryIdentityIndex[record.identityKey] {
                if mergeLibrary(at: index, from: record) { enriched += 1 }
            } else if let index = queueIdentityIndex[record.identityKey] {
                if mergeQueue(at: index, from: record) { enriched += 1 }
            } else {
                appendToQueue(record)
                added += 1
            }
        }
        return (added, enriched)
    }

    private func appendToLibrary(_ record: CatalogRecord) {
        libraryIdentityIndex[record.identityKey] = library.count
        library.append(record)
    }

    private func appendToQueue(_ record: CatalogRecord) {
        queueIdentityIndex[record.identityKey] = queue.count
        queue.append(record)
    }

    @discardableResult
    private func mergeLibrary(at index: Int, from record: CatalogRecord) -> Bool {
        guard library.indices.contains(index) else { rebuildLibraryIdentityIndex(); return false }
        let oldKey = library[index].identityKey
        let changed = library[index].mergeEnrichment(from: record)
        if changed {
            if libraryIdentityIndex[oldKey] == index { libraryIdentityIndex.removeValue(forKey: oldKey) }
            libraryIdentityIndex[library[index].identityKey] = index
        }
        return changed
    }

    @discardableResult
    private func mergeQueue(at index: Int, from record: CatalogRecord) -> Bool {
        guard queue.indices.contains(index) else { rebuildQueueIdentityIndex(); return false }
        let oldKey = queue[index].identityKey
        let changed = queue[index].mergeEnrichment(from: record)
        if changed {
            if queueIdentityIndex[oldKey] == index { queueIdentityIndex.removeValue(forKey: oldKey) }
            queueIdentityIndex[queue[index].identityKey] = index
        }
        return changed
    }

    private func rebuildIdentityIndexes() {
        rebuildLibraryIdentityIndex()
        rebuildQueueIdentityIndex()
    }

    private func rebuildLibraryIdentityIndex() {
        libraryIdentityIndex.removeAll(keepingCapacity: true)
        for index in library.indices { libraryIdentityIndex[library[index].identityKey] = index }
    }

    private func rebuildQueueIdentityIndex() {
        queueIdentityIndex.removeAll(keepingCapacity: true)
        for index in queue.indices { queueIdentityIndex[queue[index].identityKey] = index }
    }

    /// Continuously walks the entire saved catalog through every applicable source.
    /// A persisted cursor guarantees large libraries advance instead of reprocessing
    /// the first page forever. Provider failures keep the current record and retry on
    /// the next cycle; partial enrichment is saved after each record.
    func enrichAllExisting(prioritizing ids: [UUID] = [], batchSize: Int = 20) async {
        guard !library.isEmpty else { return }
        let cursorKey = "catalog.enrichmentCursor.v2"
        let start = UserDefaults.standard.integer(forKey: cursorKey) % library.count
        let prioritized = ids.compactMap { id in library.firstIndex(where: { $0.id == id }) }
        let rotating = (0..<min(batchSize, library.count)).map { (start + $0) % library.count }
        var seen = Set<Int>()
        let indexes = (prioritized + rotating).filter { seen.insert($0).inserted }
        defer {
            requestQueryOverride = nil
            requestLocationOverride = nil
            UserDefaults.standard.set((start + rotating.count) % max(1, library.count), forKey: cursorKey)
            save()
        }

        for index in indexes where library.indices.contains(index) {
            let base = library[index]
            requestQueryOverride = base.name
            if base.kind == .store {
                requestLocationOverride = base.address ?? base.name
            } else if Self.isHEBRecord(base) {
                requestLocationOverride = "Texas"
            }
            var candidates: [CatalogRecord] = []
            for source in orderedSources() where source != .legacyRemoved {
                do { candidates += try await fetch(source: source, limit: 12) }
                catch { continue }
            }
            let matches = candidates.filter { Self.matches($0, base) }.sorted { $0.confidence > $1.confidence }
            for match in matches { _ = library[index].mergeEnrichment(from: match) }
            if library[index].aisle?.nilIfBlank == nil {
                library[index].aisle = GroceryAisleClassifier.aisle(for: library[index].category ?? library[index].name)
            }
            save()
            try? await Task.sleep(for: .milliseconds(250))
        }
        rebuildLibraryIdentityIndex()
    }

    func enrichInventoryItem(id: UUID, store: MacKitchenStore) async {
        guard let item = store.inventory.first(where: { $0.id == id }) else { return }
        defer { requestQueryOverride = nil; requestLocationOverride = nil }
        requestQueryOverride = [item.brand, item.name].compactMap { $0?.nilIfBlank }.joined(separator: " ")
        if [item.brand, item.name].compactMap({ $0 }).contains(where: Self.isHEBText) {
            requestLocationOverride = "Texas"
        }
        var candidates: [CatalogRecord] = []
        for source in orderedSources() where source != .legacyRemoved && source != .openStreetMap {
            do { candidates += try await fetch(source: source, limit: 12) }
            catch { continue }
        }
        let base = CatalogRecord(kind: .product, name: item.name, brand: item.brand,
                                 barcode: item.barcode, source: .stockedReference, state: .imported)
        let matches = candidates.filter { Self.matches($0, base) }.sorted { $0.confidence > $1.confidence }
        guard !matches.isEmpty else { return }
        var enriched = base
        for match in matches { _ = enriched.mergeEnrichment(from: match) }
        store.updateInventory(id: id, requestEnrichment: false) { current in
            if current.brand?.nilIfBlank == nil { current.brand = enriched.brand }
            if current.barcode?.nilIfBlank == nil { current.barcode = enriched.barcode }
            if current.price == nil { current.price = enriched.promotionalPrice ?? enriched.regularPrice }
            if current.storePurchasedAt?.nilIfBlank == nil { current.storePurchasedAt = enriched.store }
        }
        if let index = libraryIdentityIndex[enriched.identityKey] {
            _ = mergeLibrary(at: index, from: enriched)
        } else {
            appendToLibrary(enriched)
        }
        save()
    }

    func enrichInventoryBatch(store: MacKitchenStore, limit: Int = 20) async {
        guard !store.inventory.isEmpty else { return }
        let key = "catalog.inventoryEnrichmentCursor.v2"
        let start = UserDefaults.standard.integer(forKey: key) % store.inventory.count
        let ids = (0..<min(limit, store.inventory.count)).map { store.inventory[(start + $0) % store.inventory.count].id }
        UserDefaults.standard.set((start + ids.count) % store.inventory.count, forKey: key)
        for id in ids { await enrichInventoryItem(id: id, store: store) }
    }

    private func fetch(source: CatalogSource, limit: Int, page: Int = 0) async throws -> [CatalogRecord] {
        switch source {
        case .kroger: return try await fetchKroger(limit: limit, page: page)
        case .openFoodFacts: return try await fetchOpenFacts(.openFoodFacts, host: "world.openfoodfacts.org", limit: limit, page: page)
        case .usda: return try await fetchUSDA(limit: limit, page: page)
        case .openStreetMap: return try await fetchStores(limit: min(limit, 50))
        case .wikidataCommons: return try await fetchWikidataCommons(limit: min(limit, 50))
        case .rapidAPIGrocery: return try await fetchRapidAPIGrocery(limit: limit, page: page)
        case .fatSecret: return try await fetchFatSecret(limit: limit, page: page)
        case .stockedReference: return CatalogReferenceData.records(matching: requestQuery, limit: limit)
        case .builtIn: return builtInAisles()
        case .legacyRemoved: return []
        }
    }

    /// H-E-B coverage is most useful in Texas. When a Texas ZIP/region is active, start
    /// with the local H-E-B reference and the providers most likely to return H-E-B
    /// identities, stores, images and branded foods. Other providers remain fallbacks.
    private func orderedSources() -> [CatalogSource] {
        guard isTexasRequest else { return CatalogSource.allCases }
        return [.stockedReference, .openStreetMap, .openFoodFacts, .usda, .fatSecret,
                .wikidataCommons, .builtIn, .rapidAPIGrocery, .kroger]
    }

    private func providerQuery(for source: CatalogSource) -> String {
        let base = requestQuery.nilIfBlank ?? "grocery"
        guard isTexasRequest else { return base }
        switch source {
        case .openFoodFacts, .usda, .fatSecret, .wikidataCommons:
            return Self.isHEBText(base) ? base : "H-E-B \(base)"
        default:
            return base
        }
    }

    private static func matches(_ candidate: CatalogRecord, _ base: CatalogRecord) -> Bool {
        if let barcode = base.barcode?.nilIfBlank, candidate.barcode?.nilIfBlank == barcode { return true }
        guard candidate.kind == base.kind else { return false }
        let lhs = candidate.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        let rhs = base.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        return lhs == rhs || (min(lhs.count, rhs.count) >= 5 && (lhs.contains(rhs) || rhs.contains(lhs)))
    }

    private func fetchOpenFacts(_ source: CatalogSource, host: String, limit: Int, page: Int) async throws -> [CatalogRecord] {
        var components = URLComponents(string: "https://\(host)/cgi/search.pl")!
        components.queryItems = [
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "search_terms", value: providerQuery(for: source)),
            .init(name: "page", value: String(page + 1)),
            .init(name: "page_size", value: String(min(limit, 100))),
            .init(name: "fields", value: "code,product_name,brands,categories,stores,url,image_front_url,image_url")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("StockedMac/\(MacBuildConfig.version) (\(MacBuildConfig.supportEmail))", forHTTPHeaderField: "User-Agent")
        let response: OFFResponse = try await decode(request)
        return response.products.flatMap { product -> [CatalogRecord] in
            let category = product.categories?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            let aisle = GroceryAisleClassifier.aisle(for: category ?? product.productName ?? "")
            let brands = product.brands?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
            guard let name = product.productName?.nilIfBlank else { return [] }
            let image = originalOpenFactsImage(product.imageFrontURL ?? product.imageURL)
            let preview = product.imageFrontURL ?? product.imageURL
            var rows = [CatalogRecord(kind: .product, name: name, brand: brands.first, category: category,
                                      aisle: aisle, store: product.stores, barcode: product.code,
                                      source: source, sourceURL: product.url, imageURL: image, imagePreviewURL: preview,
                                      imageSourceURL: product.url, imageAttribution: "Open Facts · CC BY-SA",
                                      confidence: 0.82)]
            rows += brands.map { CatalogRecord(kind: .brand, name: $0, category: category, aisle: aisle,
                                               source: source, sourceURL: product.url, imageURL: image, imagePreviewURL: preview,
                                               imageSourceURL: product.url, imageAttribution: "Open Facts · CC BY-SA",
                                               confidence: 0.78) }
            return rows
        }
    }

    private func originalOpenFactsImage(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else { return nil }
        return raw.replacingOccurrences(of: ".400.jpg", with: ".full.jpg")
            .replacingOccurrences(of: ".200.jpg", with: ".full.jpg")
    }

    private func fetchUSDA(limit: Int, page: Int) async throws -> [CatalogRecord] {
        var request = URLRequest(url: URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(usdaAPIKey.nilIfBlank ?? "DEMO_KEY")")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": providerQuery(for: .usda), "dataType": ["Branded"], "pageSize": min(limit, 100), "pageNumber": page + 1])
        let response: USDAResponse = try await decode(request)
        return response.foods.flatMap { food -> [CatalogRecord] in
            guard let name = food.description.nilIfBlank else { return [] }
            let category = food.foodCategory
            let brand = food.brandOwner ?? food.brandName
            var rows = [CatalogRecord(kind: .product, name: name, brand: brand,
                                 category: category, aisle: GroceryAisleClassifier.aisle(for: category ?? name),
                                 barcode: food.gtinUpc, source: .usda,
                                 sourceURL: "https://fdc.nal.usda.gov/fdc-app.html#/food-details/\(food.fdcId)/nutrients",
                                 confidence: 0.9)]
            if let brand = brand?.nilIfBlank {
                rows.append(CatalogRecord(kind: .brand, name: brand, category: category,
                                          aisle: GroceryAisleClassifier.aisle(for: category ?? name),
                                          source: .usda,
                                          sourceURL: "https://fdc.nal.usda.gov/fdc-app.html#/food-details/\(food.fdcId)/nutrients",
                                          confidence: 0.86))
            }
            return rows
        }
    }

    private func fetchWikidataCommons(limit: Int) async throws -> [CatalogRecord] {
        guard requestQuery.nilIfBlank != nil else {
            throw MacServiceError.invalidRequest("Enter a brand or store name for Wikidata + Commons discovery.")
        }
        let term = providerQuery(for: .wikidataCommons)
        var searchComponents = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        searchComponents.queryItems = [
            .init(name: "action", value: "wbsearchentities"), .init(name: "format", value: "json"),
            .init(name: "language", value: "en"), .init(name: "type", value: "item"),
            .init(name: "search", value: term), .init(name: "limit", value: String(min(limit, 50)))
        ]
        var searchRequest = URLRequest(url: searchComponents.url!)
        searchRequest.setValue("StockedMac/\(MacBuildConfig.version) (\(MacBuildConfig.supportEmail))", forHTTPHeaderField: "User-Agent")
        let search: WikidataSearchResponse = try await decode(searchRequest)
        guard !search.search.isEmpty else { return [] }

        var entityComponents = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        entityComponents.queryItems = [
            .init(name: "action", value: "wbgetentities"), .init(name: "format", value: "json"),
            .init(name: "ids", value: search.search.map(\.id).joined(separator: "|")),
            .init(name: "props", value: "claims")
        ]
        var entityRequest = URLRequest(url: entityComponents.url!)
        entityRequest.setValue("StockedMac/\(MacBuildConfig.version) (\(MacBuildConfig.supportEmail))", forHTTPHeaderField: "User-Agent")
        let entities: WikidataEntitiesResponse = try await decode(entityRequest)

        return search.search.compactMap { item in
            let description = item.description?.lowercased() ?? ""
            let commercialTerms = ["food brand", "food company", "food manufacturer", "beverage company", "grocery store", "supermarket", "hypermarket", "food producer"]
            guard commercialTerms.contains(where: description.contains) else { return nil }
            let isStore = ["store", "supermarket", "grocery", "retail", "hypermarket"].contains(where: description.contains)
            let entity = entities.entities[item.id]
            let imageName = entity?.stringClaim("P18")
            let officialURL = entity?.stringClaim("P856")
            let imageURL = imageName.flatMap(Self.commonsOriginalURL)
            return CatalogRecord(kind: isStore ? .store : .brand, name: item.label,
                                 store: isStore ? item.label : nil, source: .wikidataCommons,
                                 sourceURL: officialURL ?? item.conceptURI, imageURL: imageURL,
                                 imageSourceURL: imageName.map { "https://commons.wikimedia.org/wiki/File:\($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0)" },
                                 imageAttribution: imageName == nil ? nil : "Wikimedia Commons · see source for license and creator",
                                 confidence: 0.74)
        }
    }

    private static func commonsOriginalURL(fileName: String) -> String? {
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        return "https://commons.wikimedia.org/wiki/Special:Redirect/file/\(encoded)"
    }

    private func fetchStores(limit: Int) async throws -> [CatalogRecord] {
        let place = requestLocation.nilIfBlank ?? requestQuery.nilIfBlank
        guard let place else { throw MacServiceError.invalidRequest("Enter a city, ZIP code, or region for store discovery.") }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        let storeQuery = isTexasRequest ? "H-E-B supermarket \(place)" : "supermarket \(place)"
        components.queryItems = [.init(name: "q", value: storeQuery), .init(name: "format", value: "jsonv2"),
                                 .init(name: "addressdetails", value: "1"), .init(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        request.setValue("StockedMac/\(MacBuildConfig.version) (\(MacBuildConfig.supportEmail))", forHTTPHeaderField: "User-Agent")
        let places: [OSMPlace] = try await decode(request)
        return places.map { place in
            CatalogRecord(kind: .store, name: place.name ?? place.displayName.components(separatedBy: ",").first ?? "Grocery store",
                          store: place.name, address: place.displayName, latitude: Double(place.lat), longitude: Double(place.lon),
                          source: .openStreetMap, sourceURL: "https://www.openstreetmap.org/\(place.osmType)/\(place.osmId)", confidence: 0.76)
        }
    }

    private func fetchKroger(limit: Int, page: Int) async throws -> [CatalogRecord] {
        guard MacWorkerClient.isConfigured else {
            throw MacServiceError.notConfigured("The Stocked Worker key")
        }
        let zip = Self.firstZIP(in: requestLocation)
        guard zip != nil || requestQuery.nilIfBlank != nil else {
            throw MacServiceError.invalidRequest("Enter a five-digit ZIP code, product, or brand for Kroger discovery.")
        }

        var rows: [CatalogRecord] = []
        var storeLocationID: String?
        var storeName: String?
        if let zip {
            let data = try await MacWorkerClient.getData(
                path: "/retail/kroger/locations",
                query: ["zipCode": zip, "radius": "25", "limit": String(min(50, limit))])
            let envelope = try JSONDecoder().decode(KrogerLocationEnvelope.self, from: data)
            storeLocationID = envelope.locations.first?.locationId
            storeName = envelope.locations.first?.name
            rows += envelope.locations.map { place in
                CatalogRecord(kind: .store, name: place.name, store: place.name,
                              address: place.address.display, latitude: place.latitude, longitude: place.longitude,
                              source: .kroger,
                              sourceURL: "https://www.kroger.com/stores/grocery/near-me",
                              externalID: place.locationId, retailerLocationID: place.locationId,
                              confidence: 0.96)
            }
        }

        if let term = requestQuery.nilIfBlank {
            var request = ["term": term, "limit": String(min(50, limit)), "start": String(page * min(50, limit) + 1)]
            if let storeLocationID { request["locationId"] = storeLocationID }
            let data = try await MacWorkerClient.getData(path: "/retail/kroger/products", query: request)
            let envelope = try JSONDecoder().decode(KrogerProductEnvelope.self, from: data)
            for product in envelope.products where Self.isGroceryRelevant(name: product.name, categories: product.categories) {
                let category = product.categories.first
                let aisle = product.aisleLocations.first?.display
                    ?? GroceryAisleClassifier.aisle(for: category ?? product.name)
                let record = CatalogRecord(
                    kind: .product, name: product.name, brand: product.brand, category: category,
                    aisle: aisle, store: storeName, barcode: product.upc, source: .kroger,
                    sourceURL: product.productURL, imageURL: product.imageURL,
                    imagePreviewURL: product.imageURL,
                    imageSourceURL: product.productURL,
                    imageAttribution: "Kroger Product API",
                    externalID: product.productId, retailerLocationID: product.locationId,
                    regularPrice: product.regularPrice, promotionalPrice: product.promoPrice,
                    inventoryLevel: product.inventoryLevel, confidence: 0.96)
                rows.append(record)
                if let brand = product.brand?.nilIfBlank {
                    rows.append(CatalogRecord(kind: .brand, name: brand, category: category, aisle: aisle,
                                              source: .kroger, sourceURL: product.productURL,
                                              imageURL: product.imageURL, imagePreviewURL: product.imageURL,
                                              imageSourceURL: product.productURL,
                                              imageAttribution: "Kroger Product API", confidence: 0.9))
                }
            }
        }
        return rows
    }

    private func fetchRapidAPIGrocery(limit: Int, page: Int) async throws -> [CatalogRecord] {
        guard let term = requestQuery.nilIfBlank else {
            throw MacServiceError.invalidRequest("Enter a grocery product or brand for RapidAPI discovery.")
        }
        var rows: [CatalogRecord] = []
        for store in ["walmart", "amazon"] {
            let data = try await MacWorkerClient.getData(
                path: "/retail/rapidapi/products",
                query: ["query": term, "store": store, "page": String(page + 1)])
            let envelope = try JSONDecoder().decode(RapidProductEnvelope.self, from: data)
            for product in envelope.products.prefix(max(1, limit / 2))
                where Self.isGroceryRelevant(name: product.name, categories: product.categories) {
                let category = product.categories.first
                let aisle = GroceryAisleClassifier.aisle(for: category ?? product.name)
                rows.append(CatalogRecord(kind: .product, name: product.name, brand: product.brand,
                                          category: category, aisle: aisle, store: product.store,
                                          barcode: product.upc, source: .rapidAPIGrocery,
                                          sourceURL: product.productURL, imageURL: product.imageURL,
                                          imagePreviewURL: product.imageURL,
                                          imageSourceURL: product.productURL,
                                          imageAttribution: "RapidAPI grocery provider",
                                          externalID: product.productId,
                                          regularPrice: product.regularPrice, confidence: 0.7))
            }
        }
        return rows
    }

    private func fetchFatSecret(limit: Int, page: Int) async throws -> [CatalogRecord] {
        guard requestQuery.nilIfBlank != nil else {
            throw MacServiceError.invalidRequest("Enter a grocery food or brand for FatSecret discovery.")
        }
        let term = providerQuery(for: .fatSecret)
        let data = try await MacWorkerClient.getData(path: "/retail/fatsecret/foods",
                                                     query: ["query": term, "limit": String(min(50, limit)), "page": String(page)])
        let envelope = try JSONDecoder().decode(RapidProductEnvelope.self, from: data)
        var rows: [CatalogRecord] = []
        for product in envelope.products where Self.isGroceryRelevant(name: product.name, categories: product.categories) {
            let category = product.categories.first
            let aisle = GroceryAisleClassifier.aisle(for: category ?? product.name)
            rows.append(CatalogRecord(kind: .product, name: product.name, brand: product.brand, category: category,
                                      aisle: aisle, source: .fatSecret, sourceURL: product.productURL,
                                      imageURL: product.imageURL, imagePreviewURL: product.imageURL,
                                      imageSourceURL: product.productURL, imageAttribution: "FatSecret Platform API",
                                      externalID: product.productId, confidence: 0.88))
            if let brand = product.brand?.nilIfBlank {
                rows.append(CatalogRecord(kind: .brand, name: brand, category: category, aisle: aisle,
                                          source: .fatSecret, sourceURL: product.productURL, confidence: 0.84))
            }
        }
        return rows
    }

    private static func firstZIP(in value: String) -> String? {
        guard let match = value.range(of: #"\b\d{5}\b"#, options: .regularExpression) else { return nil }
        return String(value[match])
    }

    private static func isTexasLocation(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "tx" || normalized.contains("texas") { return true }
        guard let zip = firstZIP(in: normalized), let number = Int(zip) else { return false }
        return (75001...79999).contains(number)
            || (73301...73399).contains(number)
            || (88510...88589).contains(number)
    }

    private static func isHEBText(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized == "heb" || normalized.contains("h-e-b") || normalized.contains("h e b")
            || normalized.contains("central market") || normalized.contains("mi tienda")
            || normalized.contains("joe v's") || normalized.contains("joe vs")
    }

    private static func isHEBRecord(_ record: CatalogRecord) -> Bool {
        [record.name, record.brand, record.store].compactMap { $0 }.contains(where: isHEBText)
    }

    private static func isGroceryRelevant(name: String, categories: [String]) -> Bool {
        let value = ([name] + categories).joined(separator: " ").lowercased()
        let excluded = ["pet food", "dog food", "cat food", "beauty", "cosmetic", "makeup",
                        "skin care", "hair care", "shampoo", "deodorant", "fragrance",
                        "toy", "electronics", "automotive", "clothing", "pharmacy"]
        return !excluded.contains(where: value.contains)
    }

    private func builtInAisles() -> [CatalogRecord] {
        ["Produce", "Bakery", "Dairy & Eggs", "Meat & Seafood", "Frozen", "Canned & Jarred",
         "Pasta, Rice & Grains", "Baking", "Snacks", "Beverages", "Condiments & Spices",
         "International", "Household", "Pantry"].map {
            CatalogRecord(kind: .aisle, name: $0, category: $0, aisle: $0, source: .builtIn, confidence: 1)
        }
    }

    private func decode<T: Decodable>(_ url: URL) async throws -> T { try await decode(URLRequest(url: url)) }
    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw MacServiceError.rateLimited(
                retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        }
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MacServiceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL), let snapshot = try? JSONDecoder().decode(CatalogSnapshot.self, from: data) else { return }
        library = snapshot.library; queue = snapshot.queue
        library.removeAll { $0.source == .legacyRemoved }
        queue.removeAll { $0.source == .legacyRemoved }
        rebuildIdentityIndexes()
        usdaAPIKey = UserDefaults.standard.string(forKey: "stocked.usdaAPIKey") ?? ""
        if UserDefaults.standard.object(forKey: "catalog.bulk.enabled.v1") == nil {
            isBulkImportEnabled = true
        } else {
            isBulkImportEnabled = UserDefaults.standard.bool(forKey: "catalog.bulk.enabled.v1")
        }
        isBulkImportPaused = UserDefaults.standard.bool(forKey: "catalog.bulk.paused.v1")
        if isBulkImportPaused { isBulkImportEnabled = false }
        if let data = UserDefaults.standard.data(forKey: "catalog.bulk.cursor.v1"),
           let cursor = try? JSONDecoder().decode(BulkCursor.self, from: data) { bulkCursor = cursor }
    }

    private func save() {
        pendingSaveTask?.cancel()
        saveGeneration &+= 1
        let generation = saveGeneration
        let snapshot = CatalogSnapshot(library: library, queue: queue)
        let destination = saveURL
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await snapshotWriter.write(snapshot, to: destination)
            if saveGeneration == generation { pendingSaveTask = nil }
        }
        persistSmallSettings()
        scheduleWorkerPublish()
    }

    /// Used at pause/stop boundaries where the resumable cursor must be durable before
    /// returning. Ordinary mutations use the coalesced writer above.
    private func saveNow() {
        pendingSaveTask?.cancel()
        saveGeneration &+= 1
        pendingSaveTask = nil
        try? JSONEncoder().encode(CatalogSnapshot(library: library, queue: queue)).write(to: saveURL, options: .atomic)
        persistSmallSettings()
    }

    private func persistSmallSettings() {
        UserDefaults.standard.set(usdaAPIKey, forKey: "stocked.usdaAPIKey")
        UserDefaults.standard.set(isBulkImportEnabled, forKey: "catalog.bulk.enabled.v1")
        UserDefaults.standard.set(isBulkImportPaused, forKey: "catalog.bulk.paused.v1")
        UserDefaults.standard.set(try? JSONEncoder().encode(bulkCursor), forKey: "catalog.bulk.cursor.v1")
    }

    private struct BulkCursor: Codable {
        var sourceIndex = 0
        var seedIndex = 0
        var regionIndex = 0
        var page = 0
        var cooldowns: [String: Date] = [:]
        var consecutiveFailures: [String: Int] = [:]
    }
    private struct KrogerLocationEnvelope: Decodable { var locations: [KrogerLocation] }
    private struct KrogerLocation: Decodable {
        var locationId: String; var name: String; var address: RetailAddress
        var latitude: Double?; var longitude: Double?
    }
    private struct RetailAddress: Decodable {
        var line1: String?; var line2: String?; var city: String?; var state: String?; var zipCode: String?
        var display: String {
            [[line1, line2].compactMap { $0 }.joined(separator: " "),
             [city, state].compactMap { $0 }.joined(separator: ", "), zipCode]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    private func scheduleWorkerPublish() {
        guard MacWorkerClient.isConfigured else { return }
        pendingWorkerPublishTask?.cancel()
        pendingWorkerPublishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await self?.publishCatalogToWorker()
        }
    }

    private func publishCatalogToWorker() async {
        let rows = library
        let pageSize = 500
        let totalPages = max(1, Int(ceil(Double(rows.count) / Double(pageSize))))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        for page in 0..<totalPages {
            guard !Task.isCancelled else { return }
            let start = page * pageSize, end = min(rows.count, start + pageSize)
            let pageRows = start < end ? Array(rows[start..<end]) : []
            struct Upload: Encodable { let page: Int; let totalPages: Int; let totalRecords: Int; let records: [CatalogRecord] }
            guard let body = try? encoder.encode(Upload(page: page, totalPages: totalPages, totalRecords: rows.count, records: pageRows)) else { return }
            do { _ = try await MacWorkerClient.postData(path: "/retail/catalog", body: body, timeout: 45) }
            catch { serverBatchStatus = "Catalog sync deferred: \(error.localizedDescription)"; return }
        }
        serverBatchStatus = "Shared \(rows.count) catalog records with Stocked iOS"
    }
    private struct KrogerProductEnvelope: Decodable { var products: [RetailProduct] }
    private struct RapidProductEnvelope: Decodable { var products: [RetailProduct] }
    private struct RetailProduct: Decodable {
        var productId: String?; var upc: String?; var name: String; var brand: String?
        var categories: [String]; var regularPrice: Double?; var promoPrice: Double?
        var inventoryLevel: String?; var aisleLocations: [RetailAisle]
        var locationId: String?; var imageURL: String?; var productURL: String?; var store: String?
    }
    private struct RetailAisle: Decodable {
        var description: String?; var number: String?; var side: String?; var shelfNumber: String?
        var display: String? {
            let values = [number.map { "Aisle \($0)" }, description, side.map { "Side \($0)" },
                          shelfNumber.map { "Shelf \($0)" }].compactMap { $0 }
            return values.isEmpty ? nil : values.joined(separator: " · ")
        }
    }
    private struct OFFResponse: Decodable { var products: [OFFProduct] }
    private struct OFFProduct: Decodable {
        var code: String?; var productName: String?; var brands: String?; var categories: String?; var stores: String?; var url: String?
        var imageFrontURL: String?; var imageURL: String?
        enum CodingKeys: String, CodingKey {
            case code, brands, categories, stores, url
            case productName = "product_name"; case imageFrontURL = "image_front_url"; case imageURL = "image_url"
        }
    }
    private struct USDAResponse: Decodable { var foods: [USDAFood] }
    private struct USDAFood: Decodable {
        var fdcId: Int; var description: String; var brandOwner: String?; var brandName: String?; var foodCategory: String?; var gtinUpc: String?
    }
    private struct OSMPlace: Decodable {
        var osmType: String; var osmId: Int; var lat: String; var lon: String; var displayName: String; var name: String?
        enum CodingKeys: String, CodingKey { case lat, lon, name; case osmType = "osm_type"; case osmId = "osm_id"; case displayName = "display_name" }
    }
    private struct WikidataSearchResponse: Decodable { var search: [WikidataSearchItem] }
    private struct WikidataSearchItem: Decodable {
        var id: String; var label: String; var description: String?; var conceptURI: String?
        enum CodingKeys: String, CodingKey { case id, label, description; case conceptURI = "concepturi" }
    }
    private struct WikidataEntitiesResponse: Decodable { var entities: [String: WikidataEntity] }
    private struct WikidataEntity: Decodable {
        var claims: [String: [WikidataClaim]]?
        func stringClaim(_ property: String) -> String? {
            claims?[property]?.first?.mainsnak.datavalue?.value
        }
    }
    private struct WikidataClaim: Decodable { var mainsnak: WikidataSnak }
    private struct WikidataSnak: Decodable { var datavalue: WikidataDataValue? }
    private struct WikidataDataValue: Decodable {
        var value: String?
        enum CodingKeys: String, CodingKey { case value }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try? container.decode(String.self, forKey: .value)
        }
    }
}
