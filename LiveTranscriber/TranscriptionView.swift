import Combine
import CoreLocation
import MapKit
import SwiftUI
import TranscriberDomain
import Translation
import UIKit

struct TranscriptionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @Binding var externalPendingRecordingDraft: RecordingDraft?
    @State private var savedRecordingName: String?
    @State private var savedRecordingBannerIsVisible = false
    @State private var savedRecordingBannerTask: Task<Void, Never>?
    @StateObject private var locationProvider = RecordingLocationProvider()
    @State private var pendingRecordingSave: PendingRecordingSave?
    @State private var pendingRecordingName = ""
    @State private var pendingRecordingCategory = ""
    @State private var pendingRecordingKeyPoints = ""
    @State private var pendingRecordingTags: [String] = []
    @State private var pendingRecordingIntelligence: RecordingIntelligence?
    @State private var pendingRecordingIncludesLocation = false
    @State private var isSavingPendingRecording = false
    @State private var liveTranslationConfiguration: TranslationSession.Configuration?
    @State private var selectedLiveTranslationLanguage: TranscriptionLanguage?
    @State private var translatedLiveTranscriptByLineID: [TranscriptionLine.ID: String] = [:]
    @State private var liveTranslatedLineSignatures: [TranscriptionLine.ID: String] = [:]
    @State private var appleTranslationLanguages: [TranscriptionLanguage] = []
    @State private var isTranslatingLiveTranscript = false
    @State private var liveTranslationErrorMessage: String?
    @State private var isShowingLiveTranslationLanguagePicker = false
    @State private var pendingSpeechLocaleReleaseAction: PendingTranscriptionSpeechLocaleReleaseAction?
    @State private var speechLocaleErrorMessage: String?
    @State private var liveTranscriptLineEditRequest: LiveTranscriptLineEditRequest?
    @State private var editedLiveTranscriptLineText = ""
    @State private var isSavingLiveTranscriptLineEdit = false

    private var isCompletingRecording: Bool {
        pendingRecordingSave != nil || isSavingPendingRecording
    }

    private var finalTranscriptLines: [TranscriptionLine] {
        transcriber.finalTranscriptStore.lines.filter { line in
            !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        GeometryReader { proxy in
            transcriptionCanvas(usesLandscapeLayout: proxy.size.width > proxy.size.height)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: transcriber.isRecording)
        .animation(.snappy(duration: 0.2, extraBounce: 0.02), value: transcriber.isPaused)
        .task {
            await transcriber.refreshSupportedLanguages()
        }
        .task {
            appleTranslationLanguages = await AppleTranslationLanguages.supportedLanguages()
        }
        .translationTask(liveTranslationConfiguration) { session in
            await translateFinalTranscriptLines(using: session)
        }
        .onAppear {
            consumeExternalPendingRecordingDraftIfNeeded()
        }
        .onReceive(transcriber.finalTranscriptStore.$revision.dropFirst()) { _ in
            scheduleFinalTranscriptTranslationIfNeeded()
        }
        .onChange(of: transcriber.selectedLanguageID) { _, _ in
            clearLiveTranscriptTranslation(playsHaptic: false)
        }
        .onChange(of: externalPendingRecordingDraft?.audioURL) { _, _ in
            consumeExternalPendingRecordingDraftIfNeeded()
        }
        .sheet(isPresented: $isShowingLiveTranslationLanguagePicker) {
            LiveTranslationLanguagePicker(
                selectedLanguageID: selectedLiveTranslationLanguage?.id,
                languages: liveTranscriptTranslationLanguages,
                onSelectOriginal: {
                    clearLiveTranscriptTranslation()
                    isShowingLiveTranslationLanguagePicker = false
                },
                onSelectLanguage: { language in
                    requestLiveTranscriptTranslation(to: language)
                    isShowingLiveTranslationLanguagePicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $liveTranscriptLineEditRequest) { request in
            TranscriptLineEditSheet(
                timeText: request.timeText,
                text: $editedLiveTranscriptLineText,
                selectedSpeakerID: .constant(nil),
                speakerOptions: [],
                newSpeakerOption: TranscriptSpeakerEditOption(
                    id: "Speaker 0",
                    displayName: String(localized: L10n.Recordings.transcriptNewSpeaker),
                    tint: AppTheme.info
                ),
                showsSpeakerEditor: false,
                isSaving: isSavingLiveTranscriptLineEdit,
                onSave: saveLiveTranscriptLineEdit,
                onCancel: {
                    liveTranscriptLineEditRequest = nil
                }
            )
            .interactiveDismissDisabled(isSavingLiveTranscriptLineEdit)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            localized(L10n.SpeechText.releaseOldLanguagesTitle),
            isPresented: Binding(
                get: { pendingSpeechLocaleReleaseAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingSpeechLocaleReleaseAction = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.SpeechText.releaseOldLanguagesAction), role: .destructive) {
                if let pendingSpeechLocaleReleaseAction {
                    releaseSpeechLocalesAndContinue(pendingSpeechLocaleReleaseAction)
                }
                pendingSpeechLocaleReleaseAction = nil
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(pendingSpeechLocaleReleaseAction?.request.messageText ?? "")
        }
        .alert(
            localized(L10n.SpeechText.localeSetupFailed),
            isPresented: Binding(
                get: { speechLocaleErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        speechLocaleErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(speechLocaleErrorMessage ?? "")
        }
        .sheet(item: $pendingRecordingSave) { pendingSave in
            RecordingSaveSheet(
                draft: pendingSave.draft,
                recordingName: $pendingRecordingName,
                categoryName: $pendingRecordingCategory,
                keyPoints: $pendingRecordingKeyPoints,
                tags: $pendingRecordingTags,
                generatedIntelligence: $pendingRecordingIntelligence,
                includesLocation: $pendingRecordingIncludesLocation,
                locationProvider: locationProvider,
                isSaving: isSavingPendingRecording,
                availableCategories: RecordingCategoryCatalog.allNames(recordings: recordingStore.recordings),
                showsTitleGeneration: recordingStore.intelligenceAvailability.isAvailable,
                onGenerateTitle: {
                    try await recordingStore.generateSuggestedTitle(for: pendingSave.draft)
                },
                onSave: savePendingRecording,
                onDiscard: discardPendingRecording
            )
            .interactiveDismissDisabled(true)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onChange(of: pendingRecordingIncludesLocation) { _, includesLocation in
                if includesLocation {
                    locationProvider.requestLocation()
                } else {
                    locationProvider.reset()
                }
            }
        }
    }

    private func transcriptionCanvas(usesLandscapeLayout: Bool) -> some View {
        ZStack(alignment: .bottom) {
            transcriptionBackground

            if usesLandscapeLayout {
                landscapeWorkspace
            } else {
                portraitWorkspace
            }

            savedRecordingBanner
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .zIndex(20)
        }
    }

    private var transcriptionBackground: some View {
        AmbientActivityBackground(state: transcriptionAmbientState)
    }

    private var transcriptionAmbientState: AmbientActivityState {
        guard transcriber.isRecording else {
            return .standby
        }
        return transcriber.isPaused ? .paused : .active
    }

    private var portraitWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            assistantGreetingHeader

            recorderCard(expandsVertically: false)

            transcriptCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var landscapeWorkspace: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactAssistantGreetingHeader

            HStack(alignment: .top, spacing: 16) {
                recorderCard(expandsVertically: true)
                    .frame(maxWidth: .infinity, alignment: .top)

                transcriptCard
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var savedRecordingBanner: some View {
        if let savedRecordingName {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.success)

                Text(localizedFormat(L10n.Transcription.savedFormat, savedRecordingName))
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .frame(maxWidth: 340)
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

    private var assistantGreetingHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image("AssistantRobot")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .scaleEffect(transcriber.isRecording && !transcriber.isPaused ? 1.04 : 1)
                .offset(y: transcriber.isRecording && !transcriber.isPaused ? -2 : 0)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.08),
                    value: transcriber.isRecording && !transcriber.isPaused
                )
                .accessibilityHidden(true)

            Text(assistantGreetingTitle)
                .font(.redditSans(.title3, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(height: 52, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var compactAssistantGreetingHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Image("AssistantRobot")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .scaleEffect(transcriber.isRecording && !transcriber.isPaused ? 1.04 : 1)
                .animation(
                    reduceMotion ? nil : .snappy(duration: 0.32, extraBounce: 0.08),
                    value: transcriber.isRecording && !transcriber.isPaused
                )
                .accessibilityHidden(true)

            Text(assistantGreetingTitle)
                .font(.redditSans(.headline, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var assistantGreetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return localized(L10n.Greeting.morning)
        case 12..<18:
            return localized(L10n.Greeting.afternoon)
        default:
            return localized(L10n.Greeting.evening)
        }
    }

    private func recorderCard(expandsVertically: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            recorderDeck

            HStack(spacing: 10) {
                RecordingStateBadge(
                    isRecording: transcriber.isRecording,
                    isPaused: transcriber.isPaused,
                    isPreparing: transcriber.isPreparing
                )

                languageMenu

                Spacer(minLength: 0)
            }

            if let errorText = transcriber.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: expandsVertically ? .infinity : nil, alignment: .top)
        .cardSurface()
    }

    private var recorderDeck: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "waveform.and.mic")
                        .font(.redditSans(.caption, weight: .bold))
                        .foregroundStyle(
                            transcriber.isRecording && !transcriber.isPaused
                                ? AppTheme.danger
                                : recorderDeckSecondaryColor
                        )
                        .scaleEffect(transcriber.isRecording && !transcriber.isPaused ? 1.08 : 1)
                        .animation(
                            reduceMotion ? nil : .snappy(duration: 0.2, extraBounce: 0),
                            value: transcriber.isRecording && !transcriber.isPaused
                        )
                        .frame(width: 34, height: 34, alignment: .leading)
                        .accessibilityLabel(Text(L10n.Transcription.liveTranscription))

                    Spacer(minLength: 8)

                    audioFormatMenu
                }

                RollingRecorderElapsedTimeText(
                    clock: transcriber.elapsedClock,
                    color: recorderDeckPrimaryColor
                )
                .allowsHitTesting(false)
            }
            .frame(height: 38)

            LiveRecordingWaveTimeline(
                store: transcriber.waveformStore,
                clock: transcriber.elapsedClock,
                primaryColor: recorderDeckPrimaryColor,
                secondaryColor: recorderDeckSecondaryColor,
                height: verticalSizeClass == .compact ? 120 : 150
            )
            .padding(.top, 8)
            .padding(.bottom, 8)
            .allowsHitTesting(false)

            Spacer(minLength: 0)
        }
        .frame(height: verticalSizeClass == .compact ? 176 : 206)
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

    private var audioFormatMenu: some View {
        Menu {
            ForEach(RecordingAudioFormat.allCases) { format in
                Button {
                    HapticFeedback.play(.menuSelection)
                    transcriber.selectedAudioFormat = format
                } label: {
                    Label(
                        format.title,
                        systemImage: format == transcriber.selectedAudioFormat ? "checkmark" : audioFormatIcon(for: format)
                    )
                }
            }
        } label: {
            CompactDropdownBadge(
                title: transcriber.selectedAudioFormat.badgeText,
                foreground: recorderDeckPrimaryColor,
                background: recorderDeckPillColor
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing)
    }

    private func audioFormatIcon(for format: RecordingAudioFormat) -> String {
        switch format {
        case .wav:
            return "waveform"
        case .m4a:
            return "waveform.badge.plus"
        }
    }

    private var languageMenu: some View {
        Menu {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        requestLanguageSelection(language)
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == transcriber.selectedLanguageID ? "checkmark" : "globe"
                    )
                }
            }
        } label: {
            DropdownStatusPill(
                systemImage: "globe",
                title: transcriber.selectedLanguage.displayName,
                tint: AppTheme.info
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing)
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
                    pendingSpeechLocaleReleaseAction = PendingTranscriptionSpeechLocaleReleaseAction(
                        request: request,
                        operation: .selectLanguage
                    )
                    HapticFeedback.play(.warning)
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func releaseSpeechLocalesAndContinue(_ pendingAction: PendingTranscriptionSpeechLocaleReleaseAction) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(pendingAction.request)
                switch pendingAction.operation {
                case .selectLanguage:
                    transcriber.selectedLanguageID = pendingAction.request.targetLanguage.id
                    HapticFeedback.play(.menuSelection)
                case .startRecording:
                    HapticFeedback.play(.recordingStart)
                    await transcriber.startRecording()
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
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
                    color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08),
                    radius: 2,
                    y: 2
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    radius: transcriber.isRecording ? 14 : 10,
                    y: transcriber.isRecording ? 9 : 7
                )
                .accessibilityHidden(true)

            if transcriber.isRecording {
                HStack(spacing: 8) {
                    FloatingIconControlButton(
                        titleResource: transcriber.isPaused
                            ? L10n.Transcription.resume
                            : L10n.Transcription.pause,
                        systemImage: transcriber.isPaused ? "play.fill" : "pause.fill",
                        tint: .primary,
                        background: Color.secondary.opacity(0.14)
                    ) {
                        togglePause()
                    }

                    FloatingIconControlButton(
                        titleResource: L10n.Transcription.stop,
                        systemImage: "stop.fill",
                        tint: .white,
                        background: AppTheme.danger
                    ) {
                        stopRecording()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.90)))
            } else {
                Button {
                    startRecording()
                } label: {
                    Group {
                        if transcriber.isPreparing {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.regular)
                        } else if isCompletingRecording {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: 23, weight: .semibold))
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 24, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
                }
                .buttonStyle(RecorderPressButtonStyle(pressedScale: 0.94))
                .disabled(transcriber.isPreparing || isCompletingRecording)
                .accessibilityLabel(
                    Text(isCompletingRecording ? L10n.Transcription.saveRecording : L10n.Transcription.startRecording)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.90)))
            }
        }
        .frame(width: transcriber.isRecording ? 120 : 64, height: 64)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.34, bounce: 0.12),
            value: transcriber.isRecording
        )
    }

    private func startRecording() {
        guard !isCompletingRecording else {
            return
        }
        hideSavedRecordingBanner()
        guard transcriber.selectedTranscriptionBackend.requiresAppleSpeech else {
            HapticFeedback.play(.recordingStart)
            Task {
                await transcriber.startRecording()
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
                    HapticFeedback.play(.recordingStart)
                    await transcriber.startRecording()
                case .needsRelease(let request):
                    pendingSpeechLocaleReleaseAction = PendingTranscriptionSpeechLocaleReleaseAction(
                        request: request,
                        operation: .startRecording
                    )
                    HapticFeedback.play(.warning)
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func togglePause() {
        HapticFeedback.play(transcriber.isPaused ? .recordingResume : .recordingPause)
        Task {
            if transcriber.isPaused {
                await transcriber.resumeRecording()
            } else {
                await transcriber.pauseRecording()
            }
        }
    }

    private func stopRecording() {
        HapticFeedback.play(.recordingStop)
        Task {
            if let draft = await transcriber.stopRecording() {
                presentSaveSheet(for: draft)
            } else {
                HapticFeedback.play(.warning)
            }
        }
    }

    private func presentSaveSheet(for draft: RecordingDraft) {
        pendingRecordingName = RecordingStore.defaultBaseName(for: draft.startedAt)
        pendingRecordingCategory = ""
        pendingRecordingKeyPoints = ""
        pendingRecordingTags = []
        pendingRecordingIntelligence = nil
        pendingRecordingIncludesLocation = false
        locationProvider.reset()
        pendingRecordingSave = PendingRecordingSave(draft: draft)
    }

    private func consumeExternalPendingRecordingDraftIfNeeded() {
        guard let draft = externalPendingRecordingDraft else {
            return
        }

        presentSaveSheet(for: draft)
        externalPendingRecordingDraft = nil
    }

    private func savePendingRecording() {
        guard let pendingRecordingSave,
              !isSavingPendingRecording else {
            return
        }

        isSavingPendingRecording = true
        Task {
            let location = pendingRecordingIncludesLocation ? locationProvider.recordingLocation : nil
            let intelligence = pendingRecordingIntelligence.map { pendingIntelligence in
                RecordingIntelligence(
                    summary: pendingIntelligence.summary,
                    tags: pendingRecordingTags,
                    generatedAt: pendingIntelligence.generatedAt
                )
            }
            if let saved = await recordingStore.save(
                pendingRecordingSave.draft,
                preferredName: pendingRecordingName,
                manualTags: pendingRecordingTags,
                intelligence: intelligence,
                projectName: nil,
                categoryName: pendingRecordingCategory,
                keyPoints: pendingRecordingKeyPoints,
                location: location
            ) {
                RecordingCategoryCatalog.register(pendingRecordingCategory)
                showSavedRecordingBanner(fileName: saved.displayFileName)
                transcriber.clearTranscript()
                self.pendingRecordingSave = nil
                pendingRecordingIntelligence = nil
                HapticFeedback.play(.recordingSaved)
            } else {
                HapticFeedback.play(.failure)
            }
            isSavingPendingRecording = false
        }
    }

    private func discardPendingRecording() {
        guard !isSavingPendingRecording else {
            return
        }
        if let audioURL = pendingRecordingSave?.draft.audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        pendingRecordingSave = nil
        pendingRecordingName = ""
        pendingRecordingCategory = ""
        pendingRecordingKeyPoints = ""
        pendingRecordingTags = []
        pendingRecordingIntelligence = nil
        pendingRecordingIncludesLocation = false
        locationProvider.reset()
        transcriber.clearTranscript()
        HapticFeedback.play(.deleteConfirmed)
    }

    private func beginLiveTranscriptLineEdit(_ line: TranscriptionLine) {
        guard line.isFinal else {
            return
        }
        HapticFeedback.play(.menuSelection)
        editedLiveTranscriptLineText = line.text
        liveTranscriptLineEditRequest = LiveTranscriptLineEditRequest(line: line)
    }

    private func saveLiveTranscriptLineEdit() {
        guard let liveTranscriptLineEditRequest,
              !isSavingLiveTranscriptLineEdit else {
            return
        }

        isSavingLiveTranscriptLineEdit = true
        transcriber.updateFinalTranscriptLine(
            id: liveTranscriptLineEditRequest.lineID,
            text: editedLiveTranscriptLineText
        )
        translatedLiveTranscriptByLineID[liveTranscriptLineEditRequest.lineID] = nil
        liveTranslatedLineSignatures[liveTranscriptLineEditRequest.lineID] = nil
        self.liveTranscriptLineEditRequest = nil
        HapticFeedback.play(.recordingSaved)
        isSavingLiveTranscriptLineEdit = false
    }

    private func showSavedRecordingBanner(fileName: String) {
        savedRecordingBannerTask?.cancel()
        savedRecordingName = fileName

        withAnimation(.snappy(duration: 0.28, extraBounce: 0.06)) {
            savedRecordingBannerIsVisible = true
        }

        savedRecordingBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
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
        withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
            savedRecordingBannerIsVisible = false
        }
        savedRecordingName = nil
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(L10n.Recordings.transcript)
                } icon: {
                    Image(systemName: "text.alignleft")
                }
                    .font(.redditSans(.headline))
                Spacer()
                LiveTranscriptLineCount(
                    finalStore: transcriber.finalTranscriptStore,
                    interimStore: transcriber.interimTranscriptStore
                )
                liveTranscriptTranslationMenu
            }

            liveTranscriptTranslationStatus

            LiveTranscriptRows(
                finalStore: transcriber.finalTranscriptStore,
                interimStore: transcriber.interimTranscriptStore,
                translatedTextByLineID: translatedLiveTranscriptByLineID,
                translatedLineSignatures: liveTranslatedLineSignatures,
                isTranslating: isTranslatingLiveTranscript,
                selectedTranslationLanguage: selectedLiveTranslationLanguage,
                bottomContentInset: transcriptControlContentInset,
                onEditFinalLine: beginLiveTranscriptLineEdit
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        .cardSurface()
        .overlay(alignment: .bottom) {
            floatingRecorderDock
                .padding(.bottom, transcriptControlBottomInset)
        }
    }

    private var transcriptControlBottomInset: CGFloat {
        verticalSizeClass == .compact ? 16 : 24
    }

    private var transcriptControlContentInset: CGFloat {
        transcriptControlBottomInset + 64
    }

    private var liveTranscriptTranslationMenu: some View {
        Button {
            HapticFeedback.play(.navigation)
            isShowingLiveTranslationLanguagePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectedLiveTranslationLanguage?.shortName ?? localized(L10n.Recordings.translate))
                    .font(.redditSans(.caption, weight: .bold))
            }
            .foregroundStyle(selectedLiveTranslationLanguage == nil ? AppTheme.info : AppTheme.brand)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background((selectedLiveTranslationLanguage == nil ? AppTheme.info : AppTheme.brand).opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var liveTranscriptTranslationStatus: some View {
        if let selectedLiveTranslationLanguage {
            HStack(spacing: 8) {
                if isTranslatingLiveTranscript {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: liveTranslationErrorMessage == nil ? "translate" : "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(liveTranslationStatusText(for: selectedLiveTranslationLanguage))
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(liveTranslationErrorMessage == nil ? .secondary : AppTheme.warning)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
        }
    }

    private var liveTranscriptTranslationLanguages: [TranscriptionLanguage] {
        appleTranslationLanguages.filter { language in
            !AppleTranslationLanguages.sameBaseLanguage(language.id, transcriber.selectedLanguageID)
        }
    }

    private func liveTranslationStatusText(for language: TranscriptionLanguage) -> String {
        if let liveTranslationErrorMessage {
            return liveTranslationErrorMessage
        }
        if finalTranscriptLines.isEmpty {
            return localized(L10n.Transcription.waitingForFinalSegments)
        }
        if isTranslatingLiveTranscript {
            return localized(L10n.Transcription.translatingFinalSegments)
        }
        return localizedFormat(L10n.Recordings.translatingToFormat, language.displayName)
    }

    private func requestLiveTranscriptTranslation(to language: TranscriptionLanguage) {
        guard !AppleTranslationLanguages.sameBaseLanguage(language.id, transcriber.selectedLanguageID) else {
            clearLiveTranscriptTranslation()
            return
        }

        HapticFeedback.play(.menuSelection)
        selectedLiveTranslationLanguage = language
        liveTranslationErrorMessage = nil
        scheduleFinalTranscriptTranslationIfNeeded()
    }

    private func clearLiveTranscriptTranslation(playsHaptic: Bool = true) {
        if playsHaptic {
            HapticFeedback.play(.menuSelection)
        }
        selectedLiveTranslationLanguage = nil
        translatedLiveTranscriptByLineID = [:]
        liveTranslatedLineSignatures = [:]
        liveTranslationErrorMessage = nil
        isTranslatingLiveTranscript = false
        liveTranslationConfiguration = nil
    }

    private func scheduleFinalTranscriptTranslationIfNeeded() {
        pruneLiveTranslationState()
        guard let language = selectedLiveTranslationLanguage else {
            return
        }
        guard !pendingFinalTranscriptLines(for: language).isEmpty else {
            isTranslatingLiveTranscript = false
            return
        }

        isTranslatingLiveTranscript = true
        liveTranslationErrorMessage = nil

        let nextConfiguration = TranslationSession.Configuration(
            source: AppleTranslationLanguages.localeLanguage(for: transcriber.selectedLanguageID),
            target: AppleTranslationLanguages.localeLanguage(for: language.id)
        )

        if var existingConfiguration = liveTranslationConfiguration,
           existingConfiguration == nextConfiguration {
            existingConfiguration.invalidate()
            liveTranslationConfiguration = existingConfiguration
        } else {
            liveTranslationConfiguration = nextConfiguration
        }
    }

    private func translateFinalTranscriptLines(using session: TranslationSession) async {
        guard let targetLanguage = selectedLiveTranslationLanguage else {
            isTranslatingLiveTranscript = false
            return
        }

        let targetLanguageID = targetLanguage.id
        let lines = pendingFinalTranscriptLines(for: targetLanguage)
        guard !lines.isEmpty else {
            isTranslatingLiveTranscript = false
            return
        }

        let signatures = Dictionary(uniqueKeysWithValues: lines.map { line in
            (line.id, liveTranslationSignature(for: line, language: targetLanguage))
        })
        let requests = lines.map { line in
            TranslationSession.Request(sourceText: line.text, clientIdentifier: line.id.uuidString)
        }

        do {
            try await session.prepareTranslation()
            for try await response in session.translate(batch: requests) {
                guard selectedLiveTranslationLanguage?.id == targetLanguageID,
                      let lineIDText = response.clientIdentifier,
                      let lineID = UUID(uuidString: lineIDText),
                      let signature = signatures[lineID],
                      let currentLine = transcriber.finalTranscriptStore.lines.first(where: { $0.id == lineID }),
                      liveTranslationSignature(for: currentLine, language: targetLanguage) == signature else {
                    continue
                }

                let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translatedText.isEmpty else {
                    liveTranslatedLineSignatures[lineID] = signature
                    continue
                }

                translatedLiveTranscriptByLineID[lineID] = translatedText
                liveTranslatedLineSignatures[lineID] = signature
            }

            guard selectedLiveTranslationLanguage?.id == targetLanguageID else {
                return
            }

            isTranslatingLiveTranscript = false
            liveTranslationErrorMessage = nil
        } catch {
            guard selectedLiveTranslationLanguage?.id == targetLanguageID else {
                return
            }

            isTranslatingLiveTranscript = false
            liveTranslationErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func pendingFinalTranscriptLines(for language: TranscriptionLanguage) -> [TranscriptionLine] {
        finalTranscriptLines.filter { line in
            liveTranslatedLineSignatures[line.id] != liveTranslationSignature(for: line, language: language)
        }
    }

    private func pruneLiveTranslationState() {
        let finalLineIDs = Set(finalTranscriptLines.map(\.id))
        translatedLiveTranscriptByLineID = translatedLiveTranscriptByLineID.filter { finalLineIDs.contains($0.key) }
        liveTranslatedLineSignatures = liveTranslatedLineSignatures.filter { finalLineIDs.contains($0.key) }
    }

    private func liveTranslationSignature(for line: TranscriptionLine, language: TranscriptionLanguage) -> String {
        "\(language.id)|\(line.id.uuidString)|\(line.text.hashValue)"
    }
}

private struct PendingRecordingSave: Identifiable {
    let id = UUID()
    let draft: RecordingDraft
}

private struct PendingTranscriptionSpeechLocaleReleaseAction: Identifiable {
    let request: SpeechLocaleReleaseRequest
    let operation: TranscriptionSpeechLocaleReleaseOperation

    var id: UUID {
        request.id
    }
}

private enum TranscriptionSpeechLocaleReleaseOperation {
    case selectLanguage
    case startRecording
}

private struct LiveRecordingWaveTimeline: View {
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
                    timelineEdgeFadeMask(
                        leftEdgeFraction: leftEdgeFraction,
                        rightEdgeFraction: rightEdgeFraction
                    )
                )
                .clipped()
        }
        .frame(height: height)
    }

    private func timelineCanvas(
        size: CGSize,
        elapsed: TimeInterval
    ) -> some View {
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

    private func timelineEdgeFadeMask(
        leftEdgeFraction: CGFloat,
        rightEdgeFraction: CGFloat
    ) -> some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: leftEdgeFraction),
                .init(color: .black, location: 1 - rightEdgeFraction),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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
                let label = Text(tickLabel(for: tickTime))
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

private struct LiveTranslationLanguagePicker: View {
    @Environment(\.dismiss) private var dismiss
    let selectedLanguageID: String?
    let languages: [TranscriptionLanguage]
    let onSelectOriginal: () -> Void
    let onSelectLanguage: (TranscriptionLanguage) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelectOriginal()
                        dismiss()
                    } label: {
                        languageRow(
                            title: localized(L10n.Recordings.original),
                            subtitle: localized(L10n.Transcription.stopLiveTranslation),
                            systemImage: "text.alignleft",
                            isSelected: selectedLanguageID == nil
                        )
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    if languages.isEmpty {
                        Text(L10n.Transcription.noTranslationLanguages)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(languages) { language in
                            Button {
                                onSelectLanguage(language)
                                dismiss()
                            } label: {
                                languageRow(
                                    title: language.displayName,
                                    subtitle: language.id,
                                    systemImage: "translate",
                                    isSelected: selectedLanguageID == language.id
                                )
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    Text(L10n.Transcription.translationLanguage)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(localized(L10n.Transcription.realTimeTranslation))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.Common.done)
                    }
                }
            }
        }
    }

    private func languageRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSelected ? AppTheme.brand : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.redditSans(.body, weight: .semibold))
                Text(subtitle)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.brand)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct RecordingSaveSheet: View {
    let draft: RecordingDraft
    @Binding var recordingName: String
    @Binding var categoryName: String
    @Binding var keyPoints: String
    @Binding var tags: [String]
    @Binding var generatedIntelligence: RecordingIntelligence?
    @Binding var includesLocation: Bool
    @ObservedObject var locationProvider: RecordingLocationProvider
    let isSaving: Bool
    let availableCategories: [String]
    let showsTitleGeneration: Bool
    let onGenerateTitle: () async throws -> RecordingTitleSuggestion
    let onSave: () -> Void
    let onDiscard: () -> Void
    @State private var isGeneratingTitle = false
    @State private var titleGenerationErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameSection
                    categorySection
                    keyPointsSection
                    tagsEntry
                    durationRow
                    locationSection
                }
                .padding(16)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(L10n.Transcription.saveRecording))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        onDiscard()
                    } label: {
                        Text(L10n.Transcription.discard)
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(L10n.Common.save)
                                .font(.redditSans(.subheadline, weight: .semibold))
                        }
                    }
                    .disabled(isSaving || recordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert(
            localized(L10n.Transcription.titleGenerationFailed),
            isPresented: Binding(
                get: { titleGenerationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        titleGenerationErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(titleGenerationErrorMessage ?? "")
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(L10n.Recordings.recordingName)
            } icon: {
                Image(systemName: "pencil")
            }
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(localized(L10n.Recordings.recordingName), text: $recordingName)
                    .font(.redditSans(.headline, weight: .semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if showsTitleGeneration {
                    Button {
                        generateTitleAndTags()
                    } label: {
                        Group {
                            if isGeneratingTitle {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .frame(width: 34, height: 34)
                        .foregroundStyle(AppTheme.brand)
                        .background(AppTheme.brand.opacity(0.11), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGenerateTitle)
                    .accessibilityLabel(localized(L10n.Transcription.generateTitleAndTagsAccessibility))
                }
            }
                .padding(.leading, 12)
                .padding(.trailing, showsTitleGeneration ? 7 : 12)
                .frame(height: 48)
                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        }
        .recordingSaveSectionSurface()
    }

    private var canGenerateTitle: Bool {
        !isSaving
            && !isGeneratingTitle
            && !draft.lines.plainTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(L10n.Recordings.categoryName)
            } icon: {
                Image(systemName: "folder")
            }
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            RecordingCategoryMenu(
                selection: categoryName.isEmpty ? nil : categoryName,
                categories: RecordingCategoryCatalog.normalized(availableCategories + [categoryName]),
                onSelect: { selectedName in
                    categoryName = selectedName ?? ""
                }
            ) {
                HStack(spacing: 8) {
                    Image(systemName: categoryName.isEmpty ? "tray" : "folder.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(categoryName.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppTheme.brand))

                    Text(categoryName.isEmpty ? localized(L10n.Recordings.uncategorized) : categoryName)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .recordingSaveSectionSurface()
    }

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(L10n.Recordings.keyPoints)
            } icon: {
                Image(systemName: "list.bullet.clipboard")
            }
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if keyPoints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.Recordings.keyPointsPlaceholder)
                        .font(.redditSans(.body))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $keyPoints)
                    .font(.redditSans(.body))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .padding(.horizontal, -4)
                    .background(Color.clear)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        }
        .recordingSaveSectionSurface()
    }

    private func generateTitleAndTags() {
        guard canGenerateTitle else {
            HapticFeedback.play(.blocked)
            return
        }

        isGeneratingTitle = true
        titleGenerationErrorMessage = nil
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                let suggestion = try await onGenerateTitle()
                let cleanedTitle = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedTitle.isEmpty else {
                    titleGenerationErrorMessage = localized(L10n.Intelligence.emptyTitle)
                    HapticFeedback.play(.failure)
                    isGeneratingTitle = false
                    return
                }
                recordingName = cleanedTitle
                let mergedTags = RecordingItem.mergedTags(tags, suggestion.tags)
                tags = mergedTags
                let summary = suggestion.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                generatedIntelligence = summary.isEmpty
                    ? nil
                    : RecordingIntelligence(summary: summary, tags: mergedTags, generatedAt: Date())
                HapticFeedback.play(.analysisComplete)
            } catch {
                titleGenerationErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isGeneratingTitle = false
        }
    }

    private var tagsEntry: some View {
        NavigationLink {
            RecordingTagsEditor(tags: $tags)
        } label: {
            HStack(spacing: 12) {
                Label {
                    Text(L10n.Recordings.tags)
                } icon: {
                    Image(systemName: "tag")
                }
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(tags.isEmpty ? localized(L10n.Recordings.notAdded) : "\(tags.count)")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .recordingSaveSectionSurface()
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            Label {
                Text(L10n.Recordings.audioDuration)
            } icon: {
                Image(systemName: "clock")
            }
                .font(.redditSans(.subheadline, weight: .semibold))
            Spacer()
            Text(TranscriptionLine.formatTimestamp(Double(draft.durationSeconds)))
                .font(.redditSans(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .recordingSaveSectionSurface()
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $includesLocation) {
                Label {
                    Text(L10n.Recordings.addLocation)
                } icon: {
                    Image(systemName: "location")
                }
                    .font(.redditSans(.subheadline, weight: .semibold))
            }
            .tint(AppTheme.brand)

            if includesLocation {
                RecordingLocationPreview(locationProvider: locationProvider)
            }
        }
        .recordingSaveSectionSurface()
    }
}

private struct RecordingTagsEditor: View {
    @Binding var tags: [String]
    @State private var newTag = ""

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField(localized(L10n.Recordings.addTag), text: $newTag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        addTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(normalizedTag.isEmpty)
                }
            }

            Section {
                if tags.isEmpty {
                    Text(L10n.Recordings.noTags)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                    }
                    .onDelete { offsets in
                        tags.remove(atOffsets: offsets)
                    }
                }
            }
        }
        .navigationTitle(localized(L10n.Recordings.tags))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var normalizedTag: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addTag() {
        let tag = normalizedTag
        guard !tag.isEmpty else {
            return
        }

        if !tags.contains(where: { $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            tags.append(tag)
        }
        newTag = ""
        HapticFeedback.play(.primaryAction)
    }
}

