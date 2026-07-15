import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LiveTranscriberWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickRecordingControl()
        LiveTranscriberHomeWidget()
        TranscriptionLiveActivityWidget()
    }
}

struct QuickRecordingControl: ControlWidget {
    static let kind = "com.iamwilliamli.LiveTranscriber.quickRecording"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartQuickRecordingIntent()) {
                Label(QuickRecordingControlL10n.startRecording, systemImage: "waveform.and.mic")
                    .controlWidgetActionHint(QuickRecordingControlL10n.startRecording)
            }
        }
        .displayName(QuickRecordingControlL10n.title)
        .description(QuickRecordingControlL10n.description)
    }
}

struct LiveTranscriberHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LiveTranscriberHomeWidget", provider: LiveTranscriberHomeProvider()) { entry in
            LiveTranscriberHomeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Live Transcriber")
        .description("Start recording, open saved files, and change recording settings.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

private struct LiveTranscriberHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> LiveTranscriberHomeEntry {
        LiveTranscriberHomeEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveTranscriberHomeEntry) -> Void) {
        completion(LiveTranscriberHomeEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveTranscriberHomeEntry>) -> Void) {
        let entry = LiveTranscriberHomeEntry(date: Date())
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct LiveTranscriberHomeEntry: TimelineEntry {
    let date: Date
}

private struct LiveTranscriberHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LiveTranscriberHomeEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallHomeWidget()
                .widgetURL(WidgetRoute.record.url)
        case .systemLarge:
            LargeHomeWidget()
        case .accessoryCircular:
            QuickRecordingCircularWidget()
                .widgetURL(WidgetRoute.record.url)
        case .accessoryRectangular:
            QuickRecordingRectangularWidget()
                .widgetURL(WidgetRoute.record.url)
        case .accessoryInline:
            QuickRecordingInlineWidget()
                .widgetURL(WidgetRoute.record.url)
        default:
            MediumHomeWidget()
        }
    }
}

private struct QuickRecordingCircularWidget: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            Image(systemName: "waveform.and.mic")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel(Text(QuickRecordingControlL10n.startRecording))
    }
}

