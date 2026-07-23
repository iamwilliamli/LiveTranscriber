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

struct SummarySkeletonView: View {
    let isAnimated: Bool

    var body: some View {
        SkeletonShimmerView(
            isAnimated: isAnimated,
            accessibilityLabel: isAnimated
                ? L10n.Recordings.analyzing
                : L10n.Recordings.noSummary
        ) {
            VStack(alignment: .leading, spacing: 9) {
                SkeletonBar(trailingInset: 8)
                SkeletonBar(trailingInset: 34)
                SkeletonBar(trailingInset: 18)
                SkeletonBar(trailingInset: 112)
            }
            .padding(.vertical, 4)
        }
    }
}

struct MeetingAnalysisSkeletonView: View {
    let isAnimated: Bool

    var body: some View {
        SkeletonShimmerView(
            isAnimated: isAnimated,
            accessibilityLabel: isAnimated
                ? L10n.Recordings.analyzingMeeting
                : L10n.Recordings.noMeetingAnalysis
        ) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 9) {
                    SkeletonBar(trailingInset: 10)
                    SkeletonBar(trailingInset: 42)
                    SkeletonBar(trailingInset: 124)
                }

                meetingSection(
                    titleTrailingInset: 178,
                    primaryTrailingInset: 24,
                    secondaryTrailingInset: 146
                )

                meetingSection(
                    titleTrailingInset: 206,
                    primaryTrailingInset: 68,
                    secondaryTrailingInset: 178
                )
            }
            .padding(.vertical, 4)
        }
    }

    private func meetingSection(
        titleTrailingInset: CGFloat,
        primaryTrailingInset: CGFloat,
        secondaryTrailingInset: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBar(trailingInset: titleTrailingInset, height: 10)

            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(AppTheme.elevatedBackground)
                    .frame(width: 8, height: 8)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    SkeletonBar(trailingInset: primaryTrailingInset, height: 10)
                    SkeletonBar(trailingInset: secondaryTrailingInset, height: 8)
                }
            }
        }
    }
}

struct LiveTranscriptSkeletonView: View {
    let isAnimated: Bool
    let statusText: LocalizedStringResource

    private let rows = [
        LiveTranscriptSkeletonRowSpec(id: 0, primaryTrailingInset: 18, secondaryTrailingInset: 92),
        LiveTranscriptSkeletonRowSpec(id: 1, primaryTrailingInset: 54, secondaryTrailingInset: nil),
        LiveTranscriptSkeletonRowSpec(id: 2, primaryTrailingInset: 8, secondaryTrailingInset: 42),
        LiveTranscriptSkeletonRowSpec(id: 3, primaryTrailingInset: 116, secondaryTrailingInset: nil),
        LiveTranscriptSkeletonRowSpec(id: 4, primaryTrailingInset: 28, secondaryTrailingInset: 128),
        LiveTranscriptSkeletonRowSpec(id: 5, primaryTrailingInset: 74, secondaryTrailingInset: nil),
        LiveTranscriptSkeletonRowSpec(id: 6, primaryTrailingInset: 12, secondaryTrailingInset: 76),
        LiveTranscriptSkeletonRowSpec(id: 7, primaryTrailingInset: 138, secondaryTrailingInset: nil),
        LiveTranscriptSkeletonRowSpec(id: 8, primaryTrailingInset: 42, secondaryTrailingInset: 104),
        LiveTranscriptSkeletonRowSpec(id: 9, primaryTrailingInset: 88, secondaryTrailingInset: nil),
    ]

    var body: some View {
        GeometryReader { geometry in
            let skeletonHeight = max(geometry.size.height - 4, 0)

            SkeletonShimmerView(
                isAnimated: isAnimated,
                accessibilityLabel: statusText
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(rows) { row in
                        LiveTranscriptSkeletonRow(spec: row)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: skeletonHeight, alignment: .top)
                .clipped()
                .opacity(isAnimated ? 1 : 0.72)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.76),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .frame(height: skeletonHeight, alignment: .top)
            .padding(.top, 4)
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .top
            )
            .clipped()
        }
    }
}

private struct LiveTranscriptSkeletonRowSpec: Identifiable {
    let id: Int
    let primaryTrailingInset: CGFloat
    let secondaryTrailingInset: CGFloat?
}

private struct LiveTranscriptSkeletonRow: View {
    let spec: LiveTranscriptSkeletonRowSpec

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(AppTheme.elevatedBackground)
                .frame(width: 68, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBar(trailingInset: spec.primaryTrailingInset, height: 12)

                if let secondaryTrailingInset = spec.secondaryTrailingInset {
                    SkeletonBar(trailingInset: secondaryTrailingInset, height: 10)
                }
            }
        }
    }
}

private struct SkeletonBar: View {
    let trailingInset: CGFloat
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: min(height / 2, 6), style: .continuous)
            .fill(AppTheme.elevatedBackground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.trailing, trailingInset)
    }
}

private struct SkeletonShimmerView<Content: View>: View {
    let isAnimated: Bool
    let accessibilityLabel: LocalizedStringResource
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(
        isAnimated: Bool,
        accessibilityLabel: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.isAnimated = isAnimated
        self.accessibilityLabel = accessibilityLabel
        self.content = content()
    }

    var body: some View {
        content
            .overlay {
                if isAnimated, !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                        GeometryReader { proxy in
                            let duration = 1.55
                            let elapsed = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: duration)
                            let progress = elapsed / duration
                            let bandWidth = max(proxy.size.width * 0.48, 100)
                            let verticalOverscan = max(proxy.size.height * 0.35, 16)
                            let diagonalInset = max(proxy.size.height * 0.12, 8)
                            let travelDistance = proxy.size.width + (bandWidth + diagonalInset) * 2

                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(
                                        color: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.18),
                                        location: 0.30
                                    ),
                                    .init(
                                        color: Color.white.opacity(colorScheme == .dark ? 0.17 : 0.72),
                                        location: 0.50
                                    ),
                                    .init(
                                        color: Color.white.opacity(colorScheme == .dark ? 0.04 : 0.18),
                                        location: 0.70
                                    ),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(
                                width: bandWidth,
                                height: proxy.size.height + verticalOverscan * 2
                            )
                            .rotationEffect(.degrees(-10))
                            .offset(
                                x: -(bandWidth + diagonalInset) + travelDistance * CGFloat(progress),
                                y: -verticalOverscan
                            )
                        }
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
    }
}

extension View {
    func liveTranscriptShimmer(isActive: Bool) -> some View {
        modifier(LiveTranscriptShimmerModifier(isActive: isActive))
    }
}

private struct LiveTranscriptShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let duration = 3.2
                let elapsed = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: duration)
                let phase = elapsed / duration
                let pulse = (1 - cos(phase * 2 * .pi)) / 2
                let textOpacity = colorScheme == .dark
                    ? 0.72 + pulse * 0.28
                    : 0.56 + pulse * 0.44
                let emphasisColor = colorScheme == .dark
                    ? AppTheme.hdrWhite
                    : Color.primary
                let emphasisOpacity = colorScheme == .dark
                    ? 0.04 + pulse * 0.16
                    : 0.02 + pulse * 0.12

                content
                    .opacity(textOpacity)
                    .overlay {
                        emphasisColor
                            .opacity(emphasisOpacity)
                            .mask {
                                content
                            }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
        } else {
            content
        }
    }
}
