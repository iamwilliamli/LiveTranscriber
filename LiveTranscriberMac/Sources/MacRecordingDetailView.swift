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

    private var currentItem: RecordingItem {
        store.recording(withID: item.id) ?? item
    }

    private var speakerPresentations: [TranscriptSpeakerPresentation] {
        TranscriptSpeakerPresentation.makePresentations(for: transcriptLines)
    }

    private var isBusyTranscribing: Bool {
        currentItem.importStatus?.isFailed == false
    }

    var body: some View {
        VStack(spacing: 0) {
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
            .padding(.vertical, 10)

            Divider()

            switch page {
            case .transcript:
                transcriptPage
            case .aiAnalysis:
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
            }
        }
        .toolbar {
            ToolbarItemGroup {
                detailActionsMenu
            }
        }
        .task(id: currentItem.transcriptFileName + "\(currentItem.lineCount)") {
            await loadTranscript()
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    playbackCard
                    transcriptCard
                }
                .padding(22)
                .frame(maxWidth: 860, alignment: .leading)
            }
            .onChange(of: player.currentTime) { _, time in
                guard player.currentItem?.id == currentItem.id, player.isPlaying else {
                    return
                }
                if let lineID = StoredTranscriptLine.currentLineID(in: transcriptLines, time: time) {
                    proxy.scrollTo(lineID, anchor: .center)
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: currentItem.displayName)
                    .font(.title.bold())
                    .textSelection(.enabled)
                if currentItem.isTranscriptLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text(currentItem.createdAt, format: .dateTime.year().month().day().hour().minute())
                Text(TranscriptionLine.formatTimestamp(Double(currentItem.durationSeconds)))
                    .monospacedDigit()
                Text(verbatim: currentItem.localizedLanguageName)
                HStack(spacing: 3) {
                    Text(verbatim: "\(currentItem.lineCount)")
                        .monospacedDigit()
                    Text(L10n.Recordings.transcript)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if currentItem.categoryName != nil
                || currentItem.projectName != nil
                || currentItem.location != nil
                || !currentItem.combinedTags.isEmpty {
                HStack(spacing: 6) {
                    if let categoryName = currentItem.categoryName {
                        chip(text: categoryName, systemImage: "folder")
                    }
                    if let projectName = currentItem.projectName {
                        chip(text: projectName, systemImage: "briefcase")
                    }
                    if let location = currentItem.location {
                        chip(
                            text: location.placeName
                                ?? "\(location.latitude.formatted(.number.precision(.fractionLength(4)))), \(location.longitude.formatted(.number.precision(.fractionLength(4))))",
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                    ForEach(currentItem.combinedTags.prefix(6), id: \.self) { tag in
                        chip(text: tag, systemImage: "tag")
                    }
                }
            }

            if let keyPoints = currentItem.keyPoints,
               !keyPoints.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label {
                    Text(verbatim: keyPoints)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "list.bullet.clipboard")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if let importStatus = currentItem.importStatus {
                Group {
                    if importStatus.isFailed {
                        HStack(spacing: 8) {
                            Label {
                                Text(verbatim: importStatus.message)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                            .foregroundStyle(AppTheme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                store.dismissFailedImportStatus(for: currentItem.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: L10n.Common.close))
                        }
                        .font(.caption)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: importStatus.progress)
                            Text(verbatim: importStatus.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(text: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private var playbackCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    preparePlayerIfNeeded()
                    player.togglePlayback()
                } label: {
                    Image(
                        systemName: player.currentItem?.id == currentItem.id && player.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.title3)
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)

                Button {
                    preparePlayerIfNeeded()
                    player.skip(by: -5)
                } label: {
                    Image(systemName: "gobackward.5")
                }

                Button {
                    preparePlayerIfNeeded()
                    player.skip(by: 5)
                } label: {
                    Image(systemName: "goforward.5")
                }

                Slider(
                    value: Binding(
                        get: {
                            player.currentItem?.id == currentItem.id
                                ? min(player.currentTime, max(player.duration, 0))
                                : 0
                        },
                        set: { newValue in
                            preparePlayerIfNeeded()
                            player.seek(to: newValue)
                        }
                    ),
                    in: 0...max(
                        player.currentItem?.id == currentItem.id && player.duration > 0
                            ? player.duration
                            : Double(max(currentItem.durationSeconds, 1)),
                        1
                    )
                )

                Text(
                    verbatim: "\(TranscriptionLine.formatTimestamp(player.currentItem?.id == currentItem.id ? player.currentTime : 0)) / \(TranscriptionLine.formatTimestamp(player.currentItem?.id == currentItem.id && player.duration > 0 ? player.duration : Double(currentItem.durationSeconds)))"
                )
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

                Menu {
                    ForEach(RecordingPlaybackController.availablePlaybackRates, id: \.self) { rate in
                        Button {
                            player.setPlaybackRate(rate)
                        } label: {
                            if player.playbackRate == rate {
                                Label(
                                    RecordingPlaybackController.playbackRateLabel(rate),
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(verbatim: RecordingPlaybackController.playbackRateLabel(rate))
                            }
                        }
                    }
                } label: {
                    Text(verbatim: RecordingPlaybackController.playbackRateLabel(player.playbackRate))
                        .monospacedDigit()
                }
                .frame(width: 72)

                Button {
                    if currentItem.audioEventAnalysis == nil {
                        analyzeAudioEvents()
                    } else {
                        isShowingAudioEvents = true
                    }
                } label: {
                    if isAnalyzingAudioEvents {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                    }
                }
                .help(String(localized: L10n.Recordings.audioEvents))
                .disabled(isAnalyzingAudioEvents)
            }

            if let events = currentItem.audioEventAnalysis?.events, !events.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(events) { event in
                            Button {
                                preparePlayerIfNeeded()
                                player.seek(to: event.startTime)
                            } label: {
                                Label {
                                    Text(verbatim: event.localizedLabel)
                                } icon: {
                                    Text(verbatim: TranscriptionLine.formatTimestamp(event.startTime))
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let errorText = player.errorText {
                Label {
                    Text(verbatim: errorText)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.Recordings.transcript)
                    .font(.title3.bold())
                Spacer()
                if speakerPresentations.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(speakerPresentations) { speaker in
                            Label {
                                Text(verbatim: speaker.displayName)
                            } icon: {
                                Circle()
                                    .fill(speaker.tint)
                                    .frame(width: 8, height: 8)
                            }
                            .font(.caption)
                        }
                    }
                }

                transcriptTranslationMenu
            }

            transcriptTranslationStatus

            if isLoadingTranscript {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else if transcriptLines.isEmpty {
                Text(MacL10n.noTranscript)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                let currentLineID = player.currentItem?.id == currentItem.id
                    ? StoredTranscriptLine.currentLineID(in: transcriptLines, time: player.currentTime)
                    : nil
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(transcriptLines) { line in
                        MacTranscriptLineRow(
                            line: line,
                            speaker: speakerPresentations.first {
                                $0.id == TranscriptSpeakerNaming.normalizedID(line.speaker)
                            },
                            isCurrent: line.id == currentLineID,
                            onSeek: {
                                preparePlayerIfNeeded()
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
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            Label {
                Text(verbatim: selectedTranslationLanguage?.shortName ?? String(localized: L10n.Recordings.translate))
            } icon: {
                Image(systemName: "translate")
            }
        }
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
                    .font(.title3.bold())
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
                    .font(.title3.bold())
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
                        .textSelection(.enabled)
                }

                if !analysis.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.Recordings.actionItems)
                                .font(.headline)
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
                            .font(.headline)
                        ForEach(analysis.decisions) { decision in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: decision.decision)
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
                            .font(.headline)
                        ForEach(analysis.openQuestions) { question in
                            Text(verbatim: question.question)
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
                Text(L10n.Recordings.retranscribe)
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
        guard player.currentItem?.id != currentItem.id || !player.isLoaded else {
            return
        }
        player.load(item: currentItem, url: store.audioURL(for: currentItem))
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: line.timeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? AppTheme.brand : Color.secondary)
                .frame(width: 66, alignment: .leading)

            if let speaker {
                Text(verbatim: speaker.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(speaker.tint)
                    .frame(width: 82, alignment: .leading)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: translatedText ?? line.spokenText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if translatedText != nil {
                    Text(verbatim: line.spokenText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if isShowingTranslation {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            isCurrent ? AppTheme.brand.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
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
