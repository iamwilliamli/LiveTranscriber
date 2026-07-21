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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var recoveredAudioDraft: RecordingDraft?
    @State private var recoveredAudioMessage: String?
    @State private var savedRecordingName: String?
    @State private var savedRecordingBannerIsVisible = false
    @State private var savedRecordingBannerTask: Task<Void, Never>?

    private var recordingInputMode: MacRecordingInputMode {
        MacRecordingInputMode(rawValue: recordingInputModeRaw)
            ?? (legacyIncludesSystemAudio ? .systemAudioOnly : .microphoneOnly)
    }

    var body: some View {
        GeometryReader { proxy in
            transcriptionCanvas(usesWideLayout: proxy.size.width >= 900)
        }
        .navigationTitle(Text(L10n.App.transcribeTab))
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.02),
            value: transcriber.isRecording
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.20, extraBounce: 0.02),
            value: transcriber.isPaused
        )
        .sheet(item: $pendingDraft) { draft in
            MacRecordingSaveSheet(
                draft: draft,
                store: recordingStore,
                onFinished: { savedName in
                    if let pendingSystemAudioStagingDirectory {
                        systemAudioCapture.discardStagingDirectory(
                            pendingSystemAudioStagingDirectory
                        )
                    }
                    pendingSystemAudioStagingDirectory = nil
                    transcriber.clearTranscript()
                    pendingDraft = nil
                    showSavedRecordingBanner(fileName: savedName)
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
                get: { recoveredAudioDraft != nil },
                set: {
                    if !$0, recoveredAudioDraft != nil {
                        discardRecoveredAudio()
                    }
                }
            )
        ) {
            Button(String(localized: MacL10n.saveRecoveredSystemAudio)) {
                pendingDraft = recoveredAudioDraft
                recoveredAudioDraft = nil
                recoveredAudioMessage = nil
            }
            Button(String(localized: L10n.Transcription.discard), role: .destructive) {
                discardRecoveredAudio()
            }
        } message: {
            Text(
                recoveredAudioMessage
                    ?? String(localized: MacL10n.systemAudioNoSamples)
            )
        }
    }

    // MARK: - Transcription workspace

    private func transcriptionCanvas(usesWideLayout: Bool) -> some View {
        ZStack(alignment: .top) {
            AmbientActivityBackground(state: transcriptionAmbientState)

            VStack(alignment: .leading, spacing: 16) {
                assistantGreetingHeader

                if usesWideLayout {
                    HStack(alignment: .top, spacing: 16) {
                        recorderCard(expandsVertically: true)
                            .frame(minWidth: 360, idealWidth: 410, maxWidth: 460)

                        transcriptCard
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        recorderCard(expandsVertically: false)
                        transcriptCard
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            savedRecordingBanner
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .zIndex(20)
        }
    }

    private var transcriptionAmbientState: AmbientActivityState {
        guard transcriber.isRecording else {
            return .standby
        }
        return transcriber.isPaused ? .paused : .active
    }

    private var assistantGreetingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("AssistantRobot")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .scaleEffect(transcriber.isRecording && !transcriber.isPaused ? 1.04 : 1)
                .offset(y: transcriber.isRecording && !transcriber.isPaused ? -2 : 0)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.08),
                    value: transcriber.isRecording && !transcriber.isPaused
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(assistantGreetingTitle)
                    .font(.redditSans(.title3, weight: .bold))
                    .foregroundStyle(.primary)

                Text(L10n.Transcription.liveTranscription)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(height: 50)
        .accessibilityElement(children: .combine)
    }

    private var assistantGreetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return String(localized: L10n.Greeting.morning)
        case 12..<18:
            return String(localized: L10n.Greeting.afternoon)
        default:
            return String(localized: L10n.Greeting.evening)
        }
    }

    private func recorderCard(expandsVertically: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            recorderDeck(expandsVertically: expandsVertically)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    MacRecordingStateBadge(
                        isRecording: transcriber.isRecording,
                        isPaused: transcriber.isPaused,
                        isPreparing: transcriber.isPreparing
                    )

                    languageMenu

                    Spacer(minLength: 0)
                }

                HStack(spacing: 9) {
                    recordingInputMenu

                    if recordingInputMode.usesSystemAudio {
                        systemAudioSourceButton
                    }

                    Spacer(minLength: 0)
                }
            }

            recorderNotices

            if expandsVertically {
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: expandsVertically ? .infinity : nil, alignment: .top)
        .macTranscriptionCardSurface()
    }

    private func recorderDeck(expandsVertically: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack(alignment: .center, spacing: 10) {
                    Image(
                        systemName: recordingInputMode.usesSystemAudio
                            ? "waveform.and.magnifyingglass"
                            : "waveform.and.mic"
                    )
                    .font(.redditSans(.caption, weight: .bold))
                    .foregroundStyle(
                        transcriber.isRecording && !transcriber.isPaused
                            ? AppTheme.danger
                            : recorderDeckSecondaryColor
                    )
                    .scaleEffect(transcriber.isRecording && !transcriber.isPaused ? 1.08 : 1)
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.20, extraBounce: 0),
                        value: transcriber.isRecording && !transcriber.isPaused
                    )
                    .frame(width: 34, height: 34, alignment: .leading)
                    .accessibilityLabel(Text(L10n.Transcription.liveTranscription))

                    Spacer(minLength: 8)

                    formatMenu
                }

                MacElapsedTimeText(
                    clock: transcriber.elapsedClock,
                    color: recorderDeckPrimaryColor
                )
                .allowsHitTesting(false)
            }
            .frame(height: 38)

            MacLiveRecordingWaveTimeline(
                store: transcriber.waveformStore,
                clock: transcriber.elapsedClock,
                primaryColor: recorderDeckPrimaryColor,
                secondaryColor: recorderDeckSecondaryColor,
                height: expandsVertically ? 214 : 142
            )
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
    }

    private var recorderDeckPrimaryColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var recorderDeckSecondaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .secondary
    }

    private var recorderDeckPillColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.06)
    }

    @ViewBuilder
    private var recorderNotices: some View {
        if transcriber.isPreparing {
            MacRecorderNotice(
                text: transcriber.statusText,
                systemImage: "ellipsis.circle",
                tint: AppTheme.warning,
                showsProgress: true
            )
        }

        if let errorText = transcriber.errorText {
            MacRecorderNotice(
                text: errorText,
                systemImage: "exclamationmark.triangle",
                tint: AppTheme.warning
            )
        }

        if let warningMessage = systemAudioCapture.warningMessage {
            MacRecorderNotice(
                text: warningMessage,
                systemImage: "exclamationmark.triangle",
                tint: AppTheme.warning
            )
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label {
                    Text(L10n.Recordings.transcript)
                } icon: {
                    Image(systemName: "text.alignleft")
                }
                .font(.redditSans(.headline, weight: .semibold))

                Spacer(minLength: 0)

                MacLiveTranscriptLineCount(
                    finalStore: transcriber.finalTranscriptStore,
                    interimStore: transcriber.interimTranscriptStore
                )

                translationMenu
            }

            translationStatus

            MacLiveTranscriptList(
                transcriber: transcriber,
                finalStore: transcriber.finalTranscriptStore,
                interimStore: transcriber.interimTranscriptStore,
                translatedTextByLineID: translatedTextByLineID,
                translatedLineSignatures: translatedLineSignatures,
                selectedTranslationLanguage: selectedTranslationLanguage,
                isTranslating: isTranslating,
                bottomContentInset: transcriptControlContentInset,
                onEditFinalLine: beginEditingTranscriptLine
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macTranscriptionCardSurface()
        .overlay(alignment: .bottom) {
            floatingRecorderDock
                .padding(.bottom, transcriptControlBottomInset)
        }
    }

    private var transcriptControlBottomInset: CGFloat { 20 }

    private var transcriptControlContentInset: CGFloat {
        transcriptControlBottomInset + 72
    }

    @ViewBuilder
    private var translationStatus: some View {
        if let selectedTranslationLanguage {
            HStack(spacing: 8) {
                if isTranslating {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(
                        systemName: translationErrorMessage == nil
                            ? "translate"
                            : "exclamationmark.triangle"
                    )
                    .font(.system(size: 12, weight: .semibold))
                }

                Text(verbatim: translationStatusText(for: selectedTranslationLanguage))
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(translationErrorMessage == nil ? .secondary : AppTheme.warning)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var savedRecordingBanner: some View {
        if let savedRecordingName {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.success)

                Text(verbatim: localizedFormat(L10n.Transcription.savedFormat, savedRecordingName))
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppTheme.success.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
            .offset(y: savedRecordingBannerIsVisible ? 0 : -74)
            .opacity(savedRecordingBannerIsVisible ? 1 : 0)
        }
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
            MacDropdownStatusPill(
                systemImage: "globe",
                title: transcriber.selectedLanguage.displayName,
                tint: AppTheme.info
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing)
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
            MacDropdownStatusPill(
                systemImage: recordingInputMode.usesSystemAudio
                    ? "speaker.wave.2.fill"
                    : "mic",
                title: String(localized: recordingInputMode.title),
                tint: recordingInputMode.usesSystemAudio ? AppTheme.purple : AppTheme.info
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing || systemAudioCapture.isCapturing)
    }

    private var systemAudioSourceButton: some View {
        Button {
            systemAudioCapture.presentSourcePicker()
        } label: {
            MacSourceStatusPill(
                title: systemAudioCapture.selectedSourceName
                    ?? String(localized: MacL10n.chooseSystemAudioSource),
                tint: systemAudioCapture.hasSelectedSource ? AppTheme.success : AppTheme.warning
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing || systemAudioCapture.isCapturing)
        .help(String(localized: MacL10n.systemAudioSourceSelectionHint))
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
            MacTranslationStatusPill(
                title: selectedTranslationLanguage?.shortName
                    ?? String(localized: L10n.Recordings.translate),
                isActive: selectedTranslationLanguage != nil
            )
        }
        .buttonStyle(.plain)
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
            MacCompactDropdownBadge(
                title: recordingInputMode.usesSystemAudio
                    ? "M4A"
                    : transcriber.selectedAudioFormat.badgeText,
                foreground: recorderDeckPrimaryColor,
                background: recorderDeckPillColor
            )
        }
        .buttonStyle(.plain)
        .disabled(
            transcriber.isRecording
                || transcriber.isPreparing
                || recordingInputMode.usesSystemAudio
        )
    }

    private var floatingRecorderDock: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            AppTheme.danger.opacity(
                                transcriber.isRecording
                                    ? 0
                                    : (colorScheme == .dark ? 0.80 : 0.86)
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .frame(width: transcriber.isRecording ? 120 : 64, height: 64)
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10),
                    radius: transcriber.isRecording ? 14 : 10,
                    y: transcriber.isRecording ? 9 : 7
                )
                .accessibilityHidden(true)

            if transcriber.isRecording {
                HStack(spacing: 8) {
                    MacFloatingIconControlButton(
                        title: String(
                            localized: transcriber.isPaused
                                ? L10n.Transcription.resume
                                : L10n.Transcription.pause
                        ),
                        systemImage: transcriber.isPaused ? "play.fill" : "pause.fill",
                        tint: .primary,
                        background: Color.secondary.opacity(0.14),
                        action: togglePause
                    )

                    MacFloatingIconControlButton(
                        title: String(localized: L10n.Transcription.stop),
                        systemImage: "stop.fill",
                        tint: .white,
                        background: AppTheme.danger,
                        action: stopRecording
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.90)))
            } else {
                Button {
                    startRecording()
                } label: {
                    Group {
                        if transcriber.isPreparing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(
                                systemName: recordingInputMode.usesSystemAudio
                                    ? "speaker.wave.2.fill"
                                    : "mic.fill"
                            )
                            .font(.system(size: 23, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
                }
                .buttonStyle(MacRecorderPressButtonStyle(pressedScale: 0.94))
                .disabled(transcriber.isPreparing || systemAudioCapture.phase == .starting)
                .keyboardShortcut("r", modifiers: [.command])
                .accessibilityLabel(Text(L10n.Transcription.startRecording))
                .transition(.opacity.combined(with: .scale(scale: 0.90)))
            }
        }
        .frame(width: transcriber.isRecording ? 120 : 64, height: 64)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.12),
            value: transcriber.isRecording
        )
    }

    private func togglePause() {
        Task {
            if transcriber.isPaused {
                systemAudioCapture.resumeCapture()
                await transcriber.resumeRecording()
            } else {
                systemAudioCapture.pauseCapture()
                await transcriber.pauseRecording()
            }
        }
    }

    private func showSavedRecordingBanner(fileName: String) {
        savedRecordingBannerTask?.cancel()
        savedRecordingName = fileName

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0.06)) {
            savedRecordingBannerIsVisible = true
        }

        savedRecordingBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }

            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0)) {
                savedRecordingBannerIsVisible = false
            }

            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else {
                return
            }

            savedRecordingName = nil
            savedRecordingBannerTask = nil
        }
    }

    private func hideSavedRecordingBanner() {
        savedRecordingBannerTask?.cancel()
        savedRecordingBannerTask = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18, extraBounce: 0)) {
            savedRecordingBannerIsVisible = false
        }
        savedRecordingName = nil
    }

    // MARK: - Recording control flow

    private func startRecording() {
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            return
        }

        hideSavedRecordingBanner()

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

            await transcriber.startRecording(
                inputSource: .externalAudio(sampleRate: 48_000, channelCount: 2)
            )
            guard transcriber.isRecording,
                  let systemAudioSampleHandler = transcriber.externalAudioSampleHandler() else {
                systemAudioMessage = transcriber.errorText
                    ?? String(localized: MacL10n.systemAudioNoSamples)
                return
            }

            guard await systemAudioCapture.startCapture(
                includesMicrophone: recordingInputMode.includesMicrophoneInSavedAudio,
                systemAudioSampleHandler: systemAudioSampleHandler
            ) else {
                if let abandonedDraft = await transcriber.stopRecording() {
                    try? FileManager.default.removeItem(at: abandonedDraft.audioURL)
                }
                systemAudioMessage = systemAudioCapture.errorMessage
                    ?? String(localized: MacL10n.systemAudioNoSamples)
                return
            }
        } else {
            await transcriber.startRecording()
        }

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
                    offerRecoveredAudioFallback(
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
                offerRecoveredAudioFallback(
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

    private func offerRecoveredAudioFallback(
        _ draft: RecordingDraft?,
        message: String
    ) {
        guard let draft else {
            systemAudioMessage = message
            return
        }
        recoveredAudioMessage = message
        recoveredAudioDraft = draft
    }

    private func discardRecoveredAudio() {
        if let recoveredAudioDraft {
            try? FileManager.default.removeItem(at: recoveredAudioDraft.audioURL)
        }
        recoveredAudioDraft = nil
        recoveredAudioMessage = nil
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
    let color: Color

    var body: some View {
        let text = TranscriptionLine.formatTimestamp(clock.elapsedTime)
        let components = text.split(separator: ":", omittingEmptySubsequences: false)

        HStack(spacing: 0) {
            ForEach(Array(components.indices), id: \.self) { index in
                Text(verbatim: String(components[index]))
                    .foregroundStyle(color)

                if index < components.index(before: components.endIndex) {
                    Text(verbatim: ":")
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
        .font(.redditSans(size: 28, weight: .semibold).monospacedDigit())
        .frame(minWidth: 104)
        .accessibilityLabel(Text(verbatim: text))
    }
}

// MARK: - Waveform timeline

private struct MacLiveRecordingWaveTimeline: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: RecordingWaveformStore
    @ObservedObject var clock: RecordingElapsedClock
    let primaryColor: Color
    let secondaryColor: Color
    let height: CGFloat

    private let visibleDuration: TimeInterval = 12
    private let majorTickInterval: TimeInterval = 2
    private let minorTickInterval: TimeInterval = 0.5
    private let rulerHeight: CGFloat = 36
    private let liveEdgeInset: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let elapsed = reduceMotion
                ? TimeInterval(clock.elapsedSeconds)
                : clock.elapsedTime
            let leftEdgeFraction = min(32 / max(size.width, 1), 0.2)
            let rightEdgeFraction = min(8 / max(size.width, 1), 0.06)

            timelineCanvas(size: size, elapsed: elapsed)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: leftEdgeFraction),
                            .init(color: .black, location: 1 - rightEdgeFraction),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipped()
        }
        .frame(height: height)
    }

    private func timelineCanvas(size: CGSize, elapsed: TimeInterval) -> some View {
        let waveformHeight = max(size.height - rulerHeight - 8, 40)
        let samples = store.samples
        let pitch = size.width / CGFloat(max(samples.count, 1))
        let barWidth = max(1.5, min(2.5, pitch * 0.48))
        let playheadX = max(size.width - liveEdgeInset, 0)
        let rulerOriginY = size.height - rulerHeight
        let rulerBaselineY = rulerOriginY + 16
        let baselineOpacity = hasAudibleSignal ? 0.08 : 0.16

        return Canvas { context, canvasSize in
            var waveformBaseline = Path()
            waveformBaseline.move(to: CGPoint(x: 0, y: waveformHeight / 2))
            waveformBaseline.addLine(to: CGPoint(x: canvasSize.width, y: waveformHeight / 2))
            context.stroke(
                waveformBaseline,
                with: .color(secondaryColor.opacity(baselineOpacity)),
                lineWidth: 1
            )

            for sample in samples where sample.isCaptured {
                let displayLevel = amplifiedLevel(for: sample.level)
                let age = max(elapsed - sample.elapsedTime, 0)
                let x = playheadX - CGFloat(age / visibleDuration) * canvasSize.width
                guard x >= -barWidth, x <= canvasSize.width + barWidth else {
                    continue
                }

                let resolvedBarHeight = barHeight(for: displayLevel, maxHeight: waveformHeight)
                let barRect = CGRect(
                    x: x - barWidth / 2,
                    y: (waveformHeight - resolvedBarHeight) / 2,
                    width: barWidth,
                    height: resolvedBarHeight
                )
                context.fill(
                    Path(roundedRect: barRect, cornerRadius: barWidth / 2),
                    with: .color(primaryColor.opacity(0.88))
                )
            }

            drawTimelineTicks(
                context: &context,
                width: canvasSize.width,
                elapsed: elapsed,
                rulerBaselineY: rulerBaselineY,
                rulerLabelY: rulerOriginY + 6
            )
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func drawTimelineTicks(
        context: inout GraphicsContext,
        width: CGFloat,
        elapsed: TimeInterval,
        rulerBaselineY: CGFloat,
        rulerLabelY: CGFloat
    ) {
        let currentTime = max(elapsed, 0)
        let playheadX = max(width - liveEdgeInset, 0)
        let playheadFraction = playheadX / max(width, 1)
        let startTime = currentTime - visibleDuration * TimeInterval(playheadFraction)
        let firstTickIndex = Int(floor(startTime / minorTickInterval))
        let tickCount = Int(ceil(visibleDuration / minorTickInterval)) + 2
        let finalTickIndex = firstTickIndex + tickCount
        let majorTickStride = max(Int((majorTickInterval / minorTickInterval).rounded()), 1)
        let labelWidth: CGFloat = 42

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: rulerBaselineY))
        baseline.addLine(to: CGPoint(x: width, y: rulerBaselineY))
        context.stroke(
            baseline,
            with: .color(secondaryColor.opacity(0.16)),
            lineWidth: 1
        )

        for tickIndex in firstTickIndex...finalTickIndex {
            let tickTime = TimeInterval(tickIndex) * minorTickInterval
            let x = width * CGFloat((tickTime - startTime) / visibleDuration)
            let isMajor = tickIndex.isMultiple(of: majorTickStride)

            if x >= -1, x <= width + 1 {
                let tickHeight: CGFloat = isMajor ? 20 : 12
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: rulerBaselineY))
                tick.addLine(to: CGPoint(x: x, y: rulerBaselineY + tickHeight))
                context.stroke(
                    tick,
                    with: .color(secondaryColor.opacity(isMajor ? 0.42 : 0.24)),
                    lineWidth: 1
                )
            }

            if isMajor,
               tickTime >= 0,
               x >= -labelWidth / 2,
               x <= width + labelWidth / 2 {
                let label = Text(verbatim: tickLabel(for: tickTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryColor.opacity(0.56))
                    .monospacedDigit()
                context.draw(
                    label,
                    at: CGPoint(x: x, y: rulerLabelY),
                    anchor: .center
                )
            }
        }
    }

    private var hasAudibleSignal: Bool {
        store.samples.contains { $0.isCaptured && amplifiedLevel(for: $0.level) > 0 }
    }

    private func amplifiedLevel(for level: Float) -> CGFloat {
        let noiseFloor: CGFloat = 0.04
        let clampedLevel = min(max(CGFloat(level), 0), 1)
        guard clampedLevel > noiseFloor else {
            return 0
        }

        let normalizedLevel = (clampedLevel - noiseFloor) / (1 - noiseFloor)
        return min(1, CGFloat(pow(Double(normalizedLevel), 1.18)) * 1.05)
    }

    private func barHeight(for displayLevel: CGFloat, maxHeight: CGFloat) -> CGFloat {
        max(5, min(maxHeight, 5 + displayLevel * (maxHeight - 5)))
    }

    private func tickLabel(for seconds: TimeInterval) -> String {
        TranscriptionLine.formatTimestamp(seconds)
    }
}

