import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum AppTypography {
    static let regularName = "RedditSans-Regular"
    static let mediumName = "RedditSans-Medium"
    static let semiBoldName = "RedditSans-SemiBold"
    static let boldName = "RedditSans-Bold"
    static let italicName = "RedditSans-Italic"

    static func fontName(for weight: Font.Weight = .regular, italic: Bool = false) -> String {
        if italic {
            return italicName
        }
        if weight == .bold || weight == .heavy || weight == .black {
            return boldName
        }
        if weight == .semibold {
            return semiBoldName
        }
        if weight == .medium {
            return mediumName
        }
        return regularName
    }

    static func pointSize(for textStyle: Font.TextStyle) -> CGFloat {
        switch textStyle {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
}

extension Font {
    static func redditSans(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        .custom(
            AppTypography.fontName(for: weight, italic: italic),
            size: AppTypography.pointSize(for: textStyle),
            relativeTo: textStyle
        )
    }

    static func redditSans(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        .custom(AppTypography.fontName(for: weight, italic: italic), size: size)
    }
}

#if canImport(UIKit)
extension AppTypography {
    static func configureUIKitAppearances() {
        let title = uiFont(size: 17, weight: .semibold)
        let largeTitle = uiFont(size: 34, weight: .bold)
        let caption = uiFont(size: 10, weight: .medium)

        UINavigationBar.appearance().titleTextAttributes = [.font: title]
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeTitle]
        UITabBarItem.appearance().setTitleTextAttributes([.font: caption], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: caption], for: .selected)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: uiFont(size: 17, weight: .regular)], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: uiFont(size: 17, weight: .semibold)], for: .highlighted)
        UITextField.appearance().font = uiFont(size: 17, weight: .regular)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(size: 13, weight: .medium)], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: uiFont(size: 13, weight: .semibold)], for: .selected)

        if #available(iOS 13.0, *) {
            UISearchTextField.appearance().font = uiFont(size: 16, weight: .regular)
        }
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> UIFont {
        UIFont(name: fontName(for: weight, italic: italic), size: size) ?? .systemFont(ofSize: size, weight: uiWeight(for: weight))
    }

    private static func uiWeight(for weight: Font.Weight) -> UIFont.Weight {
        if weight == .bold || weight == .heavy || weight == .black {
            return .bold
        }
        if weight == .semibold {
            return .semibold
        }
        if weight == .medium {
            return .medium
        }
        return .regular
    }
}
#endif
