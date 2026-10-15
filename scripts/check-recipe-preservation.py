#!/usr/bin/env python3
"""Exercise the actual hydration policy with disposable recipe metadata."""
import pathlib, subprocess, tempfile
root=pathlib.Path(__file__).resolve().parents[1]
policy=(root/'StockedMac/Core/MacRecipeImagePolicy.swift').read_text().replace('nonisolated enum','enum')
fixtures='''
struct UserRecipe: Sendable { var id: Int; var imageData: Data?; var imageURL: String?; var sourceURL: String? }
enum CompanionError: Error { case invalidURL(String), parseFailed(String) }
extension String { var nilIfBlank: String? { isEmpty ? nil : self } }
@main struct Checks {
 static func main() async {
  let recipes = [UserRecipe(id: 1, sourceURL: "https://example.invalid/recipe"), UserRecipe(id: 2, imageURL: "http://example.invalid/image", sourceURL: "https://example.invalid/other")]
  for concurrency in [0, 1, 6] {
   let hydrated = await MacRecipeImagePolicy.hydrate(recipes, maximumConcurrent: concurrency)
   precondition(hydrated.map(\\.id) == [1,2], "Saved recipes must survive missing images and offline hydration")
  }
  print("3 actual hydration preservation checks passed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='stockedmac-hydration-') as d:
 p=pathlib.Path(d);(p/'checks.swift').write_text(policy+fixtures)
 subprocess.run([subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip(),'-parse-as-library','-sdk',subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip(),str(p/'checks.swift'),'-o',str(p/'checks')],check=True)
 subprocess.run([str(p/'checks')],check=True)
