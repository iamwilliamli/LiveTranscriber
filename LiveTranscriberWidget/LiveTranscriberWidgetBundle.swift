import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiveTranscriberWidgetBundle: WidgetBundle {
    var body: some Widget {
        TranscriptionLiveActivityWidget()
    }
}

struct TranscriptionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranscriptionActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .padding(.horizontal, LiveActivityLayout.lockScreenHorizontalPadding)
                .padding(.vertical, LiveActivityLayout.lockScreenVerticalPadding)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(context.state.isRecording ? .red : .green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityStatusLine(state: context.state, font: .redditSans(size: 12, weight: .semibold))
                        .padding(.leading, LiveActivityLayout.islandHorizontalPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveElapsedText(
                        state: context.state,
                        font: .redditSans(size: 12, weight: .semibold)
                    )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, LiveActivityLayout.islandHorizontalPadding)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedTranscriptionIslandContent(state: context.state)
                }
            } compactLeading: {
                ActivityStatusDot(state: context.state, size: 7, showsRing: false)
                    .frame(width: 14, height: 14, alignment: .center)
            } compactTrailing: {
                LiveElapsedText(
                    state: context.state,
                    font: .redditSans(size: 10, weight: .semibold)
                )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 36, alignment: .trailing)
            } minimal: {
                ActivityStatusDot(state: context.state, size: 7, showsRing: false)
            }
        }
    }
}

private enum LiveActivityLayout {
    static let islandHorizontalPadding: CGFloat = 14
    static let lockScreenHorizontalPadding: CGFloat = 14
    static let lockScreenVerticalPadding: CGFloat = 12
}

private struct LockScreenLiveActivityView: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                ActivityStatusLine(state: state, font: .redditSans(.caption, weight: .semibold))

                Spacer(minLength: 8)

                LiveElapsedText(
                    state: state,
                    font: .redditSans(.headline, weight: .semibold)
                )
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
                .frame(minWidth: 58, alignment: .trailing)
            }

            ActivityTranscriptPanel(
                text: state.lockScreenLatestText,
                lineLimit: 3,
                font: .redditSans(.subheadline, weight: .medium)
            )

            ZStack {
                HStack(alignment: .center, spacing: 8) {
                    ActivityMetricLabel(systemImage: "globe", text: state.languageName)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ActivityMetricLabel(systemImage: "text.alignleft", text: "\(state.lineCount)")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if state.isRecording {
                    StopRecordingLink()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityStatusLine: View {
    let state: TranscriptionActivityAttributes.ContentState
    let font: Font

    var body: some View {
        HStack(spacing: 6) {
            ActivityStatusDot(state: state, size: 7)
            Text(state.status)
                .font(font)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        state.isRecording ? .red : .green
    }
}

private struct ActivityMetricsRow: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ActivityMetricLabel(systemImage: "globe", text: state.languageName)
                .frame(maxWidth: .infinity, alignment: .leading)

            ActivityMetricLabel(systemImage: "text.alignleft", text: "\(state.lineCount)")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StopRecordingLink: View {
    private let stopURL = URL(string: "livetranscriber://stop-recording")!

    var body: some View {
        Link(destination: stopURL) {
            Label("停止", systemImage: "stop.fill")
                .font(.redditSans(.caption2, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(.red, in: Capsule())
        }
    }
}

private struct ExpandedTranscriptionIslandContent: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ActivityTranscriptPanel(
                text: state.islandLatestText,
                lineLimit: 2,
                font: .redditSans(size: 13, weight: .semibold)
            )

            ActivityMetricsRow(state: state)
        }
        .padding(.horizontal, LiveActivityLayout.islandHorizontalPadding)
        .padding(.top, 1)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityStatusDot: View {
    let state: TranscriptionActivityAttributes.ContentState
    let size: CGFloat
    var showsRing = true

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
            .overlay {
                if state.isRecording && showsRing {
                    Circle()
                        .stroke(statusColor.opacity(0.45), lineWidth: 2)
                        .frame(width: size + 5, height: size + 5)
                }
            }
    }

    private var statusColor: Color {
        state.isRecording ? .red : .green
    }
}

private struct ActivityMetricLabel: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.redditSans(.caption2, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

private struct ActivityTranscriptPanel: View {
    let text: String
    let lineLimit: Int
    let font: Font

    var body: some View {
        LatestTranscriptionText(
            text: text,
            font: font,
            lineLimit: lineLimit
        )
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveElapsedText: View {
    let state: TranscriptionActivityAttributes.ContentState
    let font: Font

    var body: some View {
        Group {
            if state.isRecording {
                Text(state.timerReferenceDate, style: .timer)
            } else {
                Text(state.elapsedText)
            }
        }
        .font(font)
        .monospacedDigit()
    }
}

private struct LatestTranscriptionText: View {
    let text: String
    let font: Font
    let lineLimit: Int

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .truncationMode(.head)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private extension TranscriptionActivityAttributes.ContentState {
    var lockScreenLatestText: String {
        displayText.trailingLines(maxLines: 3, maxCharacters: 220)
    }

    var islandLatestText: String {
        displayText.trailingLines(maxLines: 2, maxCharacters: 130)
    }

    var compactLatestText: String {
        displayText.trailingText(maxCharacters: 28)
    }
}

private extension String {
    func trailingLines(maxLines: Int, maxCharacters: Int) -> String {
        let cleaned = cleanedLines
        let text = cleaned.suffix(max(maxLines, 1)).joined(separator: "\n")
        return text.trailingCharacters(maxCharacters: maxCharacters)
    }

    func trailingText(maxCharacters: Int) -> String {
        cleanedLines
            .joined(separator: " ")
            .trailingCharacters(maxCharacters: maxCharacters)
    }

    private var cleanedLines: [String] {
        components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\t", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private func trailingCharacters(maxCharacters: Int) -> String {
        guard count > maxCharacters, maxCharacters > 1 else {
            return self
        }
        return "…" + suffix(maxCharacters - 1)
    }
}

private enum AppTypography {
    static func fontName(for weight: Font.Weight = .regular, italic: Bool = false) -> String {
        if italic {
            return "RedditSans-Italic"
        }
        if weight == .bold || weight == .heavy || weight == .black {
            return "RedditSans-Bold"
        }
        if weight == .semibold {
            return "RedditSans-SemiBold"
        }
        if weight == .medium {
            return "RedditSans-Medium"
        }
        return "RedditSans-Regular"
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

private extension Font {
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

#if DEBUG
#Preview("Live Activity", as: .content, using: TranscriptionActivityAttributes(startedAt: Date())) {
    TranscriptionLiveActivityWidget()
} contentStates: {
    TranscriptionActivityAttributes.ContentState(
        status: "正在录音",
        languageName: "简体中文",
        latestText: "这是一句实时转录文本，会同步显示到灵动岛。",
        placeholderText: String(localized: "等待语音"),
        elapsedSeconds: 92,
        timerReferenceDate: Date(timeIntervalSinceNow: -92),
        lineCount: 8,
        isRecording: true
    )
}
#endif
