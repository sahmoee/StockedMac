import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DesktopExperienceRegressionTests(unittest.TestCase):
    def test_delete_requires_confirmation_and_explicit_selection(self):
        source = self.read("StockedMac/Views/MacRecipesView.swift")
        self.assertIn('.confirmationDialog("Delete recipe?"', source)
        handler = source.split("private func deleteCurrentRecipe()",1)[1].split("private func preview",1)[0]
        self.assertIn("guard let selection", handler)
        self.assertIn("pendingDeletion = recipe", handler)
        self.assertNotIn("store.deleteRecipe", handler)

    def test_preview_identity_and_new_library_tools(self):
        source = self.read("StockedMac/Views/MacRecipesView.swift")
        self.assertIn('Recipe-\\(recipe.id.uuidString).txt',source)
        for label in ["Oldest added", "Recently updated", "Fewest ingredients", "Copy source link", "Reset search and filters", "Quick Look unavailable"]:
            self.assertIn(label,source)

    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_visible_sidebar_shortcuts_are_unique(self):
        source = self.read("StockedMac/Views/MacRootView.swift")
        expected = {
            "recipes": "1",
            "browse": "2",
            "catalog": "3",
            "sync": "4",
        }
        for section, shortcut in expected.items():
            pattern = rf"case \.{section}:\s+return \"{shortcut}\""
            self.assertRegex(source, pattern)
        sections = re.search(r"recipeManagerSections: \[MacSection\] = \[(.*?)\]", source).group(1)
        self.assertNotIn(".categories", sections)

    def test_category_discovery_stays_background_only(self):
        root = self.read("StockedMac/Views/MacRootView.swift")
        model = self.read("StockedMac/Harvest/HarvestModel.swift")
        self.assertNotIn('case categories = "Categories"', root)
        self.assertIn("recordCategories(outcome.categories", model)
        self.assertIn("rebuildCuisineRecipeCache", model)

    def test_desktop_state_is_shared_by_every_scene(self):
        app = self.read("StockedMac/StockedMacApp.swift")
        self.assertIn("@State private var desktop = MacDesktopExperience()", app)
        self.assertGreaterEqual(app.count(".environment(desktop)"), 3)
        self.assertIn('WindowGroup("Recipe", id: "recipe", for: UUID.self)', app)
        self.assertIn('MenuBarExtra("Stocked"', app)

    def test_import_center_uses_existing_safe_pipelines(self):
        panels = self.read("StockedMac/Views/MacDesktopPanels.swift")
        self.assertIn("harvest.appendImportURLs", panels)
        self.assertIn("harvest.importURLs()", panels)
        self.assertIn("store.importData", panels)
        self.assertIn("MacRecipeMaintenance.removeFromCSV", panels)
        self.assertNotIn("store.recipes =", panels)

    def test_recipe_workspace_retains_accessible_adaptive_tools(self):
        recipes = self.read("StockedMac/Views/MacRecipesView.swift")
        for feature in [
            "HSplitView", ".searchable(", "Table(rows", ".inspector(",
            ".quickLookPreview(", ".onDeleteCommand", ".draggable(",
            'openWindow(id: "recipe"',
        ]:
            self.assertIn(feature, recipes)
        self.assertNotRegex(recipes, r"\.frame\(width:\s*330\)")

    def test_file_menu_exposes_backup_and_recipe_maintenance(self):
        commands = self.read("StockedMac/Views/MacCommands.swift")
        for label in [
            "Import Center…", "Import Stocked Backup…", "Export Stocked Backup…",
            "Export recipes as CSV…", "Remove recipes from a CSV…",
        ]:
            self.assertIn(label, commands)


if __name__ == "__main__":
    unittest.main()
