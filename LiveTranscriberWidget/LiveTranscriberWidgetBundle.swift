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
        .configurationDisplayName(HomeWidgetL10n.appName)
        .description(HomeWidgetL10n.configurationDescription)
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
        LiveTranscriberHomeEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveTranscriberHomeEntry) -> Void) {
        completion(
            LiveTranscriberHomeEntry(
                date: Date(),
                snapshot: context.isPreview ? .preview : HomeWidgetSnapshotStore.load()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveTranscriberHomeEntry>) -> Void) {
        let entry = LiveTranscriberHomeEntry(
            date: Date(),
            snapshot: HomeWidgetSnapshotStore.load()
        )
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date) ?? entry.date
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct LiveTranscriberHomeEntry: TimelineEntry {
    let date: Date
    let snapshot: HomeWidgetSnapshot
}

private extension HomeWidgetSnapshot {
    static var preview: HomeWidgetSnapshot {
        HomeWidgetSnapshot(
            updatedAt: Date(),
            recordingCount: 12,
            recentRecordings: [
                HomeWidgetRecentRecording(
                    id: UUID(),
                    title: "Product Design Review",
                    createdAt: Date().addingTimeInterval(-12 * 60),
                    durationSeconds: 1_247,
                    languageName: "English"
                ),
                HomeWidgetRecentRecording(
                    id: UUID(),
                    title: "Weekly Planning",
                    createdAt: Date().addingTimeInterval(-4_800),
                    durationSeconds: 843,
                    languageName: "English"
                ),
                HomeWidgetRecentRecording(
                    id: UUID(),
                    title: "Interview Notes",
                    createdAt: Date().addingTimeInterval(-86_400),
                    durationSeconds: 2_106,
                    languageName: "Chinese"
                )
            ]
        )
    }
}

private struct LiveTranscriberHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LiveTranscriberHomeEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallHomeWidget(snapshot: entry.snapshot)
                .widgetURL(WidgetRoute.record.url)
        case .systemLarge:
            LargeHomeWidget(snapshot: entry.snapshot)
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
            MediumHomeWidget(snapshot: entry.snapshot)
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
    let snapshot: HomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetBrandHeader()

            Spacer(minLength: 8)

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(QuickRecordingControlL10n.startRecording)
                        .font(.redditSans(.title3, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Label(HomeWidgetL10n.liveTranscript, systemImage: "captions.bubble")
                        .font(.redditSans(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)

                WidgetRecordGlyph(size: 50)
            }

            if snapshot.recordingCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                    Text("\(snapshot.recordingCount)")
                        .monospacedDigit()
                }
                .font(.redditSans(.caption2, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityLabel(Text(HomeWidgetL10n.savedFiles))
            }
        }
    }
}

private struct MediumHomeWidget: View {
    let snapshot: HomeWidgetSnapshot

