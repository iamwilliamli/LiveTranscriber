import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @State private var iCloudSyncRefreshTick = 0
    private static let repositoryURL = URL(string: "https://github.com/iamwilliamli/LiveTranscriber")!
    private static let designNotesURL = URL(string: "https://chengqili.com/post/livetranscriber/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink {
                        transcriptionSettingsPage
                    } label: {
                        SettingsNavigationRow(
                            icon: "captions.bubble",
                            titleResource: L10n.Settings.transcription,
                            value: transcriber.selectedLanguage.displayName,
                            subtitleResource: L10n.Settings.languageAndModel,
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink {
                        recordingSettingsPage
                    } label: {
                        SettingsNavigationRow(
                            icon: "waveform.badge.mic",
                            titleResource: L10n.Settings.recording,
                            value: transcriber.selectedAudioFormat.title,
                            subtitleResource: L10n.Settings.audioFormatAndBehavior,
                            tint: AppTheme.brand
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink {
                        fileSettingsPage
                    } label: {
                        SettingsNavigationRow(
                            icon: "folder",
                            titleResource: L10n.Settings.files,
                            value: recordingStore.storageDisplayName,
                            subtitleResource: L10n.Settings.storageLocationAndCount,
                            tint: AppTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink {
                        privacySettingsPage
                    } label: {
                        SettingsNavigationRow(
                            icon: "lock.shield",
                            titleResource: L10n.Settings.privacy,
                            value: String(localized: L10n.Settings.localProcessing),
                            subtitleResource: L10n.Settings.dataBoundariesAndPermissions,
                            tint: AppTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink {
                        sourceSettingsPage
                    } label: {
                        SettingsNavigationRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            titleResource: L10n.Source.title,
                            value: String(localized: L10n.Source.sourceAvailable),
                            subtitleResource: L10n.Source.subtitle,
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()

                    NavigationLink {
                        developerSettingsPage
                    } label: {
                        SettingsNavigationRow(
                            icon: "wrench.and.screwdriver",
                            titleResource: L10n.Settings.developerOptions,
                            value: transcriber.speechPipelineDiagnostics.activePipelineName,
                            subtitleResource: L10n.Settings.deviceAndPipelineDiagnostics,
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsSurface()
                }
                .padding()
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .toolbar(.visible, for: .navigationBar)
            .navigationTitle(String(localized: L10n.Settings.title))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            await recordingStore.reload()
            recordingStore.refreshIntelligenceAvailability()
        }
        .task {
            await refreshICloudSyncStatusPeriodically()
        }
    }

    private var transcriptionSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.transcription) {
            SettingsSection(titleResource: L10n.Settings.transcription, systemImage: "captions.bubble", tint: AppTheme.info) {
                NavigationLink {
                    transcriptionLanguagePage
                } label: {
                        SettingsNavigationRow(
                            icon: "globe",
                            titleResource: L10n.Settings.transcriptionLanguage,
                            value: transcriber.selectedLanguage.displayName,
                            subtitleResource: L10n.Settings.nextStartUsesLanguage,
                            tint: AppTheme.info
                        )
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", textResource: L10n.Settings.cannotChangeLanguageWhileRecording, tint: AppTheme.warning)
                }
            }
        }
    }

    private var transcriptionLanguagePage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.transcriptionLanguage) {
            SettingsSection(titleResource: L10n.Settings.transcriptionLanguage, systemImage: "globe", tint: AppTheme.info) {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedLanguageID = language.id
                    } label: {
                        SettingsSelectionRow(
                            icon: "globe",
                            title: language.displayName,
                            subtitle: language.id,
                            isSelected: language.id == transcriber.selectedLanguageID,
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(transcriber.isRecording || transcriber.isPreparing)
                }
            }
        }
    }

    private var recordingSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.recording) {
            SettingsSection(titleResource: L10n.Settings.recording, systemImage: "waveform.badge.mic", tint: AppTheme.brand) {
                NavigationLink {
                    recordingFormatPage
                } label: {
                    SettingsNavigationRow(
                        icon: "waveform.badge.mic",
                        titleResource: L10n.Settings.recordingFormat,
                        value: transcriber.selectedAudioFormat.title,
                        subtitleResource: transcriber.selectedAudioFormat.detailResource,
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", textResource: L10n.Settings.cannotChangeFormatWhileRecording, tint: AppTheme.warning)
                }
            }
        }
    }

    private var recordingFormatPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.recordingFormat) {
            SettingsSection(titleResource: L10n.Settings.recordingFormat, systemImage: "waveform.badge.mic", tint: AppTheme.brand) {
                ForEach(RecordingAudioFormat.allCases) { format in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedAudioFormat = format
                    } label: {
                        SettingsSelectionRow(
                            icon: format == .wav ? "waveform" : "waveform.badge.plus",
                            title: format.title,
                            subtitleResource: format.detailResource,
                            isSelected: format == transcriber.selectedAudioFormat,
                            tint: AppTheme.brand
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(transcriber.isRecording || transcriber.isPreparing)
                }
            }
        }
    }

    private var fileSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.files) {
            fileSection
        }
    }

    private var iCloudStorageBinding: Binding<Bool> {
        Binding {
            recordingStore.isICloudStorageEnabled
        } set: { isEnabled in
            HapticFeedback.play(.menuSelection)
            Task {
                await recordingStore.setICloudStorageEnabled(isEnabled)
            }
        }
    }

    private var developerSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.developerOptions) {
            developerSection
        }
    }

    private var privacySettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.privacy) {
            SettingsSection(titleResource: L10n.Settings.localProcessing, systemImage: "lock.shield", tint: AppTheme.success) {
                SettingsStatusRow(
                    icon: "server.rack",
                    textResource: L10n.Settings.noDeveloperServers,
                    tint: AppTheme.success
                )

                SettingsStatusRow(
                    icon: "waveform.badge.mic",
                    textResource: L10n.Settings.onDeviceProcessing,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "person.crop.circle.badge.xmark",
                    textResource: L10n.Settings.developerCannotAccessContent,
                    tint: AppTheme.success
                )
            }

            SettingsSection(titleResource: L10n.Settings.storage, systemImage: "internaldrive", tint: AppTheme.info) {
                SettingsMetricRow(
                    icon: "folder",
                    titleResource: L10n.Settings.currentLocation,
                    value: recordingStore.storageDisplayName,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "icloud",
                    textResource: L10n.Settings.localThenICloudStorage,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "list.bullet.rectangle",
                    textResource: L10n.Settings.indexSyncPrivateDatabase,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "trash",
                    textResource: L10n.Settings.deleteRemovesManagedFiles,
                    tint: AppTheme.danger
                )
            }

            SettingsSection(titleResource: L10n.Settings.permissionUsage, systemImage: "checkmark.shield", tint: AppTheme.brand) {
                SettingsStatusRow(
                    icon: "mic",
                    textResource: L10n.Settings.microphonePermissionUse,
                    tint: AppTheme.brand
                )

                SettingsStatusRow(
                    icon: "captions.bubble",
                    textResource: L10n.Settings.speechPermissionUse,
                    tint: AppTheme.brand
                )

                SettingsStatusRow(
                    icon: "location",
                    textResource: L10n.Settings.locationPermissionUse,
                    tint: AppTheme.brand
                )

                SettingsStatusRow(
                    icon: "camera",
                    textResource: L10n.Settings.cameraPermissionUse,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "waveform.circle",
                    textResource: L10n.Settings.backgroundAudioUse,
                    tint: AppTheme.warning
                )
            }
        }
    }

    private var sourceSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Source.title) {
            SettingsSection(titleResource: L10n.Source.title, systemImage: "chevron.left.forwardslash.chevron.right", tint: AppTheme.info) {
                SettingsStatusRow(
                    icon: "doc.text",
                    textResource: L10n.Source.description,
                    tint: AppTheme.info
                )

                SettingsStatusRow(
                    icon: "exclamationmark.shield",
                    textResource: L10n.Source.licenseNote,
                    tint: AppTheme.warning
                )

                SettingsStatusRow(
                    icon: "person.text.rectangle",
                    textResource: L10n.Source.requiredAttribution,
                    tint: AppTheme.info
                )

                Link(destination: Self.repositoryURL) {
                    SettingsExternalLinkRow(
                        icon: "link",
                        titleResource: L10n.Source.repositoryTitle,
                        value: Self.repositoryURL.absoluteString,
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)

                Link(destination: Self.designNotesURL) {
                    SettingsExternalLinkRow(
                        icon: "doc.text.magnifyingglass",
                        titleResource: L10n.Source.designNotesTitle,
                        value: Self.designNotesURL.absoluteString,
                        tint: AppTheme.info
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var speechPipelineModePage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.speechPipelineMode) {
            SettingsSection(titleResource: L10n.Settings.speechPipelineMode, systemImage: "waveform.path.ecg", tint: AppTheme.brand) {
                ForEach(SpeechPipelineMode.allCases) { mode in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedSpeechPipelineMode = mode
                    } label: {
                        SettingsSelectionRow(
                            icon: mode == .nativeIOS27 ? "sparkles" : "checkmark.shield",
                            title: mode.title,
                            subtitleResource: mode.detailResource,
                            isSelected: mode == transcriber.selectedSpeechPipelineMode,
                            tint: mode.isSupportedOnCurrentOS ? AppTheme.brand : AppTheme.warning
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!mode.isSupportedOnCurrentOS || transcriber.isRecording || transcriber.isPreparing)
                }

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", textResource: L10n.Settings.cannotChangePipelineWhileRecording, tint: AppTheme.warning)
                }
            }
        }
    }

    private var fileSection: some View {
        let refreshTick = iCloudSyncRefreshTick
        let iCloudSyncSummary = recordingStore.iCloudSyncSummary
        let iCloudSyncTint = iCloudSyncSummary.failedRecordingCount > 0 ? AppTheme.warning : AppTheme.info

        return SettingsSection(titleResource: L10n.Settings.files, systemImage: "folder", tint: AppTheme.success) {
            SettingsMetricRow(
                icon: "number",
                titleResource: L10n.Settings.recordingCount,
                value: "\(recordingStore.recordings.count)",
                tint: AppTheme.success
            )

            SettingsMetricRow(
                icon: "icloud",
                titleResource: L10n.Settings.storageLocation,
                value: recordingStore.storageDisplayName,
                tint: AppTheme.info
            )

            Toggle(isOn: iCloudStorageBinding) {
                HStack(alignment: .top, spacing: 10) {
                    SettingsIcon(systemImage: "icloud", tint: AppTheme.info)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Settings.iCloudSync)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(L10n.Settings.iCloudSyncDescription)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(recordingStore.isStorageLocationChanging)

            SettingsMetricRow(
                icon: "icloud.and.arrow.up",
                titleResource: L10n.Settings.iCloudStatus,
                value: recordingStore.iCloudStorageStatusDisplayName,
                tint: recordingStore.isICloudStorageEnabled ? AppTheme.info : AppTheme.warning
            )

            SettingsVerbatimStatusRow(
                icon: recordingStore.isICloudStorageEnabled ? "icloud" : "internaldrive",
                text: recordingStore.iCloudStorageDetailText,
                tint: recordingStore.isICloudStorageEnabled ? AppTheme.info : AppTheme.success
            )

            SettingsMetricRow(
                icon: iCloudSyncSummary.systemImage,
                titleResource: L10n.Settings.iCloudProgress,
                value: iCloudSyncSummary.statusText,
                tint: iCloudSyncTint
            )
            .id(refreshTick)

            SettingsVerbatimStatusRow(
                icon: iCloudSyncSummary.systemImage,
                text: iCloudSyncSummary.detailText,
                tint: iCloudSyncTint
            )
            .id("detail-\(refreshTick)")
        }
    }

    private func refreshICloudSyncStatusPeriodically() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }

            await MainActor.run {
                iCloudSyncRefreshTick &+= 1
            }
        }
    }

    private var developerSection: some View {
        let availability = recordingStore.intelligenceAvailability
        let tint = availability.isAvailable ? AppTheme.success : AppTheme.warning
        let device = DeveloperDeviceInfo.current
        let build = DeveloperBuildInfo.current
        let pipeline = transcriber.speechPipelineDiagnostics

        return SettingsSection(titleResource: L10n.Settings.developerOptions, systemImage: "wrench.and.screwdriver", tint: AppTheme.purple) {
            SettingsMetricRow(
                icon: "iphone",
                titleResource: L10n.Settings.device,
                value: device.modelIdentifier,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "gearshape",
                titleResource: L10n.Settings.systemVersion,
                value: device.systemVersion,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "number",
                titleResource: L10n.Settings.version,
                value: build.version,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "calendar.badge.clock",
                titleResource: L10n.Settings.buildTime,
                value: build.buildTime,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "waveform.path.ecg",
                titleResource: L10n.Settings.currentSpeechPipeline,
                value: pipeline.activePipelineName,
                tint: AppTheme.brand
            )

            NavigationLink {
                speechPipelineModePage
            } label: {
                SettingsNavigationRow(
                    icon: "slider.horizontal.3",
                    titleResource: L10n.Settings.speechPipelineMode,
                    value: pipeline.configuredPipelineName,
                    subtitleResource: L10n.Settings.switchPipelineSubtitle,
                    tint: AppTheme.brand
                )
            }
            .buttonStyle(.plain)
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            SettingsVerbatimStatusRow(
                icon: "slider.horizontal.3",
                text: pipeline.supportedPipelinesText,
                tint: AppTheme.brand
            )

            SettingsVerbatimStatusRow(
                icon: "waveform",
                text: pipeline.analyzerFormatText,
                tint: AppTheme.info
            )

            SettingsVerbatimStatusRow(
                icon: "waveform.path",
                text: pipeline.runtimeAnalyzerFormatText,
                tint: AppTheme.info
            )

            SettingsMetricRow(
                icon: "sparkles",
                titleResource: L10n.Settings.advancedModel,
                value: availability.statusText,
                tint: tint
            )

            SettingsVerbatimStatusRow(
                icon: availability.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                text: availability.detailText,
                tint: tint
            )
        }
    }
}

