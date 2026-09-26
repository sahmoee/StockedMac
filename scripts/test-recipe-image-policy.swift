// Native image policy check. Compile this fixture with production MacRecipeImagePolicy.swift.
// Minimal unrelated model/transport definitions keep this independent from app startup.
import Foundation
struct UserRecipe: Sendable {
    var imageData: Data?
    var imageURL: String?
    var sourceURL: String?
    var imageValidatedAt: Date?
}
enum MacPortableRecipePolicy { static func allowsCatalogueSharing(_ recipe: UserRecipe) -> Bool { true } }
enum CompanionError: Error { case invalidURL(String), parseFailed(String) }
extension String { var nilIfBlank: String? { isEmpty ? nil : self } }
@main struct RecipeImagePolicyChecks {
    static func main() {
        let stock = "https://food.fnr.sndimg.com/content/dam/images/food/editorial/homepage/fn-feature.jpg.rend.hgtvcom.1280.1280.suffix/1474463768097.webp"
        for value in [stock, stock.replacingOccurrences(of: "1280.1280", with: "616.462"),
            stock.replacingOccurrences(of: "fn-feature", with: "fn%2Dfeature")] {
            precondition(!MacRecipeImagePolicy.isLikelyRecipeImageURL(value))
            precondition(!MacRecipeImagePolicy.hasRequiredImage(UserRecipe(imageData: Data(repeating: 1, count: 5000), imageURL: value,
                sourceURL: "https://www.foodnetwork.com/recipes/soup", imageValidatedAt: Date())))
        }
        let dish = "https://food.fnr.sndimg.com/content/dam/images/food/fullset/2018/4/1/2/LS-Library_Roasted-Garlic-Bread_s4x3.jpg.rend.hgtvcom.1280.1280.suffix/1522678795843.webp"
        precondition(MacRecipeImagePolicy.isLikelyRecipeImageURL(dish))
        precondition(MacRecipeImagePolicy.hasRequiredImage(UserRecipe(imageURL: dish,
            sourceURL: "https://www.foodnetwork.com/recipes/garlic-bread", imageValidatedAt: Date())))
        precondition(!MacRecipeImagePolicy.isKnownPublisherPlaceholder("https://other.example/content/dam/images/food/editorial/homepage/fn-feature.jpg"))
        print("Mac recipe image policy checks passed: stock artwork blocked; validated dish photos retained")
    }
}
