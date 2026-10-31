// Native measurement display check. Compile with production MacMeasurementConverter.swift:
//   swiftc -parse-as-library StockedMac/Core/MacMeasurementConverter.swift \
//          scripts/test-measurement-converter.swift -o /tmp/measure && /tmp/measure
import Foundation

@main struct MeasurementConverterChecks {
    static func check(_ actual: String, _ expected: String, _ note: String) {
        guard actual == expected else {
            fatalError("\(note): expected “\(expected)”, got “\(actual)”")
        }
    }

    static func main() {
        typealias M = MacMeasurementConverter
        // Parsing
        precondition(M.leadingQuantity("1 1/2 cups")?.value == 1.5)
        precondition(M.leadingQuantity("½ tsp")?.value == 0.5)
        precondition(M.leadingQuantity("1½ cups")?.value == 1.5)
        precondition(M.leadingQuantity("to taste") == nil)
        // As written, unscaled: unchanged text.
        check(M.display("2 cups", factor: 1, system: .asWritten), "2 cups", "identity")
        check(M.display("a pinch", factor: 3, system: .metric), "a pinch", "descriptive amounts stay")
        check(M.display("1-2 cups", factor: 2, system: .metric), "1-2 cups", "ranges stay as written")
        // Scaling keeps the unit and uses kitchen fractions.
        check(M.display("1 cup", factor: 0.5, system: .asWritten), "½ cup", "halve")
        check(M.display("3/4 tsp", factor: 2, system: .asWritten), "1½ tsp", "double fraction")
        check(M.display("4", factor: 1.5, system: .asWritten), "6", "count scaling")
        // Conversions.
        check(M.display("1 cup", factor: 1, system: .metric), "235 ml", "cup to ml")
        check(M.display("1 lb", factor: 1, system: .metric), "455 g", "pound to grams")
        check(M.display("500 g", factor: 1, system: .us), "1⅛ lb", "grams to pounds")
        check(M.display("2 tbsp", factor: 1, system: .metric), "30 ml", "tbsp to ml")
        check(M.display("250 ml", factor: 1, system: .us), "1 cup", "ml to cup")
        check(M.display("2 cloves garlic", factor: 1, system: .metric), "2 cloves garlic", "c is not cups")
        check(M.display("1 T", factor: 1, system: .metric), "15 ml", "capital T tablespoon")
        // Leading units keep the written token.
        precondition(M.leadingUnit("cups flour")! == (unit: "cups", remainder: "flour"))
        precondition(M.leadingUnit("tbsp. olive oil")! == (unit: "tbsp.", remainder: "olive oil"))
        precondition(M.leadingUnit("fl oz milk")! == (unit: "fl oz", remainder: "milk"))
        precondition(M.leadingUnit("cloves garlic")! == (unit: "cloves", remainder: "garlic"))
        precondition(M.leadingUnit("can (14 oz) tomatoes")! == (unit: "can", remainder: "(14 oz) tomatoes"))
        precondition(M.leadingUnit("large eggs") == nil, "l is not litres")
        precondition(M.leadingUnit("carrots") == nil, "c is not cups")
        precondition(M.leadingUnit("canola oil") == nil, "can needs a word boundary")
        print("Measurement converter checks passed: parsing, units, scaling, ranges and US/metric conversion")
    }
}
