import Foundation

@main struct RecipeInterchangeChecks {
    static func main() throws {
        let source = """
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"Not a recipe"},
          {"@type":["Thing","Recipe"],"name":"Example lunch","url":"https://food.example/Recipe?flavor=A",
           "image":{"@type":"ImageObject","url":"https://food.example/photo.jpg","creditText":"Example photographer","license":"https://example.org/photo-license"},
           "author":[{"@type":"Person","name":"Example cook"}],"license":"https://example.org/recipe-license",
           "recipeIngredient":["1 cup rice","2 cups water"],
           "recipeInstructions":[{"@type":"HowToSection","name":"Prepare","itemListElement":[{"@type":"HowToStep","text":"Rinse the rice."},{"@type":"HowToStep","text":"Cook with water."}]}],
           "recipeYield":"2","prepTime":"PT5M","cookTime":"PT20M","nutrition":{"@type":"NutritionInformation","calories":"150 kcal"}}
        ]}
        """
        let recipes = try MacRecipeInterchange.decode(Data(source.utf8))
        precondition(recipes.count == 1)
        let recipe = recipes[0]
        precondition(recipe.title == "Example lunch")
        precondition(recipe.instructions == ["Prepare:", "Rinse the rice.", "Cook with water."])
        precondition(recipe.ingredients == ["1 cup rice", "2 cups water"])
        precondition(recipe.author == "Example cook")
        precondition(recipe.imageCredit.contains("Example photographer"))
        precondition(recipe.license == "https://example.org/recipe-license")
        precondition(recipe.contentProblems.isEmpty)
        precondition(recipe.nutrition == ["calories": "150 kcal"])
        let reread = try MacRecipeInterchange.decode(MacRecipeInterchange.encode(recipes))[0]
        precondition(reread.instructions == recipe.instructions)
        precondition(reread.ingredients == recipe.ingredients)
        precondition(reread.imageCredit == recipe.imageCredit)
        precondition(reread.license == recipe.license)
        precondition(reread.sourceURL == recipe.sourceURL)
        precondition(reread.nutrition == recipe.nutrition)
        precondition(MacRecipeInterchange.sourceKey("https://FOOD.example/Recipe#ingredients") == "https://food.example/Recipe")
        precondition(MacRecipeInterchange.sourceKey("https://food.example/Recipe") != MacRecipeInterchange.sourceKey("https://food.example/recipe"))
        for url in ["http://food.example/recipe", "https://user:pass@food.example/x", "https://localhost/image", "https://127.0.0.1/image", "https://[::1]/image", "file:///private/image"] {
            precondition(MacRecipeInterchange.secureURL(url) == nil)
        }
        let incomplete = try MacRecipeInterchange.decode(Data("{\"@type\":\"Recipe\",\"name\":\"Incomplete\"}".utf8))[0]
        precondition(incomplete.contentProblems.count == 3)
        precondition(incomplete.publicationProblems.count == 1)
        for input in ["{}", "[]", "{\"@type\":\"Product\",\"name\":\"Rice\"}", "not json"] {
            do { _ = try MacRecipeInterchange.decode(Data(input.utf8)); preconditionFailure("Unexpected accepted input") }
            catch {}
        }
        do {
            _ = try MacRecipeInterchange.decode(Data(repeating: 65, count: MacRecipeInterchange.byteLimit + 1))
            preconditionFailure("Oversized data accepted")
        } catch {}
        let large = Array(repeating: "{\"@type\":\"Recipe\",\"name\":\"Recipe\"}", count: 251).joined(separator: ",")
        do { _ = try MacRecipeInterchange.decode(Data(("[" + large + "]").utf8)); preconditionFailure("Oversized batch accepted") }
        catch {}
        print("Recipe interchange: nested JSON-LD, credits, round-trip, source identity, rejected files and bounds passed; no network requests")
    }
}