private struct DeveloperBuildInfo {
    var version: String
    var buildTime: String

    static var current: DeveloperBuildInfo {
        DeveloperBuildInfo(
            version: versionText(),
            buildTime: buildTimeText()
        )
    }

    private static func versionText(bundle: Bundle = .main) -> String {
        let unknown = String(localized: L10n.Common.unknown)
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? unknown
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        guard let build else {
            return version
        }

        return "\(version) (\(build))"
    }

    private static func buildTimeText(bundle: Bundle = .main) -> String {
        if let stampedTimestamp = bundle.object(forInfoDictionaryKey: "LTBuildTimestamp") as? String,
           let stampedDate = iso8601Formatter.date(from: stampedTimestamp) {
            return displayFormatter.string(from: stampedDate)
        }

        if let executableURL = bundle.executableURL,
           let values = try? executableURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let date = values.contentModificationDate {
            return displayFormatter.string(from: date)
        }

        return String(localized: L10n.Common.unknown)
    }

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter
    }()
}

private struct DeveloperDeviceInfo {
    var modelIdentifier: String
    var systemVersion: String

    static var current: DeveloperDeviceInfo {
        DeveloperDeviceInfo(
            modelIdentifier: machineIdentifier(),
            systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        )
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { reboundPointer in
                String(cString: reboundPointer)
            }
        }
    }
}

