import SwiftUI

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
    static let raisedControlBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.26, green: 0.27, blue: 0.30, alpha: 1)
            : UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    })
    static let assistantBubbleBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.24, green: 0.25, blue: 0.28, alpha: 1)
            : UIColor(red: 0.918, green: 0.924, blue: 0.940, alpha: 1)
    })
    static let playbackGlassTint = Color.black.opacity(0.08)
    static let subtleBorder = Color(.separator).opacity(0.18)
    static let cardBorder = Color(.separator).opacity(0.36)
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
