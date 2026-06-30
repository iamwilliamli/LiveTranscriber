import CoreLocation
import MapKit
import SwiftUI
import Translation

struct TranscriptionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var recordingStore: RecordingStore
    @Binding var externalPendingRecordingDraft: RecordingDraft?
    @State private var savedRecordingName: String?
    @State private var savedRecordingBannerIsVisible = false
    @State private var savedRecordingBannerTask: Task<Void, Never>?
    @StateObject private var locationProvider = RecordingLocationProvider()
    @State private var pendingRecordingSave: PendingRecordingSave?
    @State private var pendingRecordingName = ""
    @State private var pendingRecordingTags: [String] = []
    @State private var pendingRecordingIncludesLocation = false
    @State private var isSavingPendingRecording = false
    @State private var liveTranslationConfiguration: TranslationSession.Configuration?
    @State private var selectedLiveTranslationLanguage: TranscriptionLanguage?
    @State private var translatedLiveTranscriptByLineID: [TranscriptionLine.ID: String] = [:]
    @State private var liveTranslatedLineSignatures: [TranscriptionLine.ID: String] = [:]
    @State private var isTranslatingLiveTranscript = false
    @State private var liveTranslationErrorMessage: String?
    @State private var isShowingLiveTranslationLanguagePicker = false

    private var isCompletingRecording: Bool {
        pendingRecordingSave != nil || isSavingPendingRecording
    }

    private var finalTranscriptLines: [TranscriptionLine] {
        transcriber.transcriptLines.filter { line in
            line.isFinal && !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var finalTranscriptSignature: String {
        finalTranscriptLines
            .map { "\($0.id.uuidString)|\($0.startSeconds)|\($0.text.hashValue)" }
            .joined(separator: "\n")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.groupedBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                recorderCard

                transcriptCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, transcriber.isRecording ? 126 : 112)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            floatingRecorderDock
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            savedRecordingBanner
                .padding(.top, 10)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .zIndex(20)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy(duration: 0.22, extraBounce: 0.02), value: transcriber.isRecording)
        .animation(.snappy(duration: 0.2, extraBounce: 0.02), value: transcriber.isPaused)
        .task {
            await transcriber.refreshSupportedLanguages()
        }
        .translationTask(liveTranslationConfiguration) { session in
            await translateFinalTranscriptLines(using: session)
        }
        .onAppear {
            consumeExternalPendingRecordingDraftIfNeeded()
        }
        .onChange(of: finalTranscriptSignature) { _, _ in
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
        .sheet(item: $pendingRecordingSave) { pendingSave in
            RecordingSaveSheet(
                draft: pendingSave.draft,
                recordingName: $pendingRecordingName,
                tags: $pendingRecordingTags,
                includesLocation: $pendingRecordingIncludesLocation,
                locationProvider: locationProvider,
                isSaving: isSavingPendingRecording,
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

    @ViewBuilder
    private var savedRecordingBanner: some View {
        if let savedRecordingName {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.success)

                Text(String(format: String(localized: "已保存: %@"), savedRecordingName))
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

    private var recorderCard: some View {
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
        .cardSurface()
    }

    private var recorderDeck: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .fill(recorderDeckBackgroundColor)

            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(recorderDeckBorderColor, lineWidth: 1)

            RollingRecorderTimeText(
                text: formatDuration(transcriber.elapsedSeconds),
                color: recorderDeckPrimaryColor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.top, 18)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Label("实时转录", systemImage: "waveform.and.mic")
                        .font(.redditSans(.caption, weight: .bold))
                        .foregroundStyle(recorderDeckSecondaryColor)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)

                    Spacer(minLength: 8)

                    Text(transcriber.selectedAudioFormat.badgeText)
                        .font(.redditSans(.caption2, weight: .bold))
                        .foregroundStyle(recorderDeckPrimaryColor)
                        .padding(.horizontal, 8)
                        .frame(height: 25)
                        .background(recorderDeckPillColor, in: Capsule())
                }

                Spacer(minLength: 0)

                Text(transcriber.statusText)
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(transcriber.isRecording && !transcriber.isPaused ? AppTheme.brandSoft : recorderDeckSecondaryColor)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)
            }
            .padding(12)
        }
        .frame(height: 138)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var recorderDeckBackgroundColor: Color {
        AppTheme.elevatedBackground
    }

    private var recorderDeckPrimaryColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var recorderDeckSecondaryColor: Color {
        colorScheme == .dark ? .white.opacity(0.72) : .secondary
    }

    private var recorderDeckBorderColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.10)
    }

    private var recorderDeckPillColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.06)
    }

    private var languageMenu: some View {
        Menu {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        HapticFeedback.play(.menuSelection)
                        transcriber.selectedLanguageID = language.id
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == transcriber.selectedLanguageID ? "checkmark" : "globe"
                    )
                }
            }
        } label: {
            StatusPill(
                systemImage: "globe",
                title: transcriber.selectedLanguage.displayName,
                tint: AppTheme.info
            )
        }
        .buttonStyle(.plain)
        .disabled(transcriber.isRecording || transcriber.isPreparing)
    }

    @ViewBuilder
    private var floatingRecorderDock: some View {
        if transcriber.isRecording {
            HStack(spacing: 10) {
                FloatingControlButton(
                    title: transcriber.isPaused ? "继续" : "暂停",
                    systemImage: transcriber.isPaused ? "play.fill" : "pause.fill",
                    tint: .primary,
                    background: Color.secondary.opacity(0.14)
                ) {
                    togglePause()
                }

                FloatingControlButton(
                    title: "停止",
                    systemImage: "stop.fill",
                    tint: .white,
                    background: AppTheme.danger
                ) {
                    stopRecording()
                }
            }
            .padding(8)
            .floatingDockSurface()
        } else {
            Button {
                startRecording()
            } label: {
                HStack(spacing: 12) {
                    if transcriber.isPreparing {
                        ProgressView()
                            .tint(.white)
                            .controlSize(.small)
                    } else if isCompletingRecording {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 20, weight: .semibold))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }

                    Text(isCompletingRecording ? LocalizedStringKey("保存录音") : LocalizedStringKey("开始录音"))
                        .font(.redditSans(.subheadline, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .background(AppTheme.danger, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: AppTheme.danger.opacity(0.24), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(transcriber.isPreparing || isCompletingRecording)
        }
    }

    private func startRecording() {
        guard !isCompletingRecording else {
            return
        }
        HapticFeedback.play(.recordingStart)
        hideSavedRecordingBanner()
        Task {
            await transcriber.startRecording()
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
        pendingRecordingTags = []
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
            if let saved = await recordingStore.save(
                pendingRecordingSave.draft,
                preferredName: pendingRecordingName,
                manualTags: pendingRecordingTags,
                location: location
            ) {
                showSavedRecordingBanner(fileName: saved.audioFileName)
                transcriber.clearTranscript()
                self.pendingRecordingSave = nil
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
        pendingRecordingTags = []
        pendingRecordingIncludesLocation = false
        locationProvider.reset()
        transcriber.clearTranscript()
        HapticFeedback.play(.deleteConfirmed)
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
                Label("转录文本", systemImage: "text.alignleft")
                    .font(.redditSans(.headline))
                Spacer()
                liveTranscriptTranslationMenu
                Text("\(transcriber.transcriptLines.count)")
                    .font(.redditSans(.caption2).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            liveTranscriptTranslationStatus

            if !transcriber.transcriptLines.isEmpty {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            Color.clear
                                .frame(height: 1)
                                .id("transcript-top")

                            ForEach(transcriber.transcriptLines.reversed()) { line in
                                TranscriptionLineRow(
                                    line: line,
                                    translatedText: line.isFinal ? translatedLiveTranscriptByLineID[line.id] : nil,
                                    isShowingTranslation: isShowingLiveTranslationPlaceholder(for: line)
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onChange(of: transcriber.transcriptLines.count) { _, _ in
                            withAnimation(.snappy(duration: 0.2)) {
                                scrollProxy.scrollTo("transcript-top", anchor: .top)
                            }
                        }
                }
            } else {
                EmptyStateView(icon: "quote.bubble", title: "暂无文本")
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity)
        .cardSurface()
    }

    private var liveTranscriptTranslationMenu: some View {
        Button {
            HapticFeedback.play(.navigation)
            isShowingLiveTranslationLanguagePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectedLiveTranslationLanguage?.shortName ?? String(localized: "翻译"))
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
        transcriber.supportedLanguages.filter { language in
            !Self.sameBaseLanguage(language.id, transcriber.selectedLanguageID)
        }
    }

    private func liveTranslationStatusText(for language: TranscriptionLanguage) -> String {
        if let liveTranslationErrorMessage {
            return liveTranslationErrorMessage
        }
        if finalTranscriptLines.isEmpty {
            return String(localized: "等待已完成段落")
        }
        if isTranslatingLiveTranscript {
            return String(localized: "正在翻译已完成段落")
        }
        return String(format: String(localized: "翻译成 %@"), language.displayName)
    }

    private func requestLiveTranscriptTranslation(to language: TranscriptionLanguage) {
        guard !Self.sameBaseLanguage(language.id, transcriber.selectedLanguageID) else {
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
            source: Self.localeLanguage(for: transcriber.selectedLanguageID),
            target: Self.localeLanguage(for: language.id)
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
                      let currentLine = transcriber.transcriptLines.first(where: { $0.id == lineID && $0.isFinal }),
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

    private func isShowingLiveTranslationPlaceholder(for line: TranscriptionLine) -> Bool {
        guard line.isFinal,
              isTranslatingLiveTranscript,
              let language = selectedLiveTranslationLanguage else {
            return false
        }
        return liveTranslatedLineSignatures[line.id] != liveTranslationSignature(for: line, language: language)
    }

    private func pruneLiveTranslationState() {
        let finalLineIDs = Set(finalTranscriptLines.map(\.id))
        translatedLiveTranscriptByLineID = translatedLiveTranscriptByLineID.filter { finalLineIDs.contains($0.key) }
        liveTranslatedLineSignatures = liveTranslatedLineSignatures.filter { finalLineIDs.contains($0.key) }
    }

    private func liveTranslationSignature(for line: TranscriptionLine, language: TranscriptionLanguage) -> String {
        "\(language.id)|\(line.id.uuidString)|\(line.text.hashValue)"
    }

    private static func localeLanguage(for identifier: String) -> Locale.Language? {
        let language = Locale(identifier: identifier).language
        guard language.languageCode != nil else {
            return nil
        }
        return language
    }

    private static func sameBaseLanguage(_ firstIdentifier: String, _ secondIdentifier: String) -> Bool {
        let firstLanguage = Locale(identifier: firstIdentifier).language
        let secondLanguage = Locale(identifier: secondIdentifier).language
        let firstCode = firstLanguage.languageCode?.identifier
        let secondCode = secondLanguage.languageCode?.identifier
        guard let firstCode, let secondCode else {
            return firstIdentifier == secondIdentifier
        }
        return firstCode == secondCode
    }

    private func formatDuration(_ seconds: Int) -> String {
        TranscriptionLine.formatTimestamp(Double(seconds))
    }
}

private struct PendingRecordingSave: Identifiable {
    let id = UUID()
    let draft: RecordingDraft
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
                            title: String(localized: "原文"),
                            subtitle: String(localized: "停止实时翻译"),
                            systemImage: "text.alignleft",
                            isSelected: selectedLanguageID == nil
                        )
                    }
                    .foregroundStyle(.primary)
                }

                Section("翻译语言") {
                    if languages.isEmpty {
                        Text("暂无可翻译语言")
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
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("实时翻译")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
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
    @Binding var tags: [String]
    @Binding var includesLocation: Bool
    @ObservedObject var locationProvider: RecordingLocationProvider
    let isSaving: Bool
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
                    tagsEntry
                    durationRow
                    locationSection
                }
                .padding(16)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle("保存录音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("丢弃", role: .destructive) {
                        onDiscard()
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
                            Text("保存")
                                .font(.redditSans(.subheadline, weight: .semibold))
                        }
                    }
                    .disabled(isSaving || recordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .alert(
            "生成标题失败",
            isPresented: Binding(
                get: { titleGenerationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        titleGenerationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(titleGenerationErrorMessage ?? "")
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("录音名称", systemImage: "pencil")
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("录音名称", text: $recordingName)
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
                    .accessibilityLabel("AI 生成标题和标签")
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
                    titleGenerationErrorMessage = String(localized: "没有生成有效的标题")
                    HapticFeedback.play(.failure)
                    isGeneratingTitle = false
                    return
                }
                recordingName = cleanedTitle
                tags = RecordingItem.mergedTags(tags, suggestion.tags)
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
                Label("标签", systemImage: "tag")
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(tags.isEmpty ? String(localized: "未添加") : "\(tags.count)")
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
            Label("音频时长", systemImage: "clock")
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
                Label("添加地理位置", systemImage: "location")
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
                    TextField("添加标签", text: $newTag)
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
                    Text("暂无标签")
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
        .navigationTitle("标签")
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
                    Marker("当前位置", coordinate: coordinate)
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
                Label("位置权限被拒绝", systemImage: "location.slash")
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
                    Text("正在获取位置")
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
            errorText = String(localized: "位置权限被拒绝")
        @unknown default:
            errorText = String(localized: "无法获取位置")
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

private struct RollingRecorderTimeText: View {
    let text: String
    let color: Color

    private let digitHeight: CGFloat = 46
    private let digitWidth: CGFloat = 27
    private let separatorWidth: CGFloat = 18

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                if let value = character.wholeNumberValue {
                    RollingRecorderDigit(
                        value: value,
                        width: digitWidth,
                        height: digitHeight,
                        color: color
                    )
                } else {
                    Text(String(character))
                        .font(.system(size: 36, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .frame(width: separatorWidth, height: digitHeight)
                }
            }
        }
        .accessibilityLabel(text)
    }
}

private struct RollingRecorderDigit: View {
    let value: Int
    let width: CGFloat
    let height: CGFloat
    let color: Color

    @State private var rollingValue = 0

    init(value: Int, width: CGFloat, height: CGFloat, color: Color) {
        self.value = value
        self.width = width
        self.height = height
        self.color = color
        _rollingValue = State(initialValue: 10 + (value % 10))
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<30, id: \.self) { index in
                Text("\(index % 10)")
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: width, height: height)
            }
        }
        .offset(y: -CGFloat(rollingValue) * height)
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .onAppear {
            reset(to: value)
        }
        .onChange(of: value) { _, newValue in
            roll(to: newValue)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: rollingValue)
    }

    private func roll(to newValue: Int) {
        let currentValue = rollingValue % 10
        let step = (newValue - currentValue + 10) % 10
        guard step != 0 else {
            return
        }

        rollingValue += step
        if rollingValue >= 20 {
            let resetValue = 10 + newValue
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                reset(to: resetValue)
            }
        }
    }

    private func reset(to newValue: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rollingValue = 10 + (newValue % 10)
        }
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

private struct TranscriptionLineRow: View {
    let line: TranscriptionLine
    let translatedText: String?
    let isShowingTranslation: Bool

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
                    Text("正在翻译")
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
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

    private var title: LocalizedStringKey {
        if isPreparing {
            return "正在请求权限"
        }
        if isRecording {
            return isPaused ? "已暂停" : "正在录音"
        }
        return "准备就绪"
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

    var body: some View {
        Label(title, systemImage: isRecording && !isPaused ? "record.circle" : "checkmark.circle")
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

private struct FloatingControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.redditSans(.subheadline, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
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
            .shadow(color: AppTheme.cardShadow, radius: 7, y: 2)
    }

    func floatingDockSurface() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
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
