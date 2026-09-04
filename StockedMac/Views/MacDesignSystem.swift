import SwiftUI

enum MacTheme {
    static let gold = Color(red: 0.78, green: 0.57, blue: 0.16)
    static let green = Color(red: 0.20, green: 0.58, blue: 0.32)
    static let low = Color.orange
    static let urgent = Color.red

    static let pad: CGFloat = 16
    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 220
    static let sidebarMax: CGFloat = 280
    static let minWindowWidth: CGFloat = 860
    static let minWindowHeight: CGFloat = 560

    static func accent(dark: Bool) -> Color {
        dark ? Color(red: 0.95, green: 0.75, blue: 0.30) : gold
    }

    /// Warm Stocked surfaces shared by every window and presentation.  These are
    /// deliberately semantic functions so changing appearance never leaves a
    /// hard-coded light card inside a dark window (or vice versa).
    static func canvas(dark: Bool) -> Color {
        dark
            ? Color(red: 0.085, green: 0.078, blue: 0.067)
            : Color(red: 0.91, green: 0.82, blue: 0.67)
    }

    static func sidebar(dark: Bool) -> Color {
        dark
            ? Color(red: 0.105, green: 0.096, blue: 0.082)
            : Color(red: 0.88, green: 0.78, blue: 0.62)
    }

    static func card(dark: Bool) -> Color {
        dark
            ? Color(red: 0.145, green: 0.132, blue: 0.113)
            : Color(red: 0.975, green: 0.955, blue: 0.91)
    }

    static func cardBorder(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.14) : Color.black.opacity(0.13)
    }

    static func expiryColor(daysLeft: Int?) -> Color {
        guard let daysLeft else { return .secondary }
        if daysLeft < 0 { return urgent }
        if daysLeft <= 2 { return .orange }
        return green
    }
}

/// Complete StockedMac presentation boundary. Apply it to scene roots and to
/// standalone sheet/popover roots; controls still use native macOS behavior,
/// while every exposed canvas uses the same warm adaptive palette.
private struct MacThemedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        ZStack {
            MacTheme.canvas(dark: dark).ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.canvas(dark: dark))
        .presentationBackground(MacTheme.canvas(dark: dark))
        .tint(MacTheme.accent(dark: dark))
    }
}

extension View {
    func macThemedSurface() -> some View {
        modifier(MacThemedSurfaceModifier())
    }
}

struct MacSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct MacPill: View {
    let text: String
    var tint: Color = .secondary
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct MacEmpty: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

struct MacCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var title: String? = nil
    var systemImage: String? = nil
    var footnote: String? = nil
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        systemImage: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || systemImage != nil || footnote != nil {
                HStack(spacing: 7) {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(MacTheme.gold) }
                    if let title { Text(title).font(.headline) }
                    Spacer(minLength: 0)
                    if let footnote { Text(footnote).font(.caption).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(MacTheme.pad)
        .background(MacTheme.card(dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(MacTheme.cardBorder(dark: scheme == .dark)))
    }
}
