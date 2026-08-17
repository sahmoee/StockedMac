import Foundation
import Observation

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
    case builtIn = "Stocked Aisle Taxonomy"

    var id: String { rawValue }
    var detail: String {
        switch self {
        case .openFoodFacts: "Open worldwide products, barcodes, brands, stores and categories"
        case .usda: "U.S. Global Branded Foods; a free data.gov key is recommended"
        case .openStreetMap: "Nearby grocery stores and addresses by city, ZIP code or region"
        case .builtIn: "Offline category-to-aisle rules used to normalize every source"
        }
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
    var confidence: Double = 0.8
    var state: CatalogImportState = .queued
    var updatedAt = Date()

    var identityKey: String {
        [kind.rawValue, name, brand ?? "", store ?? "", barcode ?? "", address ?? ""]
            .joined(separator: "|").foldedCatalogKey
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
            ("Health & Beauty", ["health", "beauty", "vitamin", "supplement", "personal care"]),
            ("Household", ["household", "cleaner", "paper", "laundry", "trash"]),
            ("Pet", ["pet", "dog", "cat"])
        ]
        return rules.first(where: { rule in rule.1.contains(where: value.contains) })?.0 ?? "Pantry"
    }
}

@MainActor @Observable
final class CatalogModel {
    var library: [CatalogRecord] = []
    var queue: [CatalogRecord] = []
    var selectedSources: Set<CatalogSource> = [.openFoodFacts, .builtIn]
    var query = ""
    var location = ""
    var resultLimit = 100
    var isDiscovering = false
    var status = "Ready"
    var lastError: String?
    var usdaAPIKey = ""

    private let session: URLSession
    private let saveURL: URL

    init(session: URLSession = .shared) {
        self.session = session
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("StockedMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        saveURL = root.appendingPathComponent("brand-store-catalog.json")
        load()
    }

    func discover() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        lastError = nil
        status = "Searching selected sources…"
        defer { isDiscovering = false; save() }
        do {
            var found: [CatalogRecord] = []
            let perSource = max(10, resultLimit / max(1, selectedSources.count))
            if selectedSources.contains(.openFoodFacts) {
                found += try await fetchOpenFoodFacts(limit: perSource)
            }
            if selectedSources.contains(.usda) {
                found += try await fetchUSDA(limit: perSource)
            }
            if selectedSources.contains(.openStreetMap) {
                found += try await fetchStores(limit: min(perSource, 50))
            }
            if selectedSources.contains(.builtIn) {
                found += builtInAisles()
            }
            let existing = Set(library.map(\.identityKey)).union(queue.map(\.identityKey))
            var seen = existing
            let unique = found.filter { seen.insert($0.identityKey).inserted }
            queue.append(contentsOf: unique)
            status = unique.isEmpty ? "No new records found; duplicates were skipped." : "Queued \(unique.count) new records from \(selectedSources.count) sources."
        } catch {
            lastError = error.localizedDescription
            status = "Discovery stopped safely. Existing queue was preserved."
        }
    }

    func importQueued(limit: Int? = nil) {
        let count = min(limit ?? queue.count, queue.count)
        guard count > 0 else { status = "Nothing is waiting to import."; return }
        var incoming = Array(queue.prefix(count))
        for index in incoming.indices { incoming[index].state = .imported; incoming[index].updatedAt = Date() }
        let existing = Set(library.map(\.identityKey))
        library.append(contentsOf: incoming.filter { !existing.contains($0.identityKey) })
        queue.removeFirst(count)
        status = "Imported \(incoming.count) records; \(queue.count) remain queued."
        save()
    }

    func removeFromQueue(_ ids: Set<UUID>) {
        queue.removeAll { ids.contains($0.id) }
        status = "Removed \(ids.count) queued records."
        save()
    }

    func deleteLibrary(_ ids: Set<UUID>) {
        library.removeAll { ids.contains($0.id) }
        status = "Deleted \(ids.count) catalog records."
        save()
    }

    func update(_ record: CatalogRecord) {
        if let index = queue.firstIndex(where: { $0.id == record.id }) { queue[index] = record }
        if let index = library.firstIndex(where: { $0.id == record.id }) { library[index] = record }
        save()
    }