// MARK: - Recorder and transcript controls

private struct MacRecordingStateBadge: View {
    let isRecording: Bool
    let isPaused: Bool
    let isPreparing: Bool

    private var titleResource: LocalizedStringResource {
        if isPreparing {
            return L10n.RecordingStatus.requestingPermission
        }
        if isRecording {
            return isPaused ? L10n.RecordingStatus.paused : L10n.RecordingStatus.recording
        }
        return L10n.RecordingStatus.ready
    }

    private var tint: Color {
        if isRecording && !isPaused {
            return AppTheme.danger
        }
        if isPreparing {
            return AppTheme.warning
        }
        return AppTheme.success
    }

    private var systemImage: String {
        if isPreparing {
            return "ellipsis.circle"
        }
        return isRecording && !isPaused ? "record.circle" : "checkmark.circle"
    }

    var body: some View {
        Label {
            Text(titleResource)
        } icon: {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.redditSans(.caption, weight: .semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.20, extraBounce: 0), value: systemImage)
    }
}

private struct MacDropdownStatusPill: View {
    @Environment(\.isEnabled) private var isEnabled
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))

            Text(verbatim: title)
                .font(.redditSans(.caption, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(isEnabled ? tint : .secondary)
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(height: 30)
        .background(
            isEnabled ? tint.opacity(0.13) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    isEnabled ? tint.opacity(0.34) : Color.secondary.opacity(0.16),
                    lineWidth: 1
                )
        }
        .contentShape(Capsule())
    }
}

