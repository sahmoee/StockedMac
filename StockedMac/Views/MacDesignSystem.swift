import SowensKit
import SwiftUI
import AppKit

enum MacTheme {
    // Current values are unchanged; a selected design variant supplies its own roles.
    // The colors resolve per appearance, so Journal/Standard follow system Light/Dark.
    nonisolated static var gold: Color { variantColor(\.accent) ?? Color(red: 0.78, green: 0.57, blue: 0.16) }
    nonisolated static var green: Color { variantColor(\.success) ?? Color(red: 0.20, green: 0.58, blue: 0.32) }
    nonisolated static var low: Color { variantColor(\.warn) ?? Color.orange }
    nonisolated static var urgent: Color { variantColor(\.danger) ?? Color.red }

    /// A dynamic color for the stored variant's role, or nil for the Current design.
    nonisolated static func variantColor(_ role: KeyPath<MacVariantPalette, UInt32>,
                                         variant: MacDesignVariant = .stored()) -> Color? {
        guard variant != .current else { return nil }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            guard let palette = variant.palette(dark: dark) else { return .controlAccentColor }
            return NSColor(macHex: palette[keyPath: role])
        })
    }

    static let pad: CGFloat = 16
    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 220
    static let sidebarMax: CGFloat = 280
    static let minWindowWidth: CGFloat = 860
    static let minWindowHeight: CGFloat = 560

    static func accent(dark: Bool) -> Color {
        if let variant = variantColor(\.accent) { return variant }
        return dark ? Color(red: 0.95, green: 0.75, blue: 0.30) : gold
    }

    /// Warm Stocked surfaces shared by every window and presentation.  These are
    /// deliberately semantic functions so changing appearance never leaves a
    /// hard-coded light card inside a dark window (or vice versa).
    static func canvas(dark: Bool) -> Color {
        variantColor(\.bg) ?? Color(nsColor: .windowBackgroundColor)
    }

    static func sidebar(dark: Bool) -> Color {
        variantColor(\.surface) ?? .clear
    }

    static func card(dark: Bool) -> Color {
        variantColor(\.surface) ?? Color(nsColor: .controlBackgroundColor)
    }

    static func cardBorder(dark: Bool) -> Color {
        variantColor(\.line) ?? .clear
    }

    static func expiryColor(daysLeft: Int?) -> Color {
        guard let daysLeft else { return .secondary }
        if daysLeft < 0 { return urgent }
        if daysLeft <= 2 { return low }
        return green
    }
}

/// Complete StockedMac presentation boundary. Apply it to scene roots and to
/// standalone sheet/popover roots; controls still use native macOS behavior,
/// while every exposed canvas uses the same warm adaptive palette.
private struct MacThemedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.macDesignVariant) private var variant

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        ZStack {
            MacTheme.canvas(dark: dark).ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.canvas(dark: dark))
        .presentationBackground(MacTheme.canvas(dark: dark))
        .tint(MacTheme.variantColor(\.accent, variant: variant))
    }
}

extension View {
    func macThemedSurface() -> some View {
        modifier(MacThemedSurfaceModifier())
    }
}

/// A two-pane desktop layout that keeps the familiar draggable divider without
/// relying on `NSSplitView`. SwiftUI's AppKit bridge can briefly install mutually
/// exclusive safe-area constraints when a nested split is restored near its maximum
/// width; this layout has the same interaction with deterministic geometry.
struct MacAdjustableSplit<Leading: View, Trailing: View>: View {
    private let minimumLeadingWidth: CGFloat
    private let maximumLeadingWidth: CGFloat
    private let minimumTrailingWidth: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    @State private var settledLeadingWidth: CGFloat
    @GestureState private var dragTranslation: CGFloat = 0