private struct RecordingLocationPreview: View {
    @ObservedObject var locationProvider: RecordingLocationProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let location = locationProvider.latestLocation {
                let coordinate = location.coordinate
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                ) {
                    Marker(localized(L10n.Recordings.currentLocation), coordinate: coordinate)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))

                if let placeName = locationProvider.placeName, !placeName.isEmpty {
                    Label(placeName, systemImage: "building.2")
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text("\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))")
                        .monospacedDigit()
                    Spacer()
                    if location.horizontalAccuracy >= 0 {
                        Text("±\(Int(location.horizontalAccuracy.rounded()))m")
                            .monospacedDigit()
                    }
                }
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
            } else if locationProvider.isDenied {
                Label {
                    Text(L10n.Recordings.locationDenied)
                } icon: {
                    Image(systemName: "location.slash")
                }
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
            } else if let errorText = locationProvider.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.Recordings.locating)
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
private final class RecordingLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var placeName: String?
    @Published private(set) var errorText: String?

    private let manager = CLLocationManager()
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var city: String?
    private var country: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            errorText = localized(L10n.Recordings.locationDenied)
        @unknown default:
            errorText = localized(L10n.Recordings.locationUnavailable)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
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
            let resolvedCity = address?.cityName
                ?? address?.cityWithContext(.short)
                ?? mapItem?.name
            let resolvedCountry = address?.regionName
            city = resolvedCity
            country = resolvedCountry
            placeName = [resolvedCity, resolvedCountry]
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

