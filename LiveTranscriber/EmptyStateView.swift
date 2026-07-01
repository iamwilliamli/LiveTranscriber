import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: Text

    init(icon: String, titleResource: LocalizedStringResource) {
        self.icon = icon
        self.title = Text(titleResource)
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            title
                .font(.redditSans(.headline))
                .foregroundStyle(.secondary)
        }
    }
}