private struct MacSourceStatusPill: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 11, weight: .semibold))

            Text(verbatim: title)
                .font(.redditSans(.caption, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(isEnabled ? tint : .secondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            isEnabled ? tint.opacity(0.11) : Color.secondary.opacity(0.08),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(
                    isEnabled ? tint.opacity(0.26) : Color.secondary.opacity(0.16),
                    lineWidth: 1
                )
        }
        .contentShape(Capsule())
    }
}

private struct MacTranslationStatusPill: View {
    let title: String
    let isActive: Bool

    private var tint: Color {
        isActive ? AppTheme.brand : AppTheme.info
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "translate")
                .font(.system(size: 11, weight: .semibold))

            Text(verbatim: title)
                .font(.redditSans(.caption, weight: .bold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(tint.opacity(0.11), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct MacCompactDropdownBadge: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let foreground: Color
    let background: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: title)
                .font(.redditSans(.caption2, weight: .bold))

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(isEnabled ? foreground : .secondary)
        .padding(.leading, 8)
        .padding(.trailing, 7)
        .frame(height: 24)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke((isEnabled ? foreground : Color.secondary).opacity(0.16), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct MacRecorderNotice: View {
    let text: String
    let systemImage: String
    let tint: Color
    var showsProgress = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 1)
            }

            Text(verbatim: text)
                .font(.redditSans(.caption))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MacFloatingIconControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(MacRecorderPressButtonStyle(pressedScale: 0.94))
        .accessibilityLabel(Text(verbatim: title))
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: systemImage)
    }
}

