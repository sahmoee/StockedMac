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
    case wikidataCommons = "Wikidata + Wikimedia Commons"
    case stockedReference = "Stocked Brand & Store Reference"
    case builtIn = "Stocked Aisle Taxonomy"
    case legacyRemoved = "Removed non-grocery source"

    static let allCases: [CatalogSource] = [
        .openFoodFacts, .usda, .openStreetMap, .wikidataCommons, .stockedReference, .builtIn
    ]

    var id: String { rawValue }
    var detail: String {
        switch self {
        case .openFoodFacts: "Worldwide grocery products, barcodes, brands, stores, categories and original product images"
        case .usda: "U.S. Global Branded Foods; a free data.gov key is recommended"
        case .openStreetMap: "Nearby grocery stores and addresses by city, ZIP code or region"
        case .wikidataCommons: "Brand and retailer identities with reusable original images from Wikimedia Commons"
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
        case .stockedReference: "Brands · Store chains · Offline"
        case .builtIn: "Categories · Aisles · Offline"
        case .legacyRemoved: "Unavailable"
        }
    }

    var icon: String {
        switch self {
        case .openStreetMap: "map"
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
    var confidence: Double = 0.8
    var state: CatalogImportState = .queued
    var updatedAt = Date()

    var identityKey: String {
        [kind.rawValue, name, brand ?? "", store ?? "", barcode ?? "", address ?? ""]
            .joined(separator: "|").foldedCatalogKey
    }

    var hasImage: Bool { imageURL?.nilIfBlank != nil }

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
        imageURL = imageURL ?? incoming.imageURL
        imagePreviewURL = imagePreviewURL ?? incoming.imagePreviewURL
        imageSourceURL = imageSourceURL ?? incoming.imageSourceURL
        imageAttribution = imageAttribution ?? incoming.imageAttribution
        confidence = max(confidence, incoming.confidence)
        if self != before { updatedAt = Date(); return true }
        return false
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
    var selectedSources: Set<CatalogSource> = [.openFoodFacts, .stockedReference, .builtIn]
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
        var found: [CatalogRecord] = []
        var failures: [String] = []
        let perSource = max(10, resultLimit / max(1, selectedSources.count))

        for source in CatalogSource.allCases where selectedSources.contains(source) {
            do {
                switch source {
                case .openFoodFacts:
                    found += try await fetchOpenFacts(.openFoodFacts, host: "world.openfoodfacts.org", limit: perSource)
                case .usda:
                    found += try await fetchUSDA(limit: perSource)
                case .openStreetMap:
                    found += try await fetchStores(limit: min(perSource, 50))
                case .wikidataCommons:
                    found += try await fetchWikidataCommons(limit: min(perSource, 50))
                case .stockedReference:
                    found += CatalogReferenceData.records(matching: query, limit: perSource)
                case .builtIn:
                    found += builtInAisles()
                case .legacyRemoved:
                    break
                }
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

    func importQueued(limit: Int? = nil) {
        let count = min(limit ?? queue.count, queue.count)
        guard count > 0 else { status = "Nothing is waiting to import."; return }
        var incoming = Array(queue.prefix(count))
        for index in incoming.indices { incoming[index].state = .imported; incoming[index].updatedAt = Date() }
        var added = 0
        var enriched = 0
        for record in incoming {
            if let index = library.firstIndex(where: { $0.identityKey == record.identityKey }) {
                if library[index].mergeEnrichment(from: record) { enriched += 1 }
            } else {
                library.append(record)
                added += 1
            }
        }
        queue.removeFirst(count)
        status = "Imported \(added) records and enriched \(enriched) existing records; \(queue.count) remain queued."
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

    private func mergeDiscovered(_ records: [CatalogRecord]) -> (added: Int, enriched: Int) {
        var added = 0
        var enriched = 0
        for record in records {
            if let index = library.firstIndex(where: { $0.identityKey == record.identityKey }) {
                if library[index].mergeEnrichment(from: record) { enriched += 1 }
            } else if let index = queue.firstIndex(where: { $0.identityKey == record.identityKey }) {
                if queue[index].mergeEnrichment(from: record) { enriched += 1 }
            } else {
                queue.append(record)
                added += 1
            }
        }
        return (added, enriched)
    }

    private func fetchOpenFacts(_ source: CatalogSource, host: String, limit: Int) async throws -> [CatalogRecord] {
        var components = URLComponents(string: "https://\(host)/cgi/search.pl")!
        components.queryItems = [
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "search_terms", value: query.nilIfBlank ?? "grocery"),
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

    private func fetchUSDA(limit: Int) async throws -> [CatalogRecord] {
        var request = URLRequest(url: URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=\(usdaAPIKey.nilIfBlank ?? "DEMO_KEY")")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query.nilIfBlank ?? "grocery", "dataType": ["Branded"], "pageSize": min(limit, 100)])
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
        guard let term = query.nilIfBlank else {
            throw MacServiceError.invalidRequest("Enter a brand or store name for Wikidata + Commons discovery.")
        }
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
            let commercialTerms = ["brand", "company", "corporation", "manufacturer", "store", "supermarket", "grocery", "retail", "hypermarket", "food producer", "beverage"]
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
        library.removeAll { $0.source == .legacyRemoved }
        queue.removeAll { $0.source == .legacyRemoved }
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
