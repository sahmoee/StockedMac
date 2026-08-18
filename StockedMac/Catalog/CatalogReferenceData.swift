import Foundation

/// A network-independent discovery baseline. These are identities only: Stocked never
/// invents a branch address, barcode, product, or aisle assignment for these records.
nonisolated enum CatalogReferenceData {
    static let storeNames = lines(from: """
    Walmart
    Kroger
    Costco
    Albertsons
    Safeway
    Publix
    H-E-B
    H-E-B plus!
    H-E-B México
    Joe V's Smart Shop
    Mi Tienda
    Meijer
    Aldi
    Lidl
    Trader Joe's
    Whole Foods Market
    Target
    Sam's Club
    BJ's Wholesale Club
    Food Lion
    Giant Food
    Giant Eagle
    Stop & Shop
    ShopRite
    Wegmans
    WinCo Foods
    Hy-Vee
    Sprouts Farmers Market
    Fresh Thyme Market
    Market Basket
    Piggly Wiggly
    Harris Teeter
    Ingles Markets
    Save Mart
    Raley's
    Stater Bros. Markets
    Smart & Final
    Grocery Outlet
    The Fresh Market
    Central Market
    United Supermarkets
    Tom Thumb
    Randalls
    Vons
    Jewel-Osco
    Acme Markets
    Shaw's
    Star Market
    Kings Food Markets
    Balducci's
    Mariano's
    Dillons
    Fred Meyer
    Ralphs
    QFC
    Smith's Food and Drug
    Fry's Food Stores
    King Soopers
    City Market
    Baker's Supermarkets
    Gerbes
    Jay C Food Stores
    Metro Market
    Pick 'n Save
    Food 4 Less
    Foods Co
    Homeland
    Reasor's
    Brookshire's
    Super 1 Foods
    Harps Food Stores
    Price Chopper
    Market 32
    Schnucks
    Dierbergs Markets
    Fareway
    Coborn's
    Cub Foods
    Lunds & Byerlys
    Festival Foods
    Woodman's Markets
    Lowes Foods
    Rouses Markets
    Winn-Dixie
    Fresco y Más
    Harveys Supermarket
    Sedano's Supermarkets
    Presidente Supermarket
    Vallarta Supermarkets
    Northgate Market
    Cardenas Markets
    El Super
    99 Ranch Market
    H Mart
    Seafood City
    Patel Brothers
    Mitsuwa Marketplace
    Uwajimaya
    Zion Market
    Key Food
    Food Bazaar
    Western Beef
    Morton Williams
    Gristedes
    Fairway Market
    DeCicco & Sons
    Weis Markets
    Redner's Markets
    Karns Foods
    Martin's Foods
    Tops Friendly Markets
    Hannaford
    Price Rite Marketplace
    Shoppers Food & Pharmacy
    MOM's Organic Market
    Erewhon
    Gelson's Markets
    Bristol Farms
    Lazy Acres Market
    PCC Community Markets
    New Seasons Market
    Harmons Grocery
    Bashas'
    AJ's Fine Foods
    Lee Lee International Supermarkets
    Associated Food Stores
    Macey's
    Ridley's Family Markets
    Rosauers Supermarkets
    Yoke's Fresh Market
    Town & Country Markets
    Metropolitan Market
    Save A Lot
    IGA
    The Food Emporium
    County Market
    Strack & Van Til
    Pete's Fresh Market
    Tony's Fresh Market
    Cermak Fresh Market
    Fresh Market Place
    Mac's Fresh Market
    Pavilions
    Lucky California
    Nob Hill Foods
    Bel Air
    FoodMaxx
    Nugget Markets
    Mollie Stone's Markets
    Draeger's Market
    Berkeley Bowl
    Community Markets
    Marc's
    Dave's Markets
    Heinen's Grocery Store
    Dorothy Lane Market
    Jungle Jim's International Market
    Remke Markets
    Busch's Fresh Food Market
    Plum Market
    Westborn Market
    Sendik's Food Market
    Trig's
    Metcalfe's Market
    Kowalski's Markets
    Jerry's Foods
    Hornbacher's
    Hugo's Family Marketplace
    Dan's Supermarket
    Family Fare
    SpartanNash
    Cash Wise Foods
    Mackenthun's Fine Foods
    Gerrity's Supermarket
    McCaffrey's Food Markets
    Roche Bros.
    Big Y
    Geissler's Supermarket
    Stew Leonard's
    Adams Hometown Markets
    Dave's Fresh Marketplace
    Market of Choice
    Zupan's Markets
    Roth's Fresh Markets
    Chuck's Produce
    Haggen
    Saar's Super Saver Foods
    Island Pacific Market
    Marukai Market
    Nijiya Market
    Tokyo Central
    Lotte Plaza Market
    Great Wall Supermarket
    Grand Mart
    Compare Foods
    Bravo Supermarkets
    Fine Fare Supermarkets
    C-Town Supermarkets
    Foodtown
    D'Agostino Supermarkets
    Zabar's
    Gourmet Garage
    Union Market
    Lincoln Market
    Brooklyn Fare
    """)

    static let brandNames = lines(from: """
    4C Foods
    5-hour Energy
    7UP
    A.1.
    Abuelita
    Activia
    Aidells
    Airheads
    Al Fresco
    Alani Nu
    Almond Breeze
    Amy's Kitchen
    Annie's
    Applegate
    Arizona Beverages
    Armour
    Atkins
    Aunt Jemima
    Aunt Millie's
    Bai
    Ball Park
    Barilla
    Barebells
    Bear Creek
    BelGioioso
    Ben & Jerry's
    Bertolli
    Betty Crocker
    Beyond Meat
    Bicentennial Foods
    Bigelow Tea
    Blue Bell
    Blue Bunny
    Bob Evans
    Bob's Red Mill
    Boar's Head
    Bolthouse Farms
    Bonne Maman
    Borden
    Bota Box
    Boulder Canyon
    Breyers
    Brisk
    Brownberry
    Bubly
    Buddig
    Bush's Best
    Butterball
    Cabot
    Campbell's
    Canada Dry
    Capri Sun
    Carbone
    Carnation
    Cascadian Farm
    Catalina Crunch
    Celestial Seasonings
    Celsius
    Chameleon Cold-Brew
    Cheerios
    Cheez-It
    Chobani
    Chomps
    Clif Bar
    Coca-Cola
    Coffee mate
    Coleman Natural
    Country Crock
    Cracker Barrel
    Crystal Light
    Daisy
    Dannon
    Dasani
    Dave's Killer Bread
    De Cecco
    Del Monte
    Dei Fratelli
    Dietz & Watson
    Dole
    Doritos
    Dr Pepper
    Duncan Hines
    Dunkin'
    Earthbound Farm
    Eggland's Best
    Eight O'Clock Coffee
    El Monterey
    Emerald
    Entenmann's
    Equal
    Essentia
    Evian
    Fairlife
    Famous Amos
    Fanta
    Farm Rich
    Farmer John
    Ferrero Rocher
    Fiber One
    Fiji Water
    FOLGERS
    Fody
    Food Should Taste Good
    Frank's RedHot
    Freschetta
    Fresh Express
    Frito-Lay
    Frontera
    G Hughes
    Gardein
    Gatorade
    General Mills
    Gerber
    Ghirardelli
    Gold Medal
    Golden State Foods
    Goldfish
    Good Culture
    Good Foods
    Goodles
    Goya
    Green Giant
    Grey Poupon
    Guerrero
    Häagen-Dazs
    Halo Top
    Hampton Farms
    Haribo
    Healthy Choice
    Heinz
    Hellmann's
    Hershey's
    Hidden Valley
    Hillshire Farm
    Hint Water
    Hormel
    Hostess
    Hot Pockets
    Huy Fong Foods
    International Delight
    Jell-O
    Jennie-O
    Jimmy Dean
    Johnsonville
    Jones Dairy Farm
    Jolly Rancher
    Justin's
    Kashi
    Keebler
    Kellogg's
    Ken's Steak House
    Kettle Brand
    Kidfresh
    KIND
    King Arthur Baking
    Kit Kat
    Knorr
    Kodiak Cakes
    Kool-Aid
    Kraft
    La Banderita
    LaCroix
    Lance
    Land O Lakes
    Larabar
    Lay's
    Lean Cuisine
    Lewis Bake Shop
    Libby's
    Life Cuisine
    Lifeway
    Lipton
    Liquid Death
    Little Debbie
    Lotus Foods
    Love Grown
    Lucky Charms
    Lundberg Family Farms
    M&M's
    MadeGood
    Malt-O-Meal
    Maruchan
    Mary’s Gone Crackers
    McCain
    McCormick
    McVitie's
    Mezzetta
    Minute Maid
    Minute Rice
    Mission
    Monster Energy
    MorningStar Farms
    Morton Salt
    Motts
    Mountain Dew
    Mrs. Butterworth's
    Muscle Milk
    Nabisco
    Naked Juice
    Nature's Bakery
    Nature Valley
    Near East
    Nescafé
    Nestlé
    Newman's Own
    Nissin
    Noosa
    Nutella
    Ocean Spray
    Oikos
    Old El Paso
    Old Orchard
    OREO
    Organic Valley
    Ortega
    Oscar Mayer
    Oatly
    Pace
    Pacific Foods
    Pam
    Panera Bread
    Parmalat
    PediaSure
    Pepperidge Farm
    Pepsi
    Perrier
    P.F. Chang's
    Pillsbury
    POM Wonderful
    Pop-Tarts
    Powerade
    Premier Protein
    Pringles
    Progresso
    Propel
    Pure Leaf
    Quaker
    Rao's Homemade
    Red Baron
    Red Bull
    Reese's
    Reynolds Kitchens
    Ritz
    Rotel
    Sabra
    San Pellegrino
    Sara Lee
    Sargento
    Silk
    Simply Orange
    SkinnyPop
    Skippy
    Smartfood
    Smucker's
    Snyder's of Hanover
    So Delicious
    Special K
    Spice Islands
    Splenda
    Sprite
    Starbucks
    Starkist
    Stonyfield Organic
    Sunkist
    Sweet Baby Ray's
    Swiss Miss
    Talenti
    Tampico
    Tate's Bake Shop
    Tazo
    Thomas'
    Tillamook
    Tostitos
    Triscuit
    Tropicana
    Tyson
    Uncle Ben's
    Uncrustables
    Valentina
    Van's Foods
    VELVEETA
    V8
    Vita Coco
    Vital Farms
    Vlasic
    Welch's
    Whisps
    White Castle
    Wonderful Pistachios
    Yoplait
    Zatarain's
    Zevia
    365 by Whole Foods Market
    H-E-B
    H-E-B Select Ingredients
    H-E-B Organics
    H-E-B Natural
    H-E-B Meat Market
    H-E-B Fish Market
    H-E-B Prime 1
    H-E-B Bakery
    H-E-B Sushiya
    H-E-B Creamy Creations
    H-E-B Mi Tienda
    H-E-B Meal Simple
    Higher Harvest by H-E-B
    Field & Future by H-E-B
    Hill Country Fare
    Central Market
    Cafe Ole by H-E-B
    Mootopia
    True Texas BBQ
    South Flo Pizza
    ALDI
    ALDI Brand
    Appleton Farms
    Bake Shop
    Barissimo
    Benton's
    Bremer
    Burman's
    California Heritage
    Chef's Cupboard
    Choceur
    Clancy's
    Countryside Creamery
    Deutsche Küche
    Earth Grown
    Elevation
    Emporium Selection
    Fit & Active
    Fremont Fish Market
    Friendly Farms
    Goldhen
    Happy Farms
    Happy Harvest
    Kirkwood
    Little Journey
    liveGfree
    L'oven Fresh
    Lunch Mate
    Mama Cozzi's Pizza Kitchen
    Millville
    Moser Roth
    Nature's Nectar
    Never Any!
    Park Street Deli
    Priano
    Pueblo Lindo
    PurAqua
    Savoritz
    Simms
    Southern Grove
    Stonemill
    Summit
    Tuscan Garden
    Winking Owl
    Amazon Fresh
    Bowl & Basket
    Great Value
    Good & Gather
    Kirkland Signature
    Kroger
    Marketside
    Open Nature
    O Organics
    Signature SELECT
    Simple Truth
    Simply Nature
    Specially Selected
    Trader Joe's
    """)

    /// Verified representative products and product families from the retailers' own
    /// catalogs. Department-level aisles are stable taxonomy hints; live store-specific
    /// aisle numbers, prices, and availability must still come from a provider response.
    private static let retailerProducts: [RetailerProduct] = [
        // H-E-B family of brands
        .init("H-E-B Creamy Creations 1905 Vanilla Ice Cream", "H-E-B Creamy Creations", "H-E-B", "Ice cream", "Frozen", hebHub),
        .init("H-E-B Mootopia Milk", "Mootopia", "H-E-B", "Milk", "Dairy & Eggs", hebHub),
        .init("H-E-B Cafe Ole Coffee", "Cafe Ole by H-E-B", "H-E-B", "Coffee", "Beverages", hebHub),
        .init("Higher Harvest Gluten Free Chicken Nuggets", "Higher Harvest by H-E-B", "H-E-B", "Frozen chicken", "Frozen", hebHub),
        .init("Higher Harvest Low Carb Hamburger Buns", "Higher Harvest by H-E-B", "H-E-B", "Bread", "Bakery", hebHub),
        .init("H-E-B Mi Tienda Fully Cooked Beef Birria", "H-E-B Mi Tienda", "H-E-B", "Prepared beef", "Meat & Seafood", hebHub),
        .init("H-E-B Meal Simple Prepared Meal", "H-E-B Meal Simple", "H-E-B", "Prepared meals", "Deli & Prepared Foods", hebHub),
        .init("H-E-B Sushiya Sushi", "H-E-B Sushiya", "H-E-B", "Prepared sushi", "Deli & Prepared Foods", hebHub),
        .init("H-E-B Sushiya Chicken Fried Rice Bowl", "H-E-B Sushiya", "H-E-B", "Prepared meals", "Deli & Prepared Foods", hebHub),
        .init("H-E-B Sushiya Chicken Egg Rolls", "H-E-B Sushiya", "H-E-B", "Prepared appetizers", "Deli & Prepared Foods", hebHub),
        .init("H-E-B Natural Breaded Chicken Fillets", "H-E-B Natural", "H-E-B", "Frozen chicken", "Frozen", hebHub),
        .init("H-E-B Smoked Atlantic Salmon", "H-E-B Fish Market", "H-E-B", "Smoked salmon", "Meat & Seafood", hebHub),
        .init("H-E-B Bakery Brioche Hamburger Buns", "H-E-B Bakery", "H-E-B", "Bread", "Bakery", hebHub),
        .init("H-E-B Everything Bagels", "H-E-B Bakery", "H-E-B", "Bagels", "Bakery", hebHub),
        .init("H-E-B Peanut Butter Filled Pretzels", "H-E-B", "H-E-B", "Snacks", "Snacks", hebHub),
        .init("H-E-B Colby and Monterey Jack Cheese Sticks", "H-E-B", "H-E-B", "Cheese", "Dairy & Eggs", hebHub),
        .init("H-E-B Fresh Baby Carrots", "H-E-B", "H-E-B", "Fresh vegetables", "Produce", hebHub),
        .init("H-E-B Frozen French Fries Garlic and Herb", "H-E-B", "H-E-B", "Frozen potatoes", "Frozen", hebHub),
        .init("Hill Country Fare Diced Tomatoes", "Hill Country Fare", "H-E-B", "Canned tomatoes", "Canned & Jarred", hebHub),
        .init("Hill Country Fare Cream Style Corn", "Hill Country Fare", "H-E-B", "Canned vegetables", "Canned & Jarred", hebHub),
        .init("Hill Country Fare Whole Kernel Corn", "Hill Country Fare", "H-E-B", "Canned vegetables", "Canned & Jarred", hebHub),
        .init("Hill Country Fare Clover Honey", "Hill Country Fare", "H-E-B", "Honey", "Baking", hebHub),
        .init("Hill Country Fare Classic Trail Mix", "Hill Country Fare", "H-E-B", "Nuts and trail mix", "Snacks", hebHub),
        .init("Hill Country Fare Ground Coffee", "Hill Country Fare", "H-E-B", "Coffee", "Beverages", hebHub),
        .init("Hill Country Fare Seasoned Beef for Fajitas", "Hill Country Fare", "H-E-B", "Fresh beef", "Meat & Seafood", hebHub),
        .init("Hill Country Fare Frozen Waffle Fries", "Hill Country Fare", "H-E-B", "Frozen potatoes", "Frozen", hebHub),
        .init("Hill Country Fare Teriyaki Stir Fry Sauce", "Hill Country Fare", "H-E-B", "Sauces", "International", hebHub),
        .init("Central Market Coconut Water", "Central Market", "Central Market", "Coconut water", "Beverages", hebHub),
        .init("Central Market Fresh Mozzarella", "Central Market", "Central Market", "Cheese", "Dairy & Eggs", hebHub),
        .init("Central Market Hatch Green Chile Queso", "Central Market", "Central Market", "Dips and queso", "Deli & Prepared Foods", hebHub),
        .init("True Texas BBQ Dill Pickle Chips", "True Texas BBQ", "H-E-B", "Pickles", "Canned & Jarred", hebHub),

        // ALDI exclusive brands
        .init("Friendly Farms Whole Milk", "Friendly Farms", "ALDI", "Milk", "Dairy & Eggs", aldiBrands),
        .init("Friendly Farms Plain Greek Yogurt", "Friendly Farms", "ALDI", "Yogurt", "Dairy & Eggs", aldiBrands),
        .init("Friendly Farms Sour Cream", "Friendly Farms", "ALDI", "Sour cream", "Dairy & Eggs", aldiBrands),
        .init("Countryside Creamery Salted Butter", "Countryside Creamery", "ALDI", "Butter", "Dairy & Eggs", aldiBrands),
        .init("Goldhen Grade A Large Eggs", "Goldhen", "ALDI", "Eggs", "Dairy & Eggs", aldiBrands),
        .init("Happy Farms Shredded Cheddar Cheese", "Happy Farms", "ALDI", "Cheese", "Dairy & Eggs", aldiBrands),
        .init("Emporium Selection Havarti Cheese", "Emporium Selection", "ALDI", "Specialty cheese", "Dairy & Eggs", aldiBrands),
        .init("Clancy's Original Kettle Chips", "Clancy's", "ALDI", "Potato chips", "Snacks", aldiBrands),
        .init("Clancy's Restaurant Style Tortilla Chips", "Clancy's", "ALDI", "Tortilla chips", "Snacks", aldiBrands),
        .init("Clancy's Pretzel Sticks", "Clancy's", "ALDI", "Pretzels", "Snacks", aldiBrands),
        .init("Happy Harvest Whole Kernel Corn", "Happy Harvest", "ALDI", "Canned vegetables", "Canned & Jarred", aldiBrands),
        .init("Happy Harvest Cut Green Beans", "Happy Harvest", "ALDI", "Canned vegetables", "Canned & Jarred", aldiBrands),
        .init("Happy Harvest Tomato Sauce", "Happy Harvest", "ALDI", "Tomato sauce", "Canned & Jarred", aldiBrands),
        .init("Fremont Fish Market Wild Caught Pink Salmon", "Fremont Fish Market", "ALDI", "Frozen seafood", "Frozen", aldiBrands),
        .init("Kirkwood Chicken", "Kirkwood", "ALDI", "Chicken", "Meat & Seafood", aldiBrands),
        .init("Never Any Oven Roasted Turkey", "Never Any!", "ALDI", "Deli meat", "Deli & Prepared Foods", aldiBrands),
        .init("Appleton Farms Thick Sliced Bacon", "Appleton Farms", "ALDI", "Bacon", "Meat & Seafood", aldiBrands),
        .init("Mama Cozzi's Pepperoni Pizza", "Mama Cozzi's Pizza Kitchen", "ALDI", "Frozen pizza", "Frozen", aldiBrands),
        .init("Park Street Deli Classic Guacamole", "Park Street Deli", "ALDI", "Dips and guacamole", "Deli & Prepared Foods", aldiBrands),
        .init("Park Street Deli Hummus", "Park Street Deli", "ALDI", "Dips and hummus", "Deli & Prepared Foods", aldiBrands),
        .init("Simply Nature Organic Hummus", "Simply Nature", "ALDI", "Dips and hummus", "Deli & Prepared Foods", aldiBrands),
        .init("Simply Nature Organic Spring Mix", "Simply Nature", "ALDI", "Fresh vegetables", "Produce", aldiBrands),
        .init("Simply Nature Organic Tortilla Chips", "Simply Nature", "ALDI", "Tortilla chips", "Snacks", aldiBrands),
        .init("Simply Nature Organic Coconut Oil", "Simply Nature", "ALDI", "Cooking oil", "Condiments & Spices", aldiBrands),
        .init("Specially Selected Brioche Buns", "Specially Selected", "ALDI", "Bread", "Bakery", aldiBrands),
        .init("Specially Selected Smoked Atlantic Salmon", "Specially Selected", "ALDI", "Smoked salmon", "Meat & Seafood", aldiBrands),
        .init("Specially Selected Balsamic Vinaigrette", "Specially Selected", "ALDI", "Salad dressing", "Condiments & Spices", aldiBrands),
        .init("Specially Selected Naan Bread", "Specially Selected", "ALDI", "Flatbread", "Bakery", aldiBrands),
        .init("Millville Fruit Rounds Cereal", "Millville", "ALDI", "Breakfast cereal", "Pasta, Rice & Grains", aldiBrands),
        .init("Millville Buttermilk Pancake Mix", "Millville", "ALDI", "Pancake mix", "Baking", aldiBrands),
        .init("Stonemill Garlic Powder", "Stonemill", "ALDI", "Spices", "Condiments & Spices", aldiBrands),
        .init("Stonemill Parsley Flakes", "Stonemill", "ALDI", "Spices", "Condiments & Spices", aldiBrands),
        .init("liveGfree Multiseed Crackers", "liveGfree", "ALDI", "Gluten free crackers", "Snacks", aldiBrands),
        .init("L'oven Fresh Everything Bagels", "L'oven Fresh", "ALDI", "Bagels", "Bakery", aldiBrands),
        .init("Moser Roth Premium Chocolate", "Moser Roth", "ALDI", "Chocolate", "Snacks", aldiBrands),
        .init("PurAqua Sparkling Water", "PurAqua", "ALDI", "Sparkling water", "Beverages", aldiBrands),
        .init("Earth Grown Veggie Burgers", "Earth Grown", "ALDI", "Plant based food", "Frozen", aldiBrands),
        .init("Little Journey Organic Fruit and Vegetable Puree", "Little Journey", "ALDI", "Baby food", "Baby Food", aldiBrands),
        .init("Barissimo Ground Coffee", "Barissimo", "ALDI", "Coffee", "Beverages", aldiBrands),
        .init("Burman's Condiments", "Burman's", "ALDI", "Condiments", "Condiments & Spices", aldiBrands),
        .init("Chef's Cupboard Beef Broth", "Chef's Cupboard", "ALDI", "Broth and stock", "Canned & Jarred", aldiBrands),
        .init("Priano Pasta", "Priano", "ALDI", "Pasta", "Pasta, Rice & Grains", aldiBrands),
        .init("Pueblo Lindo Tortillas", "Pueblo Lindo", "ALDI", "Tortillas", "International", aldiBrands),
        .init("Southern Grove Nuts", "Southern Grove", "ALDI", "Nuts", "Snacks", aldiBrands),
        .init("Tuscan Garden Salad Dressing", "Tuscan Garden", "ALDI", "Salad dressing", "Condiments & Spices", aldiBrands)
    ]

    static func records(matching rawQuery: String, limit: Int) -> [CatalogRecord] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let stores = filtered(storeNames, by: query)
        let brands = filtered(brandNames, by: query)
        let products = retailerProducts.filter { $0.matches(query) }
        let safeLimit = max(1, limit)
        let storeLimit = min(stores.count, max(1, safeLimit / 3))
        let brandLimit = min(brands.count, max(0, safeLimit / 3))
        let productLimit = min(products.count, max(0, safeLimit - storeLimit - brandLimit))
        var rows = stores.prefix(storeLimit).map {
            CatalogRecord(kind: .store, name: $0, store: $0, source: .stockedReference, confidence: 0.92)
        }
        rows += brands.prefix(brandLimit).map {
            CatalogRecord(kind: .brand, name: $0, source: .stockedReference, confidence: 0.92)
        }
        rows += products.prefix(productLimit).map { product in
            CatalogRecord(kind: .product, name: product.name, brand: product.brand,
                          category: product.category, aisle: product.aisle, store: product.store,
                          source: .stockedReference, sourceURL: product.sourceURL, confidence: 0.94)
        }
        return rows
    }

    private static let hebHub = "https://www.heb.com/discover/own-brand-hub"
    private static let aldiBrands = "https://www.aldi.us/store/aldi/pages/aldi-brands"

    private struct RetailerProduct: Sendable {
        var name: String
        var brand: String
        var store: String
        var category: String
        var aisle: String
        var sourceURL: String

        init(_ name: String, _ brand: String, _ store: String, _ category: String,
             _ aisle: String, _ sourceURL: String) {
            self.name = name; self.brand = brand; self.store = store
            self.category = category; self.aisle = aisle; self.sourceURL = sourceURL
        }

        func matches(_ query: String) -> Bool {
            guard !query.isEmpty else { return true }
            return [name, brand, store, category, aisle].contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private static func filtered(_ values: [String], by query: String) -> [String] {
        guard !query.isEmpty else { return values }
        return values.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func lines(from value: String) -> [String] {
        value.split(whereSeparator: \.isNewline).map(String.init)
    }
}
