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
    @ObservedObject var systemAudioCoordinator: SystemAudioSessionCoordinator
    @ObservedObject var captionStore: CaptionPresentationStore
    @ObservedObject var captionPiPController: CaptionPiPController
    @Binding var externalPendingRecordingDraft: RecordingDraft?
    let onOpenRecording: (RecordingItem.ID) -> Void
    let onShowRecordings: () -> Void
    @State private var selectedAudioInput: TranscriptionAudioInput = .microphone
    @State private var savedRecordingName: String?
    @State private var savedRecordingBannerIsVisible = false
    @State private var savedRecordingBannerTask: Task<Void, Never>?
    @StateObject private var locationProvider = RecordingLocationProvider()
    @State private var pendingRecordingSave: PendingRecordingSave?
    @State private var pendingRecordingName = ""
    @State private var pendingRecordingLanguageID = ""
    @State private var pendingRecordingCategory = ""
    @State private var pendingRecordingKeyPoints = ""
    @State private var pendingRecordingTags: [String] = []
    @State private var pendingRecordingIntelligence: RecordingIntelligence?
    @State private var pendingRecordingIncludesLocation = false
    @State private var isSavingPendingRecording = false
    @State private var isStoppingRecording = false
    @State private var recordingSaveErrorMessage: String?
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
    @State private var isShowingWeeklyRecap = false
    @State private var selectedDashboardInsight: DashboardInsight?
    @AppStorage(RecordingPlaybackHistoryStore.defaultsKey)
    private var playbackHistoryJSON = "{}"
    @Namespace private var recorderLaunchNamespace
    @Namespace private var assistantHeaderNamespace

    private var isCompletingRecording: Bool {
        isStoppingRecording || pendingRecordingSave != nil || isSavingPendingRecording
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
            refreshCaptionPresentation()
        }
        .onReceive(transcriber.finalTranscriptStore.$lines) { _ in
            refreshCaptionPresentation()
        }
        .onReceive(transcriber.interimTranscriptStore.$line) { _ in
            refreshCaptionPresentation()
        }
        .onReceive(transcriber.finalTranscriptStore.$revision.dropFirst()) { _ in
            scheduleFinalTranscriptTranslationIfNeeded()
        }
        .onReceive(systemAudioCoordinator.$completedDraft.compactMap { $0 }) { _ in
            guard let draft = systemAudioCoordinator.takeCompletedDraft() else {
                return
            }
            presentSaveSheet(for: draft)
        }
        .onChange(of: transcriber.selectedLanguageID) { _, _ in
            clearLiveTranscriptTranslation(playsHaptic: false)
            refreshCaptionPresentation()
        }
        .onChange(of: translatedLiveTranscriptByLineID) { _, _ in
            refreshCaptionPresentation()
        }
        .onChange(of: selectedLiveTranslationLanguage?.id) { _, _ in
            refreshCaptionPresentation()
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
        .sheet(isPresented: $isShowingWeeklyRecap) {
            WeeklyRecordingRecapView(
                snapshot: dashboardSnapshot,
                onOpenRecording: { recordingID in
                    isShowingWeeklyRecap = false
                    onOpenRecording(recordingID)
                },
                onShowRecordings: {
                    isShowingWeeklyRecap = false
                    onShowRecordings()
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedDashboardInsight) { insight in
            DashboardInsightDetailView(
                insight: insight,
                snapshot: dashboardSnapshot,
                onOpenRecording: { recordingID in
                    selectedDashboardInsight = nil
                    onOpenRecording(recordingID)
                }
            )
            .presentationDetents([.large])
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
                languageID: $pendingRecordingLanguageID,
                categoryName: $pendingRecordingCategory,
                keyPoints: $pendingRecordingKeyPoints,
                tags: $pendingRecordingTags,
                generatedIntelligence: $pendingRecordingIntelligence,
                includesLocation: $pendingRecordingIncludesLocation,
                locationProvider: locationProvider,
                isSaving: isSavingPendingRecording,
                saveErrorMessage: $recordingSaveErrorMessage,
                languageOptions: pendingRecordingLanguageOptions,
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

    private var dashboardSnapshot: RecordingDashboardSnapshot {
        RecordingDashboardSnapshot(
            recordings: recordingStore.recordings,
            playbackHistory: RecordingPlaybackHistoryStore.entries(from: playbackHistoryJSON)
        )
    }

    private var shouldShowIdleDashboard: Bool {
        !transcriber.isRecording
            && !transcriber.isPreparing
            && !isCompletingRecording
            && !systemAudioCoordinator.state.isActive
            && finalTranscriptLines.isEmpty
    }

    private var portraitWorkspace: some View {
        ZStack(alignment: .top) {
            if shouldShowIdleDashboard {
                idleRecordingDashboard
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    assistantGreetingHeader

                    recorderCard(expandsVertically: false)

                    transcriptCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .smooth(duration: 0.24),
            value: shouldShowIdleDashboard
        )
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

    private var idleRecordingDashboard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                dashboardPersonalPromptHeader

                idleRecorderDashboardCard

                dashboardMetrics

                dashboardLocationCollectionCard

                dashboardActivityCard

                if let continueListeningItem = dashboardSnapshot.continueListeningItem {
                    dashboardResumeCard(continueListeningItem)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var idleRecorderDashboardCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Label {
                    Text(L10n.Dashboard.ready)
                } icon: {
                    Image(systemName: "waveform.and.mic")
                        .foregroundStyle(AppTheme.brand)
                }
                .font(.redditSans(.subheadline, weight: .semibold))

                Spacer(minLength: 8)

                audioFormatMenu
            }

            ZStack {
                DashboardIdleWaveform()
                    .frame(height: 72)
                    .allowsHitTesting(false)

                floatingRecorderDock
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)

            VStack(spacing: 3) {
                Text(L10n.Transcription.startRecording)
                    .font(.redditSans(.headline, weight: .bold))
                    .foregroundStyle(AppTheme.brand)

                Text(L10n.Dashboard.startHint)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    audioInputMenu
                    languageMenu
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    audioInputMenu
                    languageMenu
                }
            }
        }
        .padding(16)
        .dashboardSurface(accent: AppTheme.brand)
    }

    private var dashboardMetrics: some View {
        HStack(spacing: 10) {
            dashboardMetricButton(
                insight: .recordings,
                systemImage: "waveform",
                value: "\(dashboardSnapshot.weekRecordings.count)",
                label: localized(L10n.Dashboard.recordingsMetric),
                tint: AppTheme.brand
            )

            dashboardMetricButton(
                insight: .duration,
                systemImage: "clock",
                value: dashboardSnapshot.compactDuration,
                label: localized(L10n.Dashboard.durationMetric),
                tint: AppTheme.purple
            )

            dashboardMetricButton(
                insight: .topics,
                systemImage: "tag",
                value: "\(dashboardSnapshot.topicCount)",
                label: localized(L10n.Dashboard.topicsMetric),
                tint: AppTheme.success
            )
        }
    }

    private func dashboardMetricButton(
        insight: DashboardInsight,
        systemImage: String,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        Button {
            HapticFeedback.play(.navigation)
            selectedDashboardInsight = insight
        } label: {
            DashboardMetricTile(
                systemImage: systemImage,
                value: value,
                label: label,
                tint: tint
            )
        }
        .buttonStyle(DashboardPressButtonStyle())
        .accessibilityHint(Text(L10n.Dashboard.openDetails))
    }

    private var dashboardActivityCard: some View {
        Button {
            HapticFeedback.play(.navigation)
            isShowingWeeklyRecap = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L10n.Dashboard.thisWeekInVoice)
                        .font(.redditSans(.headline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Text(L10n.Dashboard.weeklyRecap)
                        Image(systemName: "chevron.right")
                    }
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                }

                DashboardWeekChart(
                    dailyDurations: dashboardSnapshot.dailyDurations,
                    dayLabels: dashboardSnapshot.dayLabels,
                    highlightedDayIndex: dashboardSnapshot.currentWeekdayIndex,
                    tint: AppTheme.purple
                )
                .frame(height: 92)
            }
            .padding(16)
            .dashboardSurface(accent: AppTheme.purple)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(DashboardPressButtonStyle())
    }

    private var dashboardLocationCollectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.success.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Dashboard.voiceFootprints)
                        .font(.redditSans(.headline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(
                        localizedFormat(
                            L10n.Dashboard.placesCollectedFormat,
                            dashboardSnapshot.collectedPlaces.count
                        )
                    )
                    .font(.redditSans(.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppTheme.warning.opacity(0.72))
                        .rotationEffect(.degrees(8))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .accessibilityHidden(true)
            }

            if dashboardSnapshot.collectedPlaces.isEmpty {
                HStack(spacing: 12) {
                    DashboardEmptyVoiceStamp()

                    Text(L10n.Dashboard.firstPlaceHint)
                        .font(.redditSans(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(
                            Array(dashboardSnapshot.collectedPlaces.prefix(6).enumerated()),
                            id: \.element.id
                        ) { index, place in
                            DashboardVoiceStamp(
                                place: place,
                                tint: DashboardVoiceStamp.tint(for: index)
                            )
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
        .padding(16)
        .dashboardSurface(accent: AppTheme.success)
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .onTapGesture {
            HapticFeedback.play(.navigation)
            selectedDashboardInsight = .places
        }
        .accessibilityAction(named: Text(L10n.Dashboard.openDetails)) {
            selectedDashboardInsight = .places
        }
    }

    private func dashboardResumeCard(_ item: DashboardContinueListeningItem) -> some View {
        Button {
            HapticFeedback.play(.navigation)
            onOpenRecording(item.recording.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.info.opacity(0.12))

                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.info)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        item.isResume
                            ? L10n.Dashboard.continueListening
                            : L10n.Dashboard.latestRecording
                    )
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(item.recording.displayName)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if item.isResume {
                        HStack(spacing: 8) {
                            ProgressView(value: item.progress)
                                .progressViewStyle(.linear)
                                .tint(AppTheme.info)
                                .frame(maxWidth: 112)

                            Text(
                                localizedFormat(
                                    L10n.Dashboard.remainingFormat,
                                    dashboardDurationText(item.remainingDuration)
                                )
                            )
                            .font(.redditSans(.caption2, weight: .medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.info, in: Circle())
            }
            .padding(14)
            .dashboardSurface(accent: AppTheme.info)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(DashboardPressButtonStyle())
        .accessibilityValue(
            item.isResume
                ? Text(
                    localizedFormat(
                        L10n.Dashboard.remainingFormat,
                        dashboardDurationText(item.remainingDuration)
                    )
                )
                : Text("")
        )
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
                .modifier(
                    AssistantHeaderGeometryModifier(
                        id: "assistant-robot",
                        namespace: assistantHeaderNamespace,
                        isEnabled: !reduceMotion
                    )
                )
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
                .modifier(
                    AssistantHeaderGeometryModifier(
                        id: "assistant-greeting",
                        namespace: assistantHeaderNamespace,
                        isEnabled: !reduceMotion
                    )
                )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var dashboardPersonalPromptHeader: some View {
        HStack(alignment: .center, spacing: 11) {
            Image("AssistantRobot")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .modifier(
                    AssistantHeaderGeometryModifier(
                        id: "assistant-robot",
                        namespace: assistantHeaderNamespace,
                        isEnabled: !reduceMotion
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(assistantGreetingTitle)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .modifier(
                        AssistantHeaderGeometryModifier(
                            id: "assistant-greeting",
                            namespace: assistantHeaderNamespace,
                            isEnabled: !reduceMotion
                        )
                    )

                Text(L10n.Dashboard.prompt)
                    .font(.redditSans(.headline, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
                if isScreenAudioMode {
                    SystemAudioStateBadge(state: systemAudioCoordinator.state)
                } else {
                    RecordingStateBadge(
                        isRecording: transcriber.isRecording,
                        isPaused: transcriber.isPaused,
                        isPreparing: transcriber.isPreparing
                    )
                }

                audioInputMenu

                languageMenu

                Spacer(minLength: 0)
            }

            if isScreenAudioMode {
                screenAudioControls
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

    private var isScreenAudioMode: Bool {
        selectedAudioInput == .screenAudio || systemAudioCoordinator.state.isActive
    }

    private var audioInputMenu: some View {
        Menu {
            ForEach(TranscriptionAudioInput.allCases) { input in
                Button {
                    selectedAudioInput = input
                    HapticFeedback.play(.menuSelection)
                } label: {
                    Label(
                        input == .microphone
                            ? localized(L10n.ScreenAudio.microphone)
                            : localized(L10n.ScreenAudio.screenAudio),
                        systemImage: input == selectedAudioInput ? "checkmark" : input.systemImage
                    )
                }
            }
        } label: {
            DropdownStatusPill(
                systemImage: selectedAudioInput.systemImage,
                title: selectedAudioInput == .microphone
                    ? localized(L10n.ScreenAudio.microphone)
                    : localized(L10n.ScreenAudio.screenAudio),
                tint: selectedAudioInput == .microphone ? AppTheme.success : AppTheme.brand
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing || systemAudioCoordinator.state.isActive)
        .accessibilityLabel(Text(L10n.ScreenAudio.inputSource))
    }

    private var screenAudioControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(screenAudioBackendTitle, systemImage: "rectangle.on.rectangle")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Label(screenAudioHeartbeatText, systemImage: "wave.3.right")
                    .font(.redditSans(.caption2, weight: .semibold))
                    .foregroundStyle(screenAudioHeartbeatTint)
                    .lineLimit(1)
            }

            CaptionPiPPreview(controller: captionPiPController)
                .frame(height: verticalSizeClass == .compact ? 52 : 78)
                .accessibilityLabel(Text(L10n.ScreenAudio.title))

            HStack(spacing: 10) {
                Button {
                    Task {
                        if captionPiPController.isActive {
                            captionPiPController.stop()
                        } else {
                            await captionPiPController.start()
                        }
                    }
                } label: {
                    Label(
                        captionPiPController.isActive
                            ? localized(L10n.ScreenAudio.closePiP)
                            : localized(L10n.ScreenAudio.openPiP),
                        systemImage: captionPiPController.isActive
                            ? "pip.exit"
                            : "pip.enter"
                    )
                    .font(.redditSans(.caption, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(AppTheme.info.opacity(0.11), in: Capsule())
                    .overlay {
                        Capsule().stroke(AppTheme.info.opacity(0.20), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!transcriber.isRecording || captionPiPController.isStarting)

                Spacer(minLength: 0)
            }

            if let diagnostic = systemAudioDiagnosticText {
                Label(diagnostic, systemImage: "exclamationmark.triangle.fill")
                    .font(.redditSans(.caption2))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else if verticalSizeClass != .compact {
                Text(
                    systemAudioCoordinator.requiresReplayKitPicker
                        ? L10n.ScreenAudio.broadcastPickerHint
                        : L10n.ScreenAudio.privacyNote
                )
                .font(.redditSans(.caption2))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AppTheme.brand.opacity(colorScheme == .dark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.brand.opacity(0.16), lineWidth: 1)
        }
    }

    private var screenAudioBackendTitle: String {
        switch systemAudioCoordinator.backend {
        case .replayKitCompatibility:
            return localized(L10n.ScreenAudio.compatibilityBackend)
        case .screenCaptureKit:
            return localized(L10n.ScreenAudio.nativeBackend)
        }
    }

    private var screenAudioHeartbeatText: String {
        guard let heartbeat = systemAudioCoordinator.lastHeartbeat else {
            return localized(L10n.ScreenAudio.noHeartbeat)
        }
        if Date().timeIntervalSince(heartbeat) < 3 {
            return localized(L10n.ScreenAudio.heartbeatNow)
        }
        return localizedFormat(
            L10n.ScreenAudio.heartbeatFormat,
            heartbeat.formatted(date: .omitted, time: .standard)
        )
    }

    private var screenAudioHeartbeatTint: Color {
        guard let heartbeat = systemAudioCoordinator.lastHeartbeat,
              Date().timeIntervalSince(heartbeat) < 5 else {
            return .secondary
        }
        return AppTheme.success
    }

    private var systemAudioDiagnosticText: String? {
        if case .failed(let message) = systemAudioCoordinator.state {
            return message
        }
        if let message = captionPiPController.errorMessage {
            return message
        }
        return systemAudioCoordinator.diagnostics.lastError
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
                    await startSelectedAudioInput()
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private enum RecorderDockContentState: Hashable {
        case idle
        case recording
        case awaitingApproval
        case stopping
    }

    private var recorderDockContentState: RecorderDockContentState {
        if isStoppingRecording {
            return .stopping
        }
        if transcriber.isRecording {
            return isAwaitingReplayKitBroadcastApproval
                ? .awaitingApproval
                : .recording
        }
        return .idle
    }

    private var recorderDockContainerWidth: CGFloat {
        120
    }

    private var floatingRecorderDock: some View {
        ZStack {
            RecorderDockBackgroundShape(width: activeRecorderDockWidth)
                .fill(.ultraThinMaterial)
                .overlay {
                    RecorderDockBackgroundShape(width: activeRecorderDockWidth)
                        .fill(
                            AppTheme.danger.opacity(
                                transcriber.isRecording
                                    ? 0
                                    : (colorScheme == .dark ? 0.80 : 0.86)
                            )
                        )
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.14),
                            value: transcriber.isRecording
                        )
                }
                .overlay {
                    RecorderDockBackgroundShape(width: activeRecorderDockWidth)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                }
                .frame(width: recorderDockContainerWidth, height: 64)
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.22),
                    value: activeRecorderDockWidth
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08),
                    radius: 2,
                    y: 2
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    radius: 12,
                    y: 8
                )
                .accessibilityHidden(true)

            Group {
                if isStoppingRecording {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.regular)
                        .frame(width: 64, height: 64)
                        .accessibilityLabel(Text(L10n.Transcription.finishingRecording))
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else if transcriber.isRecording {
                    Group {
                        if isAwaitingReplayKitBroadcastApproval {
                            ZStack {
                                Image(systemName: "rectangle.on.rectangle.angled")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(AppTheme.brand, in: Circle())

                                ReplayKitBroadcastPicker()
                                    .frame(width: 64, height: 64)
                            }
                            .frame(width: 64, height: 64)
                            .contentShape(Circle())
                            .accessibilityLabel(Text(L10n.ScreenAudio.startBroadcast))
                        } else {
                            HStack(spacing: 8) {
                                if showsPauseControl {
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
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
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
                                Image(systemName: selectedAudioInput == .microphone ? "mic.fill" : "rectangle.on.rectangle.angled")
                                    .font(.system(size: 24, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                    }
                    .buttonStyle(
                        RecorderPressButtonStyle(
                            pressedScale: 0.94,
                            usesHDRPressHighlight: true
                        )
                    )
                    .disabled(transcriber.isPreparing || isCompletingRecording)
                    .accessibilityLabel(
                        Text(isCompletingRecording ? L10n.Transcription.saveRecording : L10n.Transcription.startRecording)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: recorderDockContentState
            )
        }
        .frame(width: recorderDockContainerWidth, height: 64)
        .modifier(
            RecorderLaunchGeometryModifier(
                namespace: recorderLaunchNamespace,
                isEnabled: !reduceMotion
            )
        )
        .zIndex(30)
    }

    private func startRecording() {
        guard !isCompletingRecording else {
            return
        }
        hideSavedRecordingBanner()
        guard transcriber.selectedTranscriptionBackend.requiresAppleSpeech else {
            HapticFeedback.play(.recordingStart)
            Task {
                await startSelectedAudioInput()
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
                    await startSelectedAudioInput()
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

    private var showsPauseControl: Bool {
        !(isScreenAudioMode && systemAudioCoordinator.backend == .replayKitCompatibility)
    }

    private var isAwaitingReplayKitBroadcastApproval: Bool {
        systemAudioCoordinator.requiresReplayKitPicker
            && systemAudioCoordinator.state == .awaitingUserApproval
    }

    private var activeRecorderDockWidth: CGFloat {
        transcriber.isRecording && !isStoppingRecording && showsPauseControl ? 120 : 64
    }

    private func startSelectedAudioInput() async {
        switch selectedAudioInput {
        case .microphone:
            await transcriber.startRecording()
        case .screenAudio:
            await systemAudioCoordinator.startSession()
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
        guard !isStoppingRecording else {
            return
        }
        isStoppingRecording = true
        HapticFeedback.play(.recordingStop)
        Task {
            defer {
                isStoppingRecording = false
            }
            let draft: RecordingDraft?
            if isScreenAudioMode || systemAudioCoordinator.state.isActive {
                captionPiPController.stop()
                draft = await systemAudioCoordinator.stopSession()
            } else {
                draft = await transcriber.stopRecording()
            }
            if let draft {
                presentSaveSheet(for: draft)
            } else {
                HapticFeedback.play(.warning)
            }
        }
    }

    private func presentSaveSheet(for draft: RecordingDraft) {
        recordingSaveErrorMessage = nil
        pendingRecordingName = RecordingStore.defaultBaseName(for: draft.startedAt)
        pendingRecordingLanguageID = TranscriptionLanguage(id: draft.languageID).baseLanguage.id
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

        let selectedLanguage = pendingRecordingLanguageOptions.first {
            $0.id == pendingRecordingLanguageID
        } ?? TranscriptionLanguage(id: pendingRecordingLanguageID).baseLanguage
        var resolvedDraft = pendingRecordingSave.draft
        resolvedDraft.languageID = selectedLanguage.id
        resolvedDraft.languageName = selectedLanguage.displayName

        isSavingPendingRecording = true
        recordingSaveErrorMessage = nil
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
                resolvedDraft,
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
                let fallbackMessage = localized(L10n.Transcription.saveRecordingFailedMessage)
                if let reason = recordingStore.lastRecordingSaveErrorMessage?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    recordingSaveErrorMessage = "\(fallbackMessage)\n\n\(reason)"
                } else {
                    recordingSaveErrorMessage = fallbackMessage
                }
                HapticFeedback.play(.failure)
            }
            isSavingPendingRecording = false
        }
    }

    private var pendingRecordingLanguageOptions: [TranscriptionLanguage] {
        TranscriptionLanguage.baseLanguageOptions(
            from: transcriber.supportedLanguages + TranscriptionLanguage.fallbackOptions,
            including: pendingRecordingLanguageID
        )
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
        recordingSaveErrorMessage = nil
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
                isRecording: transcriber.isRecording,
                isPaused: transcriber.isPaused,
                isPreparing: transcriber.isPreparing,
                onEditFinalLine: beginLiveTranscriptLineEdit
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
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

    private func refreshCaptionPresentation() {
        captionStore.updateTranscript(
            finalLines: transcriber.finalTranscriptStore.lines,
            interimLine: transcriber.interimTranscriptStore.line,
            sourceLanguageID: transcriber.selectedLanguageID
        )
        captionStore.updateTranslation(
            translatedLiveTranscriptByLineID,
            targetLanguageID: selectedLiveTranslationLanguage?.id
        )
    }
}

private enum DashboardInsight: String, Identifiable {
    case recordings
    case duration
    case topics
    case places

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recordings:
            return localized(L10n.Dashboard.recordingsMetric)
        case .duration:
            return localized(L10n.Dashboard.durationMetric)
        case .topics:
            return localized(L10n.Dashboard.topicsMetric)
        case .places:
            return localized(L10n.Dashboard.voiceFootprints)
        }
    }

    var systemImage: String {
        switch self {
        case .recordings:
            return "waveform"
        case .duration:
            return "clock"
        case .topics:
            return "tag"
        case .places:
            return "mappin.and.ellipse"
        }
    }

    var tint: Color {
        switch self {
        case .recordings:
            return AppTheme.brand
        case .duration:
            return AppTheme.purple
        case .topics:
            return AppTheme.success
        case .places:
            return AppTheme.info
        }
    }
}

private struct DashboardTopicStatistic: Identifiable, Hashable {
    let id: String
    let title: String
    var recordingCount: Int
    var duration: TimeInterval
}

private struct DashboardCollectedPlace: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let latitude: Double
    let longitude: Double
    var recordingIDs: [RecordingItem.ID]
    let latestRecordedAt: Date

    var recordingCount: Int {
        recordingIDs.count
    }
}

private struct DashboardContinueListeningItem {
    let recording: RecordingItem
    let position: TimeInterval
    let duration: TimeInterval
    let lastPlayedAt: Date?
    let isResume: Bool

    var progress: Double {
        guard duration > 0 else {
            return 0
        }
        return min(max(position / duration, 0), 1)
    }

    var remainingDuration: TimeInterval {
        max(duration - position, 0)
    }
}

private struct RecordingDashboardSnapshot {
    let allRecordings: [RecordingItem]
    let weekRecordings: [RecordingItem]
    let dailyDurations: [TimeInterval]
    let dailyRecordingCounts: [TimeInterval]
    let dayLabels: [String]
    let currentWeekdayIndex: Int
    let totalDuration: TimeInterval
    let allTimeDuration: TimeInterval
    let topicCount: Int
    let topTopics: [String]
    let topicStatistics: [DashboardTopicStatistic]
    let collectedPlaces: [DashboardCollectedPlace]
    let locatedRecordingCount: Int
    let continueListeningItem: DashboardContinueListeningItem?
    let replayRecording: RecordingItem?
    let longestRecording: RecordingItem?
    let pendingOrganizationCount: Int

    init(
        recordings: [RecordingItem],
        playbackHistory: [RecordingItem.ID: RecordingPlaybackHistoryEntry] = [:],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let sortedRecordings = recordings.sorted { $0.createdAt > $1.createdAt }
        allRecordings = sortedRecordings
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let weekStart = weekInterval?.start ?? calendar.startOfDay(for: now)
        let weekEnd = weekInterval?.end ?? calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now

        weekRecordings = sortedRecordings.filter { item in
            item.createdAt >= weekStart && item.createdAt < weekEnd
        }
        totalDuration = weekRecordings.reduce(0) { partialResult, item in
            partialResult + TimeInterval(max(item.durationSeconds, 0))
        }
        allTimeDuration = sortedRecordings.reduce(0) { partialResult, item in
            partialResult + TimeInterval(max(item.durationSeconds, 0))
        }

        var resolvedDurations: [TimeInterval] = []
        var resolvedRecordingCounts: [TimeInterval] = []
        var resolvedDayLabels: [String] = []
        for offset in 0..<7 {
            let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayRecordings = weekRecordings.filter { item in
                item.createdAt >= dayStart && item.createdAt < nextDay
            }
            let duration = dayRecordings.reduce(0) { partialResult, item in
                partialResult + TimeInterval(max(item.durationSeconds, 0))
            }
            resolvedDurations.append(duration)
            resolvedRecordingCounts.append(TimeInterval(dayRecordings.count))
            resolvedDayLabels.append(dayStart.formatted(.dateTime.weekday(.narrow)))
        }
        dailyDurations = resolvedDurations
        dailyRecordingCounts = resolvedRecordingCounts
        dayLabels = resolvedDayLabels

        let currentDayStart = calendar.startOfDay(for: now)
        let weekdayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: weekStart),
            to: currentDayStart
        ).day ?? 0
        currentWeekdayIndex = min(max(weekdayOffset, 0), 6)

        var topicCounts: [String: (displayName: String, count: Int)] = [:]
        for item in weekRecordings {
            let itemTopics = RecordingItem.mergedTags(
                item.combinedTags,
                item.categoryName.map { [$0] } ?? []
            )
            for topic in itemTopics {
                let key = topic.normalizedForRecordingSearch
                guard !key.isEmpty else {
                    continue
                }
                let existing = topicCounts[key]
                topicCounts[key] = (
                    displayName: existing?.displayName ?? topic,
                    count: (existing?.count ?? 0) + 1
                )
            }
        }
        let sortedTopics = topicCounts.values.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        topicCount = topicCounts.count
        topTopics = Array(sortedTopics.prefix(2).map(\.displayName))

        var allTopicStatistics: [String: DashboardTopicStatistic] = [:]
        for item in sortedRecordings {
            let itemTopics = RecordingItem.mergedTags(
                item.combinedTags,
                item.categoryName.map { [$0] } ?? []
            )
            for topic in itemTopics {
                let key = topic.normalizedForRecordingSearch
                guard !key.isEmpty else {
                    continue
                }
                var statistic = allTopicStatistics[key] ?? DashboardTopicStatistic(
                    id: key,
                    title: topic,
                    recordingCount: 0,
                    duration: 0
                )
                statistic.recordingCount += 1
                statistic.duration += TimeInterval(max(item.durationSeconds, 0))
                allTopicStatistics[key] = statistic
            }
        }
        topicStatistics = allTopicStatistics.values.sorted { lhs, rhs in
            if lhs.duration != rhs.duration {
                return lhs.duration > rhs.duration
            }
            if lhs.recordingCount != rhs.recordingCount {
                return lhs.recordingCount > rhs.recordingCount
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        var resolvedPlaces: [DashboardCollectedPlace] = []
        var placeIndexByName: [String: Int] = [:]
        for item in sortedRecordings {
            guard let location = item.location else {
                continue
            }

            let trimmedCity = location.city?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedCountry = location.country?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let city = trimmedCity?.isEmpty == false ? trimmedCity : nil
            let country = trimmedCountry?.isEmpty == false ? trimmedCountry : nil
            let namedParts = [city, country].compactMap(\.self)
            let nameIdentity = namedParts
                .joined(separator: "|")
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased()
            let coordinate = CLLocation(
                latitude: location.latitude,
                longitude: location.longitude
            )
            let nearbyIndex = resolvedPlaces.firstIndex { place in
                let storedCoordinate = CLLocation(
                    latitude: place.latitude,
                    longitude: place.longitude
                )
                return coordinate.distance(from: storedCoordinate) <= 20_000
            }
            let namedIndex = nameIdentity.isEmpty ? nil : placeIndexByName[nameIdentity]

            if let existingIndex = nearbyIndex ?? namedIndex {
                resolvedPlaces[existingIndex].recordingIDs.append(item.id)
                if !nameIdentity.isEmpty {
                    placeIndexByName[nameIdentity] = existingIndex
                }
                continue
            }

            let coordinateID = [
                (location.latitude * 100).rounded() / 100,
                (location.longitude * 100).rounded() / 100
            ]
            .map { String(format: "%.2f", $0) }
            .joined(separator: ",")
            let coordinateLabel = "\(location.latitude.formatted(.number.precision(.fractionLength(2))))°, \(location.longitude.formatted(.number.precision(.fractionLength(2))))°"
            let title = city ?? country ?? localized(L10n.Dashboard.pinnedPlace)
            let subtitle = city != nil ? country : (country == nil ? coordinateLabel : nil)
            let identity = "place|\(coordinateID)"
            if !nameIdentity.isEmpty {
                placeIndexByName[nameIdentity] = resolvedPlaces.count
            }
            resolvedPlaces.append(
                DashboardCollectedPlace(
                    id: identity,
                    title: title,
                    subtitle: subtitle,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    recordingIDs: [item.id],
                    latestRecordedAt: item.createdAt
                )
            )
        }
        collectedPlaces = resolvedPlaces.sorted { lhs, rhs in
            if lhs.recordingCount != rhs.recordingCount {
                return lhs.recordingCount > rhs.recordingCount
            }
            return lhs.latestRecordedAt > rhs.latestRecordedAt
        }
        locatedRecordingCount = sortedRecordings.reduce(0) { count, item in
            count + (item.location == nil ? 0 : 1)
        }

        let playableRecordings = sortedRecordings.filter { item in
            let resolvedDuration = max(
                TimeInterval(item.durationSeconds),
                playbackHistory[item.id]?.duration ?? 0
            )
            return item.importStatus == nil
                && !item.audioFileName.isEmpty
                && resolvedDuration > 0
        }
        let resumableItems = playableRecordings.compactMap { item -> DashboardContinueListeningItem? in
            guard let history = playbackHistory[item.id] else {
                return nil
            }
            let resolvedDuration = max(TimeInterval(item.durationSeconds), history.duration)
            guard let resumePosition = history.resumePosition(for: resolvedDuration) else {
                return nil
            }
            return DashboardContinueListeningItem(
                recording: item,
                position: resumePosition,
                duration: resolvedDuration,
                lastPlayedAt: history.lastPlayedAt,
                isResume: true
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.lastPlayedAt ?? .distantPast
            let rhsDate = rhs.lastPlayedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.recording.createdAt > rhs.recording.createdAt
        }

        if let resumableItem = resumableItems.first {
            continueListeningItem = resumableItem
        } else if let latestRecording = playableRecordings.first {
            continueListeningItem = DashboardContinueListeningItem(
                recording: latestRecording,
                position: 0,
                duration: max(
                    TimeInterval(latestRecording.durationSeconds),
                    playbackHistory[latestRecording.id]?.duration ?? 0
                ),
                lastPlayedAt: nil,
                isResume: false
            )
        } else {
            continueListeningItem = nil
        }
        replayRecording = weekRecordings.max { lhs, rhs in
            lhs.durationSeconds < rhs.durationSeconds
        } ?? sortedRecordings.first
        longestRecording = sortedRecordings.max { lhs, rhs in
            lhs.durationSeconds < rhs.durationSeconds
        }
        pendingOrganizationCount = sortedRecordings.filter { $0.categoryName == nil }.count
    }

    var compactDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropLeading
        if totalDuration >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.minute]
        }
        return formatter.string(from: max(totalDuration, 0)) ?? "0m"
    }

    var compactAllTimeDuration: String {
        dashboardDurationText(allTimeDuration)
    }

    var compactAverageDuration: String {
        guard !allRecordings.isEmpty else {
            return dashboardDurationText(0)
        }
        return dashboardDurationText(allTimeDuration / Double(allRecordings.count))
    }

    var compactLongestDuration: String {
        dashboardDurationText(TimeInterval(longestRecording?.durationSeconds ?? 0))
    }

    var activeDayCount: Int {
        dailyRecordingCounts.filter { $0 > 0 }.count
    }
}

private func dashboardDurationText(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropLeading
    if duration >= 3_600 {
        formatter.allowedUnits = [.hour, .minute]
    } else if duration >= 60 {
        formatter.allowedUnits = [.minute]
    } else {
        formatter.allowedUnits = [.second]
    }
    return formatter.string(from: max(duration, 0)) ?? "0s"
}

private struct DashboardIdleWaveform: View {
    var body: some View {
        Canvas { context, size in
            let barCount = 31
            let pitch = size.width / CGFloat(barCount)
            let center = CGFloat(barCount - 1) / 2

            for index in 0..<barCount {
                let distance = abs(CGFloat(index) - center) / max(center, 1)
                let envelope = pow(max(1 - distance, 0), 0.7)
                let rhythm = 0.38 + 0.62 * abs(sin(CGFloat(index) * 1.17))
                let barHeight = max(5, size.height * envelope * rhythm * 0.62)
                let rect = CGRect(
                    x: CGFloat(index) * pitch + pitch * 0.36,
                    y: (size.height - barHeight) / 2,
                    width: max(2, pitch * 0.28),
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: rect.width / 2),
                    with: .color(AppTheme.brand.opacity(0.28))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DashboardMetricTile: View {
    let systemImage: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .center, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.11), in: Circle())

            Text(value)
                .font(.redditSans(.headline, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(label)
                .font(.redditSans(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .center)
        .dashboardSurface(accent: tint)
    }
}

private struct DashboardVoiceStamp: View {
    let place: DashboardCollectedPlace
    let tint: Color

    static func tint(for index: Int) -> Color {
        switch index % 5 {
        case 0:
            return AppTheme.success
        case 1:
            return AppTheme.info
        case 2:
            return AppTheme.purple
        case 3:
            return AppTheme.warning
        default:
            return AppTheme.brand
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 17, weight: .semibold))

                Spacer(minLength: 8)

                if place.recordingCount > 1 {
                    Text("×\(place.recordingCount)")
                        .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.title)
                    .font(.redditSans(.subheadline, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = place.subtitle {
                    Text(subtitle)
                        .font(.redditSans(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(11)
        .frame(width: 116, height: 82, alignment: .leading)
        .background(
            tint.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    tint.opacity(0.34),
                    style: StrokeStyle(
                        lineWidth: 1,
                        lineCap: .round,
                        dash: [2.5, 3.5]
                    )
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardEmptyVoiceStamp: View {
    var body: some View {
        Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(AppTheme.success.opacity(0.72))
            .frame(width: 72, height: 64)
            .background(
                AppTheme.success.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        AppTheme.success.opacity(0.28),
                        style: StrokeStyle(
                            lineWidth: 1,
                            lineCap: .round,
                            dash: [2.5, 3.5]
                        )
                    )
            }
            .accessibilityHidden(true)
    }
}

private struct DashboardWeekChart: View {
    let dailyDurations: [TimeInterval]
    let dayLabels: [String]
    let highlightedDayIndex: Int
    var tint: Color = AppTheme.brand

    var body: some View {
        GeometryReader { proxy in
            let maxDuration = max(dailyDurations.max() ?? 0, 1)
            let chartHeight = max(proxy.size.height - 22, 1)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(dailyDurations.enumerated()), id: \.offset) { index, duration in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)

                        Capsule()
                            .fill(
                                index == highlightedDayIndex
                                    ? tint
                                    : tint.opacity(duration > 0 ? 0.22 : 0.08)
                            )
                            .frame(
                                height: max(
                                    5,
                                    chartHeight * CGFloat(duration / maxDuration)
                                )
                            )

                        Text(dayLabels.indices.contains(index) ? dayLabels[index] : "")
                            .font(.redditSans(.caption2, weight: .medium))
                            .foregroundStyle(
                                index == highlightedDayIndex
                                    ? tint
                                    : Color.secondary
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.Dashboard.thisWeekInVoice))
    }
}

private struct DashboardPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.14, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct DashboardInsightDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlace: DashboardCollectedPlace?
    let insight: DashboardInsight
    let snapshot: RecordingDashboardSnapshot
    let onOpenRecording: (RecordingItem.ID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    detailHero

                    switch insight {
                    case .recordings:
                        recordingsDetail
                    case .duration:
                        durationDetail
                    case .topics:
                        topicsDetail
                    case .places:
                        placesDetail
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle(insight.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $selectedPlace) { place in
                DashboardPlaceRecordingsView(
                    place: place,
                    recordings: recordings(in: place),
                    onOpenRecording: onOpenRecording
                )
            }
        }
    }

    private var detailHero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(insight.tint)
                .frame(width: 54, height: 54)
                .background(insight.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(heroValue)
                    .font(.redditSans(.largeTitle, weight: .bold).monospacedDigit())
                    .tracking(-0.7)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text(heroCaption)
                    .font(.redditSans(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .dashboardSurface(accent: insight.tint)
    }

    private var heroValue: String {
        switch insight {
        case .recordings:
            return "\(snapshot.weekRecordings.count)"
        case .duration:
            return snapshot.compactDuration
        case .topics:
            return "\(snapshot.topicCount)"
        case .places:
            return "\(snapshot.collectedPlaces.count)"
        }
    }

    private var heroCaption: String {
        switch insight {
        case .recordings, .duration, .topics:
            return localized(L10n.Dashboard.thisWeek)
        case .places:
            return localized(L10n.Dashboard.allTimeCollection)
        }
    }

    private var recordingsDetail: some View {
        VStack(spacing: 14) {
            dashboardChartCard(
                values: snapshot.dailyRecordingCounts,
                tint: AppTheme.brand,
                title: localized(L10n.Dashboard.recordingRhythm)
            )

            HStack(spacing: 10) {
                DashboardDetailMetric(
                    value: "\(snapshot.allRecordings.count)",
                    label: localized(L10n.Dashboard.allTime),
                    systemImage: "archivebox",
                    tint: AppTheme.brand
                )
                DashboardDetailMetric(
                    value: "\(snapshot.activeDayCount)",
                    label: localized(L10n.Dashboard.activeDays),
                    systemImage: "calendar",
                    tint: AppTheme.warning
                )
                DashboardDetailMetric(
                    value: "\(snapshot.locatedRecordingCount)",
                    label: localized(L10n.Dashboard.withLocation),
                    systemImage: "location",
                    tint: AppTheme.info
                )
            }

            recentRecordingsCard
        }
    }

    private var durationDetail: some View {
        VStack(spacing: 14) {
            dashboardChartCard(
                values: snapshot.dailyDurations,
                tint: AppTheme.purple,
                title: localized(L10n.Dashboard.listeningRhythm)
            )

            HStack(spacing: 10) {
                DashboardDetailMetric(
                    value: snapshot.compactAllTimeDuration,
                    label: localized(L10n.Dashboard.allTime),
                    systemImage: "sum",
                    tint: AppTheme.purple
                )
                DashboardDetailMetric(
                    value: snapshot.compactAverageDuration,
                    label: localized(L10n.Dashboard.averageSession),
                    systemImage: "divide",
                    tint: AppTheme.info
                )
                DashboardDetailMetric(
                    value: snapshot.compactLongestDuration,
                    label: localized(L10n.Dashboard.longestSession),
                    systemImage: "arrow.up.right",
                    tint: AppTheme.warning
                )
            }

            if let longestRecording = snapshot.longestRecording {
                recordingSpotlightCard(
                    recording: longestRecording,
                    eyebrow: localized(L10n.Dashboard.longestSession),
                    tint: AppTheme.purple
                )
            }
        }
    }

    @ViewBuilder
    private var topicsDetail: some View {
        if snapshot.topicStatistics.isEmpty {
            DashboardInsightEmptyState(
                systemImage: "tag",
                title: localized(L10n.Dashboard.noTopics),
                detail: localized(L10n.Dashboard.moreStatisticsHint),
                tint: AppTheme.success
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.Dashboard.timeByTopic)
                        .font(.redditSans(.headline, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(
                        localizedFormat(
                            L10n.Dashboard.topicsCountFormat,
                            snapshot.topicStatistics.count
                        )
                    )
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                }

                let maximumDuration = max(snapshot.topicStatistics.first?.duration ?? 0, 1)
                ForEach(Array(snapshot.topicStatistics.prefix(10).enumerated()), id: \.element.id) { index, statistic in
                    DashboardTopicBar(
                        statistic: statistic,
                        maximumDuration: maximumDuration,
                        tint: DashboardVoiceStamp.tint(for: index)
                    )
                }
            }
            .padding(16)
            .dashboardSurface(accent: AppTheme.success)
        }
    }

    @ViewBuilder
    private var placesDetail: some View {
        if snapshot.collectedPlaces.isEmpty {
            DashboardInsightEmptyState(
                systemImage: "mappin.and.ellipse",
                title: localized(L10n.Dashboard.firstPlaceHint),
                detail: localized(L10n.Dashboard.moreStatisticsHint),
                tint: AppTheme.info
            )
        } else {
            VStack(spacing: 14) {
                DashboardVoiceFootprintMap(
                    places: snapshot.collectedPlaces,
                    onOpenPlace: openPlace
                )
                .frame(height: 250)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: AppTheme.cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                        .stroke(AppTheme.info.opacity(0.18), lineWidth: 1)
                }

                HStack(spacing: 10) {
                    DashboardDetailMetric(
                        value: "\(snapshot.collectedPlaces.count)",
                        label: localized(L10n.Dashboard.placesMetric),
                        systemImage: "map",
                        tint: AppTheme.info
                    )
                    DashboardDetailMetric(
                        value: "\(snapshot.locatedRecordingCount)",
                        label: localized(L10n.Dashboard.recordingsMetric),
                        systemImage: "waveform",
                        tint: AppTheme.brand
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Dashboard.voiceStampCollection)
                        .font(.redditSans(.headline, weight: .semibold))
                        .padding(.bottom, 6)

                    ForEach(Array(snapshot.collectedPlaces.enumerated()), id: \.element.id) { index, place in
                        Button {
                            openPlace(place)
                        } label: {
                            DashboardPlaceRankRow(
                                place: place,
                                rank: index + 1,
                                tint: DashboardVoiceStamp.tint(for: index)
                            )
                        }
                        .buttonStyle(DashboardPressButtonStyle())

                        if index < snapshot.collectedPlaces.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(16)
                .dashboardSurface(accent: AppTheme.info)
            }
        }
    }

    private func openPlace(_ place: DashboardCollectedPlace) {
        guard let recordingID = place.recordingIDs.first else {
            return
        }

        HapticFeedback.play(.navigation)
        if place.recordingIDs.count == 1 {
            onOpenRecording(recordingID)
        } else {
            selectedPlace = place
        }
    }

    private func recordings(in place: DashboardCollectedPlace) -> [RecordingItem] {
        let recordingIDs = Set(place.recordingIDs)
        return snapshot.allRecordings.filter { recordingIDs.contains($0.id) }
    }

    private func dashboardChartCard(
        values: [TimeInterval],
        tint: Color,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.redditSans(.headline, weight: .semibold))

            DashboardWeekChart(
                dailyDurations: values,
                dayLabels: snapshot.dayLabels,
                highlightedDayIndex: snapshot.currentWeekdayIndex,
                tint: tint
            )
            .frame(height: 124)
        }
        .padding(16)
        .dashboardSurface(accent: tint)
    }

    @ViewBuilder
    private var recentRecordingsCard: some View {
        if !snapshot.allRecordings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Dashboard.recentRecordings)
                    .font(.redditSans(.headline, weight: .semibold))
                    .padding(.bottom, 6)

                ForEach(Array(snapshot.allRecordings.prefix(4).enumerated()), id: \.element.id) { index, recording in
                    Button {
                        onOpenRecording(recording.id)
                    } label: {
                        DashboardRecordingRow(recording: recording, tint: AppTheme.brand)
                    }
                    .buttonStyle(DashboardPressButtonStyle())

                    if index < min(snapshot.allRecordings.count, 4) - 1 {
                        Divider()
                            .padding(.leading, 42)
                    }
                }
            }
            .padding(16)
            .dashboardSurface(accent: AppTheme.brand)
        }
    }

    private func recordingSpotlightCard(
        recording: RecordingItem,
        eyebrow: String,
        tint: Color
    ) -> some View {
        Button {
            onOpenRecording(recording.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(recording.displayName)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(dashboardDurationText(TimeInterval(recording.durationSeconds)))
                    .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .dashboardSurface(accent: tint)
        }
        .buttonStyle(DashboardPressButtonStyle())
    }
}

private struct DashboardDetailMetric: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.redditSans(.headline, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(label)
                .font(.redditSans(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .dashboardSurface(accent: tint)
    }
}

private struct DashboardRecordingRow: View {
    let recording: RecordingItem
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.displayName)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(dashboardDurationText(TimeInterval(recording.durationSeconds)))
                .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

private struct DashboardPlaceRecordingsView: View {
    let place: DashboardCollectedPlace
    let recordings: [RecordingItem]
    let onOpenRecording: (RecordingItem.ID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                placeHeader

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Dashboard.voiceStampCollection)
                        .font(.redditSans(.headline, weight: .semibold))
                        .padding(.bottom, 6)

                    ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                        Button {
                            HapticFeedback.play(.navigation)
                            onOpenRecording(recording.id)
                        } label: {
                            DashboardRecordingRow(
                                recording: recording,
                                tint: AppTheme.info
                            )
                        }
                        .buttonStyle(DashboardPressButtonStyle())

                        if index < recordings.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
                .padding(16)
                .dashboardSurface(accent: AppTheme.info)
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(place.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var placeHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.info)
                .frame(width: 50, height: 50)
                .background(AppTheme.info.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(place.title)
                    .font(.redditSans(.title3, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(
                    localizedFormat(
                        L10n.Dashboard.recordingsCountFormat,
                        recordings.count
                    )
                )
                .font(.redditSans(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let subtitle = place.subtitle {
                Text(subtitle)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.info.opacity(0.10), in: Capsule())
            }
        }
        .padding(16)
        .dashboardSurface(accent: AppTheme.info)
    }
}

private struct DashboardTopicBar: View {
    let statistic: DashboardTopicStatistic
    let maximumDuration: TimeInterval
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(statistic.title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(dashboardDurationText(statistic.duration))
                    .font(.redditSans(.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(tint)
            }

            GeometryReader { proxy in
                let progress = min(max(statistic.duration / maximumDuration, 0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.09))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.58)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
            .frame(height: 8)

            Text(
                localizedFormat(
                    L10n.Dashboard.recordingsCountFormat,
                    statistic.recordingCount
                )
            )
            .font(.redditSans(.caption2, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardPlaceRankRow: View {
    let place: DashboardCollectedPlace
    let rank: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Text("\(rank)")
                .font(.redditSans(.caption, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(place.title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = place.subtitle {
                    Text(subtitle)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text("×\(place.recordingCount)")
                .font(.redditSans(.caption, weight: .bold).monospacedDigit())
                .foregroundStyle(tint)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

private struct DashboardVoiceFootprintMap: View {
    let places: [DashboardCollectedPlace]
    let onOpenPlace: (DashboardCollectedPlace) -> Void

    var body: some View {
        Map(initialPosition: .region(region)) {
            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                Annotation(
                    place.title,
                    coordinate: CLLocationCoordinate2D(
                        latitude: place.latitude,
                        longitude: place.longitude
                    )
                ) {
                    Button {
                        onOpenPlace(place)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.regularMaterial)
                                .frame(width: 38, height: 38)

                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(DashboardVoiceStamp.tint(for: index))
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    DashboardVoiceStamp.tint(for: index).opacity(0.38),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel(Text(L10n.Dashboard.collectionMap))
    }

    private var region: MKCoordinateRegion {
        let latitudes = places.map(\.latitude)
        let longitudes = places.map(\.longitude)
        guard let minimumLatitude = latitudes.min(),
              let maximumLatitude = latitudes.max(),
              let minimumLongitude = longitudes.min(),
              let maximumLongitude = longitudes.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 300)
            )
        }

        let latitudeDelta = max((maximumLatitude - minimumLatitude) * 1.55, 0.12)
        let longitudeDelta = max((maximumLongitude - minimumLongitude) * 1.55, 0.12)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: min(latitudeDelta, 160),
                longitudeDelta: min(longitudeDelta, 340)
            )
        )
    }
}

private struct DashboardInsightEmptyState: View {
    let systemImage: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 58, height: 58)
                .background(tint.opacity(0.11), in: Circle())

            Text(title)
                .font(.redditSans(.headline, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .dashboardSurface(accent: tint)
    }
}

private struct WeeklyRecordingRecapView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: RecordingDashboardSnapshot
    let onOpenRecording: (RecordingItem.ID) -> Void
    let onShowRecordings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Dashboard.thisWeekInVoice)
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(snapshot.compactDuration)
                            .font(.redditSans(.largeTitle, weight: .bold).monospacedDigit())
                            .tracking(-0.8)

                        DashboardWeekChart(
                            dailyDurations: snapshot.dailyDurations,
                            dayLabels: snapshot.dayLabels,
                            highlightedDayIndex: snapshot.currentWeekdayIndex
                        )
                        .frame(height: 118)
                    }
                    .padding(18)
                    .dashboardSurface(accent: AppTheme.brand)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Dashboard.mostDiscussed)
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(
                            snapshot.topTopics.isEmpty
                                ? localized(L10n.Dashboard.noTopics)
                                : snapshot.topTopics.joined(separator: " · ")
                        )
                        .font(.redditSans(.title3, weight: .bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dashboardSurface(accent: AppTheme.success)

                    if let replayRecording = snapshot.replayRecording {
                        Button {
                            onOpenRecording(replayRecording.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(AppTheme.brand, in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.Dashboard.worthReplaying)
                                        .font(.redditSans(.caption, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(replayRecording.displayName)
                                        .font(.redditSans(.subheadline, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .dashboardSurface(accent: AppTheme.brand)
                        }
                        .buttonStyle(DashboardPressButtonStyle())
                    }

                    if snapshot.pendingOrganizationCount > 0 {
                        Button {
                            onShowRecordings()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "tray.full")
                                Text(L10n.Dashboard.organizeUncategorized)
                                Spacer(minLength: 8)
                                Text(
                                    localizedFormat(
                                        L10n.Dashboard.pendingOrganizationFormat,
                                        snapshot.pendingOrganizationCount
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(AppTheme.info)
                            .padding(16)
                            .dashboardSurface(accent: AppTheme.info)
                        }
                        .buttonStyle(DashboardPressButtonStyle())
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle(localized(L10n.Dashboard.weeklyRecap))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension TranscriptionAudioInput {
    var systemImage: String {
        switch self {
        case .microphone:
            return "mic"
        case .screenAudio:
            return "rectangle.on.rectangle.angled"
        }
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
    @Binding var languageID: String
    @Binding var categoryName: String
    @Binding var keyPoints: String
    @Binding var tags: [String]
    @Binding var generatedIntelligence: RecordingIntelligence?
    @Binding var includesLocation: Bool
    @ObservedObject var locationProvider: RecordingLocationProvider
    let isSaving: Bool
    @Binding var saveErrorMessage: String?
    let languageOptions: [TranscriptionLanguage]
    let availableCategories: [String]
    let showsTitleGeneration: Bool
    let onGenerateTitle: () async throws -> RecordingTitleSuggestion
    let onSave: () -> Void
    let onDiscard: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGeneratingTitle = false
    @State private var titleGenerationErrorMessage: String?
    @State private var isShowingLanguagePicker = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case name
        case summary
        case keyPoints
    }

    private var summaryText: Binding<String> {
        Binding(
            get: {
                generatedIntelligence?.summary ?? ""
            },
            set: { newValue in
                if var intelligence = generatedIntelligence {
                    intelligence.summary = newValue
                    generatedIntelligence = intelligence
                } else if !newValue.isEmpty {
                    generatedIntelligence = RecordingIntelligence(
                        summary: newValue,
                        tags: tags,
                        generatedAt: Date()
                    )
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    primaryInformationCard
                    contentCard
                    metadataCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSaving)
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(L10n.Transcription.saveRecording))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        focusedField = nil
                        onDiscard()
                    } label: {
                        Text(L10n.Transcription.discard)
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        focusedField = nil
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
                    .tint(AppTheme.brand)
                }

                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(localized(L10n.Common.done)) {
                        focusedField = nil
                    }
                }
                #endif
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: focusedField
        )
        .sheet(isPresented: $isShowingLanguagePicker) {
            RecordingRetranscriptionLanguagePicker(
                title: localized(L10n.Settings.transcriptionLanguage),
                recordingLanguageID: languageID,
                languages: languageOptions,
                onCancel: {
                    isShowingLanguagePicker = false
                },
                onSelect: { language in
                    languageID = language.id
                    isShowingLanguagePicker = false
                    HapticFeedback.play(.menuSelection)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        .alert(
            localized(L10n.Transcription.saveRecordingFailed),
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? localized(L10n.Transcription.saveRecordingFailedMessage))
        }
    }

    private var primaryInformationCard: some View {
        let selectedLanguage = languageOptions.first(where: { $0.id == languageID })
            ?? TranscriptionLanguage(id: languageID).baseLanguage
        let appearance = categoryName.isEmpty
            ? nil
            : RecordingCategoryAppearanceCatalog.appearance(for: categoryName)

        return VStack(alignment: .leading, spacing: 0) {
            recordingSaveFieldHeader(
                L10n.Recordings.recordingName,
                systemImage: "pencil",
                tint: AppTheme.brand
            )

            HStack(spacing: 8) {
                TextField(localized(L10n.Recordings.recordingName), text: $recordingName)
                    .font(.redditSans(.headline, weight: .semibold))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .name)
                    .onSubmit {
                        focusedField = nil
                    }

                if showsTitleGeneration {
                    Button {
                        generateTitleAndTags()
                    } label: {
                        Group {
                            if isGeneratingTitle {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("AI")
                                        .font(.redditSans(.caption, weight: .bold))
                                }
                            }
                        }
                        .foregroundStyle(AppTheme.brand)
                        .frame(minWidth: 48)
                        .frame(height: 36)
                        .background(
                            AppTheme.brand.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGenerateTitle)
                    .accessibilityLabel(localized(L10n.Transcription.generateTitleAndTagsAccessibility))
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, showsTitleGeneration ? 8 : 13)
            .frame(minHeight: 52)
            .recordingSaveInputSurface(
                isFocused: focusedField == .name,
                tint: AppTheme.brand
            )
            .padding(.top, 10)
            .padding(.bottom, 14)

            recordingSaveDivider

            Button {
                focusedField = nil
                isShowingLanguagePicker = true
                HapticFeedback.play(.menuSelection)
            } label: {
                recordingSaveSelectionRow(
                    title: L10n.Settings.transcriptionLanguage,
                    value: selectedLanguage.displayName,
                    systemImage: "globe",
                    tint: AppTheme.info,
                    trailingSystemImage: "chevron.right"
                )
            }
            .buttonStyle(.plain)

            recordingSaveDivider

            RecordingCategoryMenu(
                selection: categoryName.isEmpty ? nil : categoryName,
                categories: RecordingCategoryCatalog.normalized(
                    availableCategories + [categoryName]
                ),
                onSelect: { selectedName in
                    categoryName = selectedName ?? ""
                    HapticFeedback.play(.menuSelection)
                }
            ) {
                recordingSaveSelectionRow(
                    title: L10n.Recordings.categoryName,
                    value: categoryName.isEmpty
                        ? localized(L10n.Recordings.uncategorized)
                        : categoryName,
                    systemImage: appearance?.iconName ?? "tray",
                    tint: appearance?.color ?? Color.secondary,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        }
        .recordingSaveSectionSurface()
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            recordingSaveTextArea(
                title: L10n.Recordings.summary,
                placeholder: L10n.Recordings.summaryPlaceholder,
                text: summaryText,
                field: .summary,
                systemImage: "text.alignleft",
                tint: AppTheme.purple,
                minimumHeight: 92
            )

            Divider()
                .overlay(AppTheme.subtleBorder)

            recordingSaveTextArea(
                title: L10n.Recordings.keyPoints,
                placeholder: L10n.Recordings.keyPointsPlaceholder,
                text: $keyPoints,
                field: .keyPoints,
                systemImage: "list.bullet.clipboard",
                tint: AppTheme.warning,
                minimumHeight: 80
            )
        }
        .recordingSaveSectionSurface()
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                RecordingTagsEditor(tags: $tags)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tag")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.info)
                        .frame(width: 30, height: 30)
                        .background(
                            AppTheme.info.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.Recordings.tags)
                            .font(.redditSans(.caption))
                            .foregroundStyle(.secondary)

                        recordingSaveTagPreview
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 62)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            recordingSaveDivider

            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Color.secondary.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                Text(L10n.Recordings.audioDuration)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(TranscriptionLine.formatTimestamp(Double(draft.durationSeconds)))
                    .font(
                        .redditSans(.subheadline, weight: .semibold)
                            .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 58)
            .accessibilityElement(children: .combine)

            recordingSaveDivider

            Toggle(isOn: $includesLocation) {
                HStack(spacing: 12) {
                    Image(systemName: "location")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 30, height: 30)
                        .background(
                            AppTheme.success.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )

                    Text(L10n.Recordings.addLocation)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .tint(AppTheme.brand)
            .frame(minHeight: 58)

            if includesLocation {
                Divider()
                    .overlay(AppTheme.subtleBorder)
                    .padding(.bottom, 14)

                RecordingLocationPreview(locationProvider: locationProvider)
            }
        }
        .recordingSaveSectionSurface()
    }

    private var recordingSaveDivider: some View {
        Divider()
            .overlay(AppTheme.subtleBorder)
            .padding(.leading, 42)
    }

    private func recordingSaveFieldHeader(
        _ title: LocalizedStringResource,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 27, height: 27)
                .background(
                    tint.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Text(title)
                .font(.redditSans(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private func recordingSaveSelectionRow(
        title: LocalizedStringResource,
        value: String,
        systemImage: String,
        tint: Color,
        trailingSystemImage: String?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    tint.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func recordingSaveTextArea(
        title: LocalizedStringResource,
        placeholder: LocalizedStringResource,
        text: Binding<String>,
        field: FocusedField,
        systemImage: String,
        tint: Color,
        minimumHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            recordingSaveFieldHeader(
                title,
                systemImage: systemImage,
                tint: tint
            )

            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    Text(placeholder)
                        .font(.redditSans(.body))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: text)
                    .font(.redditSans(.body))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .focused($focusedField, equals: field)
                    .padding(8)
                    .frame(minHeight: minimumHeight)
                    .background(Color.clear)
            }
            .recordingSaveInputSurface(
                isFocused: focusedField == field,
                tint: tint
            )
        }
    }

    @ViewBuilder
    private var recordingSaveTagPreview: some View {
        if tags.isEmpty {
            Text(L10n.Recordings.notAdded)
                .font(.redditSans(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 5) {
                ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                    Text(tag)
                        .font(.redditSans(.caption2, weight: .semibold))
                        .foregroundStyle(AppTheme.info)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(AppTheme.info.opacity(0.11), in: Capsule())
                }

                if tags.count > 2 {
                    Text("+\(tags.count - 2)")
                        .font(.redditSans(.caption2, weight: .bold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var canGenerateTitle: Bool {
        !isSaving
            && !isGeneratingTitle
            && !draft.lines.plainTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                let currentSummary = generatedIntelligence?.summary.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
                let suggestedSummary = suggestion.summary?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
                if currentSummary.isEmpty, !suggestedSummary.isEmpty {
                    generatedIntelligence = RecordingIntelligence(
                        summary: suggestedSummary,
                        tags: mergedTags,
                        generatedAt: Date()
                    )
                }
                HapticFeedback.play(.analysisComplete)
            } catch {
                titleGenerationErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isGeneratingTitle = false
        }
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

private struct RecordingSaveInputSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isFocused: Bool
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .background(AppTheme.elevatedBackground, in: shape)
            .overlay {
                shape.strokeBorder(
                    isFocused ? tint.opacity(0.52) : AppTheme.subtleBorder,
                    lineWidth: isFocused ? 1.5 : 1
                )
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.16),
                value: isFocused
            )
    }
}

private extension View {
    func recordingSaveSectionSurface() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
            }
    }

    func recordingSaveInputSurface(
        isFocused: Bool,
        tint: Color
    ) -> some View {
        modifier(
            RecordingSaveInputSurfaceModifier(
                isFocused: isFocused,
                tint: tint
            )
        )
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var finalStore: LiveFinalTranscriptStore
    @ObservedObject var interimStore: LiveInterimTranscriptStore
    let translatedTextByLineID: [TranscriptionLine.ID: String]
    let translatedLineSignatures: [TranscriptionLine.ID: String]
    let isTranslating: Bool
    let selectedTranslationLanguage: TranscriptionLanguage?
    let isRecording: Bool
    let isPaused: Bool
    let isPreparing: Bool
    let onEditFinalLine: (TranscriptionLine) -> Void

    private var totalLineCount: Int {
        finalStore.lines.count + (interimStore.line == nil ? 0 : 1)
    }

    private var emptyStateStatus: LocalizedStringResource {
        if isPreparing {
            return L10n.RecordingStatus.startingRecorder
        }
        if isRecording {
            return isPaused
                ? L10n.RecordingStatus.paused
                : L10n.RecordingStatus.waitingForSpeech
        }
        return L10n.Transcription.startRecording
    }

    private var animatesEmptyState: Bool {
        isPreparing || (isRecording && !isPaused)
    }

    var body: some View {
        ZStack {
            if totalLineCount > 0 {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            Color.clear
                                .frame(height: 1)
                                .id("transcript-top")

                            LiveInterimTranscriptRow(
                                interimStore: interimStore,
                                isShimmering: isRecording && !isPaused
                            )

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
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.76),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .onChange(of: totalLineCount) { _, _ in
                        if reduceMotion {
                            scrollProxy.scrollTo("transcript-top", anchor: .top)
                        } else {
                            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                                scrollProxy.scrollTo("transcript-top", anchor: .top)
                            }
                        }
                    }
                }
                .transition(.opacity)
            } else {
                LiveTranscriptSkeletonView(
                    isAnimated: animatesEmptyState,
                    statusText: emptyStateStatus
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: totalLineCount > 0)
    }
}

private struct LiveInterimTranscriptRow: View {
    @ObservedObject var interimStore: LiveInterimTranscriptStore
    let isShimmering: Bool

    var body: some View {
        if let line = interimStore.line {
            TranscriptionLineRow(
                line: line,
                translatedText: nil,
                isShowingTranslation: false,
                shimmersText: isShimmering,
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
                shimmersText: false,
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
    let shimmersText: Bool
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
                Text(displayedText)
                    .font(.redditSans(.body))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liveTranscriptShimmer(isActive: shimmersText)

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

    private var displayedText: String {
        translatedText ?? line.text
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

private struct SystemAudioStateBadge: View {
    let state: SystemAudioSessionState

    private var titleResource: LocalizedStringResource {
        switch state {
        case .idle:
            return L10n.ScreenAudio.statusReady
        case .awaitingUserApproval:
            return L10n.ScreenAudio.statusApproval
        case .waitingForAudio:
            return L10n.ScreenAudio.statusWaiting
        case .capturing:
            return L10n.ScreenAudio.statusCapturing
        case .paused:
            return L10n.ScreenAudio.statusPaused
        case .stopping:
            return L10n.ScreenAudio.statusStopping
        case .failed:
            return L10n.ScreenAudio.statusFailed
        }
    }

    private var tint: Color {
        switch state {
        case .capturing:
            return AppTheme.danger
        case .awaitingUserApproval, .waitingForAudio, .paused, .stopping:
            return AppTheme.warning
        case .failed:
            return AppTheme.danger
        case .idle:
            return AppTheme.success
        }
    }

    private var systemImage: String {
        switch state {
        case .idle:
            return "checkmark.circle"
        case .awaitingUserApproval:
            return "person.crop.circle.badge.questionmark"
        case .waitingForAudio:
            return "waveform.badge.magnifyingglass"
        case .capturing:
            return "record.circle"
        case .paused:
            return "pause.circle"
        case .stopping:
            return "stop.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
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
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay {
            Capsule().stroke(tint.opacity(0.18), lineWidth: 1)
        }
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

private struct RecorderDockBackgroundShape: Shape {
    var width: CGFloat

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let resolvedWidth = min(max(width, rect.height), rect.width)
        let shapeRect = CGRect(
            x: rect.midX - resolvedWidth / 2,
            y: rect.minY,
            width: resolvedWidth,
            height: rect.height
        )
        return Path(
            roundedRect: shapeRect,
            cornerRadius: rect.height / 2,
            style: .continuous
        )
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
    var usesHDRPressHighlight = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if usesHDRPressHighlight {
                    Circle()
                        .fill(AppTheme.hdrDanger)
                        .overlay {
                            Circle()
                                .stroke(AppTheme.hdrWhite.opacity(0.68), lineWidth: 1)
                        }
                        .shadow(
                            color: AppTheme.hdrDanger.opacity(0.62),
                            radius: 12
                        )
                        .opacity(configuration.isPressed && isEnabled ? 1 : 0)
                        .animation(
                            reduceMotion
                                ? nil
                                : configuration.isPressed
                                    ? .easeOut(duration: 0.10)
                                    : .easeOut(duration: 0.12),
                            value: configuration.isPressed
                        )
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.58)
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.12, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct RecorderLaunchGeometryModifier: ViewModifier {
    let namespace: Namespace.ID
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.matchedGeometryEffect(
                id: "primary-recorder-dock",
                in: namespace,
                properties: .position,
                anchor: .center
            )
        } else {
            content
        }
    }
}

private struct AssistantHeaderGeometryModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .leading
            )
        } else {
            content
        }
    }
}

private extension View {
    func dashboardSurface(accent: Color) -> some View {
        background {
            let shape = RoundedRectangle(
                cornerRadius: AppTheme.cornerRadius,
                style: .continuous
            )

            shape
                .fill(AppTheme.cardBackground)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.085),
                                accent.opacity(0.028),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(accent.opacity(0.16), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(0.045),
                radius: 8,
                y: 3
            )
    }

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
    let transcriber = LiveTranscriptionManager()
    let captionStore = CaptionPresentationStore()
    TranscriptionView(
        transcriber: transcriber,
        recordingStore: RecordingStore(),
        systemAudioCoordinator: SystemAudioSessionCoordinator(
            transcriber: transcriber,
            captionStore: captionStore
        ),
        captionStore: captionStore,
        captionPiPController: CaptionPiPController(store: captionStore),
        externalPendingRecordingDraft: .constant(nil),
        onOpenRecording: { _ in },
        onShowRecordings: {}
    )
    .font(.redditSans(.body))
    .tint(AppTheme.brand)
}
#endif
