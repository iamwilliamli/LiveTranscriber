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
                .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                    max(0, length - 32)
                }
                .padding(16)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(context.state.isRecording ? .red : .green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        ActivityStatusDot(state: context.state, size: 8)
                        Text("Transcribe")
                            .font(.redditSans(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .padding(.leading, 12)
                    .frame(minWidth: 82, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    LiveElapsedText(
                        state: context.state,
                        font: .redditSans(size: 12, weight: .semibold)
                    )
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 52, alignment: .trailing)
                        .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedTranscriptionIslandContent(state: context.state)
            }
        } compactLeading: {
            ActivityStatusDot(state: context.state, size: 8, showsRing: false)
                .padding(.leading, 3)
            } compactTrailing: {
                LiveElapsedText(
                    state: context.state,
                    font: .redditSans(size: 10, weight: .semibold)
                )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 36, alignment: .leading)
            } minimal: {
                ActivityStatusDot(state: context.state, size: 7, showsRing: false)
            }
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LockScreenLiveActivityHeader(state: state)

            ActivityTranscriptPanel(
                text: state.lockScreenLatestText,
                lineLimit: 4,
                font: .redditSans(.subheadline, weight: .medium)
            )

            HStack(alignment: .center, spacing: 10) {
                ActivityMetricLabel(systemImage: "globe", text: state.languageName)

                Spacer(minLength: 10)

                if state.isRecording {
                    StopRecordingLink()
                }

                ActivityMetricLabel(systemImage: "text.alignleft", text: "\(state.lineCount)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            LiveElapsedText(
                state: state,
                font: .redditSans(.headline, weight: .semibold)
            )
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .monospacedDigit()
            .frame(width: 96, height: 28, alignment: .trailing)
        }
    }
}

private struct LockScreenLiveActivityHeader: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        ActivityStatusPill(state: state)
            .padding(.trailing, 108)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                ActivityStatusPill(state: state)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ActivityTranscriptPanel(
                text: state.islandLatestText,
                lineLimit: 3,
                font: .redditSans(size: 13, weight: .semibold)
            )

            HStack(alignment: .center, spacing: 8) {
                ActivityMetricLabel(systemImage: "globe", text: state.languageName)

                Spacer(minLength: 8)

                ActivityMetricLabel(systemImage: "text.alignleft", text: "\(state.lineCount)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
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

private struct ActivityStatusPill: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            ActivityStatusDot(state: state, size: 7)
            Text(state.status)
                .font(.redditSans(.caption2, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(statusColor.opacity(0.14), in: Capsule())
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 18)

            LatestTranscriptionText(
                text: text,
                font: font,
                lineLimit: lineLimit
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        displayText.trailingLines(maxLines: 4, maxCharacters: 260)
    }

    var islandLatestText: String {
        displayText.trailingLines(maxLines: 3, maxCharacters: 170)
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
        placeholderText: "Waiting for speech",
        elapsedSeconds: 92,
        timerReferenceDate: Date(timeIntervalSinceNow: -92),
        lineCount: 8,
        isRecording: true
    )
}
#endif
