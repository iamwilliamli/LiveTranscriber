import SwiftUI

enum AppTheme {
    static let cornerRadius: CGFloat = 8
    static let compactCornerRadius: CGFloat = 7

    static let brand = Color(red: 0.96, green: 0.22, blue: 0.10)
    static let brandSoft = Color(red: 1.0, green: 0.49, blue: 0.25)
    static let info = Color(red: 0.12, green: 0.44, blue: 0.95)
    static let success = Color(red: 0.08, green: 0.62, blue: 0.36)
    static let warning = Color(red: 0.93, green: 0.58, blue: 0.12)
    static let danger = Color(red: 0.86, green: 0.18, blue: 0.18)
    static let purple = Color(red: 0.47, green: 0.34, blue: 0.86)

    static let groupedBackground = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let elevatedBackground = Color(.tertiarySystemGroupedBackground)
    static let subtleBorder = Color(.separator).opacity(0.24)
    static let cardBorder = Color(.separator).opacity(0.52)
    static let cardShadow = Color.black.opacity(0.06)
}
