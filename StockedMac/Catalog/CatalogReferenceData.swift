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

    static func records(matching rawQuery: String, limit: Int) -> [CatalogRecord] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let stores = filtered(storeNames, by: query)
        let brands = filtered(brandNames, by: query)
        let safeLimit = max(1, limit)
        let storeLimit = min(stores.count, max(1, safeLimit / 2))
        let brandLimit = min(brands.count, safeLimit - storeLimit)
        var rows = stores.prefix(storeLimit).map {
            CatalogRecord(kind: .store, name: $0, store: $0, source: .stockedReference, confidence: 0.92)
        }
        rows += brands.prefix(brandLimit).map {
            CatalogRecord(kind: .brand, name: $0, source: .stockedReference, confidence: 0.92)
        }
        return rows
    }

    private static func filtered(_ values: [String], by query: String) -> [String] {
        guard !query.isEmpty else { return values }
        return values.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func lines(from value: String) -> [String] {
        value.split(whereSeparator: \.isNewline).map(String.init)
    }
}
