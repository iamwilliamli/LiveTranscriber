import Combine
import CoreLocation
import MapKit
import SwiftUI
import TranscriberDomain
import Translation

enum MacRecordingInputMode: String, CaseIterable, Identifiable {
    case microphoneOnly
    case systemAudioOnly
    case microphoneAndSystemAudio

    var id: Self { self }

    var usesSystemAudio: Bool {
        self != .microphoneOnly
    }

    var includesMicrophoneInSavedAudio: Bool {
        self == .microphoneAndSystemAudio
    }

    var title: LocalizedStringResource {
        switch self {
        case .microphoneOnly:
            return MacL10n.microphoneOnly
        case .systemAudioOnly:
            return MacL10n.systemAudioOnly
        case .microphoneAndSystemAudio:
            return MacL10n.microphoneAndSystemAudio
        }
    }
}

/// Live microphone transcription mirroring the iOS transcribe tab: language and
/// format selection, waveform, timer, interim/final transcript rows, and the
/// save-to-library flow.
struct MacTranscriptionView: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @ObservedObject var systemAudioCapture: MacSystemAudioCaptureController
    @Binding var pendingDraft: RecordingDraft?
    @Binding var externalStartRequested: Bool
    @Binding var externalStopRequested: Bool

    @AppStorage("mac.recording.input-mode")
    private var recordingInputModeRaw = ""
    @AppStorage("mac.recording.includes-system-audio")
    private var legacyIncludesSystemAudio = false

    @State private var localeReleaseAction: MacPendingSpeechLocaleReleaseAction?
    @State private var speechLocaleErrorMessage: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var selectedTranslationLanguage: TranscriptionLanguage?
    @State private var translationLanguages: [TranscriptionLanguage] = []
    @State private var translatedTextByLineID: [TranscriptionLine.ID: String] = [:]
    @State private var translatedLineSignatures: [TranscriptionLine.ID: String] = [:]
    @State private var isTranslating = false
    @State private var translationErrorMessage: String?
    @State private var lineEditRequest: MacLiveTranscriptLineEditRequest?
    @State private var pendingSystemAudioStagingDirectory: URL?
    @State private var systemAudioMessage: String?
    @State private var microphoneFallbackDraft: RecordingDraft?
    @State private var microphoneFallbackMessage: String?

    private var recordingInputMode: MacRecordingInputMode {
        MacRecordingInputMode(rawValue: recordingInputModeRaw)
            ?? (legacyIncludesSystemAudio ? .systemAudioOnly : .microphoneOnly)
    }

    var body: some View {
        VStack(spacing: 0) {
            recorderBar
            Divider()
            MacLiveTranscriptList(
                transcriber: transcriber,
                finalStore: transcriber.finalTranscriptStore,
                interimStore: transcriber.interimTranscriptStore,
                translatedTextByLineID: translatedTextByLineID,
                translatedLineSignatures: translatedLineSignatures,
                selectedTranslationLanguage: selectedTranslationLanguage,
                isTranslating: isTranslating,
                onEditFinalLine: beginEditingTranscriptLine
            )
        }
        .navigationTitle(Text(L10n.App.transcribeTab))
        .background(AppTheme.groupedBackground)
        .sheet(item: $pendingDraft) { draft in
            MacRecordingSaveSheet(
                draft: draft,
                store: recordingStore,
                onFinished: {
                    if let pendingSystemAudioStagingDirectory {
                        systemAudioCapture.discardStagingDirectory(
                            pendingSystemAudioStagingDirectory
                        )
                    }
                    pendingSystemAudioStagingDirectory = nil
                    transcriber.clearTranscript()
                    pendingDraft = nil
                },
                onDiscard: {
                    try? FileManager.default.removeItem(at: draft.audioURL)
                    if let pendingSystemAudioStagingDirectory {
                        systemAudioCapture.discardStagingDirectory(
                            pendingSystemAudioStagingDirectory
                        )
                    }
                    pendingSystemAudioStagingDirectory = nil
                    transcriber.clearTranscript()
                    pendingDraft = nil
                }
            )
        }
        .sheet(item: $lineEditRequest) { request in
            MacLiveTranscriptLineEditSheet(
                request: request,
                onSave: { text in
                    transcriber.updateFinalTranscriptLine(id: request.line.id, text: text)
                    translatedTextByLineID[request.line.id] = nil
                    translatedLineSignatures[request.line.id] = nil
                    lineEditRequest = nil
                },
                onCancel: {
                    lineEditRequest = nil
                }
            )
        }
        .task {
            translationLanguages = await AppleTranslationLanguages.supportedLanguages()
        }
        .translationTask(translationConfiguration) { session in
            await translateFinalTranscriptLines(using: session)
        }
        .onReceive(transcriber.finalTranscriptStore.$revision.dropFirst()) { _ in
            scheduleTranslationIfNeeded()
        }
        .onChange(of: transcriber.selectedLanguageID) { _, _ in
            clearTranslation()
        }
        .onAppear {
            consumeExternalStartRequest()
            consumeExternalStopRequest()
        }
        .onChange(of: externalStartRequested) { _, _ in
            consumeExternalStartRequest()
        }
        .onChange(of: externalStopRequested) { _, _ in
            consumeExternalStopRequest()
        }
        .alert(
            String(localized: L10n.SpeechText.releaseOldLanguagesTitle),
            isPresented: Binding(
                get: { localeReleaseAction != nil },
                set: { if !$0 { localeReleaseAction = nil } }
            )
        ) {
            Button(String(localized: L10n.SpeechText.releaseOldLanguagesAction), role: .destructive) {
                if let action = localeReleaseAction {
                    releaseSpeechLocalesAndContinue(action)
                }
                localeReleaseAction = nil
            }
            Button(String(localized: L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(verbatim: localeReleaseAction?.request.messageText ?? "")
        }
        .alert(
            String(localized: L10n.SpeechText.localeSetupFailed),
            isPresented: Binding(
                get: { speechLocaleErrorMessage != nil },
                set: { if !$0 { speechLocaleErrorMessage = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(speechLocaleErrorMessage ?? "")
        }
        .alert(
            String(localized: MacL10n.systemAudioRecording),
            isPresented: Binding(
                get: { systemAudioMessage != nil },
                set: { if !$0 { systemAudioMessage = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(systemAudioMessage ?? "")
        }
        .alert(
            String(localized: MacL10n.systemAudioUnavailable),
            isPresented: Binding(
                get: { microphoneFallbackDraft != nil },
                set: {
                    if !$0, microphoneFallbackDraft != nil {
                        discardMicrophoneFallback()
                    }
                }
            )
        ) {
            Button(String(localized: MacL10n.saveMicrophoneInstead)) {
                pendingDraft = microphoneFallbackDraft
                microphoneFallbackDraft = nil
                microphoneFallbackMessage = nil
            }
            Button(String(localized: L10n.Transcription.discard), role: .destructive) {
                discardMicrophoneFallback()
            }
        } message: {
            Text(
                microphoneFallbackMessage
                    ?? String(localized: MacL10n.systemAudioNoSamples)
            )
        }
    }

    // MARK: - Recorder bar

    private var recorderBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                MacElapsedTimeText(clock: transcriber.elapsedClock)

                MacLiveWaveform(store: transcriber.waveformStore)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)

                recordingInputMenu
                translationMenu
                languageMenu
                formatMenu
            }

            HStack(spacing: 12) {
                statusBadge

                if let errorText = transcriber.errorText {
                    Label {
                        Text(verbatim: errorText)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                }

                if let selectedTranslationLanguage {
                    Label {
                        Text(verbatim: translationStatusText(for: selectedTranslationLanguage))
                    } icon: {
                        if isTranslating {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: translationErrorMessage == nil ? "translate" : "exclamationmark.triangle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(translationErrorMessage == nil ? .secondary : AppTheme.warning)
                    .lineLimit(1)
                }

                if recordingInputMode.usesSystemAudio {
                    Label {
                        Text(
                            verbatim: systemAudioCapture.selectedSourceName
                                ?? String(localized: MacL10n.chooseSystemAudioSource)
                        )
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(
                        systemAudioCapture.hasSelectedSource ? .secondary : AppTheme.warning
                    )
                    .lineLimit(1)
                }

                if let warningMessage = systemAudioCapture.warningMessage {
                    Label(warningMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                        .lineLimit(1)
                }

                Spacer()

                recordControls
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusBadge: some View {
        Label {
            Text(verbatim: transcriber.statusText)
        } icon: {
            Circle()
                .fill(
                    transcriber.isRecording
                        ? (transcriber.isPaused ? AppTheme.success : AppTheme.danger)
                        : AppTheme.warning
                )
                .frame(width: 8, height: 8)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(transcriber.supportedLanguages) { language in
                Button {
                    selectLanguage(language)
                } label: {
                    if language.id == transcriber.selectedLanguageID {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(verbatim: language.displayName)
                    }
                }
            }
        } label: {
            Label {
                Text(verbatim: transcriber.selectedLanguage.displayName)
            } icon: {
                Image(systemName: "globe")
            }
        }
        .disabled(transcriber.isRecording || transcriber.isPreparing)
        .fixedSize()

    }

    private var recordingInputMenu: some View {
        Menu {
            ForEach(MacRecordingInputMode.allCases) { mode in
                Button {
                    selectRecordingInputMode(mode)
                    if mode.usesSystemAudio,
                       !systemAudioCapture.hasSelectedSource {
                        systemAudioCapture.presentSourcePicker()
                    }
                } label: {
                    if recordingInputMode == mode {
                        Label(String(localized: mode.title), systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }

            Divider()

            Button {
                if !recordingInputMode.usesSystemAudio {
                    selectRecordingInputMode(.systemAudioOnly)
                }
                systemAudioCapture.presentSourcePicker()
            } label: {
                Label(MacL10n.chooseSystemAudioSource, systemImage: "macwindow.on.rectangle")
            }

            if let sourceName = systemAudioCapture.selectedSourceName {
                LabeledContent(String(localized: MacL10n.systemAudioSource)) {
                    Text(verbatim: sourceName)
                }
            }

            Divider()
            if recordingInputMode == .systemAudioOnly {
                Text(MacL10n.systemAudioOnlyLiveCaptionNote)
            } else if recordingInputMode == .microphoneAndSystemAudio {
                Text(MacL10n.systemAudioLiveCaptionNote)
            }
            Text(MacL10n.systemAudioSourceSelectionHint)
        } label: {
            Label {
                Text(recordingInputMode.title)
            } icon: {
                Image(
                    systemName: recordingInputMode.usesSystemAudio
                        ? "speaker.wave.2.fill"
                        : "mic"
                )
            }
        }
        .disabled(transcriber.isRecording || transcriber.isPreparing || systemAudioCapture.isCapturing)
        .fixedSize()
    }

    private var translationMenu: some View {
        Menu {
            Button {
                clearTranslation()
            } label: {
                if selectedTranslationLanguage == nil {
                    Label(String(localized: L10n.Recordings.original), systemImage: "checkmark")
                } else {
                    Text(L10n.Recordings.original)
                }
            }

            Divider()

            ForEach(availableTranslationLanguages) { language in
                Button {
                    requestTranslation(to: language)
                } label: {
                    if selectedTranslationLanguage?.id == language.id {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(verbatim: language.displayName)
                    }
                }
            }

            if availableTranslationLanguages.isEmpty {
                Text(MacL10n.translationUnavailable)
            }
        } label: {
            Label {
                Text(verbatim: selectedTranslationLanguage?.shortName ?? String(localized: L10n.Recordings.translate))
            } icon: {
                Image(systemName: "translate")
            }
        }
        .fixedSize()
    }

    private var formatMenu: some View {
        Menu {
            ForEach(RecordingAudioFormat.allCases) { format in
                Button {
                    transcriber.selectedAudioFormat = format
                } label: {
                    if format == transcriber.selectedAudioFormat {
                        Label(format.title, systemImage: "checkmark")
                    } else {
                        Text(format.title)
                    }
                }
            }
        } label: {
            Label {
                Text(
                    verbatim: recordingInputMode.usesSystemAudio
                        ? "M4A"
                        : transcriber.selectedAudioFormat.badgeText
                )
            } icon: {
                Image(systemName: "waveform.circle")
            }
        }
        .disabled(
            transcriber.isRecording
                || transcriber.isPreparing
                || recordingInputMode.usesSystemAudio
        )
        .fixedSize()
    }

    private var recordControls: some View {
        HStack(spacing: 10) {
            if transcriber.isRecording {
                Button {
                    Task {
                        if transcriber.isPaused {
                            systemAudioCapture.resumeCapture()
                            await transcriber.resumeRecording()
                        } else {
                            systemAudioCapture.pauseCapture()
                            await transcriber.pauseRecording()
                        }
                    }
                } label: {
                    Image(systemName: transcriber.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)

                Button {
                    stopRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(AppTheme.danger)
            } else {
                Button {
                    startRecording()
                } label: {
                    if transcriber.isPreparing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "mic.fill")
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(AppTheme.brand)
                .disabled(transcriber.isPreparing || systemAudioCapture.phase == .starting)
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }

    // MARK: - Recording control flow

    private func startRecording() {
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            return
        }

        guard transcriber.selectedTranscriptionBackend.requiresAppleSpeech else {
            Task {
                await startPreparedRecording()
            }
            return
        }

        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    transcriber.selectedLanguage,
                    preservingLanguageIDs: [transcriber.selectedLanguageID]
                )
                switch preparation {
                case .ready:
                    await startPreparedRecording()
                case .needsRelease(let request):
                    localeReleaseAction = MacPendingSpeechLocaleReleaseAction(
                        request: request,
                        operation: .startRecording
                    )
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
            }
        }
    }

    private func consumeExternalStartRequest() {
        guard externalStartRequested else {
            return
        }
        externalStartRequested = false
        startRecording()
    }

    private func consumeExternalStopRequest() {
        guard externalStopRequested else {
            return
        }
        externalStopRequested = false
        stopRecording()
    }

    private func startPreparedRecording() async {
        if recordingInputMode.usesSystemAudio {
            guard systemAudioCapture.hasSelectedSource else {
                systemAudioCapture.presentSourcePicker()
                return
            }
            guard await systemAudioCapture.startCapture(
                includesMicrophone: recordingInputMode.includesMicrophoneInSavedAudio
            ) else {
                systemAudioMessage = systemAudioCapture.errorMessage
                    ?? String(localized: MacL10n.systemAudioNoSamples)
                return
            }
        }

        await transcriber.startRecording()
        guard transcriber.isRecording else {
            if let result = await systemAudioCapture.stopCapture() {
                systemAudioCapture.discardStagingDirectory(result.stagingDirectoryURL)
            }
            systemAudioMessage = transcriber.errorText
                ?? systemAudioCapture.errorMessage
                ?? String(localized: MacL10n.systemAudioNoSamples)
            return
        }
    }

    private func stopRecording() {
        guard transcriber.isRecording || transcriber.isPreparing || systemAudioCapture.isCapturing else {
            return
        }

        Task {
            let microphoneDraft = await transcriber.stopRecording()
            guard systemAudioCapture.isCapturing else {
                if recordingInputMode.usesSystemAudio {
                    offerMicrophoneFallback(
                        microphoneDraft,
                        message: systemAudioCapture.errorMessage
                            ?? String(localized: MacL10n.systemAudioNoSamples)
                    )
                } else {
                    pendingDraft = microphoneDraft
                }
                return
            }

            guard let result = await systemAudioCapture.stopCapture() else {
                offerMicrophoneFallback(
                    microphoneDraft,
                    message: systemAudioCapture.errorMessage
                        ?? String(localized: MacL10n.systemAudioNoSamples)
                )
                return
            }

            if let microphoneDraft,
               microphoneDraft.audioURL.standardizedFileURL != result.audioURL.standardizedFileURL {
                try? FileManager.default.removeItem(at: microphoneDraft.audioURL)
            }
            let durationSeconds = max(
                max(
                    Int(result.durationSeconds.rounded()),
                    microphoneDraft?.durationSeconds ?? 0
                ),
                1
            )
            pendingSystemAudioStagingDirectory = result.stagingDirectoryURL
            pendingDraft = RecordingDraft(
                audioURL: result.audioURL,
                startedAt: result.startedAt,
                durationSeconds: durationSeconds,
                languageID: microphoneDraft?.languageID ?? transcriber.selectedLanguageID,
                languageName: microphoneDraft?.languageName ?? transcriber.selectedLanguage.displayName,
                lines: microphoneDraft?.lines ?? finalTranscriptLines
            )
            if let warningMessage = systemAudioCapture.warningMessage {
                systemAudioMessage = warningMessage
            }
        }
    }

    private func selectRecordingInputMode(_ mode: MacRecordingInputMode) {
        recordingInputModeRaw = mode.rawValue
        legacyIncludesSystemAudio = mode.usesSystemAudio
    }

    private func offerMicrophoneFallback(
        _ draft: RecordingDraft?,
        message: String
    ) {
        guard let draft else {
            systemAudioMessage = message
            return
        }
        microphoneFallbackMessage = message
        microphoneFallbackDraft = draft
    }

    private func discardMicrophoneFallback() {
        if let microphoneFallbackDraft {
            try? FileManager.default.removeItem(at: microphoneFallbackDraft.audioURL)
        }
        microphoneFallbackDraft = nil
        microphoneFallbackMessage = nil
        transcriber.clearTranscript()
    }

    private func selectLanguage(_ language: TranscriptionLanguage) {
        guard transcriber.selectedTranscriptionBackend.requiresAppleSpeech else {
            transcriber.selectedLanguageID = language.id
            return
        }

        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    language,
                    preservingLanguageIDs: [language.id]
                )
                switch preparation {
                case .ready:
                    transcriber.selectedLanguageID = language.id
                case .needsRelease(let request):
                    localeReleaseAction = MacPendingSpeechLocaleReleaseAction(
                        request: request,
                        operation: .selectLanguage
                    )
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
            }
        }
    }

    private func releaseSpeechLocalesAndContinue(_ action: MacPendingSpeechLocaleReleaseAction) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(action.request)
                switch action.operation {
                case .selectLanguage:
                    transcriber.selectedLanguageID = action.request.targetLanguage.id
                case .startRecording:
                    await startPreparedRecording()
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Live translation and editing

    private var finalTranscriptLines: [TranscriptionLine] {
        transcriber.finalTranscriptStore.lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var availableTranslationLanguages: [TranscriptionLanguage] {
        translationLanguages.filter {
            !AppleTranslationLanguages.sameBaseLanguage($0.id, transcriber.selectedLanguageID)
        }
    }

    private func translationStatusText(for language: TranscriptionLanguage) -> String {
        if let translationErrorMessage {
            return translationErrorMessage
        }
        if finalTranscriptLines.isEmpty {
            return String(localized: L10n.Transcription.waitingForFinalSegments)
        }
        if isTranslating {
            return String(localized: L10n.Transcription.translatingFinalSegments)
        }
        return String(
            format: String(localized: L10n.Recordings.translatingToFormat),
            language.displayName
        )
    }

    private func requestTranslation(to language: TranscriptionLanguage) {
        selectedTranslationLanguage = language
        translationErrorMessage = nil
        scheduleTranslationIfNeeded()
    }

    private func clearTranslation() {
        selectedTranslationLanguage = nil
        translatedTextByLineID = [:]
        translatedLineSignatures = [:]
        translationErrorMessage = nil
        isTranslating = false
        translationConfiguration = nil
    }

    private func scheduleTranslationIfNeeded() {
        pruneTranslationState()
        guard let language = selectedTranslationLanguage else {
            return
        }
        guard !pendingTranslationLines(for: language).isEmpty else {
            isTranslating = false
            return
        }

        isTranslating = true
        translationErrorMessage = nil
        let nextConfiguration = TranslationSession.Configuration(
            source: AppleTranslationLanguages.localeLanguage(for: transcriber.selectedLanguageID),
            target: AppleTranslationLanguages.localeLanguage(for: language.id)
        )
        if var existingConfiguration = translationConfiguration,
           existingConfiguration == nextConfiguration {
            existingConfiguration.invalidate()
            translationConfiguration = existingConfiguration
        } else {
            translationConfiguration = nextConfiguration
        }
    }

    private func translateFinalTranscriptLines(using session: TranslationSession) async {
        guard let targetLanguage = selectedTranslationLanguage else {
            isTranslating = false
            return
        }
        let targetLanguageID = targetLanguage.id
        let lines = pendingTranslationLines(for: targetLanguage)
        guard !lines.isEmpty else {
            isTranslating = false
            return
        }

        let signatures = Dictionary(uniqueKeysWithValues: lines.map {
            ($0.id, translationSignature(for: $0, language: targetLanguage))
        })
        let requests = lines.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString)
        }

        do {
            try await session.prepareTranslation()
            for try await response in session.translate(batch: requests) {
                guard selectedTranslationLanguage?.id == targetLanguageID,
                      let identifier = response.clientIdentifier,
                      let lineID = UUID(uuidString: identifier),
                      let signature = signatures[lineID],
                      let currentLine = transcriber.finalTranscriptStore.lines.first(where: { $0.id == lineID }),
                      translationSignature(for: currentLine, language: targetLanguage) == signature else {
                    continue
                }

                let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !translatedText.isEmpty {
                    translatedTextByLineID[lineID] = translatedText
                }
                translatedLineSignatures[lineID] = signature
            }
            guard selectedTranslationLanguage?.id == targetLanguageID else {
                return
            }
            isTranslating = false
            translationErrorMessage = nil
        } catch {
            guard selectedTranslationLanguage?.id == targetLanguageID else {
                return
            }
            isTranslating = false
            translationErrorMessage = error.localizedDescription
        }
    }

    private func pendingTranslationLines(for language: TranscriptionLanguage) -> [TranscriptionLine] {
        finalTranscriptLines.filter {
            translatedLineSignatures[$0.id] != translationSignature(for: $0, language: language)
        }
    }

    private func pruneTranslationState() {
        let lineIDs = Set(finalTranscriptLines.map(\.id))
        translatedTextByLineID = translatedTextByLineID.filter { lineIDs.contains($0.key) }
        translatedLineSignatures = translatedLineSignatures.filter { lineIDs.contains($0.key) }
    }

    private func translationSignature(for line: TranscriptionLine, language: TranscriptionLanguage) -> String {
        "\(language.id)|\(line.id.uuidString)|\(line.text.hashValue)"
    }

    private func beginEditingTranscriptLine(_ line: TranscriptionLine) {
        guard line.isFinal else {
            return
        }
        lineEditRequest = MacLiveTranscriptLineEditRequest(line: line)
    }
}

private struct MacPendingSpeechLocaleReleaseAction {
    let request: SpeechLocaleReleaseRequest
    let operation: MacSpeechLocaleReleaseOperation
}

private enum MacSpeechLocaleReleaseOperation {
    case selectLanguage
    case startRecording
}

private struct MacLiveTranscriptLineEditRequest: Identifiable {
    let line: TranscriptionLine
    var id: TranscriptionLine.ID { line.id }
}

extension RecordingDraft: Identifiable {
    var id: URL { audioURL }
}

// MARK: - Elapsed time

private struct MacElapsedTimeText: View {
    @ObservedObject var clock: RecordingElapsedClock

    var body: some View {
        Text(verbatim: TranscriptionLine.formatTimestamp(clock.elapsedTime))
            .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            .frame(minWidth: 96, alignment: .leading)
    }
}

// MARK: - Waveform

private struct MacLiveWaveform: View {
    @ObservedObject var store: RecordingWaveformStore

    var body: some View {
        Canvas { context, size in
            let samples = store.samples
            guard !samples.isEmpty else {
                return
            }
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 2
            let step = barWidth + spacing
            let maxBars = Int(size.width / step)
            let visible = samples.suffix(maxBars)
            var x = size.width - CGFloat(visible.count) * step

            for sample in visible {
                let amplified = max(CGFloat(sample.level), 0.04)
                let height = max(size.height * amplified, 2)
                let rect = CGRect(
                    x: x,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(
                        sample.isCaptured
                            ? AppTheme.brand.opacity(0.85)
                            : Color.secondary.opacity(0.35)
                    )
                )
                x += step
            }
        }
    }
}

// MARK: - Live transcript list

private struct MacLiveTranscriptList: View {
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    @ObservedObject var interimStore: LiveInterimTranscriptStore
    let translatedTextByLineID: [TranscriptionLine.ID: String]
    let translatedLineSignatures: [TranscriptionLine.ID: String]
    let selectedTranslationLanguage: TranscriptionLanguage?
    let isTranslating: Bool
    let onEditFinalLine: (TranscriptionLine) -> Void

    private static let topAnchorID = "live-transcript-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Color.clear
                        .frame(height: 1)
                        .id(Self.topAnchorID)

                    if let interim = interimStore.line {
                        MacLiveTranscriptRow(
                            line: interim,
                            translatedText: nil,
                            isShowingTranslationPlaceholder: false,
                            isInterim: true,
                            onEdit: nil
                        )
                    }

                    ForEach(finalStore.lines.reversed()) { line in
                        MacLiveTranscriptRow(
                            line: line,
                            translatedText: translatedTextByLineID[line.id],
                            isShowingTranslationPlaceholder: isShowingTranslationPlaceholder(for: line),
                            isInterim: false,
                            onEdit: {
                                onEditFinalLine(line)
                            }
                        )
                    }

                    if finalStore.lines.isEmpty && interimStore.line == nil {
                        VStack(spacing: 10) {
                            Image(systemName: "quote.bubble")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(L10n.RecordingStatus.waitingForSpeech)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
                .padding(18)
            }
            .onChange(of: finalStore.revision) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.topAnchorID, anchor: .top)
                }
            }
        }
    }

    private func isShowingTranslationPlaceholder(for line: TranscriptionLine) -> Bool {
        guard isTranslating,
              let language = selectedTranslationLanguage else {
            return false
        }
        let signature = "\(language.id)|\(line.id.uuidString)|\(line.text.hashValue)"
        return translatedLineSignatures[line.id] != signature
    }
}

private struct MacLiveTranscriptRow: View {
    let line: TranscriptionLine
    let translatedText: String?
    let isShowingTranslationPlaceholder: Bool
    let isInterim: Bool
    let onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: line.timestampText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isInterim ? AppTheme.warning : AppTheme.brand)
                .frame(width: 66, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: translatedText ?? line.text)
                    .textSelection(.enabled)
                    .foregroundStyle(isInterim ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let translatedText, !translatedText.isEmpty {
                    Text(verbatim: line.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isShowingTranslationPlaceholder {
                    Text(L10n.Recordings.translating)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button {
                AppPasteboard.copy(line.text)
            } label: {
                Label {
                    Text(L10n.Common.copy)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label {
                        Text(L10n.Recordings.editTranscriptLine)
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
    }
}

private struct MacLiveTranscriptLineEditSheet: View {
    let request: MacLiveTranscriptLineEditRequest
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(
        request: MacLiveTranscriptLineEditRequest,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: request.line.text)
    }

    var body: some View {
        TranscriptLineEditSheet(
            timeText: request.line.timestampText,
            text: $text,
            selectedSpeakerID: .constant(nil),
            speakerOptions: [],
            newSpeakerOption: TranscriptSpeakerEditOption(
                id: "Speaker 0",
                displayName: String(localized: L10n.Recordings.transcriptNewSpeaker),
                tint: AppTheme.info
            ),
            showsSpeakerEditor: false,
            isSaving: false,
            onSave: {
                onSave(text)
            },
            onCancel: onCancel
        )
        .frame(minWidth: 460, minHeight: 320)
    }
}

// MARK: - Save sheet

private struct MacRecordingSaveSheet: View {
    let draft: RecordingDraft
    @ObservedObject var store: RecordingStore
    let onFinished: () -> Void
    let onDiscard: () -> Void

    @StateObject private var locationProvider = MacRecordingLocationProvider()
    @State private var name: String
    @State private var categoryName: String?
    @State private var newCategoryName = ""
    @State private var tagsText = ""
    @State private var keyPoints = ""
    @State private var suggestedIntelligence: RecordingIntelligence?
    @State private var isGeneratingTitle = false
    @State private var isSaving = false
    @State private var includesLocation = false
    @State private var errorMessage: String?

    init(
        draft: RecordingDraft,
        store: RecordingStore,
        onFinished: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.draft = draft
        _store = ObservedObject(wrappedValue: store)
        self.onFinished = onFinished
        self.onDiscard = onDiscard
        _name = State(initialValue: RecordingStore.defaultBaseName(for: draft.startedAt))
    }

    private var categories: [String] {
        RecordingCategoryCatalog.allNames(recordings: store.recordings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Transcription.saveRecording)
                .font(.title2.bold())
                .padding(.bottom, 14)

            Form {
                HStack {
                    TextField(text: $name) {
                        Text(L10n.Recordings.recordingName)
                    }

                    if store.intelligenceAvailability.isAvailable {
                        Button {
                            generateTitle()
                        } label: {
                            if isGeneratingTitle {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .help(String(localized: L10n.Recordings.generateTagsAndSummary))
                        .disabled(isGeneratingTitle)
                    }
                }

                Picker(selection: $categoryName) {
                    Text(L10n.Recordings.uncategorized)
                        .tag(String?.none)
                    ForEach(categories, id: \.self) { category in
                        Text(verbatim: category)
                            .tag(String?.some(category))
                    }
                } label: {
                    Text(L10n.Recordings.categoryName)
                }

                TextField(text: $newCategoryName) {
                    Text(L10n.Recordings.categoryNamePlaceholder)
                }

                TextField(text: $tagsText) {
                    Text(L10n.Recordings.tags)
                }

                TextField(text: $keyPoints) {
                    Text(L10n.Recordings.keyPoints)
                }

                LabeledContent {
                    Text(verbatim: TranscriptionLine.formatTimestamp(Double(draft.durationSeconds)))
                        .monospacedDigit()
                } label: {
                    Text(L10n.Recordings.audioDuration)
                }

                Toggle(isOn: $includesLocation) {
                    Text(L10n.Recordings.addLocation)
                }

                if includesLocation {
                    MacRecordingLocationPreview(provider: locationProvider)
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label {
                    Text(verbatim: errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.red)
                .padding(.top, 8)
            }

            HStack {
                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Text(L10n.Transcription.discard)
                }

                Spacer()

                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.Common.save)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
            .padding(.top, 14)
        }
        .padding(22)
        .frame(minWidth: 480)
        .onChange(of: includesLocation) { _, isEnabled in
            if isEnabled {
                locationProvider.requestLocation()
            } else {
                locationProvider.reset()
            }
        }
    }

    private func generateTitle() {
        isGeneratingTitle = true
        Task {
            defer { isGeneratingTitle = false }
            do {
                let suggestion = try await store.generateSuggestedTitle(for: draft)
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    name = suggestion.title
                }
                if tagsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tagsText = suggestion.tags.joined(separator: ", ")
                }
                if let summary = suggestion.summary {
                    suggestedIntelligence = RecordingIntelligence(
                        summary: summary,
                        tags: suggestion.tags,
                        generatedAt: Date()
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        isSaving = true
        let manualTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmedNewCategory = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = trimmedNewCategory.isEmpty ? categoryName : trimmedNewCategory
        let trimmedKeyPoints = keyPoints.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let item = await store.save(
                draft,
                preferredName: trimmedName.isEmpty ? nil : trimmedName,
                manualTags: manualTags,
                intelligence: suggestedIntelligence,
                categoryName: resolvedCategory,
                keyPoints: trimmedKeyPoints.isEmpty ? nil : trimmedKeyPoints,
                location: includesLocation ? locationProvider.recordingLocation : nil
            )
            isSaving = false
            if item != nil {
                onFinished()
            } else {
                errorMessage = String(localized: MacL10n.actionFailed)
            }
        }
    }
}

struct MacRecordingLocationPreview: View {
    @ObservedObject var provider: MacRecordingLocationProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let location = provider.latestLocation {
                let coordinate = location.coordinate
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                ) {
                    Marker(String(localized: L10n.Recordings.currentLocation), coordinate: coordinate)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))

                if let placeName = provider.placeName, !placeName.isEmpty {
                    Label(placeName, systemImage: "building.2")
                        .font(.caption.weight(.semibold))
                }

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(verbatim: "\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                        .monospacedDigit()
                    Spacer()
                    if location.horizontalAccuracy >= 0 {
                        Text(verbatim: "±\(Int(location.horizontalAccuracy.rounded()))m")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if provider.isDenied {
                Label {
                    Text(L10n.Recordings.locationDenied)
                } icon: {
                    Image(systemName: "location.slash")
                }
                .foregroundStyle(AppTheme.warning)
            } else if let errorText = provider.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppTheme.warning)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.Recordings.locating)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }
}

@MainActor
final class MacRecordingLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var placeName: String?
    @Published private(set) var errorText: String?

    private let manager = CLLocationManager()
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var city: String?
    private var country: String?

    init(recordingLocation: RecordingLocation? = nil) {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if let recordingLocation {
            latestLocation = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: recordingLocation.latitude,
                    longitude: recordingLocation.longitude
                ),
                altitude: 0,
                horizontalAccuracy: recordingLocation.horizontalAccuracy ?? -1,
                verticalAccuracy: -1,
                timestamp: recordingLocation.capturedAt
            )
            city = recordingLocation.city
            country = recordingLocation.country
            placeName = recordingLocation.placeName
        }
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var recordingLocation: RecordingLocation? {
        guard let latestLocation else {
            return nil
        }
        return RecordingLocation(
            latitude: latestLocation.coordinate.latitude,
            longitude: latestLocation.coordinate.longitude,
            horizontalAccuracy: latestLocation.horizontalAccuracy >= 0 ? latestLocation.horizontalAccuracy : nil,
            capturedAt: Date(),
            city: city,
            country: country
        )
    }

    func reset() {
        latestLocation = nil
        placeName = nil
        city = nil
        country = nil
        errorText = nil
        reverseGeocodingRequest?.cancel()
        reverseGeocodingRequest = nil
    }

    func requestLocation() {
        errorText = nil
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            errorText = String(localized: L10n.Recordings.locationDenied)
        @unknown default:
            errorText = String(localized: L10n.Recordings.locationUnavailable)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                return
            }
            latestLocation = location
            errorText = nil
            await resolvePlaceName(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            errorText = error.localizedDescription
        }
    }

    private func resolvePlaceName(for location: CLLocation) async {
        placeName = nil
        city = nil
        country = nil
        reverseGeocodingRequest?.cancel()
        do {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return
            }
            reverseGeocodingRequest = request
            let mapItems = try await request.mapItems
            let mapItem = mapItems.first
            guard reverseGeocodingRequest === request else {
                return
            }
            let address = mapItem?.addressRepresentations
            city = address?.cityName ?? address?.cityWithContext(.short) ?? mapItem?.name
            country = address?.regionName
            placeName = [city, country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } catch {
            if reverseGeocodingRequest?.isCancelled != true {
                placeName = nil
            }
        }
    }
}