private struct RollingRecorderElapsedTimeText: View {
    @ObservedObject var clock: RecordingElapsedClock
    let color: Color

    var body: some View {
        let text = TranscriptionLine.formatTimestamp(clock.elapsedTime)
        let components = text.split(separator: ":", omittingEmptySubsequences: false)

        HStack(spacing: 0) {
            ForEach(Array(components.indices), id: \.self) { index in
                Text(String(components[index]))
                    .foregroundStyle(color)

                if index < components.index(before: components.endIndex) {
                    Text(":")
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
        .font(.custom(AppTypography.baloo2SemiBoldName, size: 25))
        .monospacedDigit()
        .contentTransition(.identity)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private extension View {
    func recordingSaveSectionSurface() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
    }
}

private struct LiveTranscriptLineCount: View {
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    @ObservedObject var interimStore: LiveInterimTranscriptStore

    var body: some View {
        Text("\(finalStore.lines.count + (interimStore.line == nil ? 0 : 1))")
            .font(.redditSans(.caption2).monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

private struct LiveTranscriptLineEditRequest: Identifiable {
    let lineID: TranscriptionLine.ID
    let timeText: String

    var id: TranscriptionLine.ID {
        lineID
    }

    init(line: TranscriptionLine) {
        lineID = line.id
        timeText = line.timestampText
    }
}

private struct LiveTranscriptRows: View {
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    @ObservedObject var interimStore: LiveInterimTranscriptStore
    let translatedTextByLineID: [TranscriptionLine.ID: String]
    let translatedLineSignatures: [TranscriptionLine.ID: String]
    let isTranslating: Bool
    let selectedTranslationLanguage: TranscriptionLanguage?
    let bottomContentInset: CGFloat
    let onEditFinalLine: (TranscriptionLine) -> Void

    private var totalLineCount: Int {
        finalStore.lines.count + (interimStore.line == nil ? 0 : 1)
    }

    var body: some View {
        if totalLineCount > 0 {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        Color.clear
                            .frame(height: 1)
                            .id("transcript-top")

                        LiveInterimTranscriptRow(interimStore: interimStore)

                        LiveFinalTranscriptRows(
                            finalStore: finalStore,
                            translatedTextByLineID: translatedTextByLineID,
                            translatedLineSignatures: translatedLineSignatures,
                            isTranslating: isTranslating,
                            selectedTranslationLanguage: selectedTranslationLanguage,
                            onEdit: onEditFinalLine
                        )
                    }
                    .padding(.vertical, 2)
                    .padding(.bottom, bottomContentInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: totalLineCount) { _, _ in
                    withAnimation(.snappy(duration: 0.2)) {
                        scrollProxy.scrollTo("transcript-top", anchor: .top)
                    }
                }
            }
        } else {
            EmptyStateView(icon: "quote.bubble", titleResource: L10n.Recordings.noText)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
    }
}

private struct LiveInterimTranscriptRow: View {
    @ObservedObject var interimStore: LiveInterimTranscriptStore

    var body: some View {
        if let line = interimStore.line {
            TranscriptionLineRow(
                line: line,
                translatedText: nil,
                isShowingTranslation: false,
                onEdit: nil
            )
        }
    }
}

private struct LiveFinalTranscriptRows: View {
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    let translatedTextByLineID: [TranscriptionLine.ID: String]
    let translatedLineSignatures: [TranscriptionLine.ID: String]
    let isTranslating: Bool
    let selectedTranslationLanguage: TranscriptionLanguage?
    let onEdit: (TranscriptionLine) -> Void

    var body: some View {
        ForEach(finalStore.lines.reversed()) { line in
            TranscriptionLineRow(
                line: line,
                translatedText: translatedTextByLineID[line.id],
                isShowingTranslation: isShowingTranslationPlaceholder(for: line),
                onEdit: {
                    onEdit(line)
                }
            )
        }
    }

    private func isShowingTranslationPlaceholder(for line: TranscriptionLine) -> Bool {
        guard isTranslating,
              let language = selectedTranslationLanguage else {
            return false
        }
        return translatedLineSignatures[line.id] != liveTranslationSignature(for: line, language: language)
    }

    private func liveTranslationSignature(for line: TranscriptionLine, language: TranscriptionLanguage) -> String {
        "\(language.id)|\(line.id.uuidString)|\(line.text.hashValue)"
    }
}

private struct TranscriptionLineRow: View {
    let line: TranscriptionLine
    let translatedText: String?
    let isShowingTranslation: Bool
    let onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.timestampText)
                .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                .foregroundStyle(line.isFinal ? AppTheme.brand : AppTheme.warning)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background((line.isFinal ? AppTheme.brand : AppTheme.warning).opacity(0.12), in: Capsule())

            VStack(alignment: .leading, spacing: 4) {
                Text(translatedText ?? line.text)
                    .font(.redditSans(.body))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let translatedText, !translatedText.isEmpty {
                    Text(line.text)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                } else if isShowingTranslation {
                    Text(L10n.Recordings.translating)
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                HapticFeedback.play(.copy)
                UIPasteboard.general.string = line.text
            } label: {
                Label(localized(L10n.Common.copy), systemImage: "doc.on.doc")
            }

            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label(localized(L10n.Recordings.editTranscriptLine), systemImage: "pencil")
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

private struct RecordingStateBadge: View {
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
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
            .animation(.snappy(duration: 0.2, extraBounce: 0), value: systemImage)
    }
}

private struct StatusPill: View {
    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.redditSans(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(tint.opacity(0.1), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct DropdownStatusPill: View {
    @Environment(\.isEnabled) private var isEnabled

    let systemImage: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .font(.redditSans(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .truncationMode(.tail)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .padding(.leading, 1)
        }
        .foregroundStyle(isEnabled ? tint : .secondary)
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(height: 32)
        .background((isEnabled ? tint.opacity(0.13) : Color.secondary.opacity(0.08)), in: Capsule())
        .overlay {
            Capsule()
                .stroke(isEnabled ? tint.opacity(0.34) : Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct CompactDropdownBadge: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let foreground: Color
    let background: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.redditSans(.caption2, weight: .bold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(isEnabled ? foreground : .secondary)
        .padding(.leading, 8)
        .padding(.trailing, 7)
        .frame(height: 25)
        .background(background, in: Capsule())
        .overlay {
            Capsule()
                .stroke((isEnabled ? foreground : Color.secondary).opacity(0.16), lineWidth: 1)
        }
        .contentShape(Capsule())
    }
}

private struct FloatingIconControlButton: View {
    let titleResource: LocalizedStringResource
    let systemImage: String
    let tint: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(RecorderPressButtonStyle(pressedScale: 0.94))
        .accessibilityLabel(Text(titleResource))
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: systemImage)
    }
}

private struct RecorderPressButtonStyle: ButtonStyle {
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

private extension View {
    func cardSurface() -> some View {
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

#if DEBUG
#Preview("Transcription") {
    TranscriptionView(
        transcriber: LiveTranscriptionManager(),
        recordingStore: RecordingStore(),
        externalPendingRecordingDraft: .constant(nil)
    )
    .font(.redditSans(.body))
    .tint(AppTheme.brand)
}
#endif
