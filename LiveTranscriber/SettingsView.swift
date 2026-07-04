import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @State private var iCloudSyncRefreshTick = 0
    @State private var pendingSpeechLocaleReleaseRequest: SpeechLocaleReleaseRequest?
    @State private var speechLocaleErrorMessage: String?
    @State private var feedbackErrorMessage: String?
    @State private var selectedLocalWhisperModel = LocalWhisperModelManager.selectedModel
    @State private var localWhisperModelStatus = LocalWhisperModelManager.currentStatus()
    @State private var localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
    @State private var isLocalWhisperCoreMLEncoderLoadingEnabled = LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled
    @State private var selectedLiveWhisperModel = LocalWhisperModelManager.selectedLiveModel
    @State private var liveWhisperModelStatus = LocalWhisperModelManager.currentLiveStatus()
    @State private var liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
    @State private var isDownloadingLocalWhisperModel = false
    @State private var isDownloadingLocalWhisperCoreMLEncoder = false
    @State private var isDownloadingLiveWhisperModel = false
    @State private var isDownloadingLiveWhisperCoreMLEncoder = false
    @State private var localWhisperDownloadProgress: Double = 0
    @State private var localWhisperCoreMLEncoderDownloadProgress: Double = 0
    @State private var liveWhisperDownloadProgress: Double = 0
    @State private var liveWhisperCoreMLEncoderDownloadProgress: Double = 0
    @State private var localWhisperDownloadErrorMessage: String?
    @State private var localWhisperDeleteErrorMessage: String?
    @State private var localWhisperModelRefreshTick = 0
    private static let repositoryURL = URL(string: "https://github.com/iamwilliamli/LiveTranscriber")!
    private static let designNotesURL = URL(string: "https://chengqili.com/post/livetranscriber")!
    private static let feedbackRecipient = "lichengqi0805@gmail.com"
    private static let mailtoQueryAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        return allowed
    }()
    private static let localWhisperSubtitleTrailingCharacters = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)

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

                    Button {
                        sendFeedbackEmail()
                    } label: {
                        SettingsCommandRow(
                            icon: "envelope",
                            titleResource: L10n.Settings.feedback,
                            tint: AppTheme.brand
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
            refreshLocalWhisperModelStatus()
        }
        .task {
            await refreshICloudSyncStatusPeriodically()
        }
        .alert(
            String(localized: L10n.SpeechText.releaseOldLanguagesTitle),
            isPresented: Binding(
                get: { pendingSpeechLocaleReleaseRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingSpeechLocaleReleaseRequest = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.SpeechText.releaseOldLanguagesAction), role: .destructive) {
                if let pendingSpeechLocaleReleaseRequest {
                    releaseSpeechLocalesAndSelectLanguage(pendingSpeechLocaleReleaseRequest)
                }
                pendingSpeechLocaleReleaseRequest = nil
            }
            Button(String(localized: L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(pendingSpeechLocaleReleaseRequest?.messageText ?? "")
        }
        .alert(
            String(localized: L10n.SpeechText.localeSetupFailed),
            isPresented: Binding(
                get: { speechLocaleErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        speechLocaleErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(speechLocaleErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.LocalWhisper.downloadFailed),
            isPresented: Binding(
                get: { localWhisperDownloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localWhisperDownloadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(localWhisperDownloadErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.LocalWhisper.deleteFailed),
            isPresented: Binding(
                get: { localWhisperDeleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localWhisperDeleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(localWhisperDeleteErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.Settings.feedbackUnavailable),
            isPresented: Binding(
                get: { feedbackErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        feedbackErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(feedbackErrorMessage ?? "")
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

                openAITranscriptionToggleSettings

                if transcriber.isOpenAITranscriptionEnabled {
                    openAITranscriptionAPIKeySettings
                }

                localWhisperModelSettings

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", textResource: L10n.Settings.cannotChangeLanguageWhileRecording, tint: AppTheme.warning)
                }
            }

            SettingsSection(titleResource: L10n.Settings.betaFeatures, systemImage: "testtube.2", tint: AppTheme.purple) {
                localWhisperLiveBetaSettings
            }
        }
    }

    private var localWhisperModelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                localWhisperModelPage
            } label: {
                SettingsNavigationRow(
                    icon: "cube",
                    titleResource: L10n.LocalWhisper.selectedModel,
                    value: selectedLocalWhisperModel.displayName,
                    subtitle: selectedLocalWhisperModel.detail,
                    tint: AppTheme.info
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloadingLocalWhisperModel || isDownloadingLocalWhisperCoreMLEncoder)

            SettingsMetricRow(
                icon: "iphone",
                titleResource: L10n.LocalWhisper.modelStatus,
                value: isDownloadingLocalWhisperModel ? localWhisperDownloadProgressText : localWhisperModelStatus.statusText,
                tint: localWhisperModelStatus.isAvailable ? AppTheme.success : AppTheme.warning
            )

            SettingsVerbatimStatusRow(
                icon: localWhisperModelStatus.isAvailable ? "checkmark.circle" : "arrow.down.circle",
                text: localWhisperModelStatus.detailText,
                tint: localWhisperModelStatus.isAvailable ? AppTheme.success : AppTheme.info
            )

            if isDownloadingLocalWhisperModel {
                ProgressView(value: localWhisperDownloadProgress)
                    .tint(AppTheme.info)
                    .frame(maxWidth: .infinity)
            }

            if !localWhisperModelStatus.isAvailable {
                Button {
                    downloadLocalWhisperModel()
                } label: {
                    SettingsCommandRow(
                        icon: "arrow.down.circle",
                        titleResource: L10n.LocalWhisper.downloadSelectedModel,
                        tint: AppTheme.info
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDownloadingLocalWhisperModel || isDownloadingLocalWhisperCoreMLEncoder)
            }

            if localWhisperModelStatus.isAvailable {
                Toggle(isOn: localWhisperCoreMLEncoderLoadingBinding) {
                    HStack(alignment: .top, spacing: 10) {
                        SettingsIcon(systemImage: "bolt.badge.clock", tint: AppTheme.info)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.LocalWhisper.coreMLEncoderLoading)
                                .font(.redditSans(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(L10n.LocalWhisper.coreMLEncoderLoadingDescription)
                                .font(.redditSans(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                if isLocalWhisperCoreMLEncoderLoadingEnabled {
                    SettingsMetricRow(
                        icon: "cpu",
                        titleResource: L10n.LocalWhisper.coreMLEncoderStatus,
                        value: isDownloadingLocalWhisperCoreMLEncoder ? localWhisperCoreMLEncoderDownloadProgressText : localWhisperCoreMLEncoderStatus.statusText,
                        tint: localWhisperCoreMLEncoderStatus.isAvailable ? AppTheme.success : AppTheme.warning
                    )

                    SettingsVerbatimStatusRow(
                        icon: localWhisperCoreMLEncoderStatus.isAvailable ? "checkmark.circle" : "bolt.badge.clock",
                        text: localWhisperCoreMLEncoderStatus.detailText,
                        tint: localWhisperCoreMLEncoderStatus.isAvailable ? AppTheme.success : AppTheme.info
                    )

                    if isDownloadingLocalWhisperCoreMLEncoder {
                        ProgressView(value: localWhisperCoreMLEncoderDownloadProgress)
                            .tint(AppTheme.info)
                            .frame(maxWidth: .infinity)
                    }

                    if !localWhisperCoreMLEncoderStatus.isAvailable {
                        Button {
                            downloadLocalWhisperCoreMLEncoder()
                        } label: {
                            SettingsCommandRow(
                                icon: "bolt.badge.clock",
                                titleResource: L10n.LocalWhisper.downloadCoreMLEncoder,
                                tint: AppTheme.info
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloadingLocalWhisperModel || isDownloadingLocalWhisperCoreMLEncoder)
                    }
                }
            }

        }
    }

    private var localWhisperModelPage: some View {
        let refreshTick = localWhisperModelRefreshTick
        let downloadedStatuses = LocalWhisperModelManager.downloadedStatuses()

        return SettingsDetailPage(titleResource: L10n.LocalWhisper.selectedModel) {
            SettingsSection(titleResource: L10n.LocalWhisper.modelTitle, systemImage: "cube", tint: AppTheme.info) {
                ForEach(LocalWhisperModelManager.availableModels) { model in
                    let status = LocalWhisperModelManager.status(for: model)
                    Button {
                        selectLocalWhisperModel(model)
                    } label: {
                        SettingsSelectionRow(
                            icon: localWhisperModelIcon(for: model),
                            title: model.displayName,
                            subtitle: localWhisperModelSubtitle(for: model, status: status),
                            isSelected: model.id == selectedLocalWhisperModel.id,
                            tint: status.isAvailable ? AppTheme.success : AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingLocalWhisperModel || isDownloadingLocalWhisperCoreMLEncoder)
                }
            }
            .id("available-\(refreshTick)")

            SettingsSection(titleResource: L10n.LocalWhisper.downloadedModelsTitle, systemImage: "internaldrive", tint: AppTheme.success) {
                if downloadedStatuses.isEmpty {
                    SettingsStatusRow(
                        icon: "tray",
                        textResource: L10n.LocalWhisper.noDownloadedModels,
                        tint: AppTheme.info
                    )
                } else {
                    ForEach(downloadedStatuses, id: \.model.id) { status in
                        Button(role: .destructive) {
                            deleteLocalWhisperModel(status.model)
                        } label: {
                            SettingsModelManagementRow(
                                icon: "trash",
                                title: status.model.displayName,
                                subtitle: status.detailText,
                                actionResource: L10n.LocalWhisper.deleteModelDownload,
                                tint: AppTheme.danger
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloadingLocalWhisperModel || isDownloadingLocalWhisperCoreMLEncoder)
                    }
                }
            }
            .id("downloaded-\(refreshTick)")
        }
    }

    private var localWhisperDownloadProgressText: String {
        String(
            format: String(localized: L10n.LocalWhisper.downloadingModelFormat),
            localWhisperDownloadProgress * 100
        )
    }

    private var localWhisperCoreMLEncoderDownloadProgressText: String {
        String(
            format: String(localized: L10n.LocalWhisper.downloadingCoreMLEncoderFormat),
            localWhisperCoreMLEncoderDownloadProgress * 100
        )
    }

    private var liveWhisperDownloadProgressText: String {
        String(
            format: String(localized: L10n.LocalWhisper.downloadingModelFormat),
            liveWhisperDownloadProgress * 100
        )
    }

    private var liveWhisperCoreMLEncoderDownloadProgressText: String {
        String(
            format: String(localized: L10n.LocalWhisper.downloadingCoreMLEncoderFormat),
            liveWhisperCoreMLEncoderDownloadProgress * 100
        )
    }

    private func refreshLocalWhisperModelStatus() {
        selectedLocalWhisperModel = LocalWhisperModelManager.selectedModel
        localWhisperModelStatus = LocalWhisperModelManager.currentStatus()
        localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
        selectedLiveWhisperModel = LocalWhisperModelManager.selectedLiveModel
        liveWhisperModelStatus = LocalWhisperModelManager.currentLiveStatus()
        liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
        localWhisperModelRefreshTick &+= 1
    }

    private func sendFeedbackEmail() {
        guard let url = feedbackMailURL() else {
            feedbackErrorMessage = String(
                format: String(localized: L10n.Settings.feedbackOpenFailedFormat),
                Self.feedbackRecipient
            )
            HapticFeedback.play(.failure)
            return
        }

        HapticFeedback.play(.menuSelection)
        UIApplication.shared.open(url) { success in
            if !success {
                DispatchQueue.main.async {
                    feedbackErrorMessage = String(
                        format: String(localized: L10n.Settings.feedbackOpenFailedFormat),
                        Self.feedbackRecipient
                    )
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func feedbackMailURL() -> URL? {
        guard let subject = feedbackEmailSubject().addingPercentEncoding(withAllowedCharacters: Self.mailtoQueryAllowedCharacters),
              let body = feedbackEmailBody().addingPercentEncoding(withAllowedCharacters: Self.mailtoQueryAllowedCharacters) else {
            return nil
        }

        return URL(string: "mailto:\(Self.feedbackRecipient)?subject=\(subject)&body=\(body)")
    }

    private func feedbackEmailSubject() -> String {
        let build = DeveloperBuildInfo.current
        return "LiveTranscriber Feedback - \(build.version)"
    }

    private func feedbackEmailBody() -> String {
        let build = DeveloperBuildInfo.current
        let device = DeveloperDeviceInfo.current
        let pipeline = transcriber.speechPipelineDiagnostics
        let localWhisperModel = LocalWhisperModelManager.selectedModel.displayName
        let liveWhisperModel = LocalWhisperModelManager.selectedLiveModel?.displayName ?? String(localized: L10n.LocalWhisper.liveModelNotSelected)
        let coreMLEncoderState = LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled ? "On" : "Off"

        return [
            "Hi,",
            "",
            "Please describe your feedback or issue here:",
            "",
            "",
            "Steps to reproduce:",
            "1.",
            "2.",
            "3.",
            "",
            "Expected result:",
            "",
            "",
            "Actual result:",
            "",
            "",
            "---",
            "Diagnostics",
            "App: LiveTranscriber",
            "Version: \(build.version)",
            "Build Time: \(build.buildTime)",
            "Device: \(device.modelIdentifier)",
            "System: \(device.systemVersion)",
            "Current Pipeline: \(pipeline.activePipelineName)",
            "Configured Pipeline: \(pipeline.configuredPipelineName)",
            "Selected Language: \(transcriber.selectedLanguage.displayName) (\(transcriber.selectedLanguageID))",
            "Live Backend: \(transcriber.selectedTranscriptionBackend.title)",
            "Local Whisper Model: \(localWhisperModel)",
            "Realtime Whisper Model: \(liveWhisperModel)",
            "Core ML Encoder Loading: \(coreMLEncoderState)",
            "Recording Count: \(recordingStore.recordings.count)",
            "Storage: \(recordingStore.storageDisplayName)"
        ].joined(separator: "\r\n")
    }

    private func selectLocalWhisperModel(_ model: LocalWhisperModel) {
        HapticFeedback.play(.menuSelection)
        LocalWhisperModelManager.selectModel(model)
        selectedLocalWhisperModel = model
        localWhisperModelStatus = LocalWhisperModelManager.status(for: model)
        localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.coreMLEncoderStatus(for: model)
        Task {
            await transcriber.refreshSupportedLanguages()
        }
    }

    private func selectLiveWhisperModel(_ model: LocalWhisperModel) {
        HapticFeedback.play(.menuSelection)
        LocalWhisperModelManager.selectLiveModel(model)
        selectedLiveWhisperModel = model
        liveWhisperModelStatus = LocalWhisperModelManager.status(for: model)
        liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.coreMLEncoderStatus(for: model)
        Task {
            await transcriber.refreshSupportedLanguages()
        }
    }

    private func localWhisperModelSubtitle(
        for model: LocalWhisperModel,
        status: LocalWhisperModelStatus
    ) -> String {
        let detail = model.detail.trimmingCharacters(in: Self.localWhisperSubtitleTrailingCharacters)
        let statusText = status.statusText
        return String(
            format: String(localized: L10n.LocalWhisper.modelChoiceSubtitleFormat),
            detail,
            statusText,
            model.expectedSizeText
        )
    }

    private func localWhisperModelIcon(for model: LocalWhisperModel) -> String {
        if model.id.contains("large") {
            return "archivebox.fill"
        }
        if model.id.contains("medium") {
            return "shippingbox.fill"
        }
        if model.id.contains("small") {
            return "cube.fill"
        }
        if model.id.contains("tiny") {
            return "cube"
        }
        return "shippingbox"
    }

    private func downloadLocalWhisperModel() {
        guard !isDownloadingLocalWhisperModel else {
            return
        }

        isDownloadingLocalWhisperModel = true
        localWhisperDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await LocalWhisperModelManager.downloadSelectedModel { progress in
                    Task { @MainActor in
                        localWhisperDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    selectedLocalWhisperModel = status.model
                    localWhisperModelStatus = status
                    localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
                    liveWhisperModelStatus = LocalWhisperModelManager.currentLiveStatus()
                    liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
                    isDownloadingLocalWhisperModel = false
                    localWhisperDownloadProgress = 1
                    localWhisperModelRefreshTick &+= 1
                    HapticFeedback.play(.menuSelection)
                    Task {
                        await transcriber.refreshSupportedLanguages()
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloadingLocalWhisperModel = false
                    localWhisperDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func downloadLocalWhisperCoreMLEncoder() {
        guard !isDownloadingLocalWhisperCoreMLEncoder,
              localWhisperModelStatus.isAvailable else {
            HapticFeedback.play(.blocked)
            return
        }

        isDownloadingLocalWhisperCoreMLEncoder = true
        localWhisperCoreMLEncoderDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await LocalWhisperModelManager.downloadCoreMLEncoder(for: selectedLocalWhisperModel) { progress in
                    Task { @MainActor in
                        localWhisperCoreMLEncoderDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    localWhisperCoreMLEncoderStatus = status
                    liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
                    isDownloadingLocalWhisperCoreMLEncoder = false
                    localWhisperCoreMLEncoderDownloadProgress = 1
                    localWhisperModelRefreshTick &+= 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    isDownloadingLocalWhisperCoreMLEncoder = false
                    localWhisperDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func downloadLiveWhisperModel() {
        guard !isDownloadingLiveWhisperModel,
              let selectedLiveWhisperModel else {
            HapticFeedback.play(.blocked)
            return
        }

        isDownloadingLiveWhisperModel = true
        liveWhisperDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await LocalWhisperModelManager.download(model: selectedLiveWhisperModel) { progress in
                    Task { @MainActor in
                        liveWhisperDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    liveWhisperModelStatus = status
                    liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
                    localWhisperModelStatus = LocalWhisperModelManager.currentStatus()
                    localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
                    isDownloadingLiveWhisperModel = false
                    liveWhisperDownloadProgress = 1
                    localWhisperModelRefreshTick &+= 1
                    HapticFeedback.play(.menuSelection)
                    Task {
                        await transcriber.refreshSupportedLanguages()
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloadingLiveWhisperModel = false
                    localWhisperDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func downloadLiveWhisperCoreMLEncoder() {
        guard !isDownloadingLiveWhisperCoreMLEncoder,
              liveWhisperModelStatus?.isAvailable == true,
              let selectedLiveWhisperModel else {
            HapticFeedback.play(.blocked)
            return
        }

        isDownloadingLiveWhisperCoreMLEncoder = true
        liveWhisperCoreMLEncoderDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await LocalWhisperModelManager.downloadCoreMLEncoder(for: selectedLiveWhisperModel) { progress in
                    Task { @MainActor in
                        liveWhisperCoreMLEncoderDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    liveWhisperCoreMLEncoderStatus = status
                    localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
                    isDownloadingLiveWhisperCoreMLEncoder = false
                    liveWhisperCoreMLEncoderDownloadProgress = 1
                    localWhisperModelRefreshTick &+= 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    isDownloadingLiveWhisperCoreMLEncoder = false
                    localWhisperDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func deleteLocalWhisperModel(_ model: LocalWhisperModel? = nil) {
        let modelToDelete = model ?? selectedLocalWhisperModel
        HapticFeedback.play(.menuSelection)
        do {
            let deletedStatus = try LocalWhisperModelManager.deleteDownloadedModel(modelToDelete)
            if modelToDelete.id == selectedLocalWhisperModel.id {
                selectedLocalWhisperModel = deletedStatus.model
                localWhisperModelStatus = deletedStatus
                localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
            } else {
                localWhisperModelStatus = LocalWhisperModelManager.currentStatus()
                localWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
            }
            if modelToDelete.id == selectedLiveWhisperModel?.id {
                liveWhisperModelStatus = deletedStatus
                liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
            } else {
                liveWhisperModelStatus = LocalWhisperModelManager.currentLiveStatus()
                liveWhisperCoreMLEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
            }
            localWhisperModelRefreshTick &+= 1
            Task {
                await transcriber.refreshSupportedLanguages()
            }
        } catch {
            localWhisperDeleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private var openAITranscriptionAPIKeySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSecureTextFieldRow(
                icon: "key",
                titleResource: L10n.Settings.openAIAPIKey,
                promptResource: L10n.Settings.openAIAPIKeyPrompt,
                text: openAIAPIKeyBinding,
                tint: AppTheme.purple
            )
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            SettingsStatusRow(icon: "key", textResource: L10n.Settings.openAIAPIKeyDescription, tint: AppTheme.warning)
            SettingsStatusRow(icon: "cloud", textResource: L10n.Settings.openAIManualRetranscriptionUploadsAudio, tint: AppTheme.warning)

            if !transcriber.openAIAPIKey.isEmpty {
                Button(role: .destructive) {
                    HapticFeedback.play(.menuSelection)
                    transcriber.openAIAPIKey = ""
                } label: {
                    SettingsCommandRow(
                        icon: "trash",
                        titleResource: L10n.Settings.clearOpenAIAPIKey,
                        tint: AppTheme.danger
                    )
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isRecording || transcriber.isPreparing)
            }
        }
    }

    private var openAITranscriptionToggleSettings: some View {
        Toggle(isOn: openAITranscriptionEnabledBinding) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIcon(systemImage: "cloud", tint: AppTheme.purple)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.Settings.onlineOpenAI)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(L10n.Settings.onlineOpenAIDescription)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .disabled(transcriber.isRecording || transcriber.isPreparing)
    }

    private var openAITranscriptionEnabledBinding: Binding<Bool> {
        Binding {
            transcriber.isOpenAITranscriptionEnabled
        } set: { value in
            transcriber.isOpenAITranscriptionEnabled = value
        }
    }

    private var localWhisperCoreMLEncoderLoadingBinding: Binding<Bool> {
        Binding {
            isLocalWhisperCoreMLEncoderLoadingEnabled
        } set: { value in
            HapticFeedback.play(.menuSelection)
            isLocalWhisperCoreMLEncoderLoadingEnabled = value
            LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled = value
        }
    }

    private var localWhisperLiveBetaSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: localWhisperLiveBetaBinding) {
                HStack(alignment: .top, spacing: 10) {
                    SettingsIcon(systemImage: "waveform.badge.mic", tint: AppTheme.purple)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Settings.localWhisperLiveBeta)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(L10n.Settings.localWhisperLiveBetaDescription)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.switch)
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            NavigationLink {
                liveWhisperModelPage
            } label: {
                SettingsNavigationRow(
                    icon: "dot.radiowaves.left.and.right",
                    titleResource: L10n.LocalWhisper.liveModelTitle,
                    value: selectedLiveWhisperModel?.displayName ?? String(localized: L10n.LocalWhisper.liveModelNotSelected),
                    subtitle: selectedLiveWhisperModel?.detail ?? String(localized: L10n.Settings.localWhisperLiveBetaRequiresSelection),
                    tint: AppTheme.purple
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloadingLiveWhisperModel || isDownloadingLiveWhisperCoreMLEncoder || transcriber.isRecording || transcriber.isPreparing)

            if let liveWhisperModelStatus {
                SettingsMetricRow(
                    icon: "iphone",
                    titleResource: L10n.LocalWhisper.modelStatus,
                    value: isDownloadingLiveWhisperModel ? liveWhisperDownloadProgressText : liveWhisperModelStatus.statusText,
                    tint: liveWhisperModelStatus.isAvailable ? AppTheme.success : AppTheme.warning
                )

                if isDownloadingLiveWhisperModel {
                    ProgressView(value: liveWhisperDownloadProgress)
                        .tint(AppTheme.purple)
                        .frame(maxWidth: .infinity)
                }

                if !liveWhisperModelStatus.isAvailable {
                    Button {
                        downloadLiveWhisperModel()
                    } label: {
                        SettingsCommandRow(
                            icon: "arrow.down.circle",
                            titleResource: L10n.LocalWhisper.downloadLiveModel,
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingLiveWhisperModel || isDownloadingLiveWhisperCoreMLEncoder)
                }

                if isLocalWhisperCoreMLEncoderLoadingEnabled,
                   liveWhisperModelStatus.isAvailable,
                   let liveWhisperCoreMLEncoderStatus {
                    SettingsMetricRow(
                        icon: "cpu",
                        titleResource: L10n.LocalWhisper.coreMLEncoderStatus,
                        value: isDownloadingLiveWhisperCoreMLEncoder ? liveWhisperCoreMLEncoderDownloadProgressText : liveWhisperCoreMLEncoderStatus.statusText,
                        tint: liveWhisperCoreMLEncoderStatus.isAvailable ? AppTheme.success : AppTheme.warning
                    )

                    SettingsVerbatimStatusRow(
                        icon: liveWhisperCoreMLEncoderStatus.isAvailable ? "checkmark.circle" : "bolt.badge.clock",
                        text: liveWhisperCoreMLEncoderStatus.detailText,
                        tint: liveWhisperCoreMLEncoderStatus.isAvailable ? AppTheme.success : AppTheme.info
                    )

                    if isDownloadingLiveWhisperCoreMLEncoder {
                        ProgressView(value: liveWhisperCoreMLEncoderDownloadProgress)
                            .tint(AppTheme.purple)
                            .frame(maxWidth: .infinity)
                    }

                    if !liveWhisperCoreMLEncoderStatus.isAvailable {
                        Button {
                            downloadLiveWhisperCoreMLEncoder()
                        } label: {
                            SettingsCommandRow(
                                icon: "bolt.badge.clock",
                                titleResource: L10n.LocalWhisper.downloadCoreMLEncoder,
                                tint: AppTheme.purple
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloadingLiveWhisperModel || isDownloadingLiveWhisperCoreMLEncoder)
                    }
                }
            }

            if transcriber.selectedTranscriptionBackend.usesLocalWhisper && selectedLiveWhisperModel == nil {
                SettingsStatusRow(
                    icon: "exclamationmark.triangle",
                    textResource: L10n.Settings.localWhisperLiveBetaRequiresSelection,
                    tint: AppTheme.warning
                )
            } else if transcriber.selectedTranscriptionBackend.usesLocalWhisper && liveWhisperModelStatus?.isAvailable != true {
                SettingsStatusRow(
                    icon: "arrow.down.circle",
                    textResource: L10n.Settings.localWhisperLiveBetaRequiresModel,
                    tint: AppTheme.warning
                )
            }
        }
    }

    private var localWhisperLiveBetaBinding: Binding<Bool> {
        Binding {
            transcriber.selectedTranscriptionBackend.usesLocalWhisper
        } set: { value in
            transcriber.selectedTranscriptionBackend = value ? .localWhisperBeta : .appleOnDevice
        }
    }

    private var liveWhisperModelPage: some View {
        let refreshTick = localWhisperModelRefreshTick

        return SettingsDetailPage(titleResource: L10n.LocalWhisper.liveModelTitle) {
            SettingsSection(titleResource: L10n.LocalWhisper.liveModelTitle, systemImage: "dot.radiowaves.left.and.right", tint: AppTheme.purple) {
                ForEach(LocalWhisperModelManager.availableModels) { model in
                    let status = LocalWhisperModelManager.status(for: model)
                    Button {
                        selectLiveWhisperModel(model)
                    } label: {
                        SettingsSelectionRow(
                            icon: localWhisperModelIcon(for: model),
                            title: model.displayName,
                            subtitle: localWhisperModelSubtitle(for: model, status: status),
                            isSelected: model.id == selectedLiveWhisperModel?.id,
                            tint: status.isAvailable ? AppTheme.success : AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingLiveWhisperModel || isDownloadingLiveWhisperCoreMLEncoder || transcriber.isRecording || transcriber.isPreparing)
                }
            }
            .id("live-\(refreshTick)")
        }
    }

    private var openAIAPIKeyBinding: Binding<String> {
        Binding {
            transcriber.openAIAPIKey
        } set: { value in
            transcriber.openAIAPIKey = value
        }
    }

    private var transcriptionLanguagePage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.transcriptionLanguage) {
            SettingsSection(titleResource: L10n.Settings.transcriptionLanguage, systemImage: "globe", tint: AppTheme.info) {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        requestLanguageSelection(language)
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

    private func requestLanguageSelection(_ language: TranscriptionLanguage) {
        HapticFeedback.play(.menuSelection)
        guard language.id != transcriber.selectedLanguageID else {
            return
        }

        guard transcriber.selectedTranscriptionBackend.requiresAppleSpeech else {
            transcriber.selectedLanguageID = language.id
            return
        }

        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    language,
                    preservingLanguageIDs: [transcriber.selectedLanguageID]
                )
                switch preparation {
                case .ready:
                    transcriber.selectedLanguageID = language.id
                case .needsRelease(let request):
                    pendingSpeechLocaleReleaseRequest = request
                    HapticFeedback.play(.warning)
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func releaseSpeechLocalesAndSelectLanguage(_ request: SpeechLocaleReleaseRequest) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(request)
                transcriber.selectedLanguageID = request.targetLanguage.id
                HapticFeedback.play(.menuSelection)
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
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
            SettingsSection(
                titleResource: L10n.Settings.localProcessing,
                systemImage: "lock.shield",
                tint: AppTheme.success
            ) {
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

                if transcriber.isOpenAITranscriptionEnabled {
                    SettingsStatusRow(
                        icon: "cloud",
                        textResource: L10n.Settings.openAIManualRetranscriptionUploadsAudio,
                        tint: AppTheme.warning
                    )
                }

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

            if transcriber.selectedTranscriptionBackend.requiresAppleSpeech {
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
            }

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

    init(
        icon: String,
        titleResource: LocalizedStringResource,
        value: String,
        subtitle: String,
        tint: Color
    ) {
        self.icon = icon
        self.title = Text(titleResource)
        self.value = value
        self.subtitle = Text(verbatim: subtitle)
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

private struct SettingsModelManagementRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: Text
    let tint: Color

    init(
        icon: String,
        title: String,
        subtitle: String,
        actionResource: LocalizedStringResource,
        tint: Color
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = Text(actionResource)
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(verbatim: subtitle)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            action
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
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

private struct SettingsSecureTextFieldRow: View {
    let icon: String
    let title: Text
    let prompt: String
    @Binding var text: String
    let tint: Color

    init(
        icon: String,
        titleResource: LocalizedStringResource,
        promptResource: LocalizedStringResource,
        text: Binding<String>,
        tint: Color
    ) {
        self.icon = icon
        self.title = Text(titleResource)
        self.prompt = String(localized: promptResource)
        self._text = text
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            VStack(alignment: .leading, spacing: 6) {
                title
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                SecureField(prompt, text: $text)
                    .font(.redditSans(.caption))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textContentType(.password)
                    .submitLabel(.done)
            }
        }
        .frame(minHeight: 48)
    }
}

private struct SettingsCommandRow: View {
    let icon: String
    let title: Text
    let tint: Color

    init(icon: String, titleResource: LocalizedStringResource, tint: Color) {
        self.icon = icon
        self.title = Text(titleResource)
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(systemImage: icon, tint: tint)

            title
                .font(.redditSans(.subheadline, weight: .semibold))
                .foregroundStyle(tint)

            Spacer(minLength: 12)
        }
        .frame(minHeight: 42)
        .contentShape(Rectangle())
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