private struct MacRecorderPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let pressedScale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.58)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.12, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct MacLiveTranscriptLineCount: View {
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    @ObservedObject var interimStore: LiveInterimTranscriptStore

    private var count: Int {
        finalStore.lines.count + (interimStore.line == nil ? 0 : 1)
    }

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Color.secondary.opacity(0.09), in: Capsule())
            .accessibilityLabel(Text(verbatim: "\(count)"))
    }
}

// MARK: - Live transcript list

private struct MacLiveTranscriptList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    @ObservedObject var interimStore: LiveInterimTranscriptStore
    let translatedTextByLineID: [TranscriptionLine.ID: String]
    let translatedLineSignatures: [TranscriptionLine.ID: String]
    let selectedTranslationLanguage: TranscriptionLanguage?
    let isTranslating: Bool
    let bottomContentInset: CGFloat
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
                        EmptyStateView(
                            icon: "quote.bubble",
                            titleResource: L10n.Recordings.noText
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .padding(.bottom, bottomContentInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onChange(of: finalStore.revision) {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.20, extraBounce: 0)) {
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
                .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                .foregroundStyle(isInterim ? AppTheme.warning : AppTheme.brand)
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(
                    (isInterim ? AppTheme.warning : AppTheme.brand).opacity(0.12),
                    in: Capsule()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: translatedText ?? line.text)
                    .font(.redditSans(.subheadline))
                    .textSelection(.enabled)
                    .foregroundStyle(isInterim ? .secondary : .primary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let translatedText, !translatedText.isEmpty {
                    Text(verbatim: line.text)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                } else if isShowingTranslationPlaceholder {
                    Text(L10n.Recordings.translating)
                        .font(.redditSans(.caption, weight: .semibold))
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
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let translatedText {
            return "\(line.timestampText) \(translatedText) \(line.text)"
        }
        return "\(line.timestampText) \(line.text)"
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
    let onFinished: (String) -> Void
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
        onFinished: @escaping (String) -> Void,
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
            if let item {
                onFinished(item.displayFileName)
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

private extension View {
    func macTranscriptionCardSurface() -> some View {
        background(AppTheme.cardBackground)
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
