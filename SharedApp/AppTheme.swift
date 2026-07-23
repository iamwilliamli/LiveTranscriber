import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Builds a dynamic light/dark color from explicit component pairs so the same
/// palette renders identically on iOS and macOS.
private func dynamicThemeColor(
    light: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat),
    dark: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)
) -> Color {
    #if canImport(UIKit)
    return Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: dark.red, green: dark.green, blue: dark.blue, alpha: dark.alpha)
            : UIColor(red: light.red, green: light.green, blue: light.blue, alpha: light.alpha)
    })
    #else
    return Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: dark.red, green: dark.green, blue: dark.blue, alpha: dark.alpha)
            : NSColor(srgbRed: light.red, green: light.green, blue: light.blue, alpha: light.alpha)
    })
    #endif
}

private var systemSeparatorColor: Color {
    #if canImport(UIKit)
    return Color(UIColor.separator)
    #else
    return Color(nsColor: .separatorColor)
    #endif
}

private func hdrThemeColor(
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
    linearExposure: CGFloat
) -> Color {
    #if canImport(UIKit)
    return Color(
        UIColor(
            red: red,
            green: green,
            blue: blue,
            alpha: 1,
            linearExposure: linearExposure
        )
    )
    #else
    return Color(
        nsColor: NSColor(
            red: red,
            green: green,
            blue: blue,
            alpha: 1,
            linearExposure: linearExposure
        )
    )
    #endif
}

enum AppTheme {
    static let navigationBarCornerRadius: CGFloat = 28
    static let cornerRadius = navigationBarCornerRadius
    static let compactCornerRadius: CGFloat = 7
    static let cardShadowRadius: CGFloat = 14
    static let cardShadowYOffset: CGFloat = 6

    static let brand = Color(red: 0.96, green: 0.22, blue: 0.10)
    static let brandSoft = Color(red: 1.0, green: 0.49, blue: 0.25)
    static let info = Color(red: 0.12, green: 0.44, blue: 0.95)
    static let success = Color(red: 0.08, green: 0.62, blue: 0.36)
    static let warning = Color(red: 0.93, green: 0.58, blue: 0.12)
    static let danger = Color(red: 0.86, green: 0.18, blue: 0.18)
    static let purple = Color(red: 0.47, green: 0.34, blue: 0.86)
    static let hdrWhite = hdrThemeColor(red: 1, green: 1, blue: 1, linearExposure: 1.75)
    static let hdrBrand = hdrThemeColor(red: 1, green: 0.30, blue: 0.14, linearExposure: 1.60)
    static let hdrDanger = hdrThemeColor(red: 0.90, green: 0.16, blue: 0.16, linearExposure: 1.60)

    #if canImport(UIKit)
    static let groupedBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemGroupedBackground
            : UIColor(red: 0.949, green: 0.953, blue: 0.965, alpha: 1)
    })
    static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .secondarySystemGroupedBackground
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    })
    static let elevatedBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .tertiarySystemGroupedBackground
            : UIColor(red: 0.929, green: 0.935, blue: 0.950, alpha: 1)
    })
    #else
    // Dark values mirror the iOS grouped-background system colors so both
    // platforms render the same palette.
    static let groupedBackground = dynamicThemeColor(
        light: (0.949, 0.953, 0.965, 1),
        dark: (0, 0, 0, 1)
    )
    static let cardBackground = dynamicThemeColor(
        light: (1, 1, 1, 1),
        dark: (0.11, 0.11, 0.118, 1)
    )
    static let elevatedBackground = dynamicThemeColor(
        light: (0.929, 0.935, 0.950, 1),
        dark: (0.173, 0.173, 0.180, 1)
    )
    #endif
    static let raisedControlBackground = dynamicThemeColor(
        light: (1, 1, 1, 1),
        dark: (0.26, 0.27, 0.30, 1)
    )
    static let assistantBubbleBackground = dynamicThemeColor(
        light: (0.918, 0.924, 0.940, 1),
        dark: (0.24, 0.25, 0.28, 1)
    )
    static let playbackGlassTint = Color.black.opacity(0.08)
    static let subtleBorder = systemSeparatorColor.opacity(0.18)
    static let cardBorder = systemSeparatorColor.opacity(0.36)
    static let cardShadow = Color.black.opacity(0.10)
}

enum AmbientActivityState: Equatable {
    case standby
    case active
    case paused
}

struct AmbientActivityBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let state: AmbientActivityState

    var body: some View {
        ZStack {
            AppTheme.groupedBackground

            ambientGradient(color: AppTheme.warning)
                .opacity(state == .standby ? 1 : 0)

            ambientGradient(color: AppTheme.danger)
                .opacity(state == .active ? 1 : 0)

            ambientGradient(color: AppTheme.success)
                .opacity(state == .paused ? 1 : 0)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.55),
            value: state
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func ambientGradient(color: Color) -> some View {
        LinearGradient(
            stops: [
                .init(color: color.opacity(colorScheme == .dark ? 0.20 : 0.52), location: 0),
                .init(color: color.opacity(colorScheme == .dark ? 0.12 : 0.25), location: 0.20),
                .init(color: color.opacity(colorScheme == .dark ? 0.04 : 0.08), location: 0.42),
                .init(color: .clear, location: 0.64)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
