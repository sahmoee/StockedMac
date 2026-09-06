import SwiftUI

struct MacCooklangConnectionView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CooklangFederationRecipe?
    private var dark: Bool { scheme == .dark }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cooklang community").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            CooklangConnectionPanel(background: MacTheme.canvas(dark: dark), card: MacTheme.card(dark: dark),
                foreground: .primary, secondary: .secondary, accent: MacTheme.accent(dark: dark)) { recipe in
                    try Task.checkCancellation(); selected = recipe
                }
        }.frame(minWidth: 600, idealWidth: 740, minHeight: 520, idealHeight: 740)
            .macThemedSurface()
            .sheet(item: $selected) { recipe in MacRecipeInterchangeView(connectedRecipe: recipe) }
    }
}
