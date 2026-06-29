import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(title))
                .font(.redditSans(.headline))
                .foregroundStyle(.secondary)
        }
    }
}
