import AppKit
import AVFoundation
import CoreGraphics
import CoreLocation
import EventKit
import Speech
import SwiftUI
import TranscriberDomain

// MARK: - General pane

struct MacGeneralSettingsPane: View {
    @AppStorage(MacAppLanguage.defaultsKey)
    private var appLanguageRawValue = MacAppLanguage.system.rawValue
    @State private var isShowingRestartPrompt = false

    private var selectedLanguage: MacAppLanguage {
        MacAppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    private var needsRelaunch: Bool {
        selectedLanguage != MacAppLanguage.selectionAtLaunch
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: languageBinding) {
                    ForEach(MacAppLanguage.allCases) { language in
                        Text(verbatim: language.displayName)
                            .tag(language)
                    }
                } label: {
                    Label {
                        Text(MacL10n.appLanguage)
                    } icon: {
                        Image(systemName: "globe")
                    }
                }

                Text(MacL10n.appLanguageDescription)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)

                if needsRelaunch {
                    HStack(spacing: 10) {
                        Label {
                            Text(MacL10n.languageRestartRequired)
                        } icon: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                        }
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)

                        Spacer()

                        Button {
                            relaunchApplication()
                        } label: {
                            Text(MacL10n.restartNow)
                        }
                    }
                }
            } header: {
                Text(MacL10n.generalSettings)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 260)
        .alert(
            String(localized: MacL10n.languageRestartTitle),
            isPresented: $isShowingRestartPrompt
        ) {
            Button(String(localized: MacL10n.restartNow)) {
                relaunchApplication()
            }
            Button(String(localized: MacL10n.restartLater), role: .cancel) {}
        } message: {
            Text(MacL10n.languageRestartMessage)
        }
    }

    private var languageBinding: Binding<MacAppLanguage> {
        Binding {
            selectedLanguage
        } set: { language in
            appLanguageRawValue = language.rawValue
            language.applyBundlePreference()
            isShowingRestartPrompt = language != MacAppLanguage.selectionAtLaunch
        }
    }

    @MainActor
    private func relaunchApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            guard error == nil else {
                return
            }
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Transcription pane

struct MacTranscriptionSettingsPane: View {
    @EnvironmentObject private var transcriber: LiveTranscriptionManager

    @StateObject private var mossModel = MacMOSSModelController()
    @StateObject private var geminiUsage = GeminiTokenUsageTracker.shared

    @State private var whisperStatus = LocalWhisperModelManager.currentStatus()
    @State private var whisperEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
    @State private var whisperLiveStatus = LocalWhisperModelManager.currentLiveStatus()
    @State private var whisperLiveEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
    @State private var downloadedWhisperStatuses = LocalWhisperModelManager.downloadedStatuses()
    @State private var selectedWhisperModelID = LocalWhisperModelManager.selectedModel.id
    @State private var selectedLiveWhisperModelID = LocalWhisperModelManager.selectedLiveModel?.id
    @State private var isCoreMLEncoderEnabled = LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled
    @State private var whisperDownloadProgress: Double?
    @State private var whisperEncoderDownloadProgress: Double?
    @State private var liveWhisperDownloadProgress: Double?
    @State private var liveWhisperEncoderDownloadProgress: Double?
    @State private var qwen3Status = Qwen3ASRModelManager.currentStatus()
    @State private var qwen3DownloadProgress: Double?
    @State private var isGeminiEnabled = GeminiCloudConfiguration.isEnabled
    @State private var geminiAPIKey = (try? GeminiAPIKeyStore.load()) ?? ""
    @State private var selectedDecoderDuration = MOSSDecoderSegmentDuration.selected
    @State private var selectedDecoderMaximumOutputTokens = MOSSDecoderMaximumOutputTokens.selected
    @State private var isConfirmingMOSSDeletion = false
    @State private var errorMessage: String?

    private let mossRecommendation = MOSSDecoderDeviceRecommendation.current

    var body: some View {
        Form {
            languageSection
            liveBackendSection
            whisperSection
            qwen3Section
            mossSection
            geminiSection
        }
        .formStyle(.grouped)
        .frame(minHeight: 520)
        .task {
            refreshAllStatuses()
        }
        .alert(
            String(localized: MacL10n.actionFailed),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            Text(L10n.MOSSLocal.deleteModel),
            isPresented: $isConfirmingMOSSDeletion
        ) {
            Button(role: .destructive) {
                mossModel.deleteModel()
            } label: {
                Text(L10n.MOSSLocal.deleteModel)
            }
        }
    }

    private func refreshAllStatuses() {
        whisperStatus = LocalWhisperModelManager.currentStatus()
        whisperEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
        whisperLiveStatus = LocalWhisperModelManager.currentLiveStatus()
        whisperLiveEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
        downloadedWhisperStatuses = LocalWhisperModelManager.downloadedStatuses()
        selectedWhisperModelID = LocalWhisperModelManager.selectedModel.id
        selectedLiveWhisperModelID = LocalWhisperModelManager.selectedLiveModel?.id
        qwen3Status = Qwen3ASRModelManager.currentStatus()
        mossModel.refresh()
    }

