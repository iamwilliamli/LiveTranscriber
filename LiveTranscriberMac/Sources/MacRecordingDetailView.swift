import AppKit
import SwiftUI
import TranscriberDomain
import Translation

/// Full-parity recording detail: playback, transcript with speakers and
/// editing, AI summary/meeting analysis/chat, export, and every
/// retranscription engine, mirroring the iOS RecordingDetailView.
struct MacRecordingDetailView: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController

    @StateObject private var chatEngine = RecordingChatEngine()

    @State private var page: RecordingDetailPage = .transcript
    @State private var transcriptLines: [StoredTranscriptLine] = []
    @State private var isLoadingTranscript = false
    @State private var isAnalyzingSummary = false
    @State private var isAnalyzingMeeting = false
    @State private var actionErrorMessage: String?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingGemini = false
    @State private var isConfirmingGeminiRestore = false
    @State private var isShowingEditSheet = false
    @State private var isShowingAudioInfo = false
    @State private var isShowingAudioEvents = false
    @State private var isAnalyzingAudioEvents = false
    @State private var lineEdit: MacTranscriptLineEdit?
    @State private var speakerPropagationRequest: MacTranscriptSpeakerPropagationRequest?
    @State private var reminderDraftRequest: MacReminderDraftRequest?
    @State private var isAddingReminders = false
    @State private var reminderConfirmationText: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var selectedTranslationLanguage: TranscriptionLanguage?
    @State private var translationLanguages: [TranscriptionLanguage] = []
    @State private var translatedTranscriptByLineID: [StoredTranscriptLine.ID: String] = [:]
    @State private var translatedTranscriptCache: [String: [StoredTranscriptLine.ID: String]] = [:]
    @State private var isTranslatingTranscript = false
    @State private var translationErrorMessage: String?
    @State private var isShowingManualGeminiImport = false
    @State private var manualGeminiJSONText = ""
    @State private var manualGeminiImportErrorMessage: String?
    @State private var appleSpeechLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @State private var downloadedWhisperModels: [LocalWhisperModel] = []
    @State private var whisperLanguagesByModelID: [String: [TranscriptionLanguage]] = [:]
    @State private var isQwenAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
    @State private var isMOSSAvailable = MOSSLocalModelManager.currentStatus().isAvailable
    @State private var isShowingAppleRetranscriptionPicker = false
    @State private var isShowingWhisperRetranscriptionPicker = false
    @State private var pendingSpeechLocaleReleaseRequest: SpeechLocaleReleaseRequest?
    @State private var scrubbedPlaybackTime: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var currentItem: RecordingItem {
        store.recording(withID: item.id) ?? item
    }

    private var speakerPresentations: [TranscriptSpeakerPresentation] {
        TranscriptSpeakerPresentation.makePresentations(for: transcriptLines)
    }

    private var isBusyTranscribing: Bool {
        currentItem.importStatus?.isFailed == false
    }

    private var playbackAmbientState: AmbientActivityState {
        guard player.isLoaded,
              player.currentItem?.id == currentItem.id else {
            return .standby
        }
        guard !player.isPlaying else {
            return .active
        }

        let playbackTime = player.currentTime
        let isBetweenStartAndEnd = playbackTime > 0.05
            && (player.duration <= 0 || playbackTime < player.duration - 0.05)
        return isBetweenStartAndEnd ? .paused : .standby
    }

    var body: some View {
        ZStack {
            AmbientActivityBackground(state: playbackAmbientState)

            VStack(spacing: 0) {
                HStack {
                    Picker(selection: $page) {
                        Text(L10n.Recordings.transcript)
                            .tag(RecordingDetailPage.transcript)
                        Text(L10n.Recordings.aiAnalysis)
                            .tag(RecordingDetailPage.aiAnalysis)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider()
                }

                ZStack {
                    transcriptPage
                        .opacity(page == .transcript ? 1 : 0)
                        .offset(x: page == .transcript ? 0 : -36)
                        .allowsHitTesting(page == .transcript)
                        .accessibilityHidden(page != .transcript)

                    RecordingAIAnalysisPage(
                        engine: chatEngine,
                        isAvailable: store.summaryProviderAvailability.hasAnyAvailableProvider,
                        makeContext: {
                            RecordingChatContext(
                                transcript: store.transcriptText(for: currentItem),
                                summary: currentItem.intelligence?.summary,
                                languageName: currentItem.languageName
                            )
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 16) {
                            intelligenceCard
                            meetingAnalysisCard
                        }
                    }
                    .opacity(page == .aiAnalysis ? 1 : 0)
                    .offset(x: page == .aiAnalysis ? 0 : 36)
                    .allowsHitTesting(page == .aiAnalysis)
                    .accessibilityHidden(page != .aiAnalysis)
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .easeInOut(duration: 0.22),
            value: page
        )
        .toolbar {
            ToolbarItemGroup {
                detailActionsMenu
            }
        }
        .task(id: currentItem.transcriptFileName + "\(currentItem.lineCount)") {
            await loadTranscript()
        }
        .task(id: currentItem.id) {
            preparePlayerIfNeeded()
        }
        .task {
            chatEngine.configure(recordingID: currentItem.id)
            translationLanguages = await AppleTranslationLanguages.supportedLanguages()
            appleSpeechLanguages = await AppleSpeechTranscriptionSupport.supportedLanguages()
            await refreshRetranscriptionAvailability()
        }
        .translationTask(translationConfiguration) { session in
            await translateTranscript(using: session)
        }
        .sheet(isPresented: $isShowingEditSheet) {
            MacRecordingEditSheet(item: currentItem, store: store) { message in
                actionErrorMessage = message
            }
        }
        .sheet(isPresented: $isShowingAudioInfo) {
            MacAudioInfoSheet(item: currentItem, store: store)
        }
        .sheet(isPresented: $isShowingAudioEvents) {
            MacAudioEventsSheet(
                analysis: currentItem.audioEventAnalysis,
                isAnalyzing: isAnalyzingAudioEvents,
                onAnalyze: analyzeAudioEvents,
                onSeek: { event in
                    preparePlayerIfNeeded()
                    player.seek(to: event.startTime)
                    isShowingAudioEvents = false
                }
            )
        }
        .sheet(isPresented: $isShowingManualGeminiImport) {
            MacManualGeminiJSONImportSheet(
                jsonText: $manualGeminiJSONText,
                errorMessage: manualGeminiImportErrorMessage,
                onPaste: pasteManualGeminiJSONFromClipboard,
                onImport: importManualGeminiJSON
            )
        }
        .sheet(isPresented: $isShowingAppleRetranscriptionPicker) {
            MacRetranscriptionLanguagePicker(
                title: String(localized: L10n.Recordings.retranscribe),
                recordingLanguageID: currentItem.languageID,
                languages: appleSpeechLanguages,
                onSelect: { language in
                    isShowingAppleRetranscriptionPicker = false
                    requestAppleRetranscription(language: language)
                }
            )
        }
        .sheet(isPresented: $isShowingWhisperRetranscriptionPicker) {
            MacWhisperRetranscriptionPicker(
                recordingLanguageID: currentItem.languageID,
                downloadedModels: downloadedWhisperModels,
                languageOptionsByModelID: whisperLanguagesByModelID,
                onSelect: { language, model in
                    isShowingWhisperRetranscriptionPicker = false
                    runAction {
                        try await store.retranscribeWithLocalWhisper(
                            currentItem,
                            language: language,
                            model: model
                        )
                    }
                }
            )
        }
        .sheet(item: $reminderDraftRequest) { request in
            MacReminderDraftReviewSheet(
                initialDrafts: request.drafts,
                isSaving: isAddingReminders,
                onSave: saveReminderDrafts,
                onCancel: {
                    reminderDraftRequest = nil
                }
            )
        }
        .sheet(item: $lineEdit) { edit in
            MacTranscriptLineEditHost(
                edit: edit,
                speakerPresentations: speakerPresentations,
                onSave: { text, speakerID in
                    saveTranscriptLine(edit: edit, text: text, speakerID: speakerID)
                }
            )
        }
        .confirmationDialog(
            String(localized: L10n.Recordings.transcriptSpeakerPropagationTitle),
            isPresented: Binding(
                get: { speakerPropagationRequest != nil },
                set: { if !$0 { speakerPropagationRequest = nil } }
            )
        ) {
            if let request = speakerPropagationRequest {
                Button(
                    String(
                        format: String(localized: L10n.Recordings.transcriptSpeakerPropagationFollowingActionFormat),
                        request.followingLines.count
                    )
                ) {
                    performTranscriptLineEdit(request, propagatingSpeakerTo: request.followingLines)
                }

                Button(String(localized: L10n.Recordings.transcriptSpeakerPropagationCurrentOnlyAction)) {
                    performTranscriptLineEdit(request, propagatingSpeakerTo: [])
                }
            }

            Button(String(localized: L10n.Common.cancel), role: .cancel) {
                speakerPropagationRequest = nil
            }
        } message: {
            if let request = speakerPropagationRequest {
                Text(
                    verbatim: String(
                        format: String(localized: L10n.Recordings.transcriptSpeakerPropagationMessageFormat),
                        request.followingLines.count
                    )
                )
            }
        }
        .confirmationDialog(
            String(localized: L10n.Recordings.deleteRecording),
            isPresented: $isConfirmingDelete
        ) {
            Button(role: .destructive) {
                deleteRecording()
            } label: {
                Text(L10n.Common.delete)
            }
        }
        .confirmationDialog(
            String(localized: L10n.Recordings.geminiProcessingConfirmation),
            isPresented: $isConfirmingGemini
        ) {
            Button {
                runAction {
                    try await store.processWithGeminiCloud(currentItem)
                }
            } label: {
                Text(L10n.Common.ok)
            }
        }
        .confirmationDialog(
            String(localized: L10n.Recordings.restoreBeforeGemini),
            isPresented: $isConfirmingGeminiRestore
        ) {
            Button(String(localized: L10n.Recordings.restoreBeforeGemini), role: .destructive) {
                restoreTranscriptBeforeGemini()
            }
            Button(String(localized: L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(L10n.Recordings.restoreBeforeGeminiConfirmation)
        }
        .alert(
            String(localized: MacL10n.actionFailed),
            isPresented: Binding(
                get: { actionErrorMessage != nil },
                set: { if !$0 { actionErrorMessage = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "")
        }
        .alert(
            reminderConfirmationText ?? "",
            isPresented: Binding(
                get: { reminderConfirmationText != nil },
                set: { if !$0 { reminderConfirmationText = nil } }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        }
        .alert(
            String(localized: L10n.SpeechText.releaseOldLanguagesTitle),
            isPresented: Binding(
                get: { pendingSpeechLocaleReleaseRequest != nil },
                set: { if !$0 { pendingSpeechLocaleReleaseRequest = nil } }
            )
        ) {
            Button(String(localized: L10n.SpeechText.releaseOldLanguagesAction), role: .destructive) {
                if let request = pendingSpeechLocaleReleaseRequest {
                    releaseSpeechLocalesAndRetranscribe(request)
                }
                pendingSpeechLocaleReleaseRequest = nil
            }
            Button(String(localized: L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(verbatim: pendingSpeechLocaleReleaseRequest?.messageText ?? "")
        }
    }

    // MARK: - Transcript page

    private var transcriptPage: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    keyPointsCard
                    transcriptCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                playbackCard(transcriptScrollProxy: scrollProxy)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    private var headerCard: some View {
        let displayDuration = player.currentItem?.id == currentItem.id && player.duration > 0
            ? player.duration
            : Double(currentItem.durationSeconds)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: currentItem.displayName)
                    .font(.redditSans(.title3, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                if currentItem.isTranscriptLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                        .padding(7)
                        .background(AppTheme.warning.opacity(0.12), in: Circle())
                }

                Spacer(minLength: 0)
            }

            RetroRecordingDisplay(
                statusText: String(localized: L10n.Recordings.recordingPlayback),
                title: currentItem.audioFileName,
                audioURL: store.audioURL(for: currentItem),
                player: player,
                scrubbedTime: scrubbedPlaybackTime,
                duration: displayDuration
            )

            MacRecordingDetailFactsGrid(
                createdAtText: currentItem.createdAt.formatted(date: .abbreviated, time: .shortened),
                durationText: TranscriptionLine.formatTimestamp(Double(currentItem.durationSeconds)),
                languageText: currentItem.localizedLanguageName,
                iCloudSyncStatus: store.iCloudSyncStatus(for: currentItem)
            )

            if !currentItem.combinedTags.isEmpty
                || currentItem.projectName != nil
                || currentItem.categoryName != nil
                || currentItem.location != nil {
                MacRecordingDetailContextStrip(
                    tags: currentItem.combinedTags,
                    projectName: currentItem.projectName,
                    categoryName: currentItem.categoryName,
                    location: currentItem.location
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var keyPointsCard: some View {
        if let keyPoints = currentItem.keyPoints?.trimmingCharacters(in: .whitespacesAndNewlines),
           !keyPoints.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(L10n.Recordings.keyPoints)
                } icon: {
                    Image(systemName: "list.bullet.clipboard")
                }
                .font(.redditSans(.subheadline, weight: .semibold))

                Text(verbatim: keyPoints)
                    .font(.redditSans(.subheadline))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button {
                            AppPasteboard.copy(keyPoints)
                        } label: {
                            Label {
                                Text(L10n.Common.copy)
                            } icon: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
    }

    private func playbackCard(transcriptScrollProxy: ScrollViewProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let isCurrentPlayerItem = player.isLoaded && player.currentItem?.id == currentItem.id
        let displayDuration = isCurrentPlayerItem && player.duration > 0
            ? player.duration
            : Double(max(currentItem.durationSeconds, 1))
        let timeLabelWidth: CGFloat = 62

        return VStack(spacing: 5) {
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 60.0,
                    paused: !player.isPlaying || scrubbedPlaybackTime != nil
                )
            ) { _ in
                let rawTime = isCurrentPlayerItem ? player.presentationTime() : 0
                let displayedTime = min(
                    max(scrubbedPlaybackTime ?? rawTime, 0),
                    displayDuration
                )

                HStack(alignment: .center, spacing: 10) {
                    Text(verbatim: TranscriptionLine.formatTimestamp(displayedTime))
                        .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                        .frame(width: timeLabelWidth, alignment: .leading)

                    MacRecordingTimelineScrubber(
                        currentTime: displayedTime,
                        duration: displayDuration,
                        scrubbedTime: $scrubbedPlaybackTime,
                        audioEvents: currentItem.audioEventAnalysis?.events ?? [],
                        isEnabled: isCurrentPlayerItem,
                        onSeek: { time in
                            preparePlayerIfNeeded()
                            player.seek(to: time)
                        },
                        onEventTap: { event in
                            preparePlayerIfNeeded()
                            scrubbedPlaybackTime = nil
                            player.seek(to: event.startTime)
                        }
                    )
                    .frame(maxWidth: .infinity)

                    Text(verbatim: TranscriptionLine.formatTimestamp(displayDuration))
                        .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: timeLabelWidth, alignment: .trailing)
                }
            }

            HStack(spacing: 22) {
                MacPlaybackRoundButton(systemImage: "gobackward.5", title: "-5s") {
                    preparePlayerIfNeeded()
                    scrubbedPlaybackTime = nil
                    player.skip(by: -5)
                }
                .disabled(!isCurrentPlayerItem)

                MacPlaybackRoundButton(
                    systemImage: player.isPlaying && isCurrentPlayerItem ? "pause.fill" : "play.fill",
                    titleResource: player.isPlaying && isCurrentPlayerItem
                        ? L10n.Recordings.pause
                        : L10n.Recordings.play,
                    isPrimary: true
                ) {
                    preparePlayerIfNeeded()
                    player.togglePlayback()
                }
                .disabled(!isCurrentPlayerItem)

                MacPlaybackRoundButton(systemImage: "goforward.5", title: "+5s") {
                    preparePlayerIfNeeded()
                    scrubbedPlaybackTime = nil
                    player.skip(by: 5)
                }
                .disabled(!isCurrentPlayerItem)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)

            HStack(spacing: 8) {
                audioEventsTimelineControl(isPlayerLoaded: isCurrentPlayerItem)
                transcriptSyncControl(
                    scrollProxy: transcriptScrollProxy,
                    isPlayerLoaded: isCurrentPlayerItem
                )
                playbackSpeedMenu(isPlayerLoaded: isCurrentPlayerItem)
            }

            if let errorText = player.errorText {
                Label {
                    Text(verbatim: errorText)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.redditSans(.caption))
                .foregroundStyle(AppTheme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AppTheme.playbackGlassTint), in: shape)
        .shadow(color: AppTheme.cardShadow, radius: 18, y: 8)
    }

    private func transcriptSyncControl(
        scrollProxy: ScrollViewProxy,
        isPlayerLoaded: Bool
    ) -> some View {
        Button {
            syncTranscriptToPlayback(using: scrollProxy)
        } label: {
            MacPlaybackUtilityControlLabel(tint: AppTheme.info) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(MacPlaybackUtilityButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!isPlayerLoaded || transcriptLines.isEmpty)
        .help(String(localized: L10n.Recordings.syncCurrentTranscript))
        .accessibilityLabel(Text(L10n.Recordings.syncCurrentTranscript))
    }

    private func syncTranscriptToPlayback(using scrollProxy: ScrollViewProxy) {
        preparePlayerIfNeeded()
        let playbackTime = scrubbedPlaybackTime ?? player.presentationTime()
        let lineID = StoredTranscriptLine.currentLineID(
            in: transcriptLines,
            time: playbackTime
        ) ?? transcriptLines.first?.id

        guard let lineID else {
            return
        }

        guard !accessibilityReduceMotion else {
            scrollProxy.scrollTo(lineID, anchor: .center)
            return
        }

        withAnimation(.snappy(duration: 0.34, extraBounce: 0)) {
            scrollProxy.scrollTo(lineID, anchor: .center)
        }
    }

    private func audioEventsTimelineControl(isPlayerLoaded: Bool) -> some View {
        Button {
            if currentItem.audioEventAnalysis == nil {
                analyzeAudioEvents()
            } else {
                isShowingAudioEvents = true
            }
        } label: {
            MacPlaybackUtilityControlLabel(tint: AppTheme.info) {
                HStack(spacing: 6) {
                    if isAnalyzingAudioEvents {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))

                        if let eventCount = currentItem.audioEventAnalysis?.events.count {
                            Text(verbatim: eventCount.formatted(.number.notation(.compactName)))
                                .font(.redditSans(.caption2, weight: .bold))
                        }
                    }
                }
            }
        }
        .buttonStyle(MacPlaybackUtilityButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!isPlayerLoaded || isAnalyzingAudioEvents)
        .help(String(localized: L10n.Recordings.audioEvents))
        .accessibilityLabel(Text(L10n.Recordings.audioEvents))
    }

    private func playbackSpeedMenu(isPlayerLoaded: Bool) -> some View {
        Menu {
            ForEach(RecordingPlaybackController.availablePlaybackRates, id: \.self) { rate in
                Button {
                    player.setPlaybackRate(rate)
                } label: {
                    Label(
                        RecordingPlaybackController.playbackRateLabel(rate),
                        systemImage: player.playbackRate == rate ? "checkmark" : "speedometer"
                    )
                }
            }
        } label: {
            MacPlaybackUtilityControlLabel(tint: AppTheme.info) {
                Text(verbatim: RecordingPlaybackController.playbackRateLabel(player.playbackRate))
                    .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity)
        .disabled(!isPlayerLoaded)
    }

    private var transcriptCard: some View {
        let showsSpeakerDistinction = speakerPresentations.count > 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label {
                    Text(L10n.Recordings.transcript)
                } icon: {
                    Image(systemName: "text.alignleft")
                }
                .font(.redditSans(.subheadline, weight: .semibold))

                if currentItem.isTranscriptLocked {
                    Label {
                        Text(L10n.Recordings.transcriptLocked)
                    } icon: {
                        Image(systemName: "lock.fill")
                    }
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(AppTheme.warning.opacity(0.12), in: Capsule())
                }

                Spacer(minLength: 8)

                transcriptTranslationMenu
            }

            if showsSpeakerDistinction {
                MacTranscriptSpeakerLegend(speakers: speakerPresentations)
            }

            transcriptTranslationStatus

            if let importStatus = currentItem.importStatus {
                Group {
                    if importStatus.isFailed {
                        HStack(spacing: 10) {
                            Label {
                                Text(verbatim: importStatus.message)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(AppTheme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                store.dismissFailedImportStatus(for: currentItem.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .frame(width: 26, height: 26)
                                    .background(AppTheme.warning.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: L10n.Common.close))
                        }
                        .font(.redditSans(.caption, weight: .semibold))
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: importStatus.progress)
                                .tint(AppTheme.brand)
                            Text(verbatim: importStatus.message)
                                .font(.redditSans(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if isLoadingTranscript {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if transcriptLines.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(MacL10n.noTranscript)
                    } icon: {
                        Image(systemName: "text.badge.xmark")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 170)
            } else {
                let currentLineID = player.currentItem?.id == currentItem.id
                    ? StoredTranscriptLine.currentLineID(in: transcriptLines, time: player.currentTime)
                    : nil
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(transcriptLines) { line in
                        MacTranscriptLineRow(
                            line: line,
                            speaker: showsSpeakerDistinction
                                ? speakerPresentations.first {
                                    $0.id == TranscriptSpeakerNaming.normalizedID(line.speaker)
                                }
                                : nil,
                            isCurrent: line.id == currentLineID,
                            onSeek: {
                                preparePlayerIfNeeded()
                                scrubbedPlaybackTime = nil
                                player.seek(to: line.startSeconds)
                            },
                            onCopy: {
                                AppPasteboard.copy(translatedTranscriptByLineID[line.id] ?? line.text)
                            },
                            onEdit: currentItem.isTranscriptLocked ? nil : {
                                lineEdit = MacTranscriptLineEdit(
                                    lineID: line.id,
                                    timeText: line.timeText,
                                    text: line.spokenText,
                                    speakerID: TranscriptSpeakerNaming.normalizedID(line.speaker)
                                )
                            },
                            translatedText: translatedTranscriptByLineID[line.id],
                            isShowingTranslation: isTranslatingTranscript
                                && selectedTranslationLanguage != nil
                                && translatedTranscriptByLineID[line.id] == nil
                        )
                        .id(line.id)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var transcriptTranslationMenu: some View {
        Menu {
            Button {
                clearTranscriptTranslation()
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
                    requestTranscriptTranslation(to: language)
                } label: {
                    if selectedTranslationLanguage?.id == language.id {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(verbatim: language.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                Text(verbatim: selectedTranslationLanguage?.shortName ?? String(localized: L10n.Recordings.translate))
                    .font(.redditSans(.caption, weight: .bold))
            }
            .foregroundStyle(selectedTranslationLanguage == nil ? AppTheme.info : AppTheme.brand)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                (selectedTranslationLanguage == nil ? AppTheme.info : AppTheme.brand).opacity(0.11),
                in: Capsule()
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(transcriptLines.isEmpty || isBusyTranscribing)
        .fixedSize()
    }

    @ViewBuilder
    private var transcriptTranslationStatus: some View {
        if let selectedTranslationLanguage {
            HStack(spacing: 8) {
                if isTranslatingTranscript {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: translationErrorMessage == nil ? "translate" : "exclamationmark.triangle")
                }

                Text(
                    verbatim: translationErrorMessage
                        ?? localizedFormat(
                            L10n.Recordings.translatingToFormat,
                            selectedTranslationLanguage.displayName
                        )
                )
                .font(.caption)
                .foregroundStyle(translationErrorMessage == nil ? Color.secondary : AppTheme.warning)
            }
        }
    }

    private var availableTranslationLanguages: [TranscriptionLanguage] {
        translationLanguages.filter {
            !AppleTranslationLanguages.sameBaseLanguage($0.id, currentItem.languageID)
        }
    }

    // MARK: - AI cards

    private var intelligenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.Recordings.intelligenceSummary)
                    .font(.redditSans(.headline, weight: .semibold))
                Spacer()
                analyzeMenu(
                    isRunning: isAnalyzingSummary,
                    title: currentItem.intelligence == nil
                        ? L10n.Recordings.analyze
                        : L10n.Recordings.analyzeAgain
                ) { provider in
                    analyzeSummary(provider: provider)
                }
            }

            if let intelligence = currentItem.intelligence {
                HStack {
                    Spacer()
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Label {
                            Text(L10n.Recordings.editSummary)
                        } icon: {
                            Image(systemName: "pencil")
                        }
                    }
                    .controlSize(.small)
                }
                Text(verbatim: intelligence.summary)
                    .font(.redditSans(.subheadline))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(intelligence.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isAnalyzingSummary {
                ProgressView(String(localized: L10n.Recordings.analyzing))
            } else {
                Text(L10n.Recordings.chatUnavailable)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var meetingAnalysisCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Recordings.analyzeMeeting)
                    .font(.redditSans(.headline, weight: .semibold))
                Spacer()
                analyzeMenu(
                    isRunning: isAnalyzingMeeting,
                    title: currentItem.meetingAnalysis == nil
                        ? L10n.Recordings.analyzeMeeting
                        : L10n.Recordings.analyzeMeetingAgain
                ) { provider in
                    analyzeMeeting(provider: provider)
                }
            }

            if let analysis = currentItem.meetingAnalysis {
                if let summary = analysis.summary, !summary.isEmpty {
                    Text(verbatim: summary)
                        .font(.redditSans(.subheadline))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }

                if !analysis.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.Recordings.actionItems)
                                .font(.redditSans(.subheadline, weight: .semibold))
                            Spacer()
                            Button {
                                addAllActionItemsToReminders(analysis)
                            } label: {
                                Label {
                                    Text(L10n.Recordings.addAllActionItemsToReminders)
                                } icon: {
                                    Image(systemName: "checklist")
                                }
                            }
                            .controlSize(.small)
                        }
                        ForEach(analysis.actionItems) { actionItem in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: actionItem.task)
                                        .font(.redditSans(.subheadline))
                                    if let owner = actionItem.owner, !owner.isEmpty {
                                        Text(verbatim: owner)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }

                if !analysis.decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.Recordings.decisions)
                            .font(.redditSans(.subheadline, weight: .semibold))
                        ForEach(analysis.decisions) { decision in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: decision.decision)
                                    .font(.redditSans(.subheadline))
                                if let rationale = decision.rationale, !rationale.isEmpty {
                                    Text(verbatim: rationale)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !analysis.openQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.Recordings.openQuestions)
                            .font(.redditSans(.subheadline, weight: .semibold))
                        ForEach(analysis.openQuestions) { question in
                            Text(verbatim: question.question)
                                .font(.redditSans(.subheadline))
                        }
                    }
                }

                Text(analysis.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isAnalyzingMeeting {
                ProgressView(String(localized: L10n.Recordings.analyzingMeeting))
            }
        }
        .padding(16)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func analyzeMenu(
        isRunning: Bool,
        title: LocalizedStringResource,
        action: @escaping (RecordingSummaryProvider) -> Void
    ) -> some View {
        Group {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Menu {
                    ForEach(RecordingSummaryProvider.menuProviders) { provider in
                        Button {
                            action(provider)
                        } label: {
                            Label(provider.displayName, systemImage: provider.systemImage)
                        }
                        .disabled(!store.summaryProviderAvailability.isAvailable(provider))
                    }
                } label: {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                }
                .disabled(!store.summaryProviderAvailability.hasAnyAvailableProvider)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    // MARK: - Toolbar actions

    private var detailActionsMenu: some View {
        Menu {
            Button {
                isShowingEditSheet = true
            } label: {
                Label {
                    Text(L10n.Recordings.editDetails)
                } icon: {
                    Image(systemName: "pencil")
                }
            }
            .disabled(isBusyTranscribing)

            Button {
                toggleTranscriptLock()
            } label: {
                Label {
                    Text(
                        currentItem.isTranscriptLocked
                            ? L10n.Recordings.unlockTranscript
                            : L10n.Recordings.lockTranscript
                    )
                } icon: {
                    Image(systemName: currentItem.isTranscriptLocked ? "lock.open" : "lock")
                }
            }

            Button {
                AppPasteboard.copy(store.transcriptText(for: currentItem))
            } label: {
                Label {
                    Text(L10n.Recordings.copyTranscript)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }

            exportMenu

            shareMenu

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: currentItem)])
            } label: {
                Label {
                    Text(MacL10n.showAudioInFinder)
                } icon: {
                    Image(systemName: "folder")
                }
            }

            Divider()

            retranscribeMenu

            manualGeminiMenu

            if store.hasGeminiTranscriptBackup(for: currentItem) {
                Button {
                    isConfirmingGeminiRestore = true
                } label: {
                    Label {
                        Text(L10n.Recordings.restoreBeforeGemini)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                }
                .disabled(currentItem.isTranscriptLocked || isBusyTranscribing)
            }

            Divider()

            Button {
                isShowingAudioInfo = true
            } label: {
                Label {
                    Text(L10n.Recordings.audioParameters)
                } icon: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
            }

            Button {
                if currentItem.audioEventAnalysis == nil {
                    analyzeAudioEvents()
                } else {
                    isShowingAudioEvents = true
                }
            } label: {
                Label {
                    Text(
                        currentItem.audioEventAnalysis == nil
                            ? L10n.Recordings.analyzeAudioEvents
                            : L10n.Recordings.audioEvents
                    )
                } icon: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
            }
            .disabled(isAnalyzingAudioEvents)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label {
                    Text(L10n.Recordings.deleteRecording)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        } label: {
            Label {
                Text(L10n.Common.more)
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var exportMenu: some View {
        Menu {
            exportButton(.txt, title: L10n.Recordings.exportTXT)
            exportButton(.markdown, title: L10n.Recordings.exportMarkdown)
            exportButton(.srt, title: L10n.Recordings.exportSRT)
            exportButton(.vtt, title: L10n.Recordings.exportVTT)
            exportButton(.json, title: L10n.Recordings.exportJSON)
        } label: {
            Label {
                Text(L10n.Recordings.exportTranscript)
            } icon: {
                Image(systemName: "square.and.arrow.up.on.square")
            }
        }
    }

    private func exportButton(
        _ format: TranscriptExportFormat,
        title: LocalizedStringResource
    ) -> some View {
        Button {
            exportTranscript(as: format)
        } label: {
            Text(title)
        }
    }

    private var shareMenu: some View {
        ShareLink(item: store.audioURL(for: currentItem)) {
            Label {
                Text(L10n.Recordings.shareAudio)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private var retranscribeMenu: some View {
        Menu {
            Button {
                isShowingAppleRetranscriptionPicker = true
            } label: {
                Label {
                    Text(L10n.TranscriptionBackend.appleOnDeviceTitle)
                } icon: {
                    Image(systemName: "apple.logo")
                }
            }

            Button {
                isShowingWhisperRetranscriptionPicker = true
            } label: {
                Label {
                    Text(L10n.Recordings.retranscribeWithLocalWhisper)
                } icon: {
                    Image(systemName: "cpu")
                }
            }
            .disabled(downloadedWhisperModels.isEmpty)

            Button {
                runAction {
                    try await store.retranscribeWithQwen3ASR(
                        currentItem,
                        language: TranscriptionLanguage(id: currentItem.languageID)
                    )
                }
            } label: {
                Label {
                    Text(L10n.Recordings.retranscribeWithQwen3ASR)
                } icon: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
            }
            .disabled(!isQwenAvailable)

            Button {
                runAction {
                    try await store.retranscribeWithMOSS(currentItem)
                }
            } label: {
                Label {
                    Text(L10n.Recordings.retranscribeWithMOSS)
                } icon: {
                    Image(systemName: "person.2")
                }
            }
            .disabled(!isMOSSAvailable)

            if store.summaryProviderAvailability.isGeminiCloudAvailable {
                Button {
                    isConfirmingGemini = true
                } label: {
                    Text(L10n.Recordings.processWithGemini)
                }
            }
        } label: {
            Label {
                Text(L10n.Recordings.transcribeMenu)
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(
            currentItem.isTranscriptLocked
                || isBusyTranscribing
                || transcriber.isRecording
                || transcriber.isPreparing
        )
    }

    private var manualGeminiMenu: some View {
        Menu {
            Button {
                shareAudioWithGeminiApp()
            } label: {
                Label {
                    Text(L10n.Recordings.manualGeminiShareAndCopyPrompt)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            Button {
                manualGeminiJSONText = ""
                manualGeminiImportErrorMessage = nil
                isShowingManualGeminiImport = true
            } label: {
                Label {
                    Text(L10n.Recordings.manualGeminiImportJSON)
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                }
            }
            .disabled(currentItem.isTranscriptLocked || isBusyTranscribing)
        } label: {
            Label {
                Text(L10n.Recordings.manualGemini)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
    }

    // MARK: - Actions

    private func preparePlayerIfNeeded() {
        if player.currentItem?.id != currentItem.id || !player.isLoaded {
            scrubbedPlaybackTime = nil
            player.load(item: currentItem, url: store.audioURL(for: currentItem))
        }
        updatePlayerNowPlayingTranscript()
    }

    private func updatePlayerNowPlayingTranscript() {
        guard player.currentItem?.id == currentItem.id else {
            return
        }
        player.setNowPlayingTranscript(
            for: currentItem.id,
            cues: transcriptLines.map { line in
                (startTime: line.startSeconds, text: line.spokenText)
            }
        )
    }

    private func loadTranscript() async {
        isLoadingTranscript = true
        defer { isLoadingTranscript = false }

        let transcriptURL = store.transcriptURL(for: currentItem)
        let diarization = currentItem.speakerDiarization
        let lines = await Task.detached(priority: .utility) { () -> [StoredTranscriptLine] in
            guard let text = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
                return []
            }
            return StoredTranscriptLine.parse(text, speakerDiarization: diarization)
        }.value
        transcriptLines = lines
        updatePlayerNowPlayingTranscript()
        translatedTranscriptByLineID = [:]
        translatedTranscriptCache = translatedTranscriptCache.filter { key, _ in
            key.hasPrefix(transcriptTranslationCachePrefix)
        }
        if let selectedTranslationLanguage {
            requestTranscriptTranslation(to: selectedTranslationLanguage)
        }
    }

    private func runAction(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                await loadTranscript()
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func refreshRetranscriptionAvailability() async {
        let options = await Task.detached(priority: .utility) {
            let models = LocalWhisperModelManager.downloadedStatuses().map(\.model)
            let languages = Dictionary(
                uniqueKeysWithValues: models.map { model in
                    (model.id, LocalWhisperTranscriptionService.supportedLanguages(for: model))
                }
            )
            return (models, languages)
        }.value
        downloadedWhisperModels = options.0
        whisperLanguagesByModelID = options.1
        isQwenAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
        isMOSSAvailable = MOSSLocalModelManager.currentStatus().isAvailable
    }

    private func requestAppleRetranscription(language: TranscriptionLanguage) {
        guard !isBusyTranscribing, !transcriber.isRecording, !transcriber.isPreparing else {
            return
        }
        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    language,
                    preservingLanguageIDs: [transcriber.selectedLanguageID, currentItem.languageID]
                )
                switch preparation {
                case .ready:
                    runAppleRetranscription(language: language)
                case .needsRelease(let request):
                    pendingSpeechLocaleReleaseRequest = request
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func releaseSpeechLocalesAndRetranscribe(_ request: SpeechLocaleReleaseRequest) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(request)
                runAppleRetranscription(language: request.targetLanguage)
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func runAppleRetranscription(language: TranscriptionLanguage) {
        runAction {
            try await store.retranscribe(currentItem, language: language)
        }
    }

    private func analyzeSummary(provider: RecordingSummaryProvider) {
        guard !isAnalyzingSummary else {
            return
        }
        guard !isTranslatingTranscript else {
            actionErrorMessage = String(localized: L10n.Recordings.waitForTranslationBeforeSummary)
            return
        }
        let translatedInput = translatedTranscriptAnalysisInput()
        if selectedTranslationLanguage != nil, translatedInput == nil {
            actionErrorMessage = String(localized: L10n.Recordings.noTranslatedTextForSummary)
            return
        }
        isAnalyzingSummary = true
        Task {
            defer { isAnalyzingSummary = false }
            do {
                _ = try await store.analyzeIntelligence(
                    for: currentItem,
                    transcriptOverride: translatedInput?.transcript,
                    languageNameOverride: translatedInput?.languageName,
                    summaryProvider: provider
                )
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func analyzeMeeting(provider: RecordingSummaryProvider) {
        guard !isAnalyzingMeeting else {
            return
        }
        guard !isTranslatingTranscript else {
            actionErrorMessage = String(localized: L10n.Recordings.waitForTranslationBeforeSummary)
            return
        }
        let translatedInput = translatedTranscriptAnalysisInput()
        if selectedTranslationLanguage != nil, translatedInput == nil {
            actionErrorMessage = String(localized: L10n.Recordings.noTranslatedTextForSummary)
            return
        }
        isAnalyzingMeeting = true
        Task {
            defer { isAnalyzingMeeting = false }
            do {
                _ = try await store.analyzeMeeting(
                    for: currentItem,
                    transcriptOverride: translatedInput?.transcript,
                    languageNameOverride: translatedInput?.languageName,
                    summaryProvider: provider
                )
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func addAllActionItemsToReminders(_ analysis: RecordingMeetingAnalysis) {
        let drafts = analysis.actionItems.map {
            ReminderDraft(actionItem: $0, recordingTitle: currentItem.displayName)
        }
        guard !drafts.isEmpty else {
            return
        }
        reminderDraftRequest = MacReminderDraftRequest(drafts: drafts)
    }

    private func saveReminderDrafts(_ drafts: [ReminderDraft]) {
        guard !isAddingReminders else {
            return
        }
        isAddingReminders = true
        Task {
            defer { isAddingReminders = false }
            do {
                let count = try await ReminderExportService.addDrafts(drafts)
                reminderDraftRequest = nil
                reminderConfirmationText = localizedFormat(
                    L10n.Recordings.addedRemindersFormat,
                    count
                )
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func analyzeAudioEvents() {
        guard !isAnalyzingAudioEvents else {
            return
        }
        isAnalyzingAudioEvents = true
        Task {
            defer { isAnalyzingAudioEvents = false }
            do {
                _ = try await store.analyzeAudioEvents(for: currentItem)
                isShowingAudioEvents = true
            } catch {
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func toggleTranscriptLock() {
        do {
            _ = try store.setTranscriptLocked(
                for: currentItem,
                isLocked: !currentItem.isTranscriptLocked
            )
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func deleteRecording() {
        do {
            if player.currentItem?.id == currentItem.id {
                player.unload()
            }
            try store.delete(currentItem)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func exportTranscript(as format: TranscriptExportFormat) {
        do {
            let text = store.transcriptText(for: currentItem)
            let exportedURL = try TranscriptExportService.export(
                item: currentItem,
                transcript: text,
                format: format
            )
            let panel = NSSavePanel()
            panel.nameFieldStringValue = exportedURL.lastPathComponent
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let destination = panel.url else {
                return
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: exportedURL, to: destination)
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func shareAudioWithGeminiApp() {
        let prompt = GeminiCloudService.manualTranscriptionPrompt(
            languageName: currentItem.localizedLanguageName
        )
        AppPasteboard.copy(prompt)

        guard let anchorView = NSApp.keyWindow?.contentView else {
            actionErrorMessage = String(localized: L10n.Common.unknown)
            return
        }
        let sharingPicker = NSSharingServicePicker(items: [store.audioURL(for: currentItem)])
        sharingPicker.show(
            relativeTo: anchorView.bounds,
            of: anchorView,
            preferredEdge: .minY
        )
    }

    private func pasteManualGeminiJSONFromClipboard() {
        guard let clipboardText = AppPasteboard.string,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            manualGeminiImportErrorMessage = String(localized: L10n.Recordings.manualGeminiClipboardEmpty)
            return
        }
        manualGeminiJSONText = clipboardText
        manualGeminiImportErrorMessage = nil
    }

    private func importManualGeminiJSON() {
        do {
            _ = try store.importManualGeminiTranscriptionJSON(
                manualGeminiJSONText,
                for: currentItem
            )
            manualGeminiImportErrorMessage = nil
            manualGeminiJSONText = ""
            isShowingManualGeminiImport = false
            Task {
                await loadTranscript()
            }
        } catch {
            manualGeminiImportErrorMessage = error.localizedDescription
        }
    }

    private func restoreTranscriptBeforeGemini() {
        do {
            _ = try store.restoreTranscriptBeforeGemini(for: currentItem)
            Task {
                await loadTranscript()
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func requestTranscriptTranslation(to language: TranscriptionLanguage) {
        guard !transcriptLines.isEmpty else {
            return
        }
        guard !AppleTranslationLanguages.sameBaseLanguage(language.id, currentItem.languageID) else {
            clearTranscriptTranslation()
            return
        }

        selectedTranslationLanguage = language
        translationErrorMessage = nil

        let cacheKey = transcriptTranslationCacheKey(for: language)
        if let cachedTranslation = translatedTranscriptCache[cacheKey] {
            translatedTranscriptByLineID = cachedTranslation
            isTranslatingTranscript = false
            return
        }

        translatedTranscriptByLineID = [:]
        isTranslatingTranscript = true

        let nextConfiguration = TranslationSession.Configuration(
            source: AppleTranslationLanguages.localeLanguage(for: currentItem.languageID),
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

    private func clearTranscriptTranslation() {
        selectedTranslationLanguage = nil
        translatedTranscriptByLineID = [:]
        translationErrorMessage = nil
        isTranslatingTranscript = false
        translationConfiguration = nil
    }

    private func translateTranscript(using session: TranslationSession) async {
        guard let targetLanguage = selectedTranslationLanguage,
              !transcriptLines.isEmpty else {
            isTranslatingTranscript = false
            return
        }

        let cacheKey = transcriptTranslationCacheKey(for: targetLanguage)
        if let cachedTranslation = translatedTranscriptCache[cacheKey] {
            translatedTranscriptByLineID = cachedTranslation
            isTranslatingTranscript = false
            return
        }

        let targetLanguageID = targetLanguage.id
        let requests = transcriptLines.map { line in
            TranslationSession.Request(sourceText: line.spokenText, clientIdentifier: line.id)
        }

        do {
            try await session.prepareTranslation()
            var translatedByLineID: [StoredTranscriptLine.ID: String] = [:]
            for try await response in session.translate(batch: requests) {
                guard let currentTargetLanguage = selectedTranslationLanguage,
                      currentTargetLanguage.id == targetLanguageID,
                      transcriptTranslationCacheKey(for: currentTargetLanguage) == cacheKey,
                      let lineID = response.clientIdentifier else {
                    continue
                }
                let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translatedText.isEmpty else {
                    continue
                }
                translatedByLineID[lineID] = translatedText
                translatedTranscriptByLineID = translatedByLineID
            }

            guard selectedTranslationLanguage?.id == targetLanguageID else {
                return
            }
            translatedTranscriptCache[cacheKey] = translatedByLineID
            translatedTranscriptByLineID = translatedByLineID
            isTranslatingTranscript = false
            translationErrorMessage = nil
        } catch {
            guard selectedTranslationLanguage?.id == targetLanguageID else {
                return
            }
            translatedTranscriptByLineID = [:]
            isTranslatingTranscript = false
            translationErrorMessage = error.localizedDescription
        }
    }

    private func translatedTranscriptAnalysisInput() -> (transcript: String, languageName: String)? {
        guard let selectedTranslationLanguage else {
            return nil
        }

        let translatedLines = transcriptLines.compactMap { line -> String? in
            guard let translatedText = translatedTranscriptByLineID[line.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translatedText.isEmpty else {
                return nil
            }
            if let speaker = line.speaker, !speaker.isEmpty {
                return "\(speaker): \(translatedText)"
            }
            return translatedText
        }
        guard !translatedLines.isEmpty else {
            return nil
        }
        return (translatedLines.joined(separator: "\n"), selectedTranslationLanguage.displayName)
    }

    private var transcriptTranslationCachePrefix: String {
        [
            currentItem.id.uuidString,
            currentItem.transcriptFileName,
            "\(currentItem.lineCount)",
            "\(currentItem.transcriptPreview.hashValue)",
        ].joined(separator: "|")
    }

    private func transcriptTranslationCacheKey(for language: TranscriptionLanguage) -> String {
        "\(transcriptTranslationCachePrefix)|\(language.id)"
    }

    private func saveTranscriptLine(edit: MacTranscriptLineEdit, text: String, speakerID: String?) {
        let followingLines = consecutiveFollowingLinesForSpeakerChange(
            edit: edit,
            proposedSpeakerID: speakerID
        )
        let request = MacTranscriptSpeakerPropagationRequest(
            edit: edit,
            text: text,
            speakerID: speakerID,
            followingLines: followingLines
        )

        guard !followingLines.isEmpty else {
            performTranscriptLineEdit(request, propagatingSpeakerTo: [])
            return
        }

        speakerPropagationRequest = request
    }

    private func consecutiveFollowingLinesForSpeakerChange(
        edit: MacTranscriptLineEdit,
        proposedSpeakerID: String?
    ) -> [StoredTranscriptLine] {
        guard let originalSpeakerID = TranscriptSpeakerNaming.normalizedID(edit.speakerID),
              !transcriptSpeakerIDsMatch(originalSpeakerID, proposedSpeakerID),
              let editedLineIndex = transcriptLines.firstIndex(where: { $0.id == edit.lineID }) else {
            return []
        }

        var followingLines: [StoredTranscriptLine] = []
        for line in transcriptLines.dropFirst(editedLineIndex + 1) {
            guard transcriptSpeakerIDsMatch(line.speaker, originalSpeakerID) else {
                break
            }
            followingLines.append(line)
        }
        return followingLines
    }

    private func transcriptSpeakerIDsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalizedLHS = TranscriptSpeakerNaming.normalizedID(lhs)
        let normalizedRHS = TranscriptSpeakerNaming.normalizedID(rhs)
        switch (normalizedLHS, normalizedRHS) {
        case let (lhs?, rhs?):
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        case (nil, nil):
            return true
        default:
            return false
        }
    }

    private func performTranscriptLineEdit(
        _ request: MacTranscriptSpeakerPropagationRequest,
        propagatingSpeakerTo followingLines: [StoredTranscriptLine]
    ) {
        do {
            _ = try store.updateTranscriptLine(
                for: currentItem,
                lineID: request.edit.lineID,
                text: request.text,
                speaker: request.speakerID,
                consecutiveFollowingLines: followingLines.map {
                    (lineID: $0.id, text: $0.spokenText)
                }
            )
            speakerPropagationRequest = nil
            lineEdit = nil
            Task {
                await loadTranscript()
            }
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }
}

private struct MacAudioEventsSheet: View {
    let analysis: RecordingAudioEventAnalysis?
    let isAnalyzing: Bool
    let onAnalyze: () -> Void
    let onSeek: (RecordingAudioEvent) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(L10n.Recordings.audioEvents)
                        .font(.title2.bold())
                } icon: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .foregroundStyle(AppTheme.info)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text(L10n.Common.done)
                }
                .keyboardShortcut(.cancelAction)
            }

            if isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.Recordings.analyzingAudioEvents)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if let analysis, !analysis.events.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(analysis.events) { event in
                            Button {
                                onSeek(event)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(AppTheme.info)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: event.localizedLabel)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(
                                            verbatim: localizedFormat(
                                                L10n.Recordings.audioEventConfidenceFormat,
                                                event.confidence * 100
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(
                                        verbatim: "\(TranscriptionLine.formatTimestamp(event.startTime))-\(TranscriptionLine.formatTimestamp(event.endTime))"
                                    )
                                    .font(.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(AppTheme.info)
                                }
                                .padding(10)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(analysis.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView {
                    Label {
                        Text(L10n.Recordings.noAudioEvents)
                    } icon: {
                        Image(systemName: "waveform.slash")
                    }
                } actions: {
                    Button(action: onAnalyze) {
                        Text(L10n.Recordings.analyzeAudioEvents)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 540, minHeight: 420)
    }
}

private struct MacManualGeminiJSONImportSheet: View {
    @Binding var jsonText: String
    let errorMessage: String?
    let onPaste: () -> Void
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Recordings.manualGeminiImportJSON)
                .font(.title2.bold())

            Text(L10n.Recordings.manualGeminiImportInstructions)
                .font(.callout)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $jsonText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                if jsonText.isEmpty {
                    Text(L10n.Recordings.manualGeminiJSONPlaceholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
            }

            if let errorMessage {
                Label {
                    Text(verbatim: errorMessage)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(AppTheme.danger)
            }

            HStack {
                Button(action: onPaste) {
                    Label {
                        Text(L10n.Recordings.manualGeminiPasteClipboard)
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text(L10n.Common.cancel)
                }
                .keyboardShortcut(.cancelAction)

                Button(action: onImport) {
                    Text(L10n.Recordings.manualGeminiImportTranscript)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 460)
    }
}

private struct MacReminderDraftRequest: Identifiable {
    let id = UUID()
    let drafts: [ReminderDraft]
}

private struct MacReminderDraftReviewSheet: View {
    let initialDrafts: [ReminderDraft]
    let isSaving: Bool
    let onSave: ([ReminderDraft]) -> Void
    let onCancel: () -> Void

    @State private var drafts: [ReminderDraft]

    init(
        initialDrafts: [ReminderDraft],
        isSaving: Bool,
        onSave: @escaping ([ReminderDraft]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialDrafts = initialDrafts
        self.isSaving = isSaving
        self.onSave = onSave
        self.onCancel = onCancel
        _drafts = State(initialValue: initialDrafts)
    }

    private var validDrafts: [ReminderDraft] {
        drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Recordings.reviewReminders)
                .font(.title2.bold())

            Text(L10n.Recordings.reminderReviewFooter)
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach($drafts) { $draft in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField(text: $draft.title) {
                                Text(L10n.Recordings.reminderTitle)
                            }
                            .font(.headline)

                            Button(role: .destructive) {
                                drafts.removeAll { $0.id == draft.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }

                        Toggle(isOn: $draft.hasDueDate) {
                            Label {
                                Text(L10n.Recordings.reminderDueDate)
                            } icon: {
                                Image(systemName: "calendar")
                            }
                        }

                        if draft.hasDueDate {
                            DatePicker(
                                selection: Binding(
                                    get: { draft.dueDate ?? Date() },
                                    set: { draft.dueDate = $0 }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            ) {
                                Text(L10n.Recordings.reminderDueDate)
                            }
                        }

                        TextEditor(text: $draft.notes)
                            .font(.callout)
                            .frame(minHeight: 64)
                    }
                    .padding(.vertical, 8)
                }
            }

            HStack {
                Button(action: onCancel) {
                    Text(L10n.Common.cancel)
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

                Spacer()

                Button {
                    onSave(validDrafts)
                } label: {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.Recordings.addToReminders)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || validDrafts.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 620, minHeight: 520)
    }
}

// MARK: - Transcript row

private struct MacTranscriptLineRow: View {
    let line: StoredTranscriptLine
    let speaker: TranscriptSpeakerPresentation?
    let isCurrent: Bool
    let onSeek: () -> Void
    let onCopy: () -> Void
    let onEdit: (() -> Void)?
    let translatedText: String?
    let isShowingTranslation: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: line.timeText)
                .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? .white : (speaker?.tint ?? AppTheme.brand))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    isCurrent ? AppTheme.brand : (speaker?.tint ?? AppTheme.brand).opacity(0.12),
                    in: Capsule()
                )

            VStack(alignment: .leading, spacing: speaker == nil ? 4 : 6) {
                if let speaker {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(speaker.tint)
                            .frame(width: 7, height: 7)

                        Text(verbatim: speaker.displayName)
                            .font(.redditSans(.caption2, weight: .bold))
                            .foregroundStyle(speaker.tint)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(speaker.tint.opacity(0.10), in: Capsule())
                    .accessibilityHidden(true)
                }

                Text(verbatim: translatedText ?? line.spokenText)
                    .font(.redditSans(.subheadline))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if translatedText != nil {
                    Text(verbatim: line.spokenText)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isShowingTranslation {
                    Text(L10n.Recordings.translating)
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, speaker == nil ? 5 : 8)
        .padding(.leading, speaker == nil ? 7 : 11)
        .padding(.trailing, 8)
        .background(
            isCurrent
                ? AppTheme.brand.opacity(0.08)
                : speaker?.tint.opacity(0.055) ?? Color.clear,
            in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
        )
        .overlay(alignment: .leading) {
            if let speaker {
                Capsule()
                    .fill(speaker.tint)
                    .frame(width: 3)
                    .padding(.vertical, 7)
                    .padding(.leading, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSeek)
        .contextMenu {
            Button {
                onCopy()
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    private var accessibilityText: String {
        let speakerText = speaker.map { "\($0.displayName) " } ?? ""
        if let translatedText {
            return "\(speakerText)\(line.timeText) \(translatedText) \(line.spokenText)"
        }
        return "\(speakerText)\(line.timeText) \(line.spokenText)"
    }
}

// MARK: - Playback presentation

private struct MacRecordingTimelineScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var scrubbedTime: TimeInterval?
    let audioEvents: [RecordingAudioEvent]
    let isEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onEventTap: (RecordingAudioEvent) -> Void

    @State private var isScrubbing = false

    private var effectiveDuration: TimeInterval {
        max(duration, 1)
    }

    private var displayedTime: TimeInterval {
        min(max(scrubbedTime ?? currentTime, 0), effectiveDuration)
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                let width = proxy.size.width
                let progress = CGFloat(displayedTime / effectiveDuration)
                let thumbX = min(max(progress * width, 0), width)
                let thumbSize: CGFloat = isScrubbing ? 18 : 14
                let trackCenterY: CGFloat = 27
                let trackHeight: CGFloat = 6
                let markerHeight: CGFloat = 16

                ZStack(alignment: .topLeading) {
                    if isScrubbing, let event = activeAudioEvent(at: displayedTime) {
                        audioEventCallout(event, thumbX: thumbX, trackWidth: width)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    }

                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: trackHeight)
                        .offset(y: trackCenterY - trackHeight / 2)

                    Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
                        for event in audioEvents {
                            let rect = markerRect(
                                for: event,
                                trackWidth: width,
                                markerHeight: markerHeight
                            )
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 3),
                                with: .color(AppTheme.info.opacity(markerOpacity(for: event)))
                            )
                            context.fill(
                                Path(
                                    roundedRect: CGRect(
                                        x: rect.minX,
                                        y: rect.minY,
                                        width: rect.width,
                                        height: 1
                                    ),
                                    cornerRadius: 0.5
                                ),
                                with: .color(Color.white.opacity(0.26))
                            )
                        }
                    }
                    .frame(width: width, height: markerHeight)
                    .offset(y: trackCenterY - markerHeight / 2)
                    .allowsHitTesting(false)

                    Capsule()
                        .fill(AppTheme.brand.opacity(isEnabled ? 0.88 : 0.34))
                        .frame(width: max(thumbX, 0), height: trackHeight)
                        .offset(y: trackCenterY - trackHeight / 2)

                    Circle()
                        .fill(isEnabled ? AppTheme.brand : Color.secondary.opacity(0.55))
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(
                            color: AppTheme.brand.opacity(isScrubbing ? 0.24 : 0.14),
                            radius: isScrubbing ? 8 : 4,
                            y: isScrubbing ? 4 : 2
                        )
                        .offset(
                            x: thumbX - thumbSize / 2,
                            y: trackCenterY - thumbSize / 2
                        )
                        .animation(.snappy(duration: 0.16, extraBounce: 0), value: isScrubbing)
                }
                .frame(width: width, height: 48, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(timelineGesture(trackWidth: width))
            }
        }
        .frame(height: 48)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.Recordings.recordingPlayback))
        .accessibilityValue(Text(verbatim: TranscriptionLine.formatTimestamp(displayedTime)))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else {
                return
            }
            switch direction {
            case .increment:
                onSeek(min(displayedTime + 5, duration))
            case .decrement:
                onSeek(max(displayedTime - 5, 0))
            @unknown default:
                break
            }
        }
    }

    private func audioEventCallout(
        _ event: RecordingAudioEvent,
        thumbX: CGFloat,
        trackWidth: CGFloat
    ) -> some View {
        let width = min(trackWidth, 190)
        let x = min(max(thumbX - width / 2, 0), max(trackWidth - width, 0))

        return HStack(spacing: 6) {
            Text(verbatim: event.localizedLabel)
                .font(.redditSans(.caption2, weight: .bold))
                .lineLimit(1)

            Text(verbatim: audioEventTimeRangeText(event))
                .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(width: width, height: 24)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .offset(x: x)
    }

    private func timelineGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else {
                    return
                }
                if !isScrubbing {
                    withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
                        isScrubbing = true
                    }
                }
                scrubbedTime = time(for: value.location.x, trackWidth: trackWidth)
            }
            .onEnded { value in
                guard isEnabled else {
                    return
                }
                let targetTime = time(for: value.location.x, trackWidth: trackWidth)
                let tapDistance = hypot(value.translation.width, value.translation.height)
                scrubbedTime = nil
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    isScrubbing = false
                }
                if tapDistance < 4, let event = activeAudioEvent(at: targetTime) {
                    onEventTap(event)
                    return
                }
                onSeek(targetTime)
            }
    }

    private func activeAudioEvent(at time: TimeInterval) -> RecordingAudioEvent? {
        var closestEvent: RecordingAudioEvent?
        var closestDistance = TimeInterval.infinity

        for event in audioEvents where time >= event.startTime - 0.45 && time <= event.endTime + 0.45 {
            let eventDistance = distance(from: time, to: event)
            if eventDistance < closestDistance
                || (eventDistance == closestDistance
                    && event.confidence > (closestEvent?.confidence ?? 0)) {
                closestEvent = event
                closestDistance = eventDistance
            }
        }

        return closestEvent
    }

    private func distance(from time: TimeInterval, to event: RecordingAudioEvent) -> TimeInterval {
        if time >= event.startTime, time <= event.endTime {
            return 0
        }
        return min(abs(time - event.startTime), abs(time - event.endTime))
    }

    private func time(for xPosition: CGFloat, trackWidth: CGFloat) -> TimeInterval {
        let normalized = min(max(xPosition / max(trackWidth, 1), 0), 1)
        return TimeInterval(normalized) * effectiveDuration
    }

    private func markerRect(
        for event: RecordingAudioEvent,
        trackWidth: CGFloat,
        markerHeight: CGFloat
    ) -> CGRect {
        let markerX = min(
            max(CGFloat(event.startTime / effectiveDuration) * trackWidth, 0),
            trackWidth
        )
        let rawWidth = CGFloat(max(event.duration, 0.1) / effectiveDuration) * trackWidth
        let remainingWidth = max(trackWidth - markerX, 3)
        let markerWidth = min(max(rawWidth, 4), remainingWidth)
        return CGRect(x: markerX, y: 0, width: markerWidth, height: markerHeight)
    }

    private func markerOpacity(for event: RecordingAudioEvent) -> Double {
        min(max(0.28 + event.confidence * 0.58, 0.34), 0.88)
    }

    private func audioEventTimeRangeText(_ event: RecordingAudioEvent) -> String {
        "\(TranscriptionLine.formatTimestamp(event.startTime))-\(TranscriptionLine.formatTimestamp(event.endTime))"
    }
}

private struct MacPlaybackUtilityControlLabel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                Capsule()
                    .fill(AppTheme.raisedControlBackground)
                    .opacity(colorScheme == .dark ? 0.58 : 0.82)
            }
            .overlay {
                Capsule()
                    .stroke(tint.opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 1)
            }
            .contentShape(Capsule())
    }
}

private struct MacPlaybackUtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
            .scaleEffect(accessibilityReduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.11, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct MacPlaybackRoundButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let title: Text
    var isPrimary = false
    let action: () -> Void

    init(
        systemImage: String,
        title: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = Text(verbatim: title)
        self.isPrimary = isPrimary
        self.action = action
    }

    init(
        systemImage: String,
        titleResource: LocalizedStringResource,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = Text(titleResource)
        self.isPrimary = isPrimary
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: isPrimary ? 22 : 18, weight: .semibold))
                .frame(width: isPrimary ? 58 : 46, height: isPrimary ? 58 : 46)
                .foregroundStyle(isPrimary ? .white : AppTheme.brand)
                .background {
                    if isPrimary {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppTheme.brandSoft, AppTheme.brand],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .opacity(colorScheme == .dark ? 0.72 : 1)
                    } else {
                        Circle()
                            .fill(AppTheme.raisedControlBackground)
                            .opacity(colorScheme == .dark ? 0.58 : 1)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
                }
        }
        .buttonStyle(MacPlaybackRoundButtonStyle(isPrimary: isPrimary, colorScheme: colorScheme))
        .accessibilityLabel(title)
    }
}

private struct MacPlaybackRoundButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let isPrimary: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            .scaleEffect(accessibilityReduceMotion ? 1 : (configuration.isPressed ? 0.91 : 1))
            .offset(y: accessibilityReduceMotion ? 0 : (configuration.isPressed ? 3 : 0))
            .shadow(
                color: shadowColor(isPressed: configuration.isPressed),
                radius: configuration.isPressed ? (isPrimary ? 7 : 5) : (isPrimary ? 18 : 10),
                y: configuration.isPressed ? (isPrimary ? 3 : 2) : (isPrimary ? 11 : 6)
            )
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.11, extraBounce: 0),
                value: configuration.isPressed
            )
    }

    private func shadowColor(isPressed: Bool) -> Color {
        if isPrimary {
            return AppTheme.brand.opacity(
                colorScheme == .dark
                    ? (isPressed ? 0.14 : 0.24)
                    : (isPressed ? 0.24 : 0.46)
            )
        }
        return Color.black.opacity(
            colorScheme == .dark
                ? (isPressed ? 0.05 : 0.09)
                : (isPressed ? 0.08 : 0.16)
        )
    }
}

// MARK: - Recording detail presentation

private struct MacRecordingDetailFactsGrid: View {
    let createdAtText: String
    let durationText: String
    let languageText: String
    let iCloudSyncStatus: RecordingICloudSyncStatus

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 280), spacing: 8, alignment: .leading)
    ]

    private var iCloudTint: Color {
        switch iCloudSyncStatus.state {
        case .uploaded:
            return AppTheme.success
        case .uploading:
            return AppTheme.info
        case .waiting, .iCloudUnavailable:
            return AppTheme.warning
        case .failed:
            return AppTheme.danger
        case .localOnly:
            return .secondary
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            MacRecordingDetailFactCell(
                systemImage: "calendar",
                text: createdAtText,
                tint: .secondary
            )
            MacRecordingDetailFactCell(
                systemImage: "clock",
                text: durationText,
                tint: .secondary
            )
            MacRecordingDetailFactCell(
                systemImage: "globe",
                text: languageText,
                tint: AppTheme.info
            )
            MacRecordingDetailFactCell(
                systemImage: iCloudSyncStatus.systemImage,
                text: iCloudSyncStatus.displayName,
                tint: iCloudTint
            )
        }
    }
}

private struct MacRecordingDetailFactCell: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 15)

            Text(verbatim: text)
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.cardBorder.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct MacRecordingDetailContextStrip: View {
    let tags: [String]
    let projectName: String?
    let categoryName: String?
    let location: RecordingLocation?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if let projectName {
                    MacRecordingDetailContextChip(
                        systemImage: "briefcase.fill",
                        text: projectName,
                        tint: AppTheme.brand
                    )
                }
                if let categoryName {
                    MacRecordingDetailContextChip(
                        systemImage: "folder.fill",
                        text: categoryName,
                        tint: AppTheme.purple
                    )
                }
                ForEach(tags, id: \.self) { tag in
                    MacRecordingDetailContextChip(
                        systemImage: "tag.fill",
                        text: tag,
                        tint: AppTheme.info
                    )
                }
                if let location {
                    MacRecordingDetailContextChip(
                        systemImage: "mappin.and.ellipse",
                        text: location.placeName
                            ?? "\(location.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.longitude.formatted(.number.precision(.fractionLength(4))))",
                        tint: AppTheme.success
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct MacRecordingDetailContextChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        Label {
            Text(verbatim: text)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.redditSans(.caption2, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(tint.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(colorScheme == .dark ? 0.42 : 0.12), lineWidth: 0.8)
        }
    }
}

private struct MacTranscriptSpeakerLegend: View {
    let speakers: [TranscriptSpeakerPresentation]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label {
                    Text(
                        verbatim: String(
                            format: String(localized: L10n.Recordings.transcriptSpeakersDetectedFormat),
                            speakers.count
                        )
                    )
                } icon: {
                    Image(systemName: "person.2.fill")
                }
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(AppTheme.elevatedBackground, in: Capsule())

                ForEach(speakers) { speaker in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speaker.tint)
                            .frame(width: 8, height: 8)
                        Text(verbatim: speaker.displayName)
                            .font(.redditSans(.caption, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(speaker.tint.opacity(0.10), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(speaker.tint.opacity(0.20), lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Retranscription pickers

private struct MacRetranscriptionLanguagePicker: View {
    let title: String
    let recordingLanguageID: String
    let languages: [TranscriptionLanguage]
    let onSelect: (TranscriptionLanguage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLanguages: [TranscriptionLanguage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = macLanguagesWithRecordingLanguageFirst(
            languages,
            recordingLanguageID: recordingLanguageID
        )
        guard !query.isEmpty else {
            return ordered
        }
        return ordered.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredLanguages) { language in
                Button {
                    onSelect(language)
                } label: {
                    HStack {
                        Text(verbatim: language.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if macTranscriptionLanguageMatches(language, languageID: recordingLanguageID) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppTheme.brand)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.Common.cancel)
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 520)
    }
}

private struct MacWhisperRetranscriptionPicker: View {
    let recordingLanguageID: String
    let downloadedModels: [LocalWhisperModel]
    let languageOptionsByModelID: [String: [TranscriptionLanguage]]
    let onSelect: (TranscriptionLanguage, LocalWhisperModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedModelID: LocalWhisperModel.ID
    @State private var searchText = ""

    init(
        recordingLanguageID: String,
        downloadedModels: [LocalWhisperModel],
        languageOptionsByModelID: [String: [TranscriptionLanguage]],
        onSelect: @escaping (TranscriptionLanguage, LocalWhisperModel) -> Void
    ) {
        self.recordingLanguageID = recordingLanguageID
        self.downloadedModels = downloadedModels
        self.languageOptionsByModelID = languageOptionsByModelID
        self.onSelect = onSelect
        let preferredModelID = downloadedModels.first(where: {
            $0.id == LocalWhisperModelManager.selectedModel.id
        })?.id ?? downloadedModels.first?.id ?? LocalWhisperModelManager.selectedModel.id
        _selectedModelID = State(initialValue: preferredModelID)
    }

    private var selectedModel: LocalWhisperModel? {
        downloadedModels.first(where: { $0.id == selectedModelID }) ?? downloadedModels.first
    }

    private var filteredLanguages: [TranscriptionLanguage] {
        guard let selectedModel else {
            return []
        }
        let ordered = macLanguagesWithRecordingLanguageFirst(
            languageOptionsByModelID[selectedModel.id] ?? [],
            recordingLanguageID: recordingLanguageID
        )
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return ordered
        }
        return ordered.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(downloadedModels) { model in
                        Button {
                            selectedModelID = model.id
                        } label: {
                            HStack {
                                Label(model.displayName, systemImage: macWhisperModelIcon(for: model))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedModelID == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.brand)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.LocalWhisper.modelTitle)
                }

                Section {
                    ForEach(filteredLanguages) { language in
                        Button {
                            guard let selectedModel else {
                                return
                            }
                            onSelect(language, selectedModel)
                        } label: {
                            HStack {
                                Text(verbatim: language.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if macTranscriptionLanguageMatches(language, languageID: recordingLanguageID) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.brand)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.Recordings.chooseTranscriptionLanguage)
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(String(localized: L10n.Recordings.retranscribeWithLocalWhisper))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.Common.cancel)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 600)
    }
}

private func macWhisperModelIcon(for model: LocalWhisperModel) -> String {
    if model.id.contains("large") { return "archivebox.fill" }
    if model.id.contains("medium") { return "shippingbox.fill" }
    if model.id.contains("small") { return "cube.fill" }
    if model.id.contains("tiny") { return "cube" }
    return "shippingbox"
}

private func macTranscriptionLanguageMatches(
    _ language: TranscriptionLanguage,
    languageID: String
) -> Bool {
    let normalizedID = languageID.replacingOccurrences(of: "_", with: "-")
    let candidateID = language.id.replacingOccurrences(of: "_", with: "-")
    if candidateID.caseInsensitiveCompare(normalizedID) == .orderedSame {
        return true
    }
    return language.locale.language.languageCode?.identifier
        == Locale(identifier: normalizedID).language.languageCode?.identifier
}

private func macLanguagesWithRecordingLanguageFirst(
    _ languages: [TranscriptionLanguage],
    recordingLanguageID: String
) -> [TranscriptionLanguage] {
    guard let index = languages.firstIndex(where: {
        macTranscriptionLanguageMatches($0, languageID: recordingLanguageID)
    }), index != languages.startIndex else {
        return languages
    }
    var ordered = languages
    let recordingLanguage = ordered.remove(at: index)
    ordered.insert(recordingLanguage, at: ordered.startIndex)
    return ordered
}

// MARK: - Line edit host

struct MacTranscriptLineEdit: Identifiable {
    let lineID: String
    let timeText: String
    var text: String
    var speakerID: String?

    var id: String { lineID }
}

private struct MacTranscriptSpeakerPropagationRequest {
    let edit: MacTranscriptLineEdit
    let text: String
    let speakerID: String?
    let followingLines: [StoredTranscriptLine]
}

private struct MacTranscriptLineEditHost: View {
    let edit: MacTranscriptLineEdit
    let speakerPresentations: [TranscriptSpeakerPresentation]
    let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var speakerID: String?

    init(
        edit: MacTranscriptLineEdit,
        speakerPresentations: [TranscriptSpeakerPresentation],
        onSave: @escaping (String, String?) -> Void
    ) {
        self.edit = edit
        self.speakerPresentations = speakerPresentations
        self.onSave = onSave
        _text = State(initialValue: edit.text)
        _speakerID = State(initialValue: edit.speakerID)
    }

    private var speakerOptions: [TranscriptSpeakerEditOption] {
        speakerPresentations.map {
            TranscriptSpeakerEditOption(id: $0.id, displayName: $0.displayName, tint: $0.tint)
        }
    }

    private var newSpeakerOption: TranscriptSpeakerEditOption {
        let name = "Speaker \(speakerPresentations.count)"
        return TranscriptSpeakerEditOption(
            id: TranscriptSpeakerNaming.normalizedID(name) ?? name,
            displayName: name,
            tint: TranscriptSpeakerPalette.tint(for: speakerPresentations.count)
        )
    }

    var body: some View {
        TranscriptLineEditSheet(
            timeText: edit.timeText,
            text: $text,
            selectedSpeakerID: $speakerID,
            speakerOptions: speakerOptions,
            newSpeakerOption: newSpeakerOption,
            showsSpeakerEditor: !speakerPresentations.isEmpty,
            isSaving: false,
            onSave: {
                let resolvedSpeaker = speakerID.flatMap { id in
                    speakerOptions.first(where: { $0.id == id })?.displayName
                        ?? (id == newSpeakerOption.id ? newSpeakerOption.displayName : nil)
                }
                onSave(text, resolvedSpeaker)
            },
            onCancel: {
                dismiss()
            }
        )
        .frame(minWidth: 460, minHeight: 320)
    }
}
