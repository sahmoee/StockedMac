import Observation
import SwiftUI

@MainActor
@Observable
final class MacAppleAuth {
    private static let signedInKey = "mac_signed_in_v1"

    var isSignedIn: Bool

    init() {
        let defaults = UserDefaults.standard
        isSignedIn = defaults.object(forKey: Self.signedInKey) as? Bool ?? true
    }

    func signIn() {
        isSignedIn = true
        UserDefaults.standard.set(true, forKey: Self.signedInKey)
    }

    func signOut() {
        isSignedIn = false
        UserDefaults.standard.set(false, forKey: Self.signedInKey)
    }

    func refreshSessionIfNeeded() async {
        // Household access is authenticated independently by its shared code and key.
        // Keep this hook so a future Apple credential refresh can be added without
        // changing application startup.
    }
}

struct MacWelcomeView: View {
    @Environment(MacAppleAuth.self) private var auth

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "refrigerator.fill")
                .font(.system(size: 54))
                .foregroundStyle(MacTheme.gold)
            Text("Welcome to Stocked").font(.largeTitle.bold())
            Text("Keep your kitchen, grocery list, recipes, and week plan together.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Continue") { auth.signIn() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 420)
        .padding(40)
    }
}