    // MARK: Language

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { transcriber.selectedLanguageID },
                set: { transcriber.selectedLanguageID = $0 }
            )) {
                ForEach(transcriber.supportedLanguages) { language in
                    Text(verbatim: language.displayName)
                        .tag(language.id)
                }
            } label: {
                Text(L10n.Settings.transcriptionLanguage)
            }
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            if transcriber.isRecording {
                Text(L10n.Settings.cannotChangeLanguageWhileRecording)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.Settings.transcription)
        }
    }

    // MARK: Live backend

    private var liveBackendSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { transcriber.selectedTranscriptionBackend == .localWhisperBeta },
                    set: { transcriber.selectedTranscriptionBackend = $0 ? .localWhisperBeta : .appleOnDevice }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.TranscriptionBackend.localWhisperBetaTitle)
                    Text(L10n.TranscriptionBackend.localWhisperBetaDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(transcriber.isRecording || transcriber.isPreparing)

            if transcriber.selectedTranscriptionBackend == .localWhisperBeta {
                Picker(selection: $selectedLiveWhisperModelID) {
                    Text(L10n.LocalWhisper.liveModelNotSelected)
                        .tag(String?.none)
                    ForEach(LocalWhisperModelManager.availableModels) { model in
                        Text(verbatim: model.displayName)
                            .tag(String?.some(model.id))
                    }
                } label: {
                    Text(L10n.LocalWhisper.liveModelTitle)
                }
                .onChange(of: selectedLiveWhisperModelID) { _, newValue in
                    if let newValue,
                       let model = LocalWhisperModelManager.model(withID: newValue) {
                        LocalWhisperModelManager.selectLiveModel(model)
                    }
                    whisperLiveStatus = LocalWhisperModelManager.currentLiveStatus()
                    whisperLiveEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
                }

                if let liveStatus = whisperLiveStatus {
                    LabeledContent {
                        Text(verbatim: liveStatus.statusText)
                    } label: {
                        Text(L10n.LocalWhisper.modelStatus)
                    }

                    if !liveStatus.isAvailable {
                        modelDownloadControl(
                            progress: $liveWhisperDownloadProgress,
                            title: L10n.LocalWhisper.downloadLiveModel
                        ) {
                            guard let modelID = selectedLiveWhisperModelID,
                                  let model = LocalWhisperModelManager.model(withID: modelID) else {
                                return
                            }
                            downloadWhisperModel(model, progress: $liveWhisperDownloadProgress) {
                                whisperLiveStatus = LocalWhisperModelManager.currentLiveStatus()
                            }
                        }
                    }

                    if isCoreMLEncoderEnabled,
                       liveStatus.isAvailable,
                       let liveEncoderStatus = whisperLiveEncoderStatus {
                        LabeledContent {
                            Text(verbatim: liveEncoderStatus.statusText)
                        } label: {
                            Text(L10n.LocalWhisper.coreMLEncoderStatus)
                        }

                        Text(verbatim: liveEncoderStatus.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !liveEncoderStatus.isAvailable {
                            modelDownloadControl(
                                progress: $liveWhisperEncoderDownloadProgress,
                                title: L10n.LocalWhisper.downloadCoreMLEncoder
                            ) {
                                downloadLiveWhisperEncoder()
                            }
                        }
                    }
                }

                if selectedLiveWhisperModelID == nil {
                    Label {
                        Text(L10n.Settings.localWhisperLiveBetaRequiresSelection)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(AppTheme.warning)
                } else if whisperLiveStatus?.isAvailable != true {
                    Label {
                        Text(L10n.Settings.localWhisperLiveBetaRequiresModel)
                    } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .foregroundStyle(AppTheme.warning)
                }
            }
        } header: {
            Text(L10n.Settings.betaFeatures)
        }
    }

    // MARK: Whisper (offline)

    private var whisperSection: some View {
        Section {
            Picker(selection: $selectedWhisperModelID) {
                ForEach(LocalWhisperModelManager.availableModels) { model in
                    Text(verbatim: model.displayName)
                        .tag(model.id)
                }
            } label: {
                Text(L10n.LocalWhisper.selectedModel)
            }
            .onChange(of: selectedWhisperModelID) { _, newValue in
                if let model = LocalWhisperModelManager.model(withID: newValue) {
                    LocalWhisperModelManager.selectModel(model)
                }
                whisperStatus = LocalWhisperModelManager.currentStatus()
                whisperEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
            }

            LabeledContent {
                Text(verbatim: whisperStatus.statusText)
            } label: {
                Text(L10n.LocalWhisper.modelStatus)
            }

            Text(verbatim: whisperStatus.detailText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !whisperStatus.isAvailable {
                modelDownloadControl(
                    progress: $whisperDownloadProgress,
                    title: L10n.LocalWhisper.downloadSelectedModel
                ) {
                    downloadWhisperModel(
                        LocalWhisperModelManager.selectedModel,
                        progress: $whisperDownloadProgress
                    ) {
                        whisperStatus = LocalWhisperModelManager.currentStatus()
                        downloadedWhisperStatuses = LocalWhisperModelManager.downloadedStatuses()
                    }
                }
            }

            Toggle(isOn: $isCoreMLEncoderEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.LocalWhisper.coreMLEncoderLoading)
                    Text(L10n.LocalWhisper.coreMLEncoderLoadingDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: isCoreMLEncoderEnabled) { _, newValue in
                LocalWhisperModelManager.isCoreMLEncoderLoadingEnabled = newValue
                whisperEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
                whisperLiveEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
            }

            if isCoreMLEncoderEnabled {
                LabeledContent {
                    Text(verbatim: whisperEncoderStatus.statusText)
                } label: {
                    Text(L10n.LocalWhisper.coreMLEncoderStatus)
                }

                if !whisperEncoderStatus.isAvailable {
                    modelDownloadControl(
                        progress: $whisperEncoderDownloadProgress,
                        title: L10n.LocalWhisper.downloadCoreMLEncoder
                    ) {
                        downloadWhisperEncoder()
                    }
                }
            }

            if !downloadedWhisperStatuses.isEmpty {
                DisclosureGroup {
                    ForEach(downloadedWhisperStatuses, id: \.model.id) { status in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: status.model.displayName)
                                Text(verbatim: status.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                deleteWhisperModel(status.model)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } label: {
                    Text(L10n.LocalWhisper.downloadedModelsTitle)
                }
            }

            Link(
                String(localized: L10n.LocalWhisper.aboutModel),
                destination: URL(string: "https://github.com/openai/whisper")!
            )
        } header: {
            Text(L10n.LocalWhisper.modelTitle)
        }
    }

    // MARK: Qwen3 ASR

    private var qwen3Section: some View {
        Section {
            LabeledContent {
                Text(verbatim: qwen3Status.statusText)
            } label: {
                Text(L10n.Qwen3ASR.modelStatus)
            }

            Text(verbatim: qwen3Status.detailText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let progress = qwen3DownloadProgress {
                ProgressView(value: progress)
            } else {
                HStack {
                    if !qwen3Status.isAvailable {
                        Button {
                            downloadQwen3()
                        } label: {
                            Text(L10n.Qwen3ASR.downloadModel)
                        }
                    }
                    if qwen3Status.hasStoredFiles {
                        Button(role: .destructive) {
                            do {
                                qwen3Status = try Qwen3ASRModelManager.deleteDownloadedModel()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            Text(L10n.Qwen3ASR.deleteModel)
                        }
                    }
                }
            }

            Link(
                String(localized: L10n.Qwen3ASR.aboutModel),
                destination: URL(string: "https://github.com/QwenLM/Qwen3-ASR")!
            )
        } header: {
            Text(L10n.Qwen3ASR.modelTitle)
        }
    }

    // MARK: MOSS

    private var mossSection: some View {
        Section {
            LabeledContent {
                Text(verbatim: mossModel.status.statusText)
            } label: {
                Text(L10n.MOSSLocal.modelName)
            }

            Text(verbatim: mossModel.status.detailText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if mossModel.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: mossModel.downloadProgress)
                    Text(
                        verbatim: String(
                            format: String(localized: L10n.MOSSLocal.downloadingModelFormat),
                            mossModel.downloadProgress * 100
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            } else {
                HStack {
                    Button {
                        mossModel.download()
                    } label: {
                        Text(L10n.MOSSLocal.downloadModel)
                    }
                    .disabled(mossModel.status.isAvailable)

                    if mossModel.status.hasStoredFiles {
                        Button(role: .destructive) {
                            isConfirmingMOSSDeletion = true
                        } label: {
                            Text(L10n.MOSSLocal.deleteModel)
                        }
                    }
                }
            }

            Picker(selection: $selectedDecoderDuration) {
                ForEach(MOSSDecoderSegmentDuration.allCases) { duration in
                    Text(verbatim: mossDecoderChoiceTitle(for: duration))
                        .tag(duration)
                }
            } label: {
                Text(L10n.MOSSLocal.decoderSegmentDuration)
            }
            .onChange(of: selectedDecoderDuration) { _, newValue in
                UserDefaults.standard.set(
                    newValue.rawValue,
                    forKey: MOSSDecoderSegmentDuration.defaultsKey
                )
            }

            Text(L10n.MOSSLocal.decoderSegmentDurationDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker(selection: $selectedDecoderMaximumOutputTokens) {
                ForEach(MOSSDecoderMaximumOutputTokens.allCases) { maximumOutputTokens in
                    Text(verbatim: maximumOutputTokens.displayName)
                        .tag(maximumOutputTokens)
                }
            } label: {
                Text(L10n.MOSSLocal.decoderMaximumOutputTokens)
            }
            .onChange(of: selectedDecoderMaximumOutputTokens) { _, newValue in
                UserDefaults.standard.set(
                    newValue.rawValue,
                    forKey: MOSSDecoderMaximumOutputTokens.defaultsKey
                )
            }

            Text(L10n.MOSSLocal.decoderMaximumOutputTokensDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(
                verbatim: String(
                    format: String(localized: L10n.MOSSLocal.decoderRecommendationFormat),
                    mossRecommendation.duration.displayName,
                    mossRecommendation.physicalMemoryText
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if selectedDecoderDuration != mossRecommendation.duration {
                Button {
                    selectedDecoderDuration = mossRecommendation.duration
                    UserDefaults.standard.set(
                        mossRecommendation.duration.rawValue,
                        forKey: MOSSDecoderSegmentDuration.defaultsKey
                    )
                } label: {
                    Text(
                        verbatim: String(
                            format: String(localized: L10n.MOSSLocal.decoderUseRecommendationFormat),
                            mossRecommendation.duration.displayName
                        )
                    )
                }

                if selectedDecoderDuration.rawValue > mossRecommendation.duration.rawValue {
                    Label {
                        Text(
                            verbatim: String(
                                format: String(localized: L10n.MOSSLocal.decoderAboveRecommendationFormat),
                                selectedDecoderDuration.displayName
                            )
                        )
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.callout)
                    .foregroundStyle(AppTheme.warning)
                }
            }

            Link(
                String(localized: L10n.MOSSLocal.aboutModel),
                destination: URL(string: "https://github.com/OpenMOSS/MOSS-Transcribe-Diarize#model-architecture")!
            )
        } header: {
            Text(L10n.MOSSLocal.modelTitle)
        } footer: {
            Text(L10n.MOSSLocal.modelDescription)
        }
    }

    // MARK: Gemini

    private var geminiSection: some View {
        Section {
            Toggle(isOn: $isGeminiEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.GeminiCloud.enableTitle)
                    Text(L10n.GeminiCloud.enableDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(transcriber.isRecording)
            .onChange(of: isGeminiEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "gemini.cloud.enabled")
                if !newValue,
                   RecordingSummaryProvider.selected == .geminiCloud {
                    UserDefaults.standard.set(
                        RecordingSummaryProvider.automatic.rawValue,
                        forKey: RecordingSummaryProvider.selectedDefaultsKey
                    )
                }
            }

            if isGeminiEnabled {
                SecureField(text: $geminiAPIKey) {
                    Text(L10n.GeminiCloud.apiKeyPrompt)
                }
                .onChange(of: geminiAPIKey) { _, newValue in
                    do {
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            try GeminiAPIKeyStore.delete()
                        } else {
                            try GeminiAPIKeyStore.save(trimmed)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }

                Text(L10n.GeminiCloud.apiKeyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !geminiAPIKey.isEmpty {
                    Button(role: .destructive) {
                        do {
                            try GeminiAPIKeyStore.delete()
                            geminiAPIKey = ""
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Text(L10n.GeminiCloud.clearAPIKey)
                    }
                }

                LabeledContent {
                    Text(verbatim: GeminiCloudService.model)
                } label: {
                    Text(L10n.GeminiCloud.usageModel)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.requestCount)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageRequests)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.totalTokens)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageTotalTokens)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.inputTokens)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageInputTokens)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.outputTokens)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageOutputTokens)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.thoughtTokens)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageThoughtTokens)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.cachedTokens)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageCachedTokens)
                }
                LabeledContent {
                    Text(verbatim: "\(geminiUsage.snapshot.lastTotalTokens)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.GeminiCloud.usageLastRequest)
                }
                if let lastUpdatedAt = geminiUsage.snapshot.lastUpdatedAt {
                    Text(
                        verbatim: String(
                            format: String(localized: L10n.GeminiCloud.usageUpdatedFormat),
                            lastUpdatedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text(L10n.GeminiCloud.usageLocalDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    geminiUsage.reset()
                } label: {
                    Text(L10n.GeminiCloud.resetUsage)
                }
            }
        } header: {
            Text(L10n.Settings.onlineTranscription)
        }
    }

    // MARK: Shared helpers

    private func mossDecoderChoiceTitle(for duration: MOSSDecoderSegmentDuration) -> String {
        guard duration == mossRecommendation.duration else {
            return duration.displayName
        }
        return String(
            format: String(localized: L10n.MOSSLocal.decoderRecommendedChoiceFormat),
            duration.displayName
        )
    }

    @ViewBuilder
    private func modelDownloadControl(
        progress: Binding<Double?>,
        title: LocalizedStringResource,
        action: @escaping () -> Void
    ) -> some View {
        if let value = progress.wrappedValue {
            ProgressView(value: value)
        } else {
            Button {
                action()
            } label: {
                Text(title)
            }
        }
    }

    private func downloadWhisperModel(
        _ model: LocalWhisperModel,
        progress: Binding<Double?>,
        completion: @escaping () -> Void
    ) {
        progress.wrappedValue = 0
        Task {
            do {
                _ = try await LocalWhisperModelManager.download(model: model) { fraction in
                    Task { @MainActor in
                        progress.wrappedValue = fraction
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            progress.wrappedValue = nil
            completion()
        }
    }

    private func downloadWhisperEncoder() {
        whisperEncoderDownloadProgress = 0
        Task {
            do {
                _ = try await LocalWhisperModelManager.downloadCoreMLEncoder(
                    for: LocalWhisperModelManager.selectedModel
                ) { fraction in
                    Task { @MainActor in
                        whisperEncoderDownloadProgress = fraction
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            whisperEncoderDownloadProgress = nil
            whisperEncoderStatus = LocalWhisperModelManager.currentCoreMLEncoderStatus()
        }
    }

    private func downloadLiveWhisperEncoder() {
        guard let modelID = selectedLiveWhisperModelID,
              let model = LocalWhisperModelManager.model(withID: modelID) else {
            return
        }
        liveWhisperEncoderDownloadProgress = 0
        Task {
            do {
                _ = try await LocalWhisperModelManager.downloadCoreMLEncoder(for: model) { fraction in
                    Task { @MainActor in
                        liveWhisperEncoderDownloadProgress = fraction
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            liveWhisperEncoderDownloadProgress = nil
            whisperLiveEncoderStatus = LocalWhisperModelManager.currentLiveCoreMLEncoderStatus()
        }
    }

    private func deleteWhisperModel(_ model: LocalWhisperModel) {
        do {
            _ = try LocalWhisperModelManager.deleteDownloadedModel(model)
            downloadedWhisperStatuses = LocalWhisperModelManager.downloadedStatuses()
            whisperStatus = LocalWhisperModelManager.currentStatus()
            whisperLiveStatus = LocalWhisperModelManager.currentLiveStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func downloadQwen3() {
        qwen3DownloadProgress = 0
        Task {
            do {
                qwen3Status = try await Qwen3ASRModelManager.download { fraction in
                    Task { @MainActor in
                        qwen3DownloadProgress = fraction
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                qwen3Status = Qwen3ASRModelManager.currentStatus()
            }
            qwen3DownloadProgress = nil
        }
    }
}

// MARK: - Intelligence pane

struct MacIntelligenceSettingsPane: View {
    @EnvironmentObject private var recordingStore: RecordingStore

    @State private var selectedProvider = RecordingSummaryProvider.selected
    @State private var selectedSummaryModelID = LocalSummaryModelManager.selectedModel.id
    @State private var summaryModelStatus = LocalSummaryModelManager.currentStatus()
    @State private var summaryDownloadProgress: Double?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Picker(selection: $selectedProvider) {
                    ForEach(RecordingSummaryProvider.menuProviders) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                } label: {
                    Text(L10n.LocalSummary.providerTitle)
                }
                .onChange(of: selectedProvider) { _, newValue in
                    UserDefaults.standard.set(
                        newValue.rawValue,
                        forKey: RecordingSummaryProvider.selectedDefaultsKey
                    )
                    recordingStore.refreshIntelligenceAvailability()
                }

                LabeledContent {
                    Text(verbatim: RecordingIntelligenceAvailability.currentAppleIntelligence().statusText)
                } label: {
                    Text(L10n.LocalSummary.providerAppleTitle)
                }

                Text(verbatim: RecordingIntelligenceAvailability.currentAppleIntelligence().detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.Settings.intelligence)
            }

            Section {
                Picker(selection: $selectedSummaryModelID) {
                    ForEach(LocalSummaryModelManager.availableModels) { model in
                        Text(verbatim: model.displayName)
                            .tag(model.id)
                    }
                } label: {
                    Text(L10n.LocalSummary.selectedModel)
                }
                .onChange(of: selectedSummaryModelID) { _, modelID in
                    guard let model = LocalSummaryModelManager.availableModels.first(where: { $0.id == modelID }) else {
                        return
                    }
                    LocalSummaryModelManager.selectModel(model)
                    summaryModelStatus = LocalSummaryModelManager.status(for: model)
                    recordingStore.refreshIntelligenceAvailability()
                }

                if let model = LocalSummaryModelManager.availableModels.first(where: { $0.id == selectedSummaryModelID }) {
                    Text(verbatim: model.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                LabeledContent {
                    Text(verbatim: summaryModelStatus.statusText)
                } label: {
                    Text(L10n.LocalSummary.modelStatus)
                }

                Text(verbatim: summaryModelStatus.detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let progress = summaryDownloadProgress {
                    ProgressView(value: progress)
                } else {
                    HStack {
                        if !summaryModelStatus.isAvailable {
                            Button {
                                downloadSummaryModel()
                            } label: {
                                Text(L10n.LocalSummary.downloadSelectedModel)
                            }
                        }
                        if summaryModelStatus.isUserInstalled {
                            Button(role: .destructive) {
                                do {
                                    summaryModelStatus = try LocalSummaryModelManager.deleteDownloadedModel(summaryModelStatus.model)
                                    recordingStore.refreshIntelligenceAvailability()
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            } label: {
                                Text(L10n.LocalSummary.deleteModelDownload)
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.LocalSummary.modelTitle)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
        .alert(
            String(localized: MacL10n.actionFailed),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func downloadSummaryModel() {
        summaryDownloadProgress = 0
        guard let model = LocalSummaryModelManager.availableModels.first(where: { $0.id == selectedSummaryModelID }) else {
            summaryDownloadProgress = nil
            return
        }
        Task {
            do {
                summaryModelStatus = try await LocalSummaryModelManager.download(model: model) { fraction in
                    Task { @MainActor in
                        summaryDownloadProgress = fraction
                    }
                }
                recordingStore.refreshIntelligenceAvailability()
            } catch {
                errorMessage = error.localizedDescription
                summaryModelStatus = LocalSummaryModelManager.currentStatus()
            }
            summaryDownloadProgress = nil
        }
    }
}

// MARK: - Recording pane

struct MacRecordingSettingsPane: View {
    @EnvironmentObject private var transcriber: LiveTranscriptionManager

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { transcriber.selectedAudioFormat },
                    set: { transcriber.selectedAudioFormat = $0 }
                )) {
                    ForEach(RecordingAudioFormat.allCases) { format in
                        Text(format.title)
                            .tag(format)
                    }
                } label: {
                    Text(L10n.Settings.recordingFormat)
                }
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                if transcriber.isRecording {
                    Text(L10n.Settings.cannotChangeFormatWhileRecording)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(transcriber.selectedAudioFormat.detailResource)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.Settings.recording)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 200)
    }
}

// MARK: - Files pane

struct MacFilesSettingsPane: View {
    @EnvironmentObject private var recordingStore: RecordingStore

    private var syncSummary: RecordingICloudSyncSummary {
        recordingStore.iCloudSyncSummary
    }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim: "\(recordingStore.recordings.count)")
                        .monospacedDigit()
                } label: {
                    Text(L10n.Settings.recordingCount)
                }

                LabeledContent {
                    Text(verbatim: recordingStore.storageDisplayName)
                } label: {
                    Text(L10n.Settings.storageLocation)
                }

                Toggle(isOn: Binding(
                    get: { recordingStore.isICloudStorageEnabled },
                    set: { newValue in
                        Task {
                            await recordingStore.setICloudStorageEnabled(newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Settings.iCloudSync)
                        Text(L10n.Settings.iCloudSyncDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(recordingStore.isStorageLocationChanging)

                if recordingStore.isStorageLocationChanging {
                    ProgressView()
                        .controlSize(.small)
                }

                LabeledContent {
                    Text(verbatim: recordingStore.iCloudStorageStatusDisplayName)
                } label: {
                    Text(L10n.Settings.iCloudStatus)
                }

                Text(verbatim: recordingStore.iCloudStorageDetailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    openRecordingsFolder()
                } label: {
                    Label {
                        Text(MacL10n.openRecordingsFolder)
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            } header: {
                Text(L10n.Settings.files)
            }

            Section {
                LabeledContent {
                    Text(verbatim: syncSummary.statusText)
                } label: {
                    Label {
                        Text(L10n.Settings.iCloudProgress)
                    } icon: {
                        Image(systemName: syncSummary.systemImage)
                    }
                }

                Text(verbatim: syncSummary.detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !recordingStore.recordings.isEmpty {
                    DisclosureGroup {
                        ForEach(recordingStore.recordings) { item in
                            let status = recordingStore.iCloudSyncStatus(for: item)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Label {
                                        Text(verbatim: item.displayName)
                                            .lineLimit(1)
                                    } icon: {
                                        Image(systemName: status.systemImage)
                                    }
                                    Spacer()
                                    Text(verbatim: status.displayName)
                                        .foregroundStyle(.secondary)
                                }
                                Text(verbatim: status.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    } label: {
                        Text(L10n.Settings.iCloudProgress)
                    }
                }
            } header: {
                Text(L10n.Settings.iCloudProgress)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
        .task {
            while !Task.isCancelled {
                recordingStore.refreshICloudSyncStatus(logDiagnostics: true)
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func openRecordingsFolder() {
        let directory = recordingStore.recordingsDirectory
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(directory)
    }
}

// MARK: - Privacy pane

struct MacPrivacySettingsPane: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionRevision = 0

    var body: some View {
        Form {
            Section {
                Label {
                    Text(L10n.Settings.noDeveloperServers)
                } icon: {
                    Image(systemName: "network.slash")
                }
                Label {
                    Text(L10n.Settings.onDeviceProcessing)
                } icon: {
                    Image(systemName: "cpu")
                }
                Label {
                    Text(L10n.Settings.developerCannotAccessContent)
                } icon: {
                    Image(systemName: "lock.shield")
                }
                Label {
                    Text(L10n.Settings.deleteRemovesManagedFiles)
                } icon: {
                    Image(systemName: "trash.slash")
                }
                Label {
                    Text(L10n.Settings.indexSyncPrivateDatabase)
                } icon: {
                    Image(systemName: "icloud")
                }

                Link(
                    String(localized: L10n.Settings.privacyPolicy),
                    destination: URL(string: "https://iamwilliamli.github.io/LiveTranscriber/privacy/")!
                )
            } header: {
                Text(L10n.Settings.localProcessing)
            }

            Section {
                Label {
                    Text(L10n.Settings.localThenICloudStorage)
                } icon: {
                    Image(systemName: "internaldrive")
                }
                Label {
                    Text(L10n.Settings.microphonePermissionUse)
                } icon: {
                    Image(systemName: "mic")
                }
                Label {
                    Text(L10n.Settings.speechPermissionUse)
                } icon: {
                    Image(systemName: "captions.bubble")
                }
                Label {
                    Text(L10n.Settings.locationPermissionUse)
                } icon: {
                    Image(systemName: "location")
                }
                Label {
                    Text(MacL10n.screenRecordingPermissionUse)
                } icon: {
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                }
                Label {
                    Text(MacL10n.menuBarStatusUse)
                } icon: {
                    Image(systemName: "menubar.rectangle")
                }
            } header: {
                Text(L10n.Settings.permissionUsage)
            }

            Section {
                MacPermissionStatusRow(
                    title: String(localized: L10n.Settings.microphonePermissionUse),
                    systemImage: "mic",
                    status: microphonePermissionStatus,
                    openSettings: { openPrivacySettings(anchor: "Privacy_Microphone") }
                )
                MacPermissionStatusRow(
                    title: String(localized: L10n.Settings.speechPermissionUse),
                    systemImage: "captions.bubble",
                    status: speechPermissionStatus,
                    openSettings: { openPrivacySettings(anchor: "Privacy_SpeechRecognition") }
                )
                MacPermissionStatusRow(
                    title: String(localized: L10n.Settings.locationPermissionUse),
                    systemImage: "location",
                    status: locationPermissionStatus,
                    openSettings: { openPrivacySettings(anchor: "Privacy_LocationServices") }
                )
                MacPermissionStatusRow(
                    title: String(localized: MacL10n.screenRecordingPermission),
                    systemImage: "rectangle.inset.filled.and.person.filled",
                    status: screenRecordingPermissionStatus,
                    openSettings: { openPrivacySettings(anchor: "Privacy_ScreenCapture") }
                )
                MacPermissionStatusRow(
                    title: String(localized: MacL10n.remindersPermission),
                    systemImage: "checklist",
                    status: remindersPermissionStatus,
                    openSettings: { openPrivacySettings(anchor: "Privacy_Reminders") }
                )
            } header: {
                Text(MacL10n.permissionStatus)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 560)
        .id(permissionRevision)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                permissionRevision += 1
            }
        }
    }

    private var microphonePermissionStatus: MacPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .allowed
        case .notDetermined: .notRequested
        case .denied, .restricted: .denied
        @unknown default: .unknown
        }
    }

    private var speechPermissionStatus: MacPermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .allowed
        case .notDetermined: .notRequested
        case .denied, .restricted: .denied
        @unknown default: .unknown
        }
    }

    private var locationPermissionStatus: MacPermissionStatus {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: .allowed
        case .notDetermined: .notRequested
        case .denied, .restricted: .denied
        @unknown default: .unknown
        }
    }

    private var screenRecordingPermissionStatus: MacPermissionStatus {
        CGPreflightScreenCaptureAccess() ? .allowed : .notGranted
    }

    private var remindersPermissionStatus: MacPermissionStatus {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess {
            return .allowed
        }
        if status == .notDetermined {
            return .notRequested
        }
        if status == .denied || status == .restricted {
            return .denied
        }
        return .notGranted
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private enum MacPermissionStatus {
    case allowed
    case notRequested
    case notGranted
    case denied
    case unknown

    var title: LocalizedStringResource {
        switch self {
        case .allowed: MacL10n.permissionAllowed
        case .notRequested: MacL10n.permissionNotRequested
        case .notGranted: MacL10n.permissionNotGranted
        case .denied: MacL10n.permissionDenied
        case .unknown: L10n.Common.unknown
        }
    }

    var color: Color {
        switch self {
        case .allowed: AppTheme.success
        case .notRequested, .notGranted: AppTheme.warning
        case .denied: AppTheme.danger
        case .unknown: .secondary
        }
    }
}

private struct MacPermissionStatusRow: View {
    let title: String
    let systemImage: String
    let status: MacPermissionStatus
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: systemImage)
                .lineLimit(2)
            Spacer()
            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.color)
            Button(action: openSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help(String(localized: MacL10n.openSystemSettings))
        }
    }
}

// MARK: - About pane

struct MacAboutSettingsPane: View {
    private static let publicBetaFeedbackURL = URL(string: "https://t.me/livetranscriber")!
    private static let feedbackRecipient = "lichengqi0805@gmail.com"
    let openPrivacy: () -> Void
    let openDeveloperOptions: () -> Void
    @EnvironmentObject private var recordingStore: RecordingStore

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var feedbackURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackRecipient
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: "Live Transcriber macOS feedback \(appVersionText)"
            ),
            URLQueryItem(
                name: "body",
                value: "\n\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nApp: \(appVersionText)"
            ),
        ]
        return components.url ?? URL(string: "mailto:\(Self.feedbackRecipient)")!
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "LiveTranscriber")
                            .font(.redditSans(.title2, weight: .bold))
                        Text(L10n.Onboarding.heroSplashTitle)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(AppTheme.brand)
                        Text(verbatim: appVersionText)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(L10n.Settings.aboutByline)
                    .font(.redditSans(.subheadline))

                Label(
                    String(
                        format: String(localized: L10n.Settings.aboutLibraryCountFormat),
                        Int64(recordingStore.recordings.count)
                    ),
                    systemImage: "waveform"
                )

                Label {
                    Text(L10n.Settings.aboutPrivacy)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AppTheme.success)
                }
            } header: {
                Text(L10n.Settings.about)
            }

            Section {
                Link(destination: Self.publicBetaFeedbackURL) {
                    Label {
                        Text(L10n.Settings.publicBetaFeedback)
                    } icon: {
                        Image(systemName: "paperplane.fill")
                    }
                }

                Link(destination: feedbackURL) {
                    Label {
                        Text(L10n.Settings.emailFeedback)
                    } icon: {
                        Image(systemName: "envelope")
                    }
                }
            } header: {
                Text(L10n.Settings.feedback)
            }

            Section {
                Button(action: openPrivacy) {
                    HStack {
                        Label {
                            Text(L10n.Settings.privacy)
                        } icon: {
                            Image(systemName: "lock.shield")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Button(action: openDeveloperOptions) {
                    HStack {
                        Label {
                            Text(L10n.Settings.developerOptions)
                        } icon: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text(L10n.Settings.about)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 360)
    }
}

struct MacDeveloperSettingsPane: View {
    @EnvironmentObject private var transcriber: LiveTranscriptionManager
    @EnvironmentObject private var recordingStore: RecordingStore
    @AppStorage(Qwen3ASRDeveloperConfiguration.streamingLongAudioDefaultsKey)
    private var isQwen3StreamingEnabled = false
    @AppStorage(ManualGeminiDeveloperConfiguration.enabledDefaultsKey)
    private var isManualGeminiEnabled = false
    @AppStorage(MacOnboardingState.completedDefaultsKey)
    private var hasCompletedOnboarding = true

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var buildTimeText: String {
        guard let executableURL = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let date = attributes[.modificationDate] as? Date else {
            return String(localized: L10n.Common.unknown)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        let diagnostics = transcriber.speechPipelineDiagnostics
        let intelligence = recordingStore.intelligenceAvailability

        Form {
            Section {
                LabeledContent {
                    Text(verbatim: Host.current().localizedName ?? "Mac")
                } label: {
                    Text(L10n.Settings.device)
                }

                LabeledContent {
                    Text(verbatim: appVersionText)
                } label: {
                    Text(L10n.Settings.version)
                }

                LabeledContent {
                    Text(verbatim: ProcessInfo.processInfo.operatingSystemVersionString)
                } label: {
                    Text(L10n.Settings.systemVersion)
                }

                LabeledContent {
                    Text(verbatim: buildTimeText)
                } label: {
                    Text(L10n.Settings.buildTime)
                }

                LabeledContent {
                    Text(verbatim: diagnostics.activePipelineName)
                } label: {
                    Text(L10n.Settings.currentSpeechPipeline)
                }

                LabeledContent {
                    Text(verbatim: intelligence.statusText)
                } label: {
                    Text(L10n.Settings.advancedModel)
                }

                Text(verbatim: intelligence.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.Settings.developerOptions)
            }

            Section {
                Picker(selection: Binding(
                    get: { transcriber.selectedSpeechPipelineMode },
                    set: { transcriber.selectedSpeechPipelineMode = $0 }
                )) {
                    ForEach(SpeechPipelineMode.allCases) { mode in
                        Text(mode.titleResource)
                            .tag(mode)
                    }
                } label: {
                    Text(L10n.Settings.currentSpeechPipeline)
                }
                .disabled(transcriber.isRecording || transcriber.isPreparing)

                Toggle(isOn: $isQwen3StreamingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Qwen3ASR.streamingLongAudio)
                        Text(L10n.Qwen3ASR.streamingLongAudioDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $isManualGeminiEnabled) {
                    Text(L10n.Recordings.manualGemini)
                }

                LabeledContent {
                    Text(verbatim: diagnostics.configuredPipelineName)
                } label: {
                    Text(L10n.Settings.speechPipelineMode)
                }

                Text(verbatim: diagnostics.supportedPipelinesText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: diagnostics.analyzerFormatText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: diagnostics.runtimeAnalyzerFormatText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    hasCompletedOnboarding = false
                } label: {
                    Label {
                        Text(L10n.Settings.showIntroduction)
                    } icon: {
                        Image(systemName: "sparkles.rectangle.stack")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 520)
    }
}
