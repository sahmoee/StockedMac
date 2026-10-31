import XCTest
import SwiftUI
import SowensKit
import SowensTestSupport
@testable import Stocked

@MainActor
final class SharedPresentationTests: XCTestCase {
    func testProductionSurface() throws {
        try assertSurfaceSnapshots(of: Fixture(), named: "surface")
    }

    private struct Fixture: View {
        @Environment(\.colorScheme) private var colorScheme
        var dark: Bool { colorScheme == .dark }
        var body: some View {
            MacCard(title: "Recipes") { SowensStatusView("No recipes yet", detail: "Import recipes to begin.", symbol: "fork.knife") }
                .foregroundStyle(dark ? Color.white : Color.black)
                .background(dark ? Color(white: 0.075) : Color.white)
        }
    }
}
