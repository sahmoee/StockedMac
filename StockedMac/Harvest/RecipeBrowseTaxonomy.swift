import Foundation

/// A stable, searchable category used to filter discovery results before they join the
/// queue. Matching is deliberately link/title based because sitemap discovery happens
/// before a recipe is downloaded; saved recipe metadata and source tags are added when
/// available to make subsequent cached passes more precise.
nonisolated struct RecipeBrowseCategory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let group: String
    let terms: [String]
}

/// Stocked's broad recipe-browsing vocabulary. The UI presents the groups separately,
/// while matching treats multiple selections as an inclusive OR ("Italian or pasta").
nonisolated enum RecipeBrowseTaxonomy {
    static let groupOrder = [
        "Meals & courses",
        "Food & dish types",
        "Cuisines & cultures",
        "Dietary needs",
        "Occasions & events",
        "Cooking methods",
        "Seasons & lifestyle",
    ]

    static let all: [RecipeBrowseCategory] = {
        var result: [RecipeBrowseCategory] = []
        func add(_ group: String, _ names: [String]) {
            for name in names {
                let id = identifier(group: group, name: name)
                result.append(RecipeBrowseCategory(
                    id: id,
                    name: name,
                    group: group,
                    terms: ([name] + (aliases[name] ?? []))
                        .flatMap(termVariants)
                        .cleanedUnique()
                ))
            }
        }

        add("Meals & courses", [
            "Breakfast", "Brunch", "Lunch", "Dinner", "Appetizers", "Small plates",
            "Snacks", "Main dishes", "Side dishes", "Soups", "Salads", "Sandwiches",
            "Wraps", "Bowls", "Desserts", "Beverages", "Cocktails", "Mocktails",
            "Sauces", "Dips", "Condiments", "Meal prep", "Kids' meals", "Baby food",
            "Late-night food",
        ])

        add("Food & dish types", [
            "Beef", "Chicken", "Turkey", "Pork", "Lamb", "Goat", "Duck", "Game",
            "Fish", "Shellfish", "Seafood", "Eggs", "Cheese", "Tofu", "Tempeh",
            "Beans & legumes", "Vegetables", "Mushrooms", "Fruit", "Pasta", "Noodles",
            "Rice", "Grains", "Potatoes", "Pizza", "Flatbreads", "Burgers", "Tacos",
            "Dumplings", "Sushi", "Curry", "Stews", "Chili", "Casseroles", "Pies",
            "Quiche", "Bread", "Biscuits", "Muffins", "Pancakes & waffles", "Cakes",
            "Cupcakes", "Cookies", "Brownies & bars", "Candy", "Ice cream", "Puddings",
            "Preserves", "Smoothies", "Coffee & tea",
        ])

        add("Cuisines & cultures", [
            "Global & fusion", "African", "West African", "North African", "East African",
            "South African", "Ethiopian", "Eritrean", "Nigerian", "Ghanaian", "Senegalese",
            "Moroccan", "Egyptian", "Tunisian", "Kenyan", "Somali", "Asian", "East Asian",
            "Southeast Asian", "South Asian", "Central Asian", "Chinese", "Cantonese",
            "Sichuan", "Taiwanese", "Hong Kong", "Japanese", "Okinawan", "Korean",
            "Vietnamese", "Thai", "Filipino", "Indonesian", "Malaysian", "Singaporean",
            "Cambodian", "Laotian", "Burmese", "Indian", "North Indian", "South Indian",
            "Punjabi", "Gujarati", "Bengali", "Goan", "Pakistani", "Bangladeshi",
            "Sri Lankan", "Nepalese", "Tibetan", "Bhutanese", "Maldivian", "Mongolian",
            "Afghan", "Uzbek", "Middle Eastern", "Arab", "Kurdish", "Jewish",
            "Ashkenazi Jewish", "Sephardic Jewish", "Mizrahi Jewish",
            "Levantine", "Lebanese", "Syrian", "Palestinian", "Jordanian", "Israeli",
            "Iraqi", "Iranian & Persian", "Turkish", "Yemeni", "Gulf Arab", "Saudi Arabian",
            "Emirati", "Omani", "Armenian",
            "Georgian", "European", "Mediterranean", "Italian", "Sicilian", "French",
            "Tuscan", "Roman", "Neapolitan", "Sardinian", "Provençal", "Spanish", "Catalan",
            "Basque", "Galician", "Portuguese", "Greek", "Cypriot", "Maltese", "British", "English", "Scottish",
            "Welsh", "Irish", "German", "Austrian", "Swiss", "Dutch", "Belgian",
            "Scandinavian", "Swedish", "Norwegian", "Danish", "Finnish", "Icelandic",
            "Polish", "Ukrainian", "Russian", "Czech", "Slovak", "Hungarian", "Romanian",
            "Bulgarian", "Balkan", "Serbian", "Croatian", "Bosnian", "Albanian", "Slovenian",
            "North Macedonian", "Moldovan", "Lithuanian", "Latvian", "Estonian", "Romani",
            "North American", "American", "Southern US", "Soul food", "Cajun & Creole",
            "Tex-Mex", "Appalachian", "New England", "Midwestern US", "Southwestern US",
            "Californian", "Pacific Northwest", "Indigenous North American", "Canadian",
            "Québécois", "French Canadian", "Latin American", "Mexican", "Oaxacan",
            "Yucatecan", "Central American", "Belizean", "Salvadoran", "Guatemalan",
            "Honduran", "Nicaraguan", "Costa Rican", "Panamanian", "Caribbean", "Jamaican",
            "Cuban", "Puerto Rican", "Dominican", "Haitian", "Trinidadian", "Bahamian",
            "Barbadian", "South American", "Brazilian", "Peruvian",
            "Colombian", "Venezuelan", "Ecuadorian", "Bolivian", "Chilean", "Argentinian",
            "Uruguayan", "Paraguayan", "Guyanese", "Surinamese", "Oceanian", "Australian",
            "Indigenous Australian", "New Zealand", "Māori", "Hawaiian", "Native Hawaiian",
            "Fijian", "Samoan", "Tongan", "Tahitian", "Chamorro", "Polynesian", "Pacific Islander",
        ])

        add("Dietary needs", [
            "Vegan", "Vegetarian", "Pescatarian", "Flexitarian", "Gluten-free",
            "Dairy-free", "Egg-free", "Nut-free", "Soy-free", "Sesame-free",
            "Grain-free", "Keto", "Low-carb", "Paleo", "Whole30", "Mediterranean diet",
            "Low-fat", "Low-sodium", "Low-sugar", "Sugar-free", "High-protein",
            "High-fiber", "Diabetic-friendly", "Heart-healthy", "Anti-inflammatory",
            "FODMAP-friendly", "Halal", "Kosher", "Raw food", "Plant-based",
        ])

        add("Occasions & events", [
            "Birthdays", "Anniversaries", "Weddings", "Engagements", "Baby showers",
            "Bridal showers", "Graduations", "Housewarming", "Dinner parties", "Potlucks",
            "Picnics", "Cookouts", "Barbecues", "Tailgating", "Game day", "Movie night",
            "Date night", "Family gatherings", "Back to school", "Camping", "Road trips",
            "Christmas", "Christmas Eve", "Thanksgiving", "Easter", "Halloween",
            "New Year's Eve", "New Year's Day", "Valentine's Day", "Mother's Day",
            "Father's Day", "Independence Day", "Memorial Day", "Labor Day", "Juneteenth",
            "Kwanzaa", "Hanukkah", "Passover", "Rosh Hashanah", "Yom Kippur", "Purim",
            "Ramadan", "Eid al-Fitr", "Eid al-Adha", "Diwali", "Holi", "Lunar New Year",
            "Nowruz", "Vesak", "Mardi Gras", "Carnival", "St. Patrick's Day",
            "Cinco de Mayo", "Oktoberfest", "Burns Night", "Boxing Day", "Super Bowl",
        ])

        add("Cooking methods", [
            "Air fryer", "Slow cooker", "Pressure cooker", "Instant Pot", "One-pot",
            "Sheet-pan", "No-cook", "Stovetop", "Oven-baked", "Roasted", "Broiled",
            "Grilled", "Barbecued", "Smoked", "Steamed", "Poached", "Braised", "Sautéed",
            "Stir-fried", "Deep-fried", "Pan-fried", "Sous vide", "Wok cooking",
            "Dutch oven", "Cast iron", "Microwave", "Fermented", "Pickled", "Canned",
            "Dehydrated", "Make-ahead", "Freezer-friendly", "30 minutes or less",
        ])

        add("Seasons & lifestyle", [
            "Spring", "Summer", "Autumn", "Winter", "Warm weather", "Cold weather",
            "Comfort food", "Healthy", "Budget-friendly", "Quick & easy", "Weeknight",
            "Weekend project", "Crowd-pleasing", "Portable", "Lunchbox", "Outdoor dining",
            "Farm-to-table", "Seasonal produce", "Zero-waste", "Pantry staples",
            "Restaurant copycat", "Street food", "Fine dining", "Traditional & heritage",
        ])
        return result
    }()

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func categories(in group: String) -> [RecipeBrowseCategory] {
        all.filter { $0.group == group }
    }

    static func matches(
        _ link: DiscoveredLink,
        selectedIDs: Set<String>,
        supplementalText: String = ""
    ) -> Bool {
        guard !selectedIDs.isEmpty else { return true }
        let decodedURL = link.url.removingPercentEncoding ?? link.url
        let haystack = " " + normalize([
            decodedURL,
            link.title ?? "",
            supplementalText,
        ].joined(separator: " ")) + " "
        return selectedIDs.compactMap { byID[$0] }.contains { category in
            category.terms.contains { term in
                !term.isEmpty && haystack.contains(" \(term) ")
            }
        }
    }

    private static func identifier(group: String, name: String) -> String {
        slug(group) + "." + slug(name)
    }

    private static func slug(_ value: String) -> String {
        normalize(value).replacingOccurrences(of: " ", with: "-")
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// Recipe URLs are inconsistent about singular/plural labels ("soup" vs
    /// "soups", "birthday" vs "birthdays"). Generate conservative variants for
    /// the final word while retaining explicit aliases for irregular food names.
    private static func termVariants(_ value: String) -> [String] {
        let term = normalize(value)
        guard let last = term.split(separator: " ").last.map(String.init), last.count > 2 else {
            return [term]
        }
        let stem = String(term.dropLast(last.count))
        if last.hasSuffix("ies"), last.count > 3 {
            return [term, stem + String(last.dropLast(3)) + "y"]
        }
        if last.hasSuffix("ches") || last.hasSuffix("shes")
            || last.hasSuffix("xes") || last.hasSuffix("zes") {
            return [term, stem + String(last.dropLast(2))]
        }
        if last.hasSuffix("s"),
           !last.hasSuffix("ss"),
           !last.hasSuffix("us"),
           !last.hasSuffix("is") {
            return [term, stem + String(last.dropLast())]
        }
        if last.hasSuffix("y"),
           let beforeY = last.dropLast().last,
           !"aeiou".contains(beforeY) {
            return [term, stem + String(last.dropLast()) + "ies"]
        }
        if last.hasSuffix("ch") || last.hasSuffix("sh")
            || last.hasSuffix("x") || last.hasSuffix("z") {
            return [term, stem + last + "es"]
        }
        return [term, stem + last + "s"]
    }

    private static let aliases: [String: [String]] = [
        "Appetizers": ["starter", "starters", "hors d'oeuvre", "antipasti"],
        "Small plates": ["tapas", "mezze", "meze"],
        "Side dishes": ["side dish", "sides"],
        "Main dishes": ["main course", "entree", "entrée"],
        "Beverages": ["drink", "drinks", "beverage"],
        "Sauces": ["gravy", "marinade", "dressing"],
        "Beans & legumes": ["beans", "lentils", "chickpeas", "peas", "pulses"],
        "Shellfish": ["shrimp", "prawn", "crab", "lobster", "mussel", "clam", "oyster"],
        "Flatbreads": ["flatbread", "naan", "pita", "roti", "focaccia"],
        "Dumplings": ["dumpling", "gyoza", "wonton", "pierogi", "momo", "ravioli"],
        "Pancakes & waffles": ["pancake", "pancakes", "waffle", "waffles", "crepe", "crêpe"],
        "Brownies & bars": ["brownie", "brownies", "blondie", "traybake"],
        "Preserves": ["jam", "jelly", "marmalade", "chutney"],
        "Coffee & tea": ["coffee", "espresso", "latte", "tea", "chai", "matcha"],
        "Global & fusion": ["fusion", "global", "international"],
        "African": ["ethiopian", "eritrean", "nigerian", "ghanaian", "senegalese", "moroccan", "egyptian", "tunisian", "kenyan", "somali", "south african"],
        "Asian": ["chinese", "japanese", "korean", "vietnamese", "thai", "filipino", "indonesian", "malaysian", "singaporean", "cambodian", "laotian", "burmese", "indian", "pakistani", "bangladeshi", "sri lankan", "nepalese", "tibetan", "afghan", "uzbek"],
        "Middle Eastern": ["middle east", "levantine", "lebanese", "syrian", "palestinian", "jordanian", "israeli", "iraqi", "iranian", "persian", "turkish", "yemeni", "gulf arab"],
        "Arab": ["arab", "arabic", "levantine", "gulf arab", "saudi", "emirati", "omani", "yemeni", "iraqi"],
        "Jewish": ["jewish", "ashkenazi", "sephardic", "mizrahi"],
        "European": ["italian", "french", "spanish", "portuguese", "greek", "british", "irish", "german", "austrian", "swiss", "dutch", "belgian", "scandinavian", "polish", "ukrainian", "russian", "czech", "hungarian", "romanian", "balkan"],
        "North American": ["american", "canadian", "mexican", "cajun", "creole", "tex mex", "soul food"],
        "Latin American": ["latin american", "latino", "mexican", "central american", "caribbean", "south american", "brazilian", "peruvian", "colombian", "venezuelan", "argentinian"],
        "Caribbean": ["jamaican", "cuban", "puerto rican", "dominican", "haitian", "trinidadian"],
        "South American": ["brazilian", "peruvian", "colombian", "venezuelan", "ecuadorian", "bolivian", "chilean", "argentinian", "uruguayan"],
        "Oceanian": ["australian", "new zealand", "maori", "hawaiian", "polynesian", "pacific islander"],
        "Cajun & Creole": ["cajun", "creole"],
        "Iranian & Persian": ["iranian", "persian"],
        "Gluten-free": ["gluten free", "glutenfree", "gf"],
        "Dairy-free": ["dairy free", "lactose free"],
        "Low-carb": ["low carb", "low carbohydrate"],
        "Plant-based": ["plant based", "plantbased"],
        "FODMAP-friendly": ["fodmap", "low fodmap"],
        "Diabetic-friendly": ["diabetic", "diabetes friendly"],
        "Lunar New Year": ["chinese new year", "tet", "seollal"],
        "New Year's Eve": ["new years eve", "nye"],
        "New Year's Day": ["new years day"],
        "St. Patrick's Day": ["st patricks day", "saint patricks day"],
        "Independence Day": ["fourth of july", "4th of july", "july 4"],
        "Game day": ["gameday", "watch party"],
        "Barbecues": ["barbecue", "bbq", "cookout"],
        "Pressure cooker": ["pressure cooker", "instant pot"],
        "Instant Pot": ["instant pot", "pressure cooker"],
        "Slow cooker": ["slow cooker", "crockpot", "crock pot"],
        "One-pot": ["one pot", "onepot"],
        "Sheet-pan": ["sheet pan", "tray bake", "traybake"],
        "Stir-fried": ["stir fry", "stir fried"],
        "Deep-fried": ["deep fry", "deep fried"],
        "Pan-fried": ["pan fry", "pan fried"],
        "Oven-baked": ["oven baked", "baked"],
        "30 minutes or less": ["30 minute", "thirty minute", "quick"],
        "Autumn": ["autumn", "fall"],
        "Comfort food": ["comfort food", "cozy"],
        "Budget-friendly": ["budget", "cheap", "affordable"],
        "Quick & easy": ["quick", "easy", "simple"],
        "Traditional & heritage": ["traditional", "heritage", "authentic", "heirloom"],
    ]
}