    var body: some View {
        HStack(spacing: 12) {
            WidgetRecordAction(compact: true)
                .frame(width: 112)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(HomeWidgetL10n.savedFiles)
                        .font(.redditSans(.caption, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Spacer(minLength: 0)

                    if snapshot.recordingCount > 0 {
                        Text("\(snapshot.recordingCount)")
                            .font(.redditSans(.caption2, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if let latestRecording = snapshot.recentRecordings.first {
                    WidgetRecentRecordingRow(recording: latestRecording, compact: true)
                } else {
                    WidgetEmptyRecentCard(compact: true)
                }

                HStack(spacing: 7) {
                    WidgetRouteButton(
                        route: .recordings,
                        systemImage: "folder.fill",
                        title: HomeWidgetL10n.files
                    )
                    WidgetRouteButton(
                        route: .settings,
                        systemImage: "gearshape.fill",
                        title: HomeWidgetL10n.settings
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LargeHomeWidget: View {
    let snapshot: HomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                WidgetBrandHeader()

                Spacer(minLength: 0)

                WidgetIconRouteButton(route: .settings, systemImage: "gearshape.fill")
            }

            WidgetRecordAction(compact: false)

            HStack(spacing: 8) {
                Label(HomeWidgetL10n.savedFiles, systemImage: "folder.fill")
                    .font(.redditSans(.subheadline, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if snapshot.recordingCount > 0 {
                    Text("\(snapshot.recordingCount)")
                        .font(.redditSans(.caption2, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 21)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }

                Spacer(minLength: 0)

                Link(destination: WidgetRoute.recordings.url) {
                    HStack(spacing: 4) {
                        Text(HomeWidgetL10n.files)
                        Image(systemName: "chevron.right")
                    }
                        .font(.redditSans(.caption2, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }

            if snapshot.recentRecordings.isEmpty {
                WidgetEmptyRecentCard(compact: false)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 7) {
                    ForEach(snapshot.recentRecordings.prefix(3)) { recording in
                        WidgetRecentRecordingRow(recording: recording, compact: false)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

private struct WidgetBrandHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.red.opacity(0.16))

                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.red)
                    .widgetAccentable()
            }
            .frame(width: 30, height: 30)

            Text(HomeWidgetL10n.appName)
                .font(.redditSans(.subheadline, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetRecordGlyph: View {
    let size: CGFloat
    var onTintedSurface = false

    var body: some View {
        ZStack {
            Group {
                if onTintedSurface {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                } else {
                    Circle()
                        .fill(.red.gradient)
                }
            }

            Circle()
                .stroke(Color.white.opacity(0.24), lineWidth: 1)

            Image(systemName: "waveform.and.mic")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}

private struct WidgetRecordAction: View {
    let compact: Bool

    var body: some View {
        Link(destination: WidgetRoute.record.url) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetRecordGlyph(size: 44, onTintedSurface: true)

                        Spacer(minLength: 8)

                        Text(HomeWidgetL10n.start)
                            .font(.redditSans(.title3, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(HomeWidgetL10n.recording)
                            .font(.redditSans(.caption2, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        WidgetRecordGlyph(size: 46, onTintedSurface: true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(QuickRecordingControlL10n.startRecording)
                                .font(.redditSans(.headline, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text(HomeWidgetL10n.liveTranscript)
                                .font(.redditSans(.caption, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                }
            }
            .background(.red.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityLabel(Text(QuickRecordingControlL10n.startRecording))
    }
}

private struct WidgetRecentRecordingRow: View {
    let recording: HomeWidgetRecentRecording
    let compact: Bool

    var body: some View {
        Link(destination: WidgetRoute.recording(recording.id).url) {
            HStack(spacing: compact ? 7 : 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                        .fill(.red.opacity(0.12))

                    Image(systemName: "waveform")
                        .font(.system(size: compact ? 11 : 13, weight: .bold))
                        .foregroundStyle(.red)
                        .widgetAccentable()
                }
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title)
                        .font(.redditSans(compact ? .caption : .subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(recording.createdAt, style: .relative)

                        Text("·")

                        Text(durationText)
                            .monospacedDigit()

                        if !compact, !recording.languageName.isEmpty {
                            Text("·")
                            Text(recording.languageName)
                                .lineLimit(1)
                        }
                    }
                    .font(.redditSans(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 48 : 50)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        let totalSeconds = max(recording.durationSeconds, 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct WidgetEmptyRecentCard: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "folder")
                .font(.system(size: compact ? 14 : 17, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(HomeWidgetL10n.quickActionsDescription)
                .font(.redditSans(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 9 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 48 : 62, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetRouteButton: View {
    let route: WidgetRoute
    let systemImage: String
    let title: LocalizedStringResource

    var body: some View {
        Link(destination: route.url) {
            Label(title, systemImage: systemImage)
                .font(.redditSans(.caption2, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}

private struct WidgetIconRouteButton: View {
    let route: WidgetRoute
    let systemImage: String

    var body: some View {
        Link(destination: route.url) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
    }
}

private enum WidgetRoute {
    case record
    case recording(UUID)
    case recordings
    case settings

    var url: URL {
        switch self {
        case .record:
            return URL(string: "livetranscriber://record?start=1")!
        case .recording(let id):
            return URL(string: "livetranscriber://recording/\(id.uuidString)")!
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
                Text(HomeWidgetL10n.activityStatus)
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
            Text(HomeWidgetL10n.activityTranscript)
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
            Label(HomeWidgetL10n.activityStop, systemImage: "stop.fill")
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
                    label: HomeWidgetL10n.activityLanguage,
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

    let label: LocalizedStringResource
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
    LiveTranscriberHomeEntry(date: Date(), snapshot: .preview)
}

#Preview("Home Medium", as: .systemMedium) {
    LiveTranscriberHomeWidget()
} timeline: {
    LiveTranscriberHomeEntry(date: Date(), snapshot: .preview)
}

#Preview("Home Large", as: .systemLarge) {
    LiveTranscriberHomeWidget()
} timeline: {
    LiveTranscriberHomeEntry(date: Date(), snapshot: .preview)
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
