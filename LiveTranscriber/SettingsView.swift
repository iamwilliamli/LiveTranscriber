import SwiftUI
import TranscriberDomain
import UIKit

struct SettingsView: View {
    private enum SettingsRoute: Hashable {
        case transcription
        case recording
        case intelligence
        case geminiCloud
        case files
        case iCloudSyncDetails
        case privacy
        case developer
        case transcriptionLanguage
        case localWhisper
        case localWhisperModel
        case liveWhisperModel
        case qwen3ASRModel
        case mossLocalModel
        case recordingFormat
        case speechPipelineMode
    }

    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @ObservedObject private var geminiUsageTracker = GeminiTokenUsageTracker.shared
    @State private var navigationPath: [SettingsRoute] = []
    @State private var interactiveNavigationPopHasPlayedHaptic = false
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
    @State private var qwen3ASRModelStatus = Qwen3ASRModelManager.currentStatus()
    @State private var isDownloadingQwen3ASRModel = false
    @State private var qwen3ASRDownloadProgress: Double = 0
    @State private var qwen3ASRDownloadErrorMessage: String?
    @State private var qwen3ASRDeleteErrorMessage: String?
    @State private var mossLocalModelStatus = MOSSLocalModelManager.currentStatus()
    @State private var isDownloadingMOSSLocalModel = false
    @State private var mossLocalDownloadProgress: Double = 0
    @State private var mossLocalDownloadErrorMessage: String?
    @State private var mossLocalDeleteErrorMessage: String?
    @State private var selectedLocalSummaryModel = LocalSummaryModelManager.selectedModel
    @State private var localSummaryModelStatus = LocalSummaryModelManager.currentStatus()
    @State private var isDownloadingLocalSummaryModel = false
    @State private var localSummaryDownloadProgress: Double = 0
    @State private var localSummaryDownloadErrorMessage: String?
    @State private var localSummaryDeleteErrorMessage: String?
    @State private var geminiAPIKey = (try? GeminiAPIKeyStore.load()) ?? ""
    @State private var geminiAPIKeyErrorMessage: String?
    @State private var isGeminiCloudEnabled = GeminiCloudConfiguration.isEnabled
    @AppStorage(OnboardingState.completedDefaultsKey) private var hasCompletedOnboarding = true
    @AppStorage(RecordingSummaryProvider.selectedDefaultsKey) private var selectedSummaryProviderRawValue = RecordingSummaryProvider.automatic.rawValue
    @AppStorage(Qwen3ASRDeveloperConfiguration.streamingLongAudioDefaultsKey) private var isQwen3ASRStreamingLongAudioEnabled = false
    @AppStorage(MOSSDecoderSegmentDuration.defaultsKey) private var mossDecoderSegmentDurationSeconds = MOSSDecoderSegmentDuration.defaultValue.rawValue
    private static let publicBetaFeedbackURL = URL(string: "https://t.me/livetranscriber")!
    private static let privacyPolicyURL = URL(string: "https://iamwilliamli.github.io/LiveTranscriber/privacy/")!
    private static let whisperModelURL = URL(string: "https://github.com/openai/whisper")!
    private static let qwen3ASRModelURL = URL(string: "https://github.com/QwenLM/Qwen3-ASR")!
    private static let mossModelURL = URL(string: "https://github.com/OpenMOSS/MOSS-Transcribe-Diarize#model-architecture")!
    private static let feedbackRecipient = "lichengqi0805@gmail.com"
    private static let mailtoQueryAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        return allowed
    }()
    private static let localWhisperSubtitleTrailingCharacters = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)

    private var selectedSummaryProvider: RecordingSummaryProvider {
        RecordingSummaryProvider(rawValue: selectedSummaryProviderRawValue) ?? .automatic
    }

    private var selectedMOSSDecoderSegmentDuration: MOSSDecoderSegmentDuration {
        MOSSDecoderSegmentDuration(rawValue: mossDecoderSegmentDurationSeconds) ?? .defaultValue
    }

    private var mossDecoderRecommendation: MOSSDecoderDeviceRecommendation {
        .current
    }

    private func mossDecoderDurationLabel(_ duration: MOSSDecoderSegmentDuration) -> String {
        guard duration == mossDecoderRecommendation.duration else {
            return duration.displayName
        }
        return String(
            format: String(localized: L10n.MOSSLocal.decoderRecommendedChoiceFormat),
            duration.displayName
        )
    }

    private var mossDecoderRecommendationText: String {
        String(
            format: String(localized: L10n.MOSSLocal.decoderRecommendationFormat),
            mossDecoderRecommendation.duration.displayName,
            mossDecoderRecommendation.physicalMemoryText
        )
    }

    private var mossDecoderUseRecommendationTitle: String {
        String(
            format: String(localized: L10n.MOSSLocal.decoderUseRecommendationFormat),
            mossDecoderRecommendation.duration.displayName
        )
    }

    private var mossDecoderAboveRecommendationText: String {
        String(
            format: String(localized: L10n.MOSSLocal.decoderAboveRecommendationFormat),
            selectedMOSSDecoderSegmentDuration.displayName
        )
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .transcription:
            transcriptionSettingsPage
        case .recording:
            recordingSettingsPage
        case .intelligence:
            intelligenceSettingsPage
        case .geminiCloud:
            geminiCloudSettingsPage
        case .files:
            fileSettingsPage
        case .iCloudSyncDetails:
            iCloudSyncDetailsPage
        case .privacy:
            privacySettingsPage
        case .developer:
            developerSettingsPage
        case .transcriptionLanguage:
            transcriptionLanguagePage
        case .localWhisper:
            localWhisperSettingsPage
        case .localWhisperModel:
            localWhisperModelPage
        case .liveWhisperModel:
            liveWhisperModelPage
        case .qwen3ASRModel:
            qwen3ASRModelPage
        case .mossLocalModel:
            mossLocalModelPage
        case .recordingFormat:
            recordingFormatPage
        case .speechPipelineMode:
            speechPipelineModePage
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NavigationLink(value: SettingsRoute.transcription) {
                        SettingsNavigationRow(
                            icon: "captions.bubble",
                            titleResource: L10n.Settings.transcription,
                            value: transcriber.selectedLanguage.displayName,
                            subtitleResource: L10n.Settings.languageAndModel,
                            tint: AppTheme.info
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsNavigationHaptic()
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.recording) {
                        SettingsNavigationRow(
                            icon: "waveform.badge.mic",
                            titleResource: L10n.Settings.recording,
                            value: transcriber.selectedAudioFormat.title,
                            subtitleResource: L10n.Settings.audioFormatAndBehavior,
                            tint: AppTheme.brand
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsNavigationHaptic()
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.intelligence) {
                        SettingsNavigationRow(
                            icon: "sparkles",
                            titleResource: L10n.Settings.intelligence,
                            value: recordingStore.intelligenceAvailability.statusText,
                            subtitleResource: L10n.Settings.summariesAndLocalModels,
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsNavigationHaptic()
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.files) {
                        SettingsNavigationRow(
                            icon: "folder",
                            titleResource: L10n.Settings.files,
                            value: recordingStore.storageDisplayName,
                            subtitleResource: L10n.Settings.storageLocationAndCount,
                            tint: AppTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsNavigationHaptic()
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.privacy) {
                        SettingsNavigationRow(
                            icon: "lock.shield",
                            titleResource: L10n.Settings.privacy,
                            value: String(localized: L10n.Settings.localProcessing),
                            subtitleResource: L10n.Settings.dataBoundariesAndPermissions,
                            tint: AppTheme.success
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsNavigationHaptic()
                    .settingsSurface()

                    NavigationLink(value: SettingsRoute.developer) {
                        SettingsNavigationRow(
                            icon: "wrench.and.screwdriver",
                            titleResource: L10n.Settings.developerOptions,
                            value: transcriber.speechPipelineDiagnostics.activePipelineName,
                            subtitleResource: L10n.Settings.deviceAndPipelineDiagnostics,
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .settingsNavigationHaptic()
                    .settingsSurface()

                    Button {
                        openPublicBetaFeedback()
                    } label: {
                        SettingsCommandRow(
                            icon: "paperplane.fill",
                            titleResource: L10n.Settings.publicBetaFeedback,
                            tint: AppTheme.info
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
            .onInteractiveNavigationPopGesture(
                onBegan: {
                    interactiveNavigationPopHasPlayedHaptic = true
                    HapticFeedback.play(.navigation)
                },
                onCancelled: {
                    interactiveNavigationPopHasPlayedHaptic = false
                }
            )
            .toolbar(.visible, for: .navigationBar)
            .navigationTitle(String(localized: L10n.Settings.title))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .onChange(of: navigationPath) { oldValue, newValue in
                if newValue.count < oldValue.count {
                    if interactiveNavigationPopHasPlayedHaptic {
                        interactiveNavigationPopHasPlayedHaptic = false
                    } else {
                        HapticFeedback.play(.navigation)
                    }
                }
            }
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            await recordingStore.reload()
            recordingStore.refreshIntelligenceAvailability()
            refreshLocalWhisperModelStatus()
            refreshQwen3ASRModelStatus()
            refreshMOSSLocalModelStatus()
            refreshLocalSummaryModelStatus()
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
            String(localized: L10n.Qwen3ASR.downloadFailed),
            isPresented: Binding(
                get: { qwen3ASRDownloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        qwen3ASRDownloadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(qwen3ASRDownloadErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.Qwen3ASR.deleteFailed),
            isPresented: Binding(
                get: { qwen3ASRDeleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        qwen3ASRDeleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(qwen3ASRDeleteErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.MOSSLocal.downloadFailed),
            isPresented: Binding(
                get: { mossLocalDownloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        mossLocalDownloadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(mossLocalDownloadErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.MOSSLocal.deleteFailed),
            isPresented: Binding(
                get: { mossLocalDeleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        mossLocalDeleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(mossLocalDeleteErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.LocalSummary.downloadFailed),
            isPresented: Binding(
                get: { localSummaryDownloadErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localSummaryDownloadErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(localSummaryDownloadErrorMessage ?? "")
        }
        .alert(
            String(localized: L10n.LocalSummary.deleteFailed),
            isPresented: Binding(
                get: { localSummaryDeleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        localSummaryDeleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(localSummaryDeleteErrorMessage ?? "")
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
        .alert(
            String(localized: L10n.GeminiCloud.settingsErrorTitle),
            isPresented: Binding(
                get: { geminiAPIKeyErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        geminiAPIKeyErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(geminiAPIKeyErrorMessage ?? "")
        }
    }

    private var transcriptionSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.Settings.transcription) {
            SettingsSection(titleResource: L10n.Settings.transcription, systemImage: "captions.bubble", tint: AppTheme.info) {
                NavigationLink(value: SettingsRoute.transcriptionLanguage) {
                    SettingsNavigationRow(
                        icon: "globe",
                        titleResource: L10n.Settings.transcriptionLanguage,
                        value: transcriber.selectedLanguage.displayName,
                        subtitleResource: L10n.Settings.nextStartUsesLanguage,
                        tint: AppTheme.info
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                if transcriber.isRecording || transcriber.isPreparing {
                    SettingsStatusRow(icon: "lock.fill", textResource: L10n.Settings.cannotChangeLanguageWhileRecording, tint: AppTheme.warning)
                }
            }

            SettingsSection(
                titleResource: L10n.Settings.offlineTranscription,
                systemImage: "cpu",
                tint: AppTheme.brand
            ) {
                NavigationLink(value: SettingsRoute.localWhisper) {
                    SettingsNavigationRow(
                        icon: "waveform",
                        titleResource: L10n.LocalWhisper.engineTitle,
                        value: localWhisperModelStatus.statusText,
                        subtitleResource: L10n.LocalWhisper.submenuDescription,
                        tint: AppTheme.info
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
                .disabled(isDownloadingLocalWhisperModel || isDownloadingLocalWhisperCoreMLEncoder)

                NavigationLink(value: SettingsRoute.qwen3ASRModel) {
                    SettingsNavigationRow(
                        icon: "waveform.badge.magnifyingglass",
                        titleResource: L10n.Qwen3ASR.modelTitle,
                        value: qwen3ASRModelStatus.statusText,
                        subtitleResource: L10n.Qwen3ASR.submenuDescription,
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
                .disabled(isDownloadingQwen3ASRModel)

                NavigationLink(value: SettingsRoute.mossLocalModel) {
                    SettingsNavigationRow(
                        icon: "person.2",
                        titleResource: L10n.MOSSLocal.modelTitle,
                        value: mossLocalModelStatus.statusText,
                        subtitleResource: L10n.MOSSLocal.submenuDescription,
                        tint: AppTheme.purple
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
                .disabled(isDownloadingMOSSLocalModel)
            }

            SettingsSection(
                titleResource: L10n.Settings.onlineTranscription,
                systemImage: "cloud",
                tint: AppTheme.purple
            ) {
                NavigationLink(value: SettingsRoute.geminiCloud) {
                    SettingsNavigationRow(
                        icon: "cloud",
                        titleResource: L10n.GeminiCloud.settingsTitle,
                        value: geminiCloudStatusText,
                        subtitleResource: L10n.GeminiCloud.submenuDescription,
                        tint: AppTheme.purple
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
            }

            SettingsSection(titleResource: L10n.Settings.betaFeatures, systemImage: "testtube.2", tint: AppTheme.purple) {
                localWhisperLiveBetaSettings
            }
        }
    }

    private var intelligenceSettingsPage: some View {
        let appleAvailability = RecordingIntelligenceAvailability.currentAppleIntelligence()
        let appleAvailabilityTint = appleAvailability.isAvailable ? AppTheme.success : AppTheme.warning

        return SettingsDetailPage(titleResource: L10n.Settings.intelligence) {
            SettingsSection(titleResource: L10n.LocalSummary.providerTitle, systemImage: "sparkles", tint: AppTheme.purple) {
                Menu {
                    ForEach(RecordingSummaryProvider.menuProviders) { provider in
                        Button {
                            selectSummaryProvider(provider)
                        } label: {
                            Label(
                                provider.displayName,
                                systemImage: provider == selectedSummaryProvider ? "checkmark" : provider.systemImage
                            )
                        }
                        .disabled(!provider.isCurrentlyAvailable)
                    }
                } label: {
                    SettingsPickerRow(
                        icon: selectedSummaryProvider.systemImage,
                        titleResource: L10n.LocalSummary.selectedProvider,
                        value: selectedSummaryProvider.displayName,
                        tint: AppTheme.purple
                    )
                }
                .buttonStyle(.plain)

                SettingsVerbatimStatusRow(
                    icon: selectedSummaryProvider.systemImage,
                    text: selectedSummaryProvider.detailText,
                    tint: AppTheme.info
                )
            }

            SettingsSection(titleResource: L10n.Intelligence.appleModelTitle, systemImage: "sparkles", tint: appleAvailabilityTint) {
                SettingsMetricRow(
                    icon: "iphone",
                    titleResource: L10n.Settings.advancedModel,
                    value: appleAvailability.statusText,
                    tint: appleAvailabilityTint
                )

                SettingsVerbatimStatusRow(
                    icon: appleAvailability.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    text: appleAvailability.detailText,
                    tint: appleAvailabilityTint
                )
            }

            SettingsSection(titleResource: L10n.LocalSummary.modelTitle, systemImage: "cpu", tint: AppTheme.purple) {
                localSummaryModelSettings
            }
        }
    }

    private var geminiCloudSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.GeminiCloud.settingsTitle) {
            SettingsSection(
                titleResource: L10n.GeminiCloud.controlTitle,
                systemImage: "cloud",
                tint: AppTheme.purple
            ) {
                Toggle(isOn: geminiCloudEnabledBinding) {
                    HStack(alignment: .top, spacing: 10) {
                        SettingsIcon(systemImage: "power", tint: AppTheme.purple)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.GeminiCloud.enableTitle)
                                .font(.redditSans(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(L10n.GeminiCloud.enableDescription)
                                .font(.redditSans(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(.switch)
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                SettingsStatusRow(
                    icon: GeminiCloudConfiguration.isAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    textResource: GeminiCloudConfiguration.isAvailable
                        ? L10n.GeminiCloud.readyDescription
                        : L10n.GeminiCloud.notReadyDescription,
                    tint: GeminiCloudConfiguration.isAvailable ? AppTheme.success : AppTheme.warning
                )
            }

            SettingsSection(
                titleResource: L10n.GeminiCloud.apiConfigurationTitle,
                systemImage: "key",
                tint: AppTheme.purple
            ) {
                geminiCloudSettings
            }

            SettingsSection(
                titleResource: L10n.GeminiCloud.usageTitle,
                systemImage: "chart.bar",
                tint: AppTheme.info
            ) {
                geminiUsageSettings
            }
        }
    }

    private var geminiCloudStatusText: String {
        guard isGeminiCloudEnabled else {
            return String(localized: L10n.GeminiCloud.statusOff)
        }
        return GeminiAPIKeyStore.isConfigured
            ? String(localized: L10n.GeminiCloud.statusOn)
            : String(localized: L10n.GeminiCloud.statusNeedsAPIKey)
    }

    private var localSummaryModelSettings: some View {
        let model = selectedLocalSummaryModel

        return VStack(alignment: .leading, spacing: 12) {
            Menu {
                ForEach(LocalSummaryModelManager.availableModels) { model in
                    Button {
                        selectLocalSummaryModel(model)
                    } label: {
                        Label(
                            model.displayName,
                            systemImage: model.id == selectedLocalSummaryModel.id ? "checkmark" : "cpu"
                        )
                    }
                }
            } label: {
                SettingsPickerRow(
                    icon: "cpu",
                    titleResource: L10n.LocalSummary.selectedModel,
                    value: model.displayName,
                    tint: AppTheme.purple
                )
            }
            .buttonStyle(.plain)
            .disabled(isDownloadingLocalSummaryModel)

            SettingsVerbatimStatusRow(
                icon: "text.alignleft",
                text: model.detail,
                tint: AppTheme.purple
            )

            SettingsMetricRow(
                icon: "internaldrive",
                titleResource: L10n.LocalSummary.modelStatus,
                value: isDownloadingLocalSummaryModel ? localSummaryDownloadProgressText : localSummaryModelStatus.statusText,
                tint: localSummaryModelStatus.isAvailable ? AppTheme.success : AppTheme.warning
            )

            SettingsVerbatimStatusRow(
                icon: localSummaryModelStatus.isAvailable ? "checkmark.circle" : "arrow.down.circle",
                text: localSummaryModelStatus.detailText,
                tint: localSummaryModelStatus.isAvailable ? AppTheme.success : AppTheme.info
            )

            if isDownloadingLocalSummaryModel {
                ProgressView(value: localSummaryDownloadProgress)
                    .tint(AppTheme.purple)
                    .frame(maxWidth: .infinity)
            }

            if !localSummaryModelStatus.isAvailable {
                Button {
                    downloadLocalSummaryModel()
                } label: {
                    SettingsCommandRow(
                        icon: "arrow.down.circle",
                        titleResource: L10n.LocalSummary.downloadSelectedModel,
                        tint: AppTheme.purple
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDownloadingLocalSummaryModel)
            }

            if localSummaryModelStatus.isUserInstalled {
                Button(role: .destructive) {
                    deleteLocalSummaryModel()
                } label: {
                    SettingsCommandRow(
                        icon: "trash",
                        titleResource: L10n.LocalSummary.deleteModelDownload,
                        tint: AppTheme.danger
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDownloadingLocalSummaryModel)
            }

            SettingsStatusRow(
                icon: "cpu",
                textResource: L10n.LocalSummary.runtimePending,
                tint: AppTheme.info
            )
        }
    }

    private var localWhisperModelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: SettingsRoute.localWhisperModel) {
                SettingsNavigationRow(
                    icon: "cube",
                    titleResource: L10n.LocalWhisper.selectedModel,
                    value: selectedLocalWhisperModel.displayName,
                    subtitle: selectedLocalWhisperModel.detail,
                    tint: AppTheme.info
                )
            }
            .buttonStyle(.plain)
            .settingsNavigationHaptic()
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

    private var localWhisperSettingsPage: some View {
        SettingsDetailPage(titleResource: L10n.LocalWhisper.engineTitle) {
            SettingsSection(
                titleResource: L10n.LocalWhisper.engineTitle,
                systemImage: "waveform",
                tint: AppTheme.info
            ) {
                localWhisperModelSettings
            }

            SettingsSection(
                titleResource: L10n.Settings.modelInformation,
                systemImage: "info.circle",
                tint: AppTheme.info
            ) {
                Link(destination: Self.whisperModelURL) {
                    SettingsExternalLinkRow(
                        icon: "safari",
                        titleResource: L10n.LocalWhisper.aboutModel,
                        tint: AppTheme.info
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
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

    private var qwen3ASRModelPage: some View {
        SettingsDetailPage(titleResource: L10n.Qwen3ASR.modelTitle) {
            SettingsSection(
                titleResource: L10n.Qwen3ASR.modelTitle,
                systemImage: "waveform.badge.magnifyingglass",
                tint: AppTheme.brand
            ) {
                SettingsMetricRow(
                    icon: "cpu",
                    titleResource: L10n.Qwen3ASR.modelName,
                    value: Qwen3ASRModelManager.expectedSizeText,
                    tint: AppTheme.brand
                )

                SettingsVerbatimStatusRow(
                    icon: "iphone",
                    text: String(localized: L10n.Qwen3ASR.modelDescription),
                    tint: AppTheme.info
                )

                SettingsMetricRow(
                    icon: "internaldrive",
                    titleResource: L10n.Qwen3ASR.modelStatus,
                    value: isDownloadingQwen3ASRModel
                        ? qwen3ASRDownloadProgressText
                        : qwen3ASRModelStatus.statusText,
                    tint: qwen3ASRModelStatus.isAvailable ? AppTheme.success : AppTheme.warning
                )

                SettingsVerbatimStatusRow(
                    icon: qwen3ASRModelStatus.isAvailable ? "checkmark.circle" : "arrow.down.circle",
                    text: qwen3ASRModelStatus.detailText,
                    tint: qwen3ASRModelStatus.isAvailable ? AppTheme.success : AppTheme.info
                )

                if isDownloadingQwen3ASRModel {
                    ProgressView(value: qwen3ASRDownloadProgress)
                        .tint(AppTheme.brand)
                        .frame(maxWidth: .infinity)
                }

                if !qwen3ASRModelStatus.isAvailable {
                    Button {
                        downloadQwen3ASRModel()
                    } label: {
                        SettingsCommandRow(
                            icon: "arrow.down.circle",
                            titleResource: L10n.Qwen3ASR.downloadModel,
                            tint: AppTheme.brand
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingQwen3ASRModel)
                }

                if qwen3ASRModelStatus.hasStoredFiles {
                    Button(role: .destructive) {
                        deleteQwen3ASRModel()
                    } label: {
                        SettingsCommandRow(
                            icon: "trash",
                            titleResource: L10n.Qwen3ASR.deleteModel,
                            tint: AppTheme.danger
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingQwen3ASRModel)
                }
            }

            SettingsSection(
                titleResource: L10n.Settings.modelInformation,
                systemImage: "info.circle",
                tint: AppTheme.brand
            ) {
                Link(destination: Self.qwen3ASRModelURL) {
                    SettingsExternalLinkRow(
                        icon: "safari",
                        titleResource: L10n.Qwen3ASR.aboutModel,
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
            }
        }
    }

    private var mossLocalModelPage: some View {
        SettingsDetailPage(titleResource: L10n.MOSSLocal.modelTitle) {
            SettingsSection(
                titleResource: L10n.MOSSLocal.modelTitle,
                systemImage: "person.2",
                tint: AppTheme.purple
            ) {
                SettingsMetricRow(
                    icon: "cpu",
                    titleResource: L10n.MOSSLocal.modelName,
                    value: MOSSLocalModelManager.expectedSizeText,
                    tint: AppTheme.purple
                )

                SettingsVerbatimStatusRow(
                    icon: "iphone",
                    text: String(localized: L10n.MOSSLocal.modelDescription),
                    tint: AppTheme.info
                )

                SettingsMetricRow(
                    icon: "internaldrive",
                    titleResource: L10n.MOSSLocal.modelStatus,
                    value: isDownloadingMOSSLocalModel
                        ? mossLocalDownloadProgressText
                        : mossLocalModelStatus.statusText,
                    tint: mossLocalModelStatus.isAvailable ? AppTheme.success : AppTheme.warning
                )

                SettingsVerbatimStatusRow(
                    icon: mossLocalModelStatus.isAvailable ? "checkmark.circle" : "arrow.down.circle",
                    text: mossLocalModelStatus.detailText,
                    tint: mossLocalModelStatus.isAvailable ? AppTheme.success : AppTheme.info
                )

                if isDownloadingMOSSLocalModel {
                    ProgressView(value: mossLocalDownloadProgress)
                        .tint(AppTheme.purple)
                        .frame(maxWidth: .infinity)
                }

                if !mossLocalModelStatus.isAvailable {
                    Button {
                        downloadMOSSLocalModel()
                    } label: {
                        SettingsCommandRow(
                            icon: "arrow.down.circle",
                            titleResource: L10n.MOSSLocal.downloadModel,
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingMOSSLocalModel)
                }

                if mossLocalModelStatus.hasStoredFiles {
                    Button(role: .destructive) {
                        deleteMOSSLocalModel()
                    } label: {
                        SettingsCommandRow(
                            icon: "trash",
                            titleResource: L10n.MOSSLocal.deleteModel,
                            tint: AppTheme.danger
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloadingMOSSLocalModel)
                }
            }

            SettingsSection(
                titleResource: L10n.MOSSLocal.decoderSectionTitle,
                systemImage: "timer",
                tint: AppTheme.purple
            ) {
                Menu {
                    ForEach(MOSSDecoderSegmentDuration.mobileOptions) { duration in
                        let isRecommended = duration == mossDecoderRecommendation.duration
                        Button {
                            HapticFeedback.play(.menuSelection)
                            mossDecoderSegmentDurationSeconds = duration.rawValue
                        } label: {
                            Label(
                                mossDecoderDurationLabel(duration),
                                systemImage: duration == selectedMOSSDecoderSegmentDuration
                                    ? "checkmark"
                                    : isRecommended ? "star.fill" : "timer"
                            )
                        }
                    }
                } label: {
                    SettingsPickerRow(
                        icon: "timer",
                        titleResource: L10n.MOSSLocal.decoderSegmentDuration,
                        value: mossDecoderDurationLabel(selectedMOSSDecoderSegmentDuration),
                        tint: AppTheme.purple
                    )
                }
                .buttonStyle(.plain)

                SettingsVerbatimStatusRow(
                    icon: "sparkles",
                    text: mossDecoderRecommendationText,
                    tint: AppTheme.success
                )

                if selectedMOSSDecoderSegmentDuration != mossDecoderRecommendation.duration {
                    Button {
                        HapticFeedback.play(.menuSelection)
                        mossDecoderSegmentDurationSeconds = mossDecoderRecommendation.duration.rawValue
                    } label: {
                        SettingsCommandRow(
                            icon: "wand.and.stars",
                            title: mossDecoderUseRecommendationTitle,
                            tint: AppTheme.purple
                        )
                    }
                    .buttonStyle(.plain)
                }

                if selectedMOSSDecoderSegmentDuration.rawValue > mossDecoderRecommendation.duration.rawValue {
                    SettingsVerbatimStatusRow(
                        icon: "exclamationmark.triangle",
                        text: mossDecoderAboveRecommendationText,
                        tint: AppTheme.warning
                    )
                }

                SettingsVerbatimStatusRow(
                    icon: "memorychip",
                    text: String(localized: L10n.MOSSLocal.decoderSegmentDurationDescription),
                    tint: AppTheme.info
                )
            }

            SettingsSection(
                titleResource: L10n.Settings.modelInformation,
                systemImage: "info.circle",
                tint: AppTheme.purple
            ) {
                Link(destination: Self.mossModelURL) {
                    SettingsExternalLinkRow(
                        icon: "safari",
                        titleResource: L10n.MOSSLocal.aboutModel,
                        tint: AppTheme.purple
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
            }
        }
    }

    private var localWhisperDownloadProgressText: String {
        String(
            format: String(localized: L10n.LocalWhisper.downloadingModelFormat),
            localWhisperDownloadProgress * 100
        )
    }

    private var qwen3ASRDownloadProgressText: String {
        String(
            format: String(localized: L10n.Qwen3ASR.downloadingModelFormat),
            qwen3ASRDownloadProgress * 100
        )
    }

    private var mossLocalDownloadProgressText: String {
        String(
            format: String(localized: L10n.MOSSLocal.downloadingModelFormat),
            mossLocalDownloadProgress * 100
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

    private var localSummaryDownloadProgressText: String {
        String(
            format: String(localized: L10n.LocalSummary.downloadingModelFormat),
            localSummaryDownloadProgress * 100
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

    private func refreshQwen3ASRModelStatus() {
        qwen3ASRModelStatus = Qwen3ASRModelManager.currentStatus()
    }

    private func refreshMOSSLocalModelStatus() {
        mossLocalModelStatus = MOSSLocalModelManager.currentStatus()
    }

    private func refreshLocalSummaryModelStatus() {
        selectedLocalSummaryModel = LocalSummaryModelManager.selectedModel
        localSummaryModelStatus = LocalSummaryModelManager.currentStatus()
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

    private func openPublicBetaFeedback() {
        HapticFeedback.play(.menuSelection)
        UIApplication.shared.open(Self.publicBetaFeedbackURL)
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
        return String(
            format: String(localized: L10n.Settings.feedbackEmailSubjectFormat),
            build.version
        )
    }

    private func feedbackEmailBody() -> String {
        let build = DeveloperBuildInfo.current
        let device = DeveloperDeviceInfo.current
        let pipeline = transcriber.speechPipelineDiagnostics
        let localWhisperModel = LocalWhisperModelManager.selectedModel.displayName
        let liveWhisperModel = LocalWhisperModelManager.selectedLiveModel?.displayName ?? String(localized: L10n.LocalWhisper.liveModelNotSelected)
        let localSummaryModel = LocalSummaryModelManager.defaultModel.displayName
        let localSummaryStatus = LocalSummaryModelManager.currentStatus().statusText
        let coreMLEncoderState = String(localized:
            LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled
                ? L10n.ICloud.enabled
                : L10n.ICloud.disabled
        )

        return [
            String(localized: L10n.Settings.feedbackEmailGreeting),
            "",
            String(localized: L10n.Settings.feedbackEmailPrompt),
            "",
            "",
            String(localized: L10n.Settings.feedbackEmailSteps),
            "1.",
            "2.",
            "3.",
            "",
            String(localized: L10n.Settings.feedbackEmailExpected),
            "",
            "",
            String(localized: L10n.Settings.feedbackEmailActual),
            "",
            "",
            "---",
            String(localized: L10n.Settings.feedbackEmailDiagnostics),
            "\(String(localized: L10n.Settings.feedbackEmailApp)): LiveTranscriber",
            "\(String(localized: L10n.Settings.version)): \(build.version)",
            "\(String(localized: L10n.Settings.buildTime)): \(build.buildTime)",
            "\(String(localized: L10n.Settings.device)): \(device.modelIdentifier)",
            "\(String(localized: L10n.Settings.systemVersion)): \(device.systemVersion)",
            "\(String(localized: L10n.Settings.feedbackEmailCurrentPipeline)): \(pipeline.activePipelineName)",
            "\(String(localized: L10n.Settings.feedbackEmailConfiguredPipeline)): \(pipeline.configuredPipelineName)",
            "\(String(localized: L10n.Settings.feedbackEmailSelectedLanguage)): \(transcriber.selectedLanguage.displayName) (\(transcriber.selectedLanguageID))",
            "\(String(localized: L10n.Settings.feedbackEmailLiveBackend)): \(transcriber.selectedTranscriptionBackend.title)",
            "\(String(localized: L10n.Settings.feedbackEmailLocalWhisperModel)): \(localWhisperModel)",
            "\(String(localized: L10n.Settings.feedbackEmailRealtimeWhisperModel)): \(liveWhisperModel)",
            "\(String(localized: L10n.Settings.feedbackEmailSummaryEngine)): \(selectedSummaryProvider.displayName)",
            "\(String(localized: L10n.Settings.feedbackEmailLocalSummaryModel)): \(localSummaryModel)",
            "\(String(localized: L10n.Settings.feedbackEmailLocalSummaryStatus)): \(localSummaryStatus)",
            "\(String(localized: L10n.Settings.feedbackEmailCoreMLEncoderLoading)): \(coreMLEncoderState)",
            "\(String(localized: L10n.Settings.recordingCount)): \(recordingStore.recordings.count)",
            "\(String(localized: L10n.Settings.storage)): \(recordingStore.storageDisplayName)"
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

    private func selectSummaryProvider(_ provider: RecordingSummaryProvider) {
        HapticFeedback.play(.menuSelection)
        selectedSummaryProviderRawValue = provider.rawValue
        RecordingSummaryProvider.select(provider)
        recordingStore.refreshIntelligenceAvailability()
    }

    private func selectLocalSummaryModel(_ model: LocalSummaryModel) {
        HapticFeedback.play(.menuSelection)
        LocalSummaryModelManager.selectModel(model)
        selectedLocalSummaryModel = model
        localSummaryModelStatus = LocalSummaryModelManager.status(for: model)
        recordingStore.refreshIntelligenceAvailability()
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

    private func downloadQwen3ASRModel() {
        guard !isDownloadingQwen3ASRModel else {
            return
        }

        isDownloadingQwen3ASRModel = true
        qwen3ASRDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await Qwen3ASRModelManager.download { progress in
                    Task { @MainActor in
                        qwen3ASRDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    qwen3ASRModelStatus = status
                    isDownloadingQwen3ASRModel = false
                    qwen3ASRDownloadProgress = 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    qwen3ASRModelStatus = Qwen3ASRModelManager.currentStatus()
                    isDownloadingQwen3ASRModel = false
                    qwen3ASRDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func deleteQwen3ASRModel() {
        guard !isDownloadingQwen3ASRModel else {
            return
        }

        HapticFeedback.play(.menuSelection)
        do {
            qwen3ASRModelStatus = try Qwen3ASRModelManager.deleteDownloadedModel()
            qwen3ASRDownloadProgress = 0
        } catch {
            qwen3ASRDeleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func downloadMOSSLocalModel() {
        guard !isDownloadingMOSSLocalModel else {
            return
        }

        isDownloadingMOSSLocalModel = true
        mossLocalDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await MOSSLocalModelManager.download { progress in
                    Task { @MainActor in
                        mossLocalDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    mossLocalModelStatus = status
                    isDownloadingMOSSLocalModel = false
                    mossLocalDownloadProgress = 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    mossLocalModelStatus = MOSSLocalModelManager.currentStatus()
                    isDownloadingMOSSLocalModel = false
                    mossLocalDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func deleteMOSSLocalModel() {
        guard !isDownloadingMOSSLocalModel else {
            return
        }

        HapticFeedback.play(.menuSelection)
        do {
            mossLocalModelStatus = try MOSSLocalModelManager.deleteDownloadedModel()
            mossLocalDownloadProgress = 0
        } catch {
            mossLocalDeleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func downloadLocalSummaryModel() {
        guard !isDownloadingLocalSummaryModel else {
            return
        }

        isDownloadingLocalSummaryModel = true
        localSummaryDownloadProgress = 0
        HapticFeedback.play(.menuSelection)

        Task {
            do {
                let status = try await LocalSummaryModelManager.downloadDefaultModel { progress in
                    Task { @MainActor in
                        localSummaryDownloadProgress = progress
                    }
                }

                await MainActor.run {
                    selectedLocalSummaryModel = status.model
                    localSummaryModelStatus = status
                    recordingStore.refreshIntelligenceAvailability()
                    isDownloadingLocalSummaryModel = false
                    localSummaryDownloadProgress = 1
                    HapticFeedback.play(.menuSelection)
                }
            } catch {
                await MainActor.run {
                    isDownloadingLocalSummaryModel = false
                    localSummaryDownloadErrorMessage = error.localizedDescription
                    HapticFeedback.play(.failure)
                }
            }
        }
    }

    private func deleteLocalSummaryModel() {
        guard !isDownloadingLocalSummaryModel else {
            HapticFeedback.play(.blocked)
            return
        }

        HapticFeedback.play(.menuSelection)
        do {
            let status = try LocalSummaryModelManager.deleteDownloadedModel()
            selectedLocalSummaryModel = status.model
            localSummaryModelStatus = status
            recordingStore.refreshIntelligenceAvailability()
        } catch {
            localSummaryDeleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private var geminiCloudSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSecureTextFieldRow(
                icon: "key",
                titleResource: L10n.GeminiCloud.apiKey,
                promptResource: L10n.GeminiCloud.apiKeyPrompt,
                text: geminiAPIKeyBinding,
                tint: AppTheme.purple
            )
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            SettingsStatusRow(
                icon: "lock.shield",
                textResource: L10n.GeminiCloud.apiKeyDescription,
                tint: AppTheme.info
            )
            SettingsStatusRow(
                icon: "arrow.up.circle",
                textResource: L10n.GeminiCloud.manualUploadDescription,
                tint: AppTheme.warning
            )

            if !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(role: .destructive) {
                    HapticFeedback.play(.menuSelection)
                    do {
                        try GeminiAPIKeyStore.delete()
                        geminiAPIKey = ""
                        if selectedSummaryProvider == .geminiCloud {
                            selectSummaryProvider(.automatic)
                        }
                        recordingStore.refreshIntelligenceAvailability()
                    } catch {
                        geminiAPIKeyErrorMessage = error.localizedDescription
                        HapticFeedback.play(.failure)
                    }
                } label: {
                    SettingsCommandRow(
                        icon: "trash",
                        titleResource: L10n.GeminiCloud.clearAPIKey,
                        tint: AppTheme.danger
                    )
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isRecording || transcriber.isPreparing)
            }
        }
    }

    private var geminiUsageSettings: some View {
        let usage = geminiUsageTracker.snapshot

        return VStack(alignment: .leading, spacing: 12) {
            SettingsMetricRow(
                icon: "cpu",
                titleResource: L10n.GeminiCloud.usageModel,
                value: GeminiCloudService.model,
                tint: AppTheme.purple
            )
            SettingsMetricRow(
                icon: "number",
                titleResource: L10n.GeminiCloud.usageRequests,
                value: formattedGeminiTokenCount(usage.requestCount),
                tint: AppTheme.info
            )
            SettingsMetricRow(
                icon: "clock.arrow.circlepath",
                titleResource: L10n.GeminiCloud.usageLastRequest,
                value: formattedGeminiTokenCount(usage.lastTotalTokens),
                tint: AppTheme.info
            )
            SettingsMetricRow(
                icon: "sum",
                titleResource: L10n.GeminiCloud.usageTotalTokens,
                value: formattedGeminiTokenCount(usage.totalTokens),
                tint: AppTheme.info
            )
            SettingsMetricRow(
                icon: "arrow.down.circle",
                titleResource: L10n.GeminiCloud.usageInputTokens,
                value: formattedGeminiTokenCount(usage.inputTokens),
                tint: AppTheme.info
            )
            SettingsMetricRow(
                icon: "arrow.up.circle",
                titleResource: L10n.GeminiCloud.usageOutputTokens,
                value: formattedGeminiTokenCount(usage.outputTokens),
                tint: AppTheme.info
            )
            SettingsMetricRow(
                icon: "brain",
                titleResource: L10n.GeminiCloud.usageThoughtTokens,
                value: formattedGeminiTokenCount(usage.thoughtTokens),
                tint: AppTheme.purple
            )
            SettingsMetricRow(
                icon: "bolt.horizontal.circle",
                titleResource: L10n.GeminiCloud.usageCachedTokens,
                value: formattedGeminiTokenCount(usage.cachedTokens),
                tint: AppTheme.info
            )

            if let lastUpdatedAt = usage.lastUpdatedAt {
                SettingsVerbatimStatusRow(
                    icon: "clock",
                    text: String(
                        format: String(localized: L10n.GeminiCloud.usageUpdatedFormat),
                        lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
                    ),
                    tint: AppTheme.info
                )
            }

            SettingsStatusRow(
                icon: "info.circle",
                textResource: L10n.GeminiCloud.usageLocalDescription,
                tint: AppTheme.info
            )

            if usage.requestCount > 0 {
                Button(role: .destructive) {
                    HapticFeedback.play(.menuSelection)
                    geminiUsageTracker.reset()
                } label: {
                    SettingsCommandRow(
                        icon: "arrow.counterclockwise",
                        titleResource: L10n.GeminiCloud.resetUsage,
                        tint: AppTheme.danger
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var geminiCloudEnabledBinding: Binding<Bool> {
        Binding {
            isGeminiCloudEnabled
        } set: { isEnabled in
            HapticFeedback.play(.menuSelection)
            isGeminiCloudEnabled = isEnabled
            GeminiCloudConfiguration.setEnabled(isEnabled)
            if !isEnabled, selectedSummaryProvider == .geminiCloud {
                selectSummaryProvider(.automatic)
            }
            recordingStore.refreshIntelligenceAvailability()
        }
    }

    private func formattedGeminiTokenCount(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private var geminiAPIKeyBinding: Binding<String> {
        Binding {
            geminiAPIKey
        } set: { value in
            geminiAPIKey = value
            do {
                try GeminiAPIKeyStore.save(value)
                recordingStore.refreshIntelligenceAvailability()
            } catch {
                geminiAPIKeyErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
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

            NavigationLink(value: SettingsRoute.liveWhisperModel) {
                SettingsNavigationRow(
                    icon: "dot.radiowaves.left.and.right",
                    titleResource: L10n.LocalWhisper.liveModelTitle,
                    value: selectedLiveWhisperModel?.displayName ?? String(localized: L10n.LocalWhisper.liveModelNotSelected),
                    subtitle: selectedLiveWhisperModel?.detail ?? String(localized: L10n.Settings.localWhisperLiveBetaRequiresSelection),
                    tint: AppTheme.purple
                )
            }
            .buttonStyle(.plain)
            .settingsNavigationHaptic()
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
                NavigationLink(value: SettingsRoute.recordingFormat) {
                    SettingsNavigationRow(
                        icon: "waveform.badge.mic",
                        titleResource: L10n.Settings.recordingFormat,
                        value: transcriber.selectedAudioFormat.title,
                        subtitleResource: transcriber.selectedAudioFormat.detailResource,
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
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

    private var iCloudSyncDetailsPage: some View {
        let summary = recordingStore.iCloudSyncSummary
        let groups = iCloudSyncDetailGroups
        let summaryTint = summary.failedRecordingCount > 0 ? AppTheme.danger : AppTheme.info

        return SettingsDetailPage(titleResource: L10n.Settings.iCloudProgress) {
            SettingsSection(
                titleResource: L10n.Settings.iCloudProgress,
                systemImage: summary.systemImage,
                tint: summaryTint
            ) {
                SettingsMetricRow(
                    icon: "waveform",
                    titleResource: L10n.Settings.recordingCount,
                    value: "\(summary.totalRecordingCount)",
                    tint: summaryTint
                )

                SettingsVerbatimStatusRow(
                    icon: summary.systemImage,
                    text: summary.detailText,
                    tint: summaryTint
                )
            }

            if groups.isEmpty {
                SettingsSection(
                    titleResource: L10n.Settings.iCloudProgress,
                    systemImage: "icloud",
                    tint: AppTheme.info
                ) {
                    SettingsStatusRow(
                        icon: "waveform",
                        textResource: L10n.ICloud.noRecordingsToSync,
                        tint: AppTheme.info
                    )
                }
            } else {
                ForEach(groups) { group in
                    SettingsICloudSyncStatusSection(group: group)
                }
            }
        }
        .task {
            recordingStore.refreshICloudSyncStatus(logDiagnostics: true)
        }
    }

    private var iCloudSyncDetailGroups: [SettingsICloudSyncGroup] {
        let entries = recordingStore.recordings.map { item in
            SettingsICloudSyncEntry(
                item: item,
                status: recordingStore.iCloudSyncStatus(for: item)
            )
        }
        let stateOrder: [RecordingICloudSyncState] = [
            .failed,
            .uploading,
            .waiting,
            .iCloudUnavailable,
            .localOnly,
            .uploaded
        ]

        return stateOrder.compactMap { state in
            let matchingEntries = entries.filter { $0.status.state == state }
            guard !matchingEntries.isEmpty else {
                return nil
            }
            return SettingsICloudSyncGroup(state: state, entries: matchingEntries)
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

                SettingsStatusRow(
                    icon: "person.crop.circle.badge.xmark",
                    textResource: L10n.Settings.developerCannotAccessContent,
                    tint: AppTheme.success
                )

                Link(destination: Self.privacyPolicyURL) {
                    SettingsExternalLinkRow(
                        icon: "doc.text",
                        titleResource: L10n.Settings.privacyPolicy,
                        tint: AppTheme.success
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
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

            NavigationLink(value: SettingsRoute.iCloudSyncDetails) {
                SettingsNavigationRow(
                    icon: iCloudSyncSummary.systemImage,
                    titleResource: L10n.Settings.iCloudProgress,
                    value: iCloudSyncSummary.statusText,
                    subtitle: iCloudSyncSummary.detailText,
                    tint: iCloudSyncTint
                )
            }
            .buttonStyle(.plain)
            .settingsNavigationHaptic()
        }
    }

    private func refreshICloudSyncStatusPeriodically() async {
        while !Task.isCancelled {
            await MainActor.run {
                recordingStore.refreshICloudSyncStatus()
            }

            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
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

            Toggle(isOn: $isQwen3ASRStreamingLongAudioEnabled) {
                HStack(alignment: .top, spacing: 10) {
                    SettingsIcon(systemImage: "waveform.path.ecg.rectangle", tint: AppTheme.purple)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.Qwen3ASR.streamingLongAudio)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(L10n.Qwen3ASR.streamingLongAudioDescription)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.switch)

            SettingsMetricRow(
                icon: "waveform.path.ecg",
                titleResource: L10n.Settings.currentSpeechPipeline,
                value: pipeline.activePipelineName,
                tint: AppTheme.brand
            )

            if transcriber.selectedTranscriptionBackend.requiresAppleSpeech {
                NavigationLink(value: SettingsRoute.speechPipelineMode) {
                    SettingsNavigationRow(
                        icon: "slider.horizontal.3",
                        titleResource: L10n.Settings.speechPipelineMode,
                        value: pipeline.configuredPipelineName,
                        subtitleResource: L10n.Settings.switchPipelineSubtitle,
                        tint: AppTheme.brand
                    )
                }
                .buttonStyle(.plain)
                .settingsNavigationHaptic()
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

            Button {
                HapticFeedback.play(.navigation)
                withAnimation(.easeInOut(duration: 0.28)) {
                    hasCompletedOnboarding = false
                }
            } label: {
                SettingsCommandRow(
                    icon: "sparkles.rectangle.stack",
                    titleResource: L10n.Settings.showIntroduction,
                    tint: AppTheme.purple
                )
            }
            .buttonStyle(.plain)
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

private struct SettingsICloudSyncEntry: Identifiable {
    let item: RecordingItem
    let status: RecordingICloudSyncStatus

    var id: RecordingItem.ID { item.id }
}

private struct SettingsICloudSyncGroup: Identifiable {
    let state: RecordingICloudSyncState
    let entries: [SettingsICloudSyncEntry]

    var id: String { state.settingsID }
    var displayName: String { entries.first?.status.displayName ?? "" }
    var systemImage: String { entries.first?.status.systemImage ?? "icloud" }
    var tint: Color { state.settingsTint }
}

private struct SettingsICloudSyncStatusSection: View {
    let group: SettingsICloudSyncGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettingsIcon(systemImage: group.systemImage, tint: group.tint)

                Text(group.displayName)
                    .font(.redditSans(.headline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                Text("\(group.entries.count)")
                    .font(.redditSans(.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(group.tint)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(group.tint.opacity(0.12), in: Capsule())
            }

            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    SettingsICloudSyncRecordingRow(entry: entry, tint: group.tint)

                    if entry.id != group.entries.last?.id {
                        Divider()
                            .padding(.leading, 38)
                    }
                }
            }
        }
        .settingsSurface()
    }
}

private struct SettingsICloudSyncRecordingRow: View {
    let entry: SettingsICloudSyncEntry
    let tint: Color

    private var supplementalFileProgress: String? {
        switch entry.status.state {
        case .waiting, .failed:
            guard entry.status.totalFileCount > 0 else {
                return nil
            }
            return String(
                format: String(localized: L10n.ICloud.filesUploadedFormat),
                entry.status.uploadedFileCount,
                entry.status.totalFileCount
            )
        case .localOnly, .iCloudUnavailable, .uploading, .uploaded:
            return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.status.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.item.displayName)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(entry.item.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)

                Text(entry.status.detailText)
                    .font(.redditSans(.caption))
                    .foregroundStyle(entry.status.state == .failed ? AppTheme.danger : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let supplementalFileProgress {
                    Text(supplementalFileProgress)
                        .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}

private extension RecordingICloudSyncState {
    var settingsID: String {
        switch self {
        case .localOnly: return "localOnly"
        case .iCloudUnavailable: return "iCloudUnavailable"
        case .waiting: return "waiting"
        case .uploading: return "uploading"
        case .uploaded: return "uploaded"
        case .failed: return "failed"
        }
    }

    var settingsTint: Color {
        switch self {
        case .localOnly: return .secondary
        case .iCloudUnavailable: return AppTheme.warning
        case .waiting: return AppTheme.warning
        case .uploading: return AppTheme.info
        case .uploaded: return AppTheme.success
        case .failed: return AppTheme.danger
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

private struct SettingsPickerRow: View {
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

            HStack(spacing: 6) {
                Text(value)
                    .font(.redditSans(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 42)
        .contentShape(Rectangle())
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

    init(icon: String, title: String, tint: Color) {
        self.icon = icon
        self.title = Text(verbatim: title)
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
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 42)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 18)

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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 18)

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
    func settingsNavigationHaptic() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                HapticFeedback.play(.navigation)
            }
        )
    }

    func settingsSurface() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(
                color: AppTheme.cardShadow,
                radius: AppTheme.cardShadowRadius,
                y: AppTheme.cardShadowYOffset
            )
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
