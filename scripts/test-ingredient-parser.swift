// Native ingredient parser check. Compile with the production parser and converter:
//   swiftc -parse-as-library StockedMac/Harvest/IngredientParser.swift \
//          StockedMac/Core/MacMeasurementConverter.swift \
//          scripts/test-ingredient-parser.swift -o /tmp/ingredients && /tmp/ingredients
// The two model types mirror HarvestTypes.swift so the check stays dependency-free.
import Foundation

nonisolated struct IngredientSection: Codable, Sendable {
    var name: String?
    var items: [IngredientItem]
}

nonisolated struct IngredientItem: Codable, Sendable {
    var raw: String
    var quantity: Double?
    var quantityText: String?
    var unit: String?
    var name: String?
    var preparation: String?
    var notes: String?
}

@main struct IngredientParserChecks {
    static func parse(_ raw: String) -> IngredientItem {
        IngredientParser().parseItem(IngredientItem(raw: raw))
    }

    static func expect(_ item: IngredientItem, quantity: Double?, text: String?, unit: String?,
                       name: String?, preparation: String? = nil, notes: String? = nil,
                       _ note: String) {
        guard item.quantity == quantity, item.quantityText == text, item.unit == unit,
              item.name == name, item.preparation == preparation, item.notes == notes else {
            fatalError("\(note): got \(item)")
        }
    }

    static func main() {
        expect(parse("1 1/2 cups all-purpose flour, sifted"), quantity: 1.5, text: "1 1/2", unit: "cups",
               name: "all-purpose flour", preparation: "sifted", "mixed fraction, unit, preparation")
        expect(parse("2 cloves garlic, minced"), quantity: 2, text: "2", unit: "cloves",
               name: "garlic", preparation: "minced", "count unit")
        expect(parse("½ tsp. kosher salt"), quantity: 0.5, text: "½", unit: "tsp.",
               name: "kosher salt", "unicode fraction")
        expect(parse("1 can (14 oz) diced tomatoes"), quantity: 1, text: "1", unit: "can",
               name: "diced tomatoes", notes: "14 oz", "parenthetical becomes a note")
        expect(parse("3 large eggs"), quantity: 3, text: "3", unit: nil, name: "large eggs", "no unit")
        expect(parse("1 cup of milk"), quantity: 1, text: "1", unit: "cup", name: "milk", "of is dropped")
        expect(parse("Salt and pepper, to taste"), quantity: nil, text: nil, unit: nil,
               name: "Salt and pepper", preparation: "to taste", "no quantity")
        expect(parse("2 cups"), quantity: nil, text: nil, unit: nil, name: nil, "no name keeps the item untouched")

        var structured = IngredientItem(raw: "1 onion")
        structured.name = "yellow onion"
        let kept = IngredientParser().parseItem(structured)
        precondition(kept.name == "yellow onion" && kept.quantity == nil, "already structured items are kept")
        precondition(parse("2 cloves garlic").raw == "2 cloves garlic", "raw never changes")

        let sections = IngredientParser().parseSections([IngredientSection(name: "Sauce", items: [IngredientItem(raw: "1 tbsp butter")])])
        precondition(sections[0].name == "Sauce" && sections[0].items[0].unit == "tbsp")
        print("Ingredient parser checks passed: quantities, units, names, preparation, notes and fallbacks")
    }
}