    init(
        initialLeadingWidth: CGFloat,
        minimumLeadingWidth: CGFloat,
        maximumLeadingWidth: CGFloat,
        minimumTrailingWidth: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        _settledLeadingWidth = State(initialValue: initialLeadingWidth)
        self.minimumLeadingWidth = minimumLeadingWidth
        self.maximumLeadingWidth = maximumLeadingWidth
        self.minimumTrailingWidth = minimumTrailingWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        GeometryReader { geometry in
            let upperBound = max(
                minimumLeadingWidth,
                min(maximumLeadingWidth, geometry.size.width - minimumTrailingWidth - 9)
            )
            let proposedWidth = settledLeadingWidth + dragTranslation
            let visibleWidth = min(max(proposedWidth, minimumLeadingWidth), upperBound)

            HStack(spacing: 0) {
                leading
                    .frame(width: visibleWidth)
                    .clipped()

                ZStack {
                    Color.clear
                    Divider()
                }
                .frame(width: 9)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation.width
                        }
                        .onEnded { value in
                            settledLeadingWidth = min(
                                max(settledLeadingWidth + value.translation.width, minimumLeadingWidth),
                                upperBound
                            )
                        }
                )
                .accessibilityElement()
                .accessibilityLabel("Resize sidebar")
                .accessibilityAdjustableAction { direction in
                    let change: CGFloat = direction == .increment ? 24 : -24
                    settledLeadingWidth = min(
                        max(settledLeadingWidth + change, minimumLeadingWidth),
                        upperBound
                    )
                }

                trailing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct MacSectionHeader: View {
    @Environment(\.macDesignVariant) private var variant
    let title: String

    var body: some View {
        if variant == .current {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            // Variants: a real heading (grouped sections, clear type hierarchy).
            Text(title)
                .font(MacTheme.heading(15, variant: variant))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, variant.compactSections ? 8 : 0)
                .padding(.vertical, variant.compactSections ? 4 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if variant.compactSections {
                        RoundedRectangle(cornerRadius: 4).fill(MacTheme.variantColor(\.soft, variant: variant) ?? .clear)
                    }
                }
        }
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
        .background(tint.opacity(0.12), in: MacTheme.chipShape(variant))
    }
    @Environment(\.macDesignVariant) private var variant
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

    @Environment(\.macDesignVariant) private var variant

    var body: some View {
        if let radius = variant.componentRadius {
            variantBody(radius: radius)
        } else {
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
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator.opacity(0.35)))
        }
    }

    /// Variant section: surface fill, hairline border, no shadow, heading-typed title.
    private func variantBody(radius: Double) -> some View {
        VStack(alignment: .leading, spacing: variant.compactSections ? 8 : 12) {
            if title != nil || systemImage != nil || footnote != nil {
                HStack(spacing: 7) {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(MacTheme.gold).accessibilityHidden(true) }
                    if let title {
                        Text(title).font(MacTheme.heading(variant.compactSections ? 14 : 17, variant: variant))
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                    if let footnote { Text(footnote).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, variant.compactSections ? 8 : 0)
                .padding(.vertical, variant.compactSections ? 5 : 0)
                .background {
                    if variant.compactSections {
                        RoundedRectangle(cornerRadius: 4).fill(MacTheme.variantColor(\.soft, variant: variant) ?? .clear)
                    }
                }
            }
            content
        }
        .padding(variant.compactSections ? 12 : MacTheme.pad)
        .background(MacTheme.variantColor(\.surface, variant: variant) ?? .clear,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(MacTheme.variantColor(\.line, variant: variant) ?? .clear, lineWidth: 1))
    }
}

// MARK: - Design variants (SwiftUI layer)

extension NSColor {
    nonisolated convenience init(macHex hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private struct MacDesignVariantKey: EnvironmentKey {
    static let defaultValue = MacDesignVariant.current
}

extension EnvironmentValues {
    var macDesignVariant: MacDesignVariant {
        get { self[MacDesignVariantKey.self] }
        set { self[MacDesignVariantKey.self] = newValue }
    }
}

extension MacTheme {
    /// Heading font: Georgia for Journal/Evening, semibold system for Standard, and the
    /// plain system headline for Current. Sizes scale with the system text size.
    static func heading(_ size: CGFloat, variant: MacDesignVariant) -> Font {
        if let family = variant.headingFamily {
            return .custom(family, size: size, relativeTo: .headline)
        }
        return variant == .current ? .headline : .system(size: size, weight: .semibold)
    }

    static func chipShape(_ variant: MacDesignVariant) -> AnyShape {
        if let radius = variant.chipRadius {
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        return AnyShape(Capsule())
    }
}

/// Installed once per scene (main window and Settings). Current applies nothing, so the
/// shipped native look and system appearance are untouched.
struct MacDesignVariantRoot: ViewModifier {
    @AppStorage(MacDesignVariant.defaultsKey) private var raw = MacDesignVariant.current.rawValue

    // No `.id`: view identity, navigation, selections and unsaved drafts survive a design
    // change. Views that read legacy `MacTheme` colors observe `macDesignVariant` and
    // re-evaluate in place; shared components read the environment directly.
    func body(content: Content) -> some View {
        let variant = MacDesignVariant(storedValue: raw)
        // nil/automatic values for Current are exactly SwiftUI's defaults.
        content
            .environment(\.macDesignVariant, variant)
            .tint(MacTheme.variantColor(\.accent, variant: variant))
            .buttonBorderShape(variant.componentRadius.map { .roundedRectangle(radius: $0) } ?? .automatic)
            .font(variant.bodyFamily.map { Font.custom($0, size: 13, relativeTo: .body) })
            .preferredColorScheme(variant.forcesDarkAppearance ? .dark : nil)
    }
}

/// Variant canvas behind detail panes and forms; Current keeps the system background.
struct MacDesignVariantCanvas: ViewModifier {
    @Environment(\.macDesignVariant) private var variant

    func body(content: Content) -> some View {
        if variant == .current {
            content
        } else {
            content
                .scrollContentBackground(.hidden)
                .background(MacTheme.variantColor(\.bg, variant: variant) ?? .clear)
        }
    }
}

extension View {
    func macDesignVariantRoot() -> some View { modifier(MacDesignVariantRoot()) }
    func macDesignVariantCanvas() -> some View { modifier(MacDesignVariantCanvas()) }
}