private struct QuickRecordingRectangularWidget: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 21, weight: .semibold))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(QuickRecordingControlL10n.title)
                    .font(.redditSans(.headline, weight: .semibold))
                    .lineLimit(1)

                Text(QuickRecordingControlL10n.startRecording)
                    .font(.redditSans(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickRecordingInlineWidget: View {
    var body: some View {
        Label(QuickRecordingControlL10n.startRecording, systemImage: "waveform.and.mic")
    }
}

private struct SmallHomeWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(compact: true)

            Spacer(minLength: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(.redditSans(size: 31, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text("Recording")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            WidgetStatusPill(systemImage: "captions.bubble", text: "Live transcript")
        }
        .padding(16)
    }
}

private struct MediumHomeWidget: View {
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeader(compact: false)

                Text("Quick Actions")
                    .font(.redditSans(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Start recording or jump to saved files.")
                    .font(.redditSans(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                WidgetActionLink(route: .record, systemImage: "record.circle", title: "Start", prominence: .primary)
                WidgetActionLink(route: .recordings, systemImage: "folder", title: "Files", prominence: .secondary)
                WidgetActionLink(route: .settings, systemImage: "gearshape", title: "Settings", prominence: .secondary)
            }
            .frame(width: 116)
        }
        .padding(16)
    }
}

private struct LargeHomeWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeader(compact: false)

            VStack(alignment: .leading, spacing: 6) {
                Text("Recording Controls")
                    .font(.redditSans(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("Start recording, open saved files, import audio, or adjust recording settings.")
                    .font(.redditSans(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                WidgetStatusPill(systemImage: "captions.bubble", text: "Live transcript")
                WidgetStatusPill(systemImage: "waveform", text: "Stereo audio")
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                WidgetActionLink(route: .record, systemImage: "record.circle", title: "Start Recording", prominence: .primary)
                WidgetActionLink(route: .recordings, systemImage: "folder", title: "Saved Files", prominence: .secondary)
                WidgetActionLink(route: .settings, systemImage: "gearshape", title: "Settings", prominence: .secondary)
            }
        }
        .padding(18)
    }
}

private struct WidgetHeader: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 11 : 12, style: .continuous)
                    .fill(.red.opacity(0.16))

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: compact ? 18 : 19, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .frame(width: compact ? 36 : 38, height: compact ? 36 : 38)

            VStack(alignment: .leading, spacing: 1) {
                Text("Live")
                    .font(.redditSans(.caption2, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("Transcriber")
                    .font(.redditSans(.subheadline, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

private struct WidgetActionLink: View {
    enum Prominence {
        case primary
        case secondary
    }

    let route: WidgetRoute
    let systemImage: String
    let title: String
    let prominence: Prominence

    var body: some View {
        Link(destination: route.url) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)

                Text(title)
                    .font(.redditSans(.caption, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var foregroundStyle: Color {
        prominence == .primary ? .white : .primary
    }

    private var backgroundStyle: Color {
        prominence == .primary ? .red : Color(.tertiarySystemFill)
    }
}

private struct WidgetStatusPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.redditSans(.caption2, weight: .bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

private enum WidgetRoute {
    case record
    case recordings
    case settings

    var url: URL {
        switch self {
        case .record:
            return URL(string: "livetranscriber://record?start=1")!
        case .recordings:
            return URL(string: "livetranscriber://recordings")!
        case .settings:
            return URL(string: "livetranscriber://settings")!
        }
    }
}

struct TranscriptionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TranscriptionActivityAttributes.self) { context in
            LockScreenLiveActivityView(state: context.state)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, LiveActivityLayout.lockScreenHorizontalPadding)
                .padding(.vertical, LiveActivityLayout.lockScreenVerticalPadding)
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(context.state.isRecording ? .red : .green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityStateBlock(state: context.state, style: .island)
                        .padding(.leading, LiveActivityLayout.islandHorizontalPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimeBlock(state: context.state, style: .island)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, LiveActivityLayout.islandHorizontalPadding)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedTranscriptionIslandContent(state: context.state)
                }
            } compactLeading: {
                CompactActivityGlyph(state: context.state)
            } compactTrailing: {
                LiveElapsedText(
                    state: context.state,
                    font: .redditSans(size: 10, weight: .bold)
                )
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: 40, alignment: .trailing)
            } minimal: {
                ActivityStatusDot(state: context.state, size: 8, showsRing: false)
            }
        }
    }
}

private enum LiveActivityLayout {
    static let islandHorizontalPadding: CGFloat = 12
    static let lockScreenHorizontalPadding: CGFloat = 14
    static let lockScreenVerticalPadding: CGFloat = 11
}

private struct LockScreenLiveActivityView: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LockScreenTopBar(state: state)

            ActivityTranscriptPanel(
                text: state.lockScreenLatestText,
                lineLimit: 2,
                font: .redditSans(.subheadline, weight: .medium)
            )

            HStack {
                Spacer(minLength: 0)
                if state.isRecording {
                    StopRecordingLink(height: 30)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LockScreenTopBar: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        GeometryReader { proxy in
            let timeWidth: CGFloat = 86
            let statusWidth = min(max(proxy.size.width * 0.34, 104), 142)
            let summaryWidth = max(proxy.size.width - statusWidth - timeWidth - 16, 44)

            HStack(alignment: .top, spacing: 8) {
                ActivityStateBlock(state: state, style: .lockScreen)
                    .frame(width: statusWidth, alignment: .topLeading)

                ActivityTopSummaryBlock(state: state)
                    .frame(width: summaryWidth, alignment: .top)

                ActivityTimeBlock(state: state, style: .lockScreen)
                    .frame(width: timeWidth, alignment: .topTrailing)
            }
            .frame(width: proxy.size.width, height: 32, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
    }
}

private struct ActivityStateBlock: View {
    enum Style {
        case lockScreen
        case island
    }

    let state: TranscriptionActivityAttributes.ContentState
    let style: Style

    var body: some View {
        HStack(spacing: 7) {
            ActivityStatusDot(state: state, size: style == .lockScreen ? 8 : 7)

            VStack(alignment: .leading, spacing: 1) {
                Text("Status")
                    .font(.redditSans(size: style == .lockScreen ? 9 : 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(state.status)
                    .font(.redditSans(size: style == .lockScreen ? 13 : 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(minHeight: style == .lockScreen ? 30 : 24, alignment: .leading)
    }

    private var statusColor: Color {
        state.isRecording ? .red : .green
    }
}

private struct ActivityTopSummaryBlock: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text("Transcript")
                .font(.redditSans(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: 9, weight: .semibold))

                Text(state.languageName)
                    .lineLimit(1)
            }
            .font(.redditSans(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .top)
    }
}

private struct ActivityTimeBlock: View {
    enum Style {
        case lockScreen
        case island
    }

    let state: TranscriptionActivityAttributes.ContentState
    let style: Style

    var body: some View {
        LiveElapsedText(
            state: state,
            font: .redditSans(size: style == .lockScreen ? 18 : 13, weight: .bold)
        )
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.68)
        .frame(
            minWidth: style == .lockScreen ? 82 : 58,
            minHeight: style == .lockScreen ? 30 : 24,
            alignment: .trailing
        )
    }
}

private struct StopRecordingLink: View {
    private let stopURL = URL(string: "livetranscriber://stop-recording")!
    var height: CGFloat = 26

    var body: some View {
        Link(destination: stopURL) {
            Label("Stop", systemImage: "stop.fill")
                .font(.redditSans(.caption2, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: height)
                .background(.red, in: Capsule())
        }
    }
}

private struct ExpandedTranscriptionIslandContent: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ActivityTranscriptPanel(
                text: state.islandLatestText,
                lineLimit: 2,
                font: .redditSans(size: 13, weight: .semibold)
            )

            HStack(alignment: .center, spacing: 7) {
                ActivityMetricBlock(
                    label: "Lang",
                    value: state.languageName,
                    systemImage: "globe",
                    alignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if state.isRecording {
                    StopRecordingLink(height: 25)
                }
            }
        }
        .padding(.horizontal, LiveActivityLayout.islandHorizontalPadding)
        .padding(.top, 0)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactActivityGlyph: View {
    let state: TranscriptionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            ActivityStatusDot(state: state, size: 6, showsRing: false)

            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(state.isRecording ? .red : .green)
        }
        .frame(width: 28, height: 18, alignment: .center)
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

private struct ActivityMetricBlock: View {
    enum Alignment {
        case leading
        case trailing
    }

    let label: String
    let value: String
    let systemImage: String
    let alignment: Alignment

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 1) {
            Label(label, systemImage: systemImage)
                .font(.redditSans(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(.redditSans(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(minHeight: 24, alignment: frameAlignment)
    }

    private var horizontalAlignment: HorizontalAlignment {
        alignment == .leading ? .leading : .trailing
    }

    private var frameAlignment: SwiftUI.Alignment {
        alignment == .leading ? .leading : .trailing
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
#Preview("Home Small", as: .systemSmall) {
    LiveTranscriberHomeWidget()
} timeline: {
    LiveTranscriberHomeEntry(date: Date())
}

#Preview("Home Medium", as: .systemMedium) {
    LiveTranscriberHomeWidget()
} timeline: {
    LiveTranscriberHomeEntry(date: Date())
}

#Preview("Home Large", as: .systemLarge) {
    LiveTranscriberHomeWidget()
} timeline: {
    LiveTranscriberHomeEntry(date: Date())
}

#Preview("Live Activity", as: .content, using: TranscriptionActivityAttributes(startedAt: Date())) {
    TranscriptionLiveActivityWidget()
} contentStates: {
    TranscriptionActivityAttributes.ContentState(
        status: "Recording",
        languageName: "English",
        latestText: "This is a live transcript preview shown in Dynamic Island.",
        placeholderText: "Waiting for speech",
        elapsedSeconds: 92,
        timerReferenceDate: Date(timeIntervalSinceNow: -92),
        lineCount: 8,
        isRecording: true
    )
}
#endif
