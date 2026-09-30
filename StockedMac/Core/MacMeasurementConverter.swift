// MacMeasurementConverter.swift — display-only ingredient scaling and unit conversion.
//
// Build 114. Foundation-only so it can be verified natively with
// scripts/test-measurement-converter.swift. Stored recipe amounts are never rewritten.

import Foundation

// MARK: - Measurement display

nonisolated enum MacMeasurementSystem: String, CaseIterable, Identifiable, Codable, Sendable {
    case asWritten = "As written"
    case us = "US customary"
    case metric = "Metric"
    var id: String { rawValue }
}

/// Display-only quantity scaling and unit conversion for ingredient amounts. Unknown or
/// descriptive amounts ("to taste", "a handful") are always returned unchanged.
nonisolated enum MacMeasurementConverter {
    private enum Dimension { case volume, mass }

    private struct Unit {
        let names: [String]
        let dimension: Dimension
        /// Millilitres for volume, grams for mass.
        let base: Double
    }

    private static let units: [Unit] = [
        Unit(names: ["fl oz", "fl. oz", "fl. oz.", "fluid ounce", "fluid ounces"], dimension: .volume, base: 29.5735),
        Unit(names: ["cup", "cups", "c"], dimension: .volume, base: 236.588),
        Unit(names: ["tablespoon", "tablespoons", "tbsp", "tbsp.", "tbs", "tbl", "T"], dimension: .volume, base: 14.7868),
        Unit(names: ["teaspoon", "teaspoons", "tsp", "tsp.", "t"], dimension: .volume, base: 4.92892),
        Unit(names: ["pint", "pints", "pt"], dimension: .volume, base: 473.176),
        Unit(names: ["quart", "quarts", "qt"], dimension: .volume, base: 946.353),
        Unit(names: ["gallon", "gallons", "gal"], dimension: .volume, base: 3785.41),
        Unit(names: ["ml", "milliliter", "milliliters", "millilitre", "millilitres"], dimension: .volume, base: 1),
        Unit(names: ["l", "liter", "liters", "litre", "litres"], dimension: .volume, base: 1000),
        Unit(names: ["oz", "ounce", "ounces"], dimension: .mass, base: 28.3495),
        Unit(names: ["lb", "lbs", "pound", "pounds"], dimension: .mass, base: 453.592),
        Unit(names: ["g", "gram", "grams", "gr"], dimension: .mass, base: 1),
        Unit(names: ["kg", "kilogram", "kilograms"], dimension: .mass, base: 1000),
    ]

    private static let metricNames: Set<String> = ["ml", "milliliter", "milliliters", "millilitre", "millilitres",
                                                   "l", "liter", "liters", "litre", "litres",
                                                   "g", "gram", "grams", "gr", "kg", "kilogram", "kilograms"]

    private static let unicodeFractions: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "¼": 0.25, "¾": 0.75,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875, "⅕": 0.2,
    ]

    /// Parses a leading quantity ("1", "1.5", "1/2", "1 1/2", "1½", "½") and returns it
    /// with the untouched remainder of the string.
    static func leadingQuantity(_ raw: String) -> (value: Double, rest: String)? {
        var text = Substring(raw.trimmingCharacters(in: .whitespaces))
        var total = 0.0
        var matched = false

        func takeNumber() -> Double? {
            var digits = ""
            while let c = text.first, c.isASCII, c.isNumber || c == "." {
                digits.append(c); text.removeFirst()
            }
            guard !digits.isEmpty else { return nil }
            if text.first == "/" {
                var probe = text.dropFirst()
                var denominator = ""
                while let c = probe.first, c.isASCII, c.isNumber { denominator.append(c); probe.removeFirst() }
                if let n = Double(digits), let d = Double(denominator), d != 0 {
                    text = probe
                    return n / d
                }
            }
            return Double(digits)
        }

        if let first = takeNumber() {
            total += first; matched = true
            if let c = text.first, let fraction = unicodeFractions[c] {
                total += fraction; text.removeFirst()
            } else {
                let saved = text
                text = Substring(text.drop(while: { $0 == " " }))
                if let c = text.first, let fraction = unicodeFractions[c] {
                    total += fraction; text.removeFirst()
                } else if text.contains("/"), let next = takeNumber(), next < 1 {
                    total += next
                } else {
                    text = saved
                }
            }
        } else if let c = text.first, let fraction = unicodeFractions[c] {
            total = fraction; matched = true; text.removeFirst()
        }
        guard matched, total.isFinite, total > 0 else { return nil }
        return (total, String(text))
    }

    /// The amount as it should read on screen for a serving factor and unit system.
    static func display(_ amount: String, factor: Double, system: MacMeasurementSystem) -> String {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let parsed = leadingQuantity(trimmed) else { return amount }
        let scaled = parsed.value * max(0.01, factor)
        let rest = parsed.rest.trimmingCharacters(in: .whitespaces)
        // Ranges ("1-2 cups", "2 to 3 tbsp") are shown exactly as written rather than
        // guessing how the publisher meant them to scale.
        if rest.hasPrefix("-") || rest.hasPrefix("–") || rest.lowercased().hasPrefix("to ") { return amount }
        guard system != .asWritten, let (unit, tail) = matchUnit(rest) else {
            if abs(factor - 1) < 0.0001 { return amount }
            return rest.isEmpty ? format(scaled) : "\(format(scaled)) \(rest)"
        }
        let isMetric = metricNames.contains(unit.names[0].lowercased())
        if (system == .metric && isMetric) || (system == .us && !isMetric) {
            if abs(factor - 1) < 0.0001 { return amount }
            return join(format(scaled), unitLabel(unit.names[0], plural: scaled > 1), tail)
        }
        let base = scaled * unit.base
        let converted: (Double, String) = system == .metric
            ? metric(base, dimension: unit.dimension)
            : customary(base, dimension: unit.dimension)
        return join(format(converted.0, decimals: system == .metric), converted.1, tail)
    }

    private static func join(_ number: String, _ unit: String, _ tail: String) -> String {
        [number, unit, tail].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func matchUnit(_ rest: String) -> (Unit, String)? {
        matchUnitToken(rest).map { ($0.unit, $0.tail) }
    }

    private static func matchUnitToken(_ rest: String) -> (unit: Unit, length: Int, tail: String)? {
        let lower = rest.lowercased()
        // Longest names first so "fl oz" wins over "oz" and "tablespoon" over "t".
        let candidates = units.flatMap { unit in unit.names.map { (unit, $0) } }
            .sorted { $0.1.count > $1.1.count }
        for (unit, name) in candidates {
            // Single-letter "T"/"t"/"c"/"l"/"g" are only accepted as whole words.
            let caseSensitive = name == "T" || name == "t"
            let haystack = caseSensitive ? rest : lower
            let needle = caseSensitive ? name : name.lowercased()
            guard haystack.hasPrefix(needle) else { continue }
            let after = haystack.dropFirst(needle.count)
            if let next = after.first, next.isLetter { continue }
            let tail = String(rest.dropFirst(needle.count)).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
            return (unit, needle.count, tail)
        }
        return nil
    }

    /// Count and descriptive units that have no conversion but still read as the unit of
    /// an ingredient line ("2 cloves garlic", "1 can tomatoes").
    private static let countUnits: [String] = [
        "cans", "can", "cloves", "clove", "packages", "package", "pkg", "slices", "slice",
        "pinches", "pinch", "dashes", "dash", "bunches", "bunch", "sprigs", "sprig",
        "sticks", "stick", "heads", "head", "jars", "jar", "bottles", "bottle", "bags", "bag",
        "boxes", "box", "pieces", "piece", "handfuls", "handful",
    ]

    /// The unit at the start of `text`, exactly as written, and the remainder after it.
    /// Used by the Harvester's ingredient parser; returns nil when no unit is recognised.
    static func leadingUnit(_ text: String) -> (unit: String, remainder: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let match = matchUnitToken(trimmed) {
            var written = String(trimmed.prefix(match.length))
            let afterToken = trimmed.dropFirst(match.length)
            if afterToken.first == "." { written += "." }
            return (written, match.tail)
        }
        let lower = trimmed.lowercased()
        for name in countUnits where lower.hasPrefix(name) {
            let after = lower.dropFirst(name.count)
            if let next = after.first, next.isLetter { continue }
            let written = String(trimmed.prefix(name.count))
            let remainder = String(trimmed.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
            return (written, remainder)
        }
        return nil
    }

    private static func unitLabel(_ name: String, plural: Bool) -> String {
        switch name {
        case "cup": return plural ? "cups" : "cup"
        case "tablespoon": return "tbsp"
        case "teaspoon": return "tsp"
        case "pint": return plural ? "pints" : "pint"
        case "quart": return plural ? "quarts" : "quart"
        case "gallon": return plural ? "gallons" : "gallon"
        case "pound", "lb": return "lb"
        case "ounce", "oz": return "oz"
        case "gram", "g": return "g"
        case "kilogram", "kg": return "kg"
        case "milliliter", "ml": return "ml"
        case "liter", "l": return "L"
        default: return name
        }
    }

    private static func metric(_ base: Double, dimension: Dimension) -> (Double, String) {
        switch dimension {
        case .volume:
            if base >= 1000 { return ((base / 100).rounded() / 10, "L") }
            return (base < 20 ? (base).rounded() : (base / 5).rounded() * 5, "ml")
        case .mass:
            if base >= 1000 { return ((base / 10).rounded() / 100, "kg") }
            return (base < 20 ? base.rounded() : (base / 5).rounded() * 5, "g")
        }
    }

    private static func customary(_ base: Double, dimension: Dimension) -> (Double, String) {
        switch dimension {
        case .volume:
            let cups = base / 236.588
            if cups >= 0.25 { return (cups, cups >= 1.07 ? "cups" : "cup") }
            let tablespoons = base / 14.7868
            if tablespoons >= 1 { return (tablespoons, "tbsp") }
            return (base / 4.92892, "tsp")
        case .mass:
            let pounds = base / 453.592
            if pounds >= 1 { return (pounds, "lb") }
            return (base / 28.3495, "oz")
        }
    }

    /// Kitchen-friendly numbers: common fractions for customary amounts, tidy decimals
    /// for metric ones.
    static func format(_ value: Double, decimals: Bool = false) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        if decimals {
            if value >= 10 || value == value.rounded() { return String(Int(value.rounded())) }
            return String(format: "%.1f", value).replacingOccurrences(of: ".0", with: "")
        }
        let whole = Int(value)
        let remainder = value - Double(whole)
        let fractions: [(Double, String)] = [(0, ""), (0.125, "⅛"), (0.25, "¼"), (1.0 / 3, "⅓"),
                                             (0.375, "⅜"), (0.5, "½"), (0.625, "⅝"), (2.0 / 3, "⅔"),
                                             (0.75, "¾"), (0.875, "⅞"), (1, "")]
        let nearest = fractions.min { abs($0.0 - remainder) < abs($1.0 - remainder) } ?? (0, "")
        if abs(nearest.0 - remainder) > 0.07, value < 10 {
            return String(format: "%.2f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        let adjustedWhole = nearest.0 == 1 ? whole + 1 : whole
        if nearest.1.isEmpty { return String(adjustedWhole) }
        return adjustedWhole == 0 ? nearest.1 : "\(adjustedWhole)\(nearest.1)"
    }
}