private struct SettingsDetailPage<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    init(titleResource: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = Text(titleResource)
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding()
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: Text
    let value: String
    let subtitle: Text
    let tint: Color

    init(
        icon: String,
        titleResource: LocalizedStringResource,
        value: String,
        subtitleResource: LocalizedStringResource,
        tint: Color
    ) {
        self.icon = icon
        self.title = Text(titleResource)
        self.value = value
        self.subtitle = Text(subtitleResource)
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                subtitle
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Text(value)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsSelectionRow: View {
    let icon: String
    let title: Text
    let subtitle: Text
    let isSelected: Bool
    let tint: Color

    init(icon: String, title: String, subtitle: String, isSelected: Bool, tint: Color) {
        self.icon = icon
        self.title = Text(verbatim: title)
        self.subtitle = Text(verbatim: subtitle)
        self.isSelected = isSelected
        self.tint = tint
    }

    init(icon: String, title: String, subtitleResource: LocalizedStringResource, isSelected: Bool, tint: Color) {
        self.icon = icon
        self.title = Text(verbatim: title)
        self.subtitle = Text(subtitleResource)
        self.isSelected = isSelected
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                subtitle
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct SettingsSection<Content: View>: View {
    let title: Text
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    init(titleResource: LocalizedStringResource, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = Text(titleResource)
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettingsIcon(systemImage: systemImage, tint: tint)

                title
                    .font(.redditSans(.headline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)
            }

            content
        }
        .settingsSurface()
    }
}

private struct SettingsMetricRow: View {
    let icon: String
    let title: Text
    let value: String
    let tint: Color

    init(icon: String, titleResource: LocalizedStringResource, value: String, tint: Color) {
        self.icon = icon
        self.title = Text(titleResource)
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            title
                .font(.redditSans(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsExternalLinkRow: View {
    let icon: String
    let title: Text
    let value: String
    let tint: Color

    init(icon: String, titleResource: LocalizedStringResource, value: String, tint: Color) {
        self.icon = icon
        self.title = Text(titleResource)
        self.value = value
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(value)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 12)

            Image(systemName: "arrow.up.forward")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct SettingsStatusRow: View {
    let icon: String
    let text: Text
    let tint: Color

    init(icon: String, textResource: LocalizedStringResource, tint: Color) {
        self.icon = icon
        self.text = Text(textResource)
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            text
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsVerbatimStatusRow: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
    }
}

private extension View {
    func settingsSurface() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(color: AppTheme.cardShadow, radius: 7, y: 2)
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(
        transcriber: LiveTranscriptionManager(),
        recordingStore: RecordingStore()
    )
    .font(.redditSans(.body))
    .tint(AppTheme.brand)
}
#endif
