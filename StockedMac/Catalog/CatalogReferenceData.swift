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
    Sam's Choice
    Waterfront Bistro
    Primo Taglio
    Nature's Promise
    Taste of Inspirations
    Guaranteed Value
    CareOne
    Wellsley Farms
    Berkley Jensen
    Wholesome Pantry
    Paperbird
    True Goodness by Meijer
    Meijer Organics
    Frederik's by Meijer
    Purple Cow
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
        .init("Tuscan Garden Salad Dressing", "Tuscan Garden", "ALDI", "Salad dressing", "Condiments & Spices", aldiBrands),

        // Walmart own brands
        .init("Great Value Whole Milk", "Great Value", "Walmart", "Milk", "Dairy & Eggs", walmartHub),
        .init("Great Value Large White Eggs", "Great Value", "Walmart", "Eggs", "Dairy & Eggs", walmartHub),
        .init("Great Value Shredded Mild Cheddar Cheese", "Great Value", "Walmart", "Cheese", "Dairy & Eggs", walmartHub),
        .init("Great Value Creamy Peanut Butter", "Great Value", "Walmart", "Peanut butter", "Condiments & Spices", walmartHub),
        .init("Great Value Thin Spaghetti", "Great Value", "Walmart", "Pasta", "Pasta, Rice & Grains", walmartHub),
        .init("Marketside Caesar Salad Kit", "Marketside", "Walmart", "Salad kit", "Produce", walmartHub),
        .init("Marketside Brioche Hamburger Buns", "Marketside", "Walmart", "Bread", "Bakery", walmartHub),
        .init("Freshness Guaranteed Rotisserie Chicken", "Freshness Guaranteed", "Walmart", "Prepared chicken", "Deli & Prepared Foods", walmartHub),
        .init("bettergoods Plant-Based Oat Milk", "bettergoods", "Walmart", "Plant based milk", "Dairy & Eggs", walmartHub),
        .init("Sam's Choice Cola", "Sam's Choice", "Walmart", "Soda", "Beverages", walmartHub),

        // Target own brands
        .init("Good & Gather Whole Milk", "Good & Gather", "Target", "Milk", "Dairy & Eggs", targetHub),
        .init("Good & Gather Large Grade A Eggs", "Good & Gather", "Target", "Eggs", "Dairy & Eggs", targetHub),
        .init("Good & Gather Organic Baby Spinach", "Good & Gather", "Target", "Fresh vegetables", "Produce", targetHub),
        .init("Good & Gather Thin Spaghetti", "Good & Gather", "Target", "Pasta", "Pasta, Rice & Grains", targetHub),
        .init("Good & Gather Marinara Pasta Sauce", "Good & Gather", "Target", "Pasta sauce", "Canned & Jarred", targetHub),
        .init("Good & Gather Kettle Cooked Potato Chips", "Good & Gather", "Target", "Potato chips", "Snacks", targetHub),
        .init("Favorite Day Chocolate Chip Cookies", "Favorite Day", "Target", "Cookies", "Bakery", targetHub),
        .init("Favorite Day Vanilla Ice Cream", "Favorite Day", "Target", "Ice cream", "Frozen", targetHub),
        .init("Market Pantry Shredded Cheddar Cheese", "Market Pantry", "Target", "Cheese", "Dairy & Eggs", targetHub),
        .init("Good & Gather Sparkling Water", "Good & Gather", "Target", "Sparkling water", "Beverages", targetHub),

        // Kroger own brands
        .init("Kroger Whole Milk", "Kroger", "Kroger", "Milk", "Dairy & Eggs", krogerHub),
        .init("Kroger Large Eggs", "Kroger", "Kroger", "Eggs", "Dairy & Eggs", krogerHub),
        .init("Kroger Shredded Cheddar Cheese", "Kroger", "Kroger", "Cheese", "Dairy & Eggs", krogerHub),
        .init("Simple Truth Organic Baby Spinach", "Simple Truth", "Kroger", "Fresh vegetables", "Produce", krogerHub),
        .init("Simple Truth Organic Black Beans", "Simple Truth", "Kroger", "Canned beans", "Canned & Jarred", krogerHub),
        .init("Private Selection Marinara Pasta Sauce", "Private Selection", "Kroger", "Pasta sauce", "Canned & Jarred", krogerHub),
        .init("Private Selection Vanilla Bean Ice Cream", "Private Selection", "Kroger", "Ice cream", "Frozen", krogerHub),
        .init("Home Chef Heat & Eat Meal", "Home Chef", "Kroger", "Prepared meals", "Deli & Prepared Foods", krogerHub),
        .init("Kroger Thin Spaghetti", "Kroger", "Kroger", "Pasta", "Pasta, Rice & Grains", krogerHub),
        .init("Smart Way Potato Chips", "Smart Way", "Kroger", "Potato chips", "Snacks", krogerHub),

        // Costco — Kirkland Signature
        .init("Kirkland Signature Organic Whole Milk", "Kirkland Signature", "Costco", "Milk", "Dairy & Eggs", costcoHub),
        .init("Kirkland Signature Cage Free Eggs", "Kirkland Signature", "Costco", "Eggs", "Dairy & Eggs", costcoHub),
        .init("Kirkland Signature Organic Ground Beef", "Kirkland Signature", "Costco", "Ground beef", "Meat & Seafood", costcoHub),
        .init("Kirkland Signature Rotisserie Chicken", "Kirkland Signature", "Costco", "Prepared chicken", "Deli & Prepared Foods", costcoHub),
        .init("Kirkland Signature Organic Extra Virgin Olive Oil", "Kirkland Signature", "Costco", "Olive oil", "Condiments & Spices", costcoHub),
        .init("Kirkland Signature Organic Peanut Butter", "Kirkland Signature", "Costco", "Peanut butter", "Condiments & Spices", costcoHub),
        .init("Kirkland Signature Ground Coffee", "Kirkland Signature", "Costco", "Coffee", "Beverages", costcoHub),
        .init("Kirkland Signature Semi-Sweet Chocolate Chips", "Kirkland Signature", "Costco", "Baking chips", "Baking", costcoHub),
        .init("Kirkland Signature Trail Mix", "Kirkland Signature", "Costco", "Trail mix", "Snacks", costcoHub),
        .init("Kirkland Signature Purified Water", "Kirkland Signature", "Costco", "Bottled water", "Beverages", costcoHub),

        // Publix own brands
        .init("Publix Whole Milk", "Publix", "Publix", "Milk", "Dairy & Eggs", publixHub),
        .init("Publix Large Eggs", "Publix", "Publix", "Eggs", "Dairy & Eggs", publixHub),
        .init("Publix Deli Chicken Tender Sub", "Publix Deli", "Publix", "Prepared sandwiches", "Deli & Prepared Foods", publixHub),
        .init("Publix Bakery Chocolate Chip Cookies", "Publix Bakery", "Publix", "Cookies", "Bakery", publixHub),
        .init("Publix Premium Vanilla Ice Cream", "Publix Premium", "Publix", "Ice cream", "Frozen", publixHub),
        .init("Publix GreenWise Organic Baby Spinach", "Publix GreenWise", "Publix", "Fresh vegetables", "Produce", publixHub),
        .init("Publix GreenWise Organic Black Beans", "Publix GreenWise", "Publix", "Canned beans", "Canned & Jarred", publixHub),
        .init("Publix Thin Spaghetti", "Publix", "Publix", "Pasta", "Pasta, Rice & Grains", publixHub),
        .init("Publix Kettle Cooked Potato Chips", "Publix", "Publix", "Potato chips", "Snacks", publixHub),
        .init("Publix Shredded Cheddar Cheese", "Publix", "Publix", "Cheese", "Dairy & Eggs", publixHub),

        // Sam's Club — Member's Mark
        .init("Member's Mark Whole Milk", "Member's Mark", "Sam's Club", "Milk", "Dairy & Eggs", samsHub),
        .init("Member's Mark Cage Free Large Eggs", "Member's Mark", "Sam's Club", "Eggs", "Dairy & Eggs", samsHub),
        .init("Member's Mark Rotisserie Chicken", "Member's Mark", "Sam's Club", "Prepared chicken", "Deli & Prepared Foods", samsHub),
        .init("Member's Mark Purified Water", "Member's Mark", "Sam's Club", "Bottled water", "Beverages", samsHub),
        .init("Member's Mark Organic Extra Virgin Olive Oil", "Member's Mark", "Sam's Club", "Olive oil", "Condiments & Spices", samsHub),
        .init("Member's Mark Ground Coffee", "Member's Mark", "Sam's Club", "Coffee", "Beverages", samsHub),
        .init("Member's Mark Sea Salt Kettle Chips", "Member's Mark", "Sam's Club", "Potato chips", "Snacks", samsHub),
        .init("Member's Mark Shredded Mozzarella Cheese", "Member's Mark", "Sam's Club", "Cheese", "Dairy & Eggs", samsHub),

        // Albertsons / Safeway own brands
        .init("Signature Select Whole Milk", "Signature Select", "Albertsons", "Milk", "Dairy & Eggs", albertsonsHub),
        .init("Lucerne Large Eggs", "Lucerne", "Albertsons", "Eggs", "Dairy & Eggs", albertsonsHub),
        .init("Lucerne Shredded Cheddar Cheese", "Lucerne", "Albertsons", "Cheese", "Dairy & Eggs", albertsonsHub),
        .init("O Organics Organic Baby Spinach", "O Organics", "Albertsons", "Fresh vegetables", "Produce", albertsonsHub),
        .init("O Organics Organic Black Beans", "O Organics", "Albertsons", "Canned beans", "Canned & Jarred", albertsonsHub),
        .init("Open Nature Boneless Skinless Chicken Breast", "Open Nature", "Albertsons", "Chicken", "Meat & Seafood", albertsonsHub),
        .init("Signature Select Marinara Pasta Sauce", "Signature Select", "Albertsons", "Pasta sauce", "Canned & Jarred", albertsonsHub),
        .init("Primo Taglio Sliced Deli Turkey", "Primo Taglio", "Albertsons", "Deli meat", "Deli & Prepared Foods", albertsonsHub),
        .init("Signature Select Kettle Potato Chips", "Signature Select", "Albertsons", "Potato chips", "Snacks", albertsonsHub),
        .init("Signature Select Sparkling Water", "Signature Select", "Albertsons", "Sparkling water", "Beverages", albertsonsHub),

        // Ahold Delhaize (Food Lion / Stop & Shop / Giant)
        .init("Nature's Promise Organic Whole Milk", "Nature's Promise", "Food Lion", "Milk", "Dairy & Eggs", aholdHub),
        .init("Nature's Promise Organic Large Eggs", "Nature's Promise", "Stop & Shop", "Eggs", "Dairy & Eggs", aholdHub),
        .init("Nature's Promise Organic Baby Spinach", "Nature's Promise", "Giant Food", "Fresh vegetables", "Produce", aholdHub),
        .init("Taste of Inspirations Brioche Buns", "Taste of Inspirations", "Stop & Shop", "Bread", "Bakery", aholdHub),
        .init("Taste of Inspirations Aged Sharp Cheddar", "Taste of Inspirations", "Giant Food", "Cheese", "Dairy & Eggs", aholdHub),
        .init("Guaranteed Value Thin Spaghetti", "Guaranteed Value", "Food Lion", "Pasta", "Pasta, Rice & Grains", aholdHub),
        .init("Nature's Promise Organic Black Beans", "Nature's Promise", "Food Lion", "Canned beans", "Canned & Jarred", aholdHub),
        .init("Nature's Promise Kettle Potato Chips", "Nature's Promise", "Stop & Shop", "Potato chips", "Snacks", aholdHub),

        // Meijer own brands
        .init("Meijer Whole Milk", "Meijer", "Meijer", "Milk", "Dairy & Eggs", meijerHub),
        .init("Meijer Large Eggs", "Meijer", "Meijer", "Eggs", "Dairy & Eggs", meijerHub),
        .init("Meijer Shredded Cheddar Cheese", "Meijer", "Meijer", "Cheese", "Dairy & Eggs", meijerHub),
        .init("True Goodness by Meijer Organic Baby Spinach", "True Goodness by Meijer", "Meijer", "Fresh vegetables", "Produce", meijerHub),
        .init("True Goodness by Meijer Organic Black Beans", "True Goodness by Meijer", "Meijer", "Canned beans", "Canned & Jarred", meijerHub),
        .init("Meijer Marinara Pasta Sauce", "Meijer", "Meijer", "Pasta sauce", "Canned & Jarred", meijerHub),
        .init("Purple Cow Vanilla Ice Cream", "Purple Cow", "Meijer", "Ice cream", "Frozen", meijerHub),
        .init("Frederik's by Meijer Brie Cheese", "Frederik's by Meijer", "Meijer", "Specialty cheese", "Dairy & Eggs", meijerHub),
        .init("Meijer Thin Spaghetti", "Meijer", "Meijer", "Pasta", "Pasta, Rice & Grains", meijerHub),
        .init("Meijer Kettle Potato Chips", "Meijer", "Meijer", "Potato chips", "Snacks", meijerHub)
    ]

    static func records(matching rawQuery: String, limit: Int, homeState: String? = nil) -> [CatalogRecord] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var stores = filtered(storeNames, by: query)
        if let homeState, !homeState.isEmpty {
            let code = stateCode(homeState)
            stores = stores.enumerated()
                .sorted { storeRank($0.element, code) != storeRank($1.element, code)
                    ? storeRank($0.element, code) < storeRank($1.element, code)
                    : $0.offset < $1.offset }
                .map(\.element)
        }
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

    // MARK: - Regional weighting (Improvement 1)

    /// Coarse state-level footprint for the clearly-regional banners, keyed by the exact name used
    /// in `storeNames`. Stores absent here are treated as national and never demoted.
    private static let storeRegions: [String: Set<String>] = [
        "H-E-B": ["TX"], "H-E-B plus!": ["TX"], "Central Market": ["TX"], "Joe V's Smart Shop": ["TX"],
        "Mi Tienda": ["TX"], "United Supermarkets": ["TX"], "Tom Thumb": ["TX"], "Randalls": ["TX"],
        "Publix": ["FL", "GA", "AL", "SC", "NC", "TN", "VA", "KY"],
        "Winn-Dixie": ["FL", "GA", "AL", "LA", "MS"], "Harveys Supermarket": ["FL", "GA", "SC"],
        "Meijer": ["MI", "OH", "IN", "IL", "KY", "WI"], "Woodman's Markets": ["WI", "IL"],
        "Food Lion": ["NC", "SC", "VA", "GA", "TN", "PA", "MD", "DE", "WV", "KY"],
        "Giant Food": ["MD", "VA", "DC", "DE"], "Giant Eagle": ["PA", "OH", "WV", "IN", "MD"],
        "Stop & Shop": ["MA", "CT", "RI", "NY", "NJ"], "Hannaford": ["ME", "NH", "VT", "MA", "NY"],
        "ShopRite": ["NJ", "NY", "CT", "PA", "DE", "MD"], "Wegmans": ["NY", "NJ", "PA", "MD", "VA", "MA", "NC", "DE"],
        "Hy-Vee": ["IA", "IL", "MO", "KS", "NE", "MN", "SD", "WI", "IN"],
        "WinCo Foods": ["ID", "WA", "OR", "CA", "NV", "UT", "TX", "AZ", "OK", "MT"],
        "Vons": ["CA", "NV"], "Ralphs": ["CA"], "Jewel-Osco": ["IL", "IN", "IA"], "Acme Markets": ["PA", "NJ", "DE", "MD", "NY", "CT"],
        "Fred Meyer": ["OR", "WA", "ID", "AK"], "QFC": ["WA", "OR"], "King Soopers": ["CO"], "Fry's Food Stores": ["AZ"],
        "Harris Teeter": ["NC", "SC", "VA", "GA", "MD", "DE", "FL", "DC"], "Ingles Markets": ["NC", "SC", "GA", "TN", "VA", "AL"],
    ]

    private static let stateNameToCode: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR", "california": "CA",
        "colorado": "CO", "connecticut": "CT", "delaware": "DE", "district of columbia": "DC",
        "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID", "illinois": "IL",
        "indiana": "IN", "iowa": "IA", "kansas": "KS", "kentucky": "KY", "louisiana": "LA",
        "maine": "ME", "maryland": "MD", "massachusetts": "MA", "michigan": "MI", "minnesota": "MN",
        "mississippi": "MS", "missouri": "MO", "montana": "MT", "nebraska": "NE", "nevada": "NV",
        "new hampshire": "NH", "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
        "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK", "oregon": "OR",
        "pennsylvania": "PA", "rhode island": "RI", "south carolina": "SC", "south dakota": "SD",
        "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT", "virginia": "VA",
        "washington": "WA", "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
    ]

    /// Normalize a US state input (two-letter code or full name) to its uppercase code.
    static func stateCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 2 { return trimmed.uppercased() }
        return stateNameToCode[trimmed.lowercased()] ?? trimmed.uppercased()
    }

    /// 0 = operates in the home state, 1 = national (unmapped), 2 = out-of-region.
    private static func storeRank(_ storeName: String, _ code: String) -> Int {
        guard let footprint = storeRegions[storeName], !footprint.isEmpty else { return 1 }
        return footprint.contains(code) ? 0 : 2
    }

    // MARK: - Canonical product key + cross-store dedup (Improvement 2)

    private static let canonicalNoise: Set<String> = [
        "organic", "original", "classic", "premium", "natural", "fresh", "whole", "large", "small",
        "kettle", "cooked", "style", "value", "brand", "the", "by", "of", "with", "and", "grade", "a",
        "select", "signature", "family", "size", "pack", "sliced", "shredded", "boneless", "skinless",
    ]

    private static func canonicalNormalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: #"[^a-zA-Z0-9]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Reduce a branded product name to a normalized generic key so store-brand equivalents across
    /// banners ("Kroger Whole Milk", "Great Value Whole Milk") collapse for dedup/merge.
    static func canonicalKey(_ name: String) -> String {
        var value = " " + canonicalNormalize(name) + " "
        for brand in brandNames.sorted(by: { $0.count > $1.count }) {
            let token = canonicalNormalize(brand)
            guard !token.isEmpty, value.contains(" " + token + " ") else { continue }
            value = value.replacingOccurrences(of: " " + token + " ", with: " ")
        }
        let words = value.split(separator: " ").map(String.init)
            .filter { !$0.isEmpty && !canonicalNoise.contains($0) }
        return words.joined(separator: " ")
    }

    /// Every reference product that shares a product's canonical identity — the store-brand
    /// equivalents of the same item across retailers. Used to merge rather than duplicate records.
    static func productEquivalents(for name: String) -> [(name: String, brand: String, store: String)] {
        let key = canonicalKey(name)
        guard !key.isEmpty else { return [] }
        return retailerProducts
            .filter { canonicalKey($0.name) == key }
            .map { (name: $0.name, brand: $0.brand, store: $0.store) }
    }

    private static let hebHub = "https://www.heb.com/discover/own-brand-hub"
    private static let aldiBrands = "https://www.aldi.us/store/aldi/pages/aldi-brands"
    private static let walmartHub = "https://www.walmart.com/cp/private-brands/1224932"
    private static let targetHub = "https://www.target.com/c/our-own-brands/-/N-4tuxs"
    private static let krogerHub = "https://www.kroger.com/pr/our-brands"
    private static let costcoHub = "https://www.costco.com/kirkland-signature.html"
    private static let publixHub = "https://www.publix.com/products-services/publix-brand"
    private static let samsHub = "https://www.samsclub.com/b/members-mark"
    private static let albertsonsHub = "https://www.albertsons.com/our-brands.html"
    private static let aholdHub = "https://www.foodlion.com/brands/"
    private static let meijerHub = "https://www.meijer.com/shopping/meijer-brands.html"

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