    private func fetchOpenFoodFacts(limit: Int) async throws -> [CatalogRecord] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "search_terms", value: query.nilIfBlank ?? "grocery"),
            .init(name: "page_size", value: String(min(limit, 100))),
            .init(name: "fields", value: "code,product_name,brands,categories,stores,url")
        ]
        let response: OFFResponse = try await decode(components.url!)
        return response.products.flatMap { product -> [CatalogRecord] in
            let category = product.categories?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
            let aisle = GroceryAisleClassifier.aisle(for: category ?? product.productName ?? "")
            let brands = product.brands?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
            guard let name = product.productName?.nilIfBlank else { return [] }
            var rows = [CatalogRecord(kind: .product, name: name, brand: brands.first, category: category,
                                      aisle: aisle, store: product.stores, barcode: product.code,
                                      source: .openFoodFacts, sourceURL: product.url, confidence: 0.82)]
            rows += brands.map { CatalogRecord(kind: .brand, name: $0, category: category, aisle: aisle,
                                               source: .openFoodFacts, sourceURL: product.url, confidence: 0.78) }
            return rows
        }
    }

    private func fetchUSDA(limit: Int) async throws -> [CatalogRecord] {
        var request = URLRequest(url: URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(usdaAPIKey.nilIfBlank ?? "DEMO_KEY")")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query.nilIfBlank ?? "grocery", "dataType": ["Branded"], "pageSize": min(limit, 100)])
        let response: USDAResponse = try await decode(request)
        return response.foods.compactMap { food in
            guard let name = food.description.nilIfBlank else { return nil }
            let category = food.foodCategory
            return CatalogRecord(kind: .product, name: name, brand: food.brandOwner ?? food.brandName,
                                 category: category, aisle: GroceryAisleClassifier.aisle(for: category ?? name),
                                 barcode: food.gtinUpc, source: .usda,
                                 sourceURL: "https://fdc.nal.usda.gov/fdc-app.html#/food-details/\(food.fdcId)/nutrients",
                                 confidence: 0.9)
        }
    }

    private func fetchStores(limit: Int) async throws -> [CatalogRecord] {
        let place = location.nilIfBlank ?? query.nilIfBlank
        guard let place else { throw MacServiceError.invalidRequest("Enter a city, ZIP code, or region for store discovery.") }
        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        components.queryItems = [.init(name: "q", value: "supermarket \(place)"), .init(name: "format", value: "jsonv2"),
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

    private func builtInAisles() -> [CatalogRecord] {
        ["Produce", "Bakery", "Dairy & Eggs", "Meat & Seafood", "Frozen", "Canned & Jarred",
         "Pasta, Rice & Grains", "Baking", "Snacks", "Beverages", "Condiments & Spices",
         "International", "Health & Beauty", "Household", "Pet", "Pantry"].map {
            CatalogRecord(kind: .aisle, name: $0, category: $0, aisle: $0, source: .builtIn, confidence: 1)
        }
    }

    private func decode<T: Decodable>(_ url: URL) async throws -> T { try await decode(URLRequest(url: url)) }
    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw MacServiceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0, nil)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL), let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        library = snapshot.library; queue = snapshot.queue
        usdaAPIKey = UserDefaults.standard.string(forKey: "stocked.usdaAPIKey") ?? ""
    }

    private func save() {
        try? JSONEncoder().encode(Snapshot(library: library, queue: queue)).write(to: saveURL, options: .atomic)
        UserDefaults.standard.set(usdaAPIKey, forKey: "stocked.usdaAPIKey")
    }

    private struct Snapshot: Codable { var library: [CatalogRecord]; var queue: [CatalogRecord] }
    private struct OFFResponse: Decodable { var products: [OFFProduct] }
    private struct OFFProduct: Decodable {
        var code: String?; var productName: String?; var brands: String?; var categories: String?; var stores: String?; var url: String?
        enum CodingKeys: String, CodingKey { case code, brands, categories, stores, url; case productName = "product_name" }
    }
    private struct USDAResponse: Decodable { var foods: [USDAFood] }
    private struct USDAFood: Decodable {
        var fdcId: Int; var description: String; var brandOwner: String?; var brandName: String?; var foodCategory: String?; var gtinUpc: String?
    }
    private struct OSMPlace: Decodable {
        var osmType: String; var osmId: Int; var lat: String; var lon: String; var displayName: String; var name: String?
        enum CodingKeys: String, CodingKey { case lat, lon, name; case osmType = "osm_type"; case osmId = "osm_id"; case displayName = "display_name" }
    }
}
