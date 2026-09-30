// IngredientParser.swift — structures written ingredient lines for the Harvester.
//
// Runs when AppSettings.parseIngredientStructure is on. Quantities and units reuse
// MacMeasurementConverter so the parser and the on-screen converter read amounts the same
// way. Kept Foundation-only; scripts/test-ingredient-parser.swift checks it natively.

import Foundation

nonisolated struct IngredientParser {
    func parseSections(_ sections: [IngredientSection]) -> [IngredientSection] {
        sections.map { section in
            var parsed = section
            parsed.items = section.items.map(parseItem)
            return parsed
        }
    }
    
    /// Splits one written ingredient line into quantity, unit, name, preparation and
    /// notes. `raw` is never changed, and anything that cannot be read confidently is
    /// returned untouched, so display and export fall back to the original wording.
    func parseItem(_ item: IngredientItem) -> IngredientItem {
        guard item.name?.isEmpty ?? true, item.quantity == nil, item.unit == nil else { return item }
        var parsed = item
        var text = item.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return item }

        // Parenthetical asides ("(about 2 cups)", "(optional)") become notes.
        var notes: [String] = []
        while let open = text.firstIndex(of: "("),
              let close = text[open...].firstIndex(of: ")") {
            let inner = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { notes.append(inner) }
            text.removeSubrange(open...close)
        }
        text = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")

        if let (value, rest) = MacMeasurementConverter.leadingQuantity(text) {
            let written = String(text.dropLast(rest.count)).trimmingCharacters(in: .whitespaces)
            parsed.quantity = value
            parsed.quantityText = written.isEmpty ? nil : written
            text = rest.trimmingCharacters(in: .whitespaces)
            if let (unit, remainder) = MacMeasurementConverter.leadingUnit(text) {
                parsed.unit = unit
                text = remainder
            }
        }
        if text.lowercased().hasPrefix("of ") { text = String(text.dropFirst(3)) }

        if let comma = text.range(of: ", ") {
            let preparation = text[comma.upperBound...].trimmingCharacters(in: .whitespaces)
            if !preparation.isEmpty { parsed.preparation = preparation }
            text = String(text[..<comma.lowerBound])
        }
        let name = text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",;-")))
        guard !name.isEmpty else { return item }
        parsed.name = name
        if !notes.isEmpty {
            parsed.notes = ([item.notes].compactMap { $0 } + notes).joined(separator: "; ")
        }
        return parsed
    }
}
