import AVFoundation
import CoreLocation
import MapKit
import MediaPlayer
import OSLog
import SwiftUI
import Translation
import UIKit
import UniformTypeIdentifiers

private func localized(_ resource: LocalizedStringResource) -> String {
    String(localized: resource)
}

private func localizedFormat(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
    String(format: String(localized: resource), arguments: arguments)
}

private func localWhisperDownloadedModels() -> [LocalWhisperModel] {
    LocalWhisperModelManager.downloadedStatuses().map(\.model)
}

private func localWhisperSupportedLanguages(for model: LocalWhisperModel) -> [TranscriptionLanguage] {
    LocalWhisperTranscriptionService.supportedLanguages(for: model)
}

private func localWhisperMenuLanguageOptions(for models: [LocalWhisperModel]) -> [String: [TranscriptionLanguage]] {
    Dictionary(
        uniqueKeysWithValues: models.map { model in
            (model.id, localWhisperSupportedLanguages(for: model))
        }
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

private func transcriptionLanguageMatches(_ language: TranscriptionLanguage, languageID: String) -> Bool {
    transcriptionLanguageMatchRank(language, languageID: languageID) != nil
}

private func transcriptionLanguageMatchRank(_ language: TranscriptionLanguage, languageID: String) -> Int? {
    let normalizedLanguageID = languageID.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "-")
    guard !normalizedLanguageID.isEmpty else {
        return nil
    }

    let normalizedCandidateID = language.id.replacingOccurrences(of: "_", with: "-")
    if normalizedCandidateID == normalizedLanguageID {
        return 0
    }

    let candidateLanguage = language.locale.language
    let recordingLanguage = Locale(identifier: normalizedLanguageID).language
    guard let candidateCode = candidateLanguage.languageCode?.identifier,
          let recordingCode = recordingLanguage.languageCode?.identifier,
          candidateCode == recordingCode else {
        return nil
    }

    if let recordingRegion = recordingLanguage.region?.identifier,
       candidateLanguage.region?.identifier == recordingRegion {
        return 1
    }

    if let recordingScript = recordingLanguage.script?.identifier,
       candidateLanguage.script?.identifier == recordingScript {
        return 2
    }

    if recordingLanguage.region == nil && recordingLanguage.script == nil {
        if let preferredRegion = preferredRegionForBaseLanguage(recordingCode),
           candidateLanguage.region?.identifier == preferredRegion {
            return 3
        }
        return 4
    }

    return 5
}

private func preferredRegionForBaseLanguage(_ languageCode: String) -> String? {
    switch languageCode {
    case "en":
        return "US"
    default:
        return nil
    }
}

private func transcriptionLanguagesWithRecordingLanguageFirst(
    _ languages: [TranscriptionLanguage],
    recordingLanguageID: String
) -> [TranscriptionLanguage] {
    guard let bestMatch = languages.indices.compactMap({ index -> (index: Int, rank: Int)? in
        guard let rank = transcriptionLanguageMatchRank(languages[index], languageID: recordingLanguageID) else {
            return nil
        }
        return (index, rank)
    })
    .min(by: { first, second in
        if first.rank != second.rank {
            return first.rank < second.rank
        }
        return first.index < second.index
    }) else {
        return languages
    }

    guard bestMatch.index != languages.startIndex else {
        return languages
    }

    var orderedLanguages = languages
    let recordingLanguage = orderedLanguages.remove(at: bestMatch.index)
    orderedLanguages.insert(recordingLanguage, at: orderedLanguages.startIndex)
    return orderedLanguages
}

private struct LocalWhisperRetranscriptionRequest: Identifiable {
    let item: RecordingItem

    var id: RecordingItem.ID {
        item.id
    }
}

private struct AppleSpeechRetranscriptionRequest: Identifiable {
    let item: RecordingItem

    var id: RecordingItem.ID {
        item.id
    }
}

private struct RecordingRetranscriptionLanguagePicker: View {
    let title: String
    let recordingLanguageID: String
    let languages: [TranscriptionLanguage]
    let onCancel: () -> Void
    let onSelect: (TranscriptionLanguage) -> Void

    @State private var searchText = ""

    private var orderedLanguages: [TranscriptionLanguage] {
        transcriptionLanguagesWithRecordingLanguageFirst(
            languages,
            recordingLanguageID: recordingLanguageID
        )
    }

    private var filteredLanguages: [TranscriptionLanguage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return orderedLanguages
        }

        return orderedLanguages.filter { language in
            language.displayName.localizedCaseInsensitiveContains(query)
                || language.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredLanguages) { language in
                Button {
                    onSelect(language)
                } label: {
                    HStack(spacing: 12) {
                        Text(language.displayName)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        if transcriptionLanguageMatches(language, languageID: recordingLanguageID) {
                            Image(systemName: "checkmark")
                                .font(.redditSans(.caption, weight: .bold))
                                .foregroundStyle(AppTheme.brand)
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
                    }
                }
            }
        }
    }
}

private struct LocalWhisperRetranscriptionButton: View {
    let downloadedModels: [LocalWhisperModel]
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(localized(L10n.Recordings.retranscribeWithLocalWhisper), systemImage: "iphone")
        }
        .disabled(isDisabled || downloadedModels.isEmpty)
        .accessibilityHint(downloadedModels.isEmpty ? localized(L10n.LocalWhisper.noDownloadedModels) : "")
    }
}

private struct LocalWhisperRetranscriptionPicker: View {
    let recordingLanguageID: String
    let downloadedModels: [LocalWhisperModel]
    let languageOptionsByModelID: [String: [TranscriptionLanguage]]
    let onCancel: () -> Void
    let onSelect: (TranscriptionLanguage, LocalWhisperModel) -> Void

    @State private var selectedModelID: LocalWhisperModel.ID
    @State private var searchText = ""

    init(
        recordingLanguageID: String,
        downloadedModels: [LocalWhisperModel],
        languageOptionsByModelID: [String: [TranscriptionLanguage]],
        onCancel: @escaping () -> Void,
        onSelect: @escaping (TranscriptionLanguage, LocalWhisperModel) -> Void
    ) {
        self.recordingLanguageID = recordingLanguageID
        self.downloadedModels = downloadedModels
        self.languageOptionsByModelID = languageOptionsByModelID
        self.onCancel = onCancel
        self.onSelect = onSelect

        let preferredModelID = downloadedModels.first { $0.id == LocalWhisperModelManager.selectedModel.id }?.id
            ?? downloadedModels.first?.id
            ?? LocalWhisperModelManager.selectedModel.id
        _selectedModelID = State(initialValue: preferredModelID)
    }

    private var selectedModel: LocalWhisperModel? {
        downloadedModels.first { $0.id == selectedModelID } ?? downloadedModels.first
    }

    private var orderedLanguages: [TranscriptionLanguage] {
        guard let selectedModel else {
            return []
        }

        return transcriptionLanguagesWithRecordingLanguageFirst(
            languageOptionsByModelID[selectedModel.id] ?? [],
            recordingLanguageID: recordingLanguageID
        )
    }

    private var filteredLanguages: [TranscriptionLanguage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return orderedLanguages
        }

        return orderedLanguages.filter { language in
            language.displayName.localizedCaseInsensitiveContains(query)
                || language.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if downloadedModels.isEmpty {
                    Label(localized(L10n.LocalWhisper.noDownloadedModels), systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                } else {
                    Section(localized(L10n.LocalWhisper.modelTitle)) {
                        ForEach(downloadedModels) { model in
                            Button {
                                selectedModelID = model.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: localWhisperModelIcon(for: model))
                                        .foregroundStyle(AppTheme.info)
                                        .frame(width: 22)

                                    Text(model.displayName)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 8)

                                    if selectedModelID == model.id {
                                        Image(systemName: "checkmark")
                                            .font(.redditSans(.caption, weight: .bold))
                                            .foregroundStyle(AppTheme.brand)
                                    }
                                }
                            }
                        }
                    }

                    Section(localized(L10n.Recordings.chooseTranscriptionLanguage)) {
                        ForEach(filteredLanguages) { language in
                            Button {
                                if let selectedModel {
                                    onSelect(language, selectedModel)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(language.displayName)
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 8)

                                    if transcriptionLanguageMatches(language, languageID: recordingLanguageID) {
                                        Image(systemName: "checkmark")
                                            .font(.redditSans(.caption, weight: .bold))
                                            .foregroundStyle(AppTheme.brand)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(localized(L10n.Recordings.retranscribeWithLocalWhisper))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
                    }
                }
            }
        }
    }
}

private struct TranscriptTranslationLanguagePicker: View {
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

private struct SummaryAnalysisMenu<LabelContent: View>: View {
    let selectedProvider: RecordingSummaryProvider
    let providerAvailability: RecordingSummaryProviderAvailability
    let isDisabled: Bool
    let primaryAction: (() -> Void)?
    let onSelect: (RecordingSummaryProvider) -> Void
    @ViewBuilder var label: () -> LabelContent

    init(
        selectedProvider: RecordingSummaryProvider,
        providerAvailability: RecordingSummaryProviderAvailability,
        isDisabled: Bool,
        primaryAction: (() -> Void)? = nil,
        onSelect: @escaping (RecordingSummaryProvider) -> Void,
        @ViewBuilder label: @escaping () -> LabelContent
    ) {
        self.selectedProvider = selectedProvider
        self.providerAvailability = providerAvailability
        self.isDisabled = isDisabled
        self.primaryAction = primaryAction
        self.onSelect = onSelect
        self.label = label
    }

    var body: some View {
        Group {
            if let primaryAction {
                Menu {
                    menuItems
                } label: {
                    label()
                } primaryAction: {
                    primaryAction()
                }
            } else {
                Menu {
                    menuItems
                } label: {
                    label()
                }
            }
        }
        .disabled(isDisabled || !providerAvailability.hasAnyAvailableProvider)
    }

    @ViewBuilder
    private var menuItems: some View {
        ForEach(RecordingSummaryProvider.menuProviders) { provider in
            Button {
                onSelect(provider)
            } label: {
                Label(
                    provider.displayName,
                    systemImage: provider == selectedProvider ? "checkmark" : provider.systemImage
                )
            }
            .disabled(!providerAvailability.isAvailable(provider))
        }
    }
}

struct RecordingsView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @Binding var incomingImportURL: URL?
    @Binding var pendingOpenRecordingID: RecordingItem.ID?
    @ObservedObject var player: RecordingPlaybackController
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var selectedRecording: RecordingItem?
    @State private var analyzingRecordingID: RecordingItem.ID?
    @State private var analysisErrorMessage: String?
    @State private var showsImporter = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var transcriptionErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var pendingSpeechLocaleReleaseAction: PendingSpeechLocaleReleaseAction?
    @State private var appleSpeechRetranscriptionRequest: AppleSpeechRetranscriptionRequest?
    @State private var appleSpeechTranscriptionLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @State private var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    @State private var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]
    @State private var localWhisperRetranscriptionRequest: LocalWhisperRetranscriptionRequest?
    @State private var searchText = ""
    @State private var isShowingRecordingsMap = false
    @State private var hidesTabBarForRecordingDetail = false
    @State private var tabBarRestoreTask: Task<Void, Never>?
    @AppStorage(RecordingSummaryProvider.selectedDefaultsKey) private var selectedSummaryProviderRawValue = RecordingSummaryProvider.automatic.rawValue

    private var selectedSummaryProvider: RecordingSummaryProvider {
        RecordingSummaryProvider(rawValue: selectedSummaryProviderRawValue) ?? .automatic
    }

    private var filteredRecordings: [RecordingItem] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return store.recordings
        }

        return store.recordings.filter { item in
            recording(item, matches: query)
        }
    }

    var body: some View {
        NavigationStack {
            recordingsList
                .navigationTitle(localized(L10n.Recordings.title))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    recordingsToolbar
                }
                .navigationDestination(item: $selectedRecording) { item in
                    RecordingDetailView(
                        item: item,
                        store: store,
                        transcriber: transcriber,
                        player: player,
                        downloadedLocalWhisperModels: downloadedLocalWhisperModels,
                        localWhisperLanguageOptionsByModelID: localWhisperLanguageOptionsByModelID
                    )
                }
        }
        .toolbar(hidesTabBarForRecordingDetail ? .hidden : .visible, for: .tabBar)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(L10n.Recordings.searchPrompt)
        )
        .task {
            await transcriber.refreshSupportedLanguages()
            appleSpeechTranscriptionLanguages = await AppleSpeechTranscriptionSupport.supportedLanguages()
            await refreshLocalWhisperMenuOptions()
            await store.reload()
            store.refreshIntelligenceAvailability()
            consumePendingOpenRecordingIDIfNeeded()
        }
        .onAppear {
            consumeIncomingImportURLIfNeeded()
            consumePendingOpenRecordingIDIfNeeded()
        }
        .onChange(of: incomingImportURL) { _, newURL in
            guard let newURL else {
                return
            }

            consumeIncomingImportURL(newURL)
        }
        .onChange(of: pendingOpenRecordingID) { _, _ in
            consumePendingOpenRecordingIDIfNeeded()
        }
        .onChange(of: store.recordings) { _, _ in
            consumePendingOpenRecordingIDIfNeeded()
        }
        .onChange(of: selectedRecording?.id) { _, newValue in
            if newValue == nil {
                HapticFeedback.play(.navigation)
                scheduleTabBarRestoreAfterPop()
            } else {
                hideTabBarForDetail()
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .sheet(isPresented: $isShowingRecordingsMap) {
            RecordingMapView(store: store, transcriber: transcriber, player: player)
        }
        .sheet(item: $localWhisperRetranscriptionRequest) { request in
            LocalWhisperRetranscriptionPicker(
                recordingLanguageID: request.item.languageID,
                downloadedModels: downloadedLocalWhisperModels,
                languageOptionsByModelID: localWhisperLanguageOptionsByModelID,
                onCancel: {
                    localWhisperRetranscriptionRequest = nil
                },
                onSelect: { language, model in
                    localWhisperRetranscriptionRequest = nil
                    retranscribeWithLocalWhisper(request.item, language: language, model: model)
                }
            )
        }
        .sheet(item: $appleSpeechRetranscriptionRequest) { request in
            RecordingRetranscriptionLanguagePicker(
                title: localized(L10n.Recordings.retranscribe),
                recordingLanguageID: request.item.languageID,
                languages: appleSpeechTranscriptionLanguages,
                onCancel: {
                    appleSpeechRetranscriptionRequest = nil
                },
                onSelect: { language in
                    appleSpeechRetranscriptionRequest = nil
                    requestRetranscription(request.item, language: language)
                }
            )
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
            localized(L10n.Recordings.analysisFailed),
            isPresented: Binding(
                get: { analysisErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        analysisErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(analysisErrorMessage ?? "")
        }
        .alert(
            localized(L10n.Recordings.importFailed),
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        importErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(
            localized(L10n.Recordings.transcriptionFailed),
            isPresented: Binding(
                get: { transcriptionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        transcriptionErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(transcriptionErrorMessage ?? "")
        }
        .alert(
            localized(L10n.Recordings.deleteRecording),
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteRequest = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.delete), role: .destructive) {
                if let request = deleteRequest {
                    delete(request.item)
                    deleteRequest = nil
                }
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(localizedFormat(L10n.Recordings.deleteConfirmationFormat, deleteRequest?.item.audioFileName ?? ""))
        }
        .alert(
            localized(L10n.Recordings.deleteFailed),
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var recordingsList: some View {
        List {
            if store.recordings.isEmpty {
                EmptyStateView(icon: "waveform.path.badge.plus", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if filteredRecordings.isEmpty {
                EmptyStateView(icon: "magnifyingglass", titleResource: L10n.Recordings.noSearchResults)
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredRecordings) { item in
                    recordingRow(for: item)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
    }

    @ToolbarContentBuilder
    private var recordingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                }

                HStack(spacing: 0) {
                    Button {
                        HapticFeedback.play(.navigation)
                        isShowingRecordingsMap = true
                    } label: {
                        Image(systemName: "map")
                            .frame(width: 32, height: 28)
                    }
                    .accessibilityLabel(Text(L10n.Recordings.map))

                    Divider()
                        .frame(height: 18)
                        .fixedSize()

                    Button {
                        HapticFeedback.play(.primaryAction)
                        showsImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 32, height: 28)
                    }
                    .disabled(isImporting || transcriber.isRecording || transcriber.isPreparing)
                    .accessibilityLabel(Text(L10n.Recordings.importRecording))
                }
                .fixedSize()
            }
        }
    }

    private func recordingRow(for item: RecordingItem) -> some View {
        RecordingRow(
            item: item,
            isAnalyzing: analyzingRecordingID == item.id,
            canGenerateIntelligence: store.intelligenceAvailability.isAvailable
        ) {
            openRecording(item)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .contextMenu {
            Button {
                HapticFeedback.play(.copy)
                UIPasteboard.general.string = store.transcriptText(for: item)
            } label: {
                Label(localized(L10n.Recordings.copyTranscript), systemImage: "doc.on.doc")
            }

            if store.summaryProviderAvailability.hasAnyAvailableProvider {
                SummaryAnalysisMenu(
                    selectedProvider: selectedSummaryProvider,
                    providerAvailability: store.summaryProviderAvailability,
                    isDisabled: analyzingRecordingID != nil
                ) { provider in
                    analyze(item, summaryProvider: provider)
                } label: {
                    Label(
                        item.intelligence == nil
                            ? localized(L10n.Recordings.generateTagsAndSummary)
                            : localized(L10n.Recordings.analyzeAgain),
                        systemImage: "sparkles"
                    )
                }
            }

            Button {
                appleSpeechRetranscriptionRequest = AppleSpeechRetranscriptionRequest(item: item)
            } label: {
                Label(localized(L10n.Recordings.retranscribe), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(item.importStatus?.isFailed == false || transcriber.isRecording || transcriber.isPreparing)

            if transcriber.isOpenAITranscriptionEnabled {
                Menu {
                    Button {
                        retranscribeWithOpenAI(item, mode: .longForm)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribeWithOpenAILongForm), systemImage: "text.alignleft")
                    }

                    Button {
                        retranscribeWithOpenAI(item, mode: .segmented)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribeWithOpenAISegmented), systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        retranscribeWithOpenAI(item, mode: .refinedSegments)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribeWithOpenAIRefinedSegments), systemImage: "wand.and.sparkles")
                    }
                } label: {
                    Label(localized(L10n.Recordings.retranscribeWithOpenAI), systemImage: "cloud")
                }
                .disabled(item.importStatus?.isFailed == false || transcriber.isRecording || transcriber.isPreparing)
            }

            LocalWhisperRetranscriptionButton(
                downloadedModels: downloadedLocalWhisperModels,
                isDisabled: item.isTranscriptLocked || item.importStatus?.isFailed == false || transcriber.isRecording || transcriber.isPreparing
            ) {
                localWhisperRetranscriptionRequest = LocalWhisperRetranscriptionRequest(item: item)
            }

            Button(role: .destructive) {
                requestDelete(item)
            } label: {
                Label(localized(L10n.Common.delete), systemImage: "trash")
            }
            .disabled(item.importStatus?.isFailed == false)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if store.intelligenceAvailability.isAvailable {
                Button {
                    analyze(item, summaryProvider: selectedSummaryProvider)
                } label: {
                    Label(localized(L10n.Recordings.analyze), systemImage: "sparkles")
                }
                .tint(AppTheme.info)
                .disabled(analyzingRecordingID != nil)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                requestDelete(item)
            } label: {
                Label(localized(L10n.Common.delete), systemImage: "trash")
            }
            .tint(AppTheme.danger)
            .disabled(item.importStatus?.isFailed == false)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                HapticFeedback.play(.warning)
                return
            }
            queueImport(from: url)
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func consumeIncomingImportURLIfNeeded() {
        guard let incomingImportURL else {
            return
        }

        consumeIncomingImportURL(incomingImportURL)
    }

    private func consumeIncomingImportURL(_ url: URL) {
        queueImport(from: url)
        incomingImportURL = nil
    }

    private func refreshLocalWhisperMenuOptions() async {
        let menuOptions = await Task.detached(priority: .utility) {
            let models = localWhisperDownloadedModels()
            return (
                models,
                localWhisperMenuLanguageOptions(for: models)
            )
        }.value

        downloadedLocalWhisperModels = menuOptions.0
        localWhisperLanguageOptionsByModelID = menuOptions.1
    }

    private func queueImport(from url: URL) {
        guard !isImporting else {
            HapticFeedback.play(.blocked)
            return
        }

        selectedRecording = nil
        importRecording(from: url)
    }

    private func importRecording(from url: URL) {
        guard !isImporting else {
            HapticFeedback.play(.blocked)
            return
        }

        isImporting = true
        HapticFeedback.play(.importStart)
        Task {
            do {
                _ = try await store.importRecording(from: url)
                HapticFeedback.play(.importComplete)
            } catch {
                importErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isImporting = false
        }
    }

    private func requestRetranscription(_ item: RecordingItem, language: TranscriptionLanguage) {
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    language,
                    preservingLanguageIDs: [transcriber.selectedLanguageID, item.languageID]
                )
                switch preparation {
                case .ready:
                    retranscribe(item, language: language)
                case .needsRelease(let request):
                    pendingSpeechLocaleReleaseAction = PendingSpeechLocaleReleaseAction(
                        request: request,
                        operation: .retranscribe(item)
                    )
                    HapticFeedback.play(.warning)
                }
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func releaseSpeechLocalesAndContinue(_ pendingAction: PendingSpeechLocaleReleaseAction) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(pendingAction.request)
                switch pendingAction.operation {
                case .retranscribe(let item):
                    retranscribe(item, language: pendingAction.request.targetLanguage)
                }
            } catch {
                switch pendingAction.operation {
                case .retranscribe:
                    transcriptionErrorMessage = error.localizedDescription
                }
                HapticFeedback.play(.failure)
            }
        }
    }

    private func analyze(_ item: RecordingItem, summaryProvider: RecordingSummaryProvider) {
        guard store.summaryProviderAvailability.isAvailable(summaryProvider) else {
            HapticFeedback.play(.blocked)
            store.refreshIntelligenceAvailability()
            return
        }
        guard analyzingRecordingID == nil else {
            HapticFeedback.play(.blocked)
            return
        }

        analyzingRecordingID = item.id
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                _ = try await store.analyzeIntelligence(for: item, summaryProvider: summaryProvider)
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            analyzingRecordingID = nil
        }
    }

    private func openRecording(_ item: RecordingItem) {
        HapticFeedback.play(.navigation)
        hideTabBarForDetail()
        selectedRecording = item
    }

    private func consumePendingOpenRecordingIDIfNeeded() {
        guard let id = pendingOpenRecordingID,
              let item = store.recording(withID: id) else {
            return
        }

        pendingOpenRecordingID = nil
        openRecording(item)
    }

    private func hideTabBarForDetail() {
        tabBarRestoreTask?.cancel()
        tabBarRestoreTask = nil
        guard !hidesTabBarForRecordingDetail else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            hidesTabBarForRecordingDetail = true
        }
    }

    private func scheduleTabBarRestoreAfterPop() {
        tabBarRestoreTask?.cancel()
        tabBarRestoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard selectedRecording == nil else {
                return
            }

            withAnimation(.easeInOut(duration: 0.24)) {
                hidesTabBarForRecordingDetail = false
            }
            tabBarRestoreTask = nil
        }
    }

    private func retranscribe(_ item: RecordingItem, language: TranscriptionLanguage) {
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.retranscribe(item, language: language)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeWithOpenAI(_ item: RecordingItem, mode: OpenAIFileTranscriptionMode) {
        guard transcriber.isOpenAITranscriptionEnabled else {
            HapticFeedback.play(.blocked)
            return
        }
        guard item.importStatus?.isFailed != false else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let language = TranscriptionLanguage(id: item.languageID)
        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.retranscribeWithOpenAI(
                    item,
                    language: language,
                    apiKey: transcriber.openAIAPIKey,
                    mode: mode
                )
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeWithLocalWhisper(_ item: RecordingItem, language: TranscriptionLanguage, model: LocalWhisperModel? = nil) {
        guard item.importStatus?.isFailed != false else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.retranscribeWithLocalWhisper(item, language: language, model: model)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func requestDelete(_ item: RecordingItem) {
        guard store.recording(withID: item.id) != nil else {
            HapticFeedback.play(.warning)
            return
        }
        deleteRequest = RecordingDeleteRequest(item: item)
        HapticFeedback.play(.deleteRequested)
    }

    private func delete(_ item: RecordingItem) {
        do {
            if selectedRecording?.id == item.id {
                selectedRecording = nil
            }
            if analyzingRecordingID == item.id {
                analyzingRecordingID = nil
            }
            try store.delete(item)
            HapticFeedback.play(.deleteConfirmed)
        } catch {
            deleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func recording(_ item: RecordingItem, matches query: String) -> Bool {
        store.normalizedSearchText(for: item).contains(query)
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.normalizedForRecordingSearch
    }
}

private struct PendingSpeechLocaleReleaseAction: Identifiable {
    let request: SpeechLocaleReleaseRequest
    let operation: SpeechLocaleReleaseOperation

    var id: UUID {
        request.id
    }
}

private enum SpeechLocaleReleaseOperation {
    case retranscribe(RecordingItem)
}

private struct TranscriptLineEditRequest: Identifiable {
    let lineID: String
    let timeText: String

    var id: String {
        lineID
    }

    init(line: StoredTranscriptLine) {
        lineID = line.id
        timeText = line.timeText
    }

    init(line: TranscriptionLine) {
        lineID = line.id.uuidString
        timeText = line.timestampText
    }
}

private struct RecordingDeleteRequest: Identifiable {
    let item: RecordingItem

    var id: RecordingItem.ID {
        item.id
    }
}

struct RecordingMapView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPoint: RecordingMapPoint?
    @State private var selectedRecording: RecordingItem?
    @State private var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    @State private var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]

    private var points: [RecordingMapPoint] {
        store.recordings.compactMap { item in
            guard let location = item.location else {
                return nil
            }
            return RecordingMapPoint(item: item, location: location)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if points.isEmpty {
                    EmptyStateView(icon: "map", titleResource: L10n.Recordings.noLocatedRecordings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.groupedBackground)
                } else {
                    Map(initialPosition: .region(mapRegion)) {
                        ForEach(points) { point in
                            Annotation(point.title, coordinate: point.coordinate) {
                                Button {
                                    HapticFeedback.play(.navigation)
                                    selectedPoint = point
                                } label: {
                                    Image(systemName: selectedPoint?.id == point.id ? "waveform.circle.fill" : "waveform.circle")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(.white, AppTheme.brand)
                                        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selectedPoint {
                    RecordingMapSelectionCard(point: selectedPoint) {
                        selectedRecording = selectedPoint.item
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(localized(L10n.Recordings.mapTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized(L10n.Common.done)) {
                        dismiss()
                    }
                }
            }
            .task {
                let menuOptions = await Task.detached(priority: .utility) {
                    let models = localWhisperDownloadedModels()
                    return (
                        models,
                        localWhisperMenuLanguageOptions(for: models)
                    )
                }.value
                downloadedLocalWhisperModels = menuOptions.0
                localWhisperLanguageOptionsByModelID = menuOptions.1
            }
            .navigationDestination(item: $selectedRecording) { item in
                RecordingDetailView(
                    item: item,
                    store: store,
                    transcriber: transcriber,
                    player: player,
                    downloadedLocalWhisperModels: downloadedLocalWhisperModels,
                    localWhisperLanguageOptionsByModelID: localWhisperLanguageOptionsByModelID
                )
            }
            .onChange(of: selectedRecording?.id) { _, newValue in
                if newValue == nil {
                    HapticFeedback.play(.navigation)
                }
            }
        }
    }

    private var mapRegion: MKCoordinateRegion {
        guard let firstPoint = points.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        let latitudes = points.map(\.coordinate.latitude)
        let longitudes = points.map(\.coordinate.longitude)
        let minLatitude = latitudes.min() ?? firstPoint.coordinate.latitude
        let maxLatitude = latitudes.max() ?? firstPoint.coordinate.latitude
        let minLongitude = longitudes.min() ?? firstPoint.coordinate.longitude
        let maxLongitude = longitudes.max() ?? firstPoint.coordinate.longitude

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.01, (maxLatitude - minLatitude) * 1.8),
                longitudeDelta: max(0.01, (maxLongitude - minLongitude) * 1.8)
            )
        )
    }
}

private struct RecordingMapPoint: Identifiable {
    let id: RecordingItem.ID
    let item: RecordingItem
    let title: String
    let durationText: String
    let createdAt: Date
    let location: RecordingLocation
    let coordinate: CLLocationCoordinate2D

    init(item: RecordingItem, location: RecordingLocation) {
        id = item.id
        self.item = item
        title = (item.audioFileName as NSString).deletingPathExtension
        durationText = TranscriptionLine.formatTimestamp(Double(item.durationSeconds))
        createdAt = item.createdAt
        self.location = location
        coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }
}

private struct RecordingMapSelectionCard: View {
    let point: RecordingMapPoint
    let onOpen: () -> Void

    var body: some View {
        Button {
            HapticFeedback.play(.navigation)
            onOpen()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                        .fill(AppTheme.brand.opacity(0.14))
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(point.title)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Label {
                            RecordingLocationNameText(location: point.location)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        Label(point.durationText, systemImage: "clock")
                    }
                    .font(.redditSans(.caption).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private extension RecordingLocation {
    var locationName: String? {
        placeName
    }

    var coordinateText: String {
        "\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
    }

    var cacheKey: String {
        "\(latitude.rounded(toPlaces: 4)),\(longitude.rounded(toPlaces: 4))"
    }
}

private struct RecordingLocationNameText: View {
    let location: RecordingLocation
    @State private var resolvedName: String?

    var body: some View {
        Text(resolvedName ?? location.locationName ?? location.coordinateText)
            .task(id: location.cacheKey) {
                guard location.locationName == nil else {
                    resolvedName = location.locationName
                    return
                }
                resolvedName = await RecordingLocationNameCache.shared.name(for: location)
            }
    }
}

@MainActor
private final class RecordingLocationNameCache {
    static let shared = RecordingLocationNameCache()

    private var namesByLocationKey: [String: String] = [:]

    func name(for location: RecordingLocation) async -> String {
        if let storedName = location.locationName {
            return storedName
        }

        let key = location.cacheKey
        if let cachedName = namesByLocationKey[key] {
            return cachedName
        }

        let fallback = location.coordinateText
        do {
            guard let request = MKReverseGeocodingRequest(location:
                CLLocation(latitude: location.latitude, longitude: location.longitude)
            ) else {
                namesByLocationKey[key] = fallback
                return fallback
            }
            let mapItems = try await request.mapItems
            let mapItem = mapItems.first
            let address = mapItem?.addressRepresentations
            let city = address?.cityName
                ?? address?.cityWithContext(.short)
                ?? mapItem?.name
            let country = address?.regionName
            let name = [city, country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let resolvedName = name.isEmpty ? fallback : name
            namesByLocationKey[key] = resolvedName
            return resolvedName
        } catch {
            namesByLocationKey[key] = fallback
            return fallback
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private struct RecordingRow: View {
    let item: RecordingItem
    let isAnalyzing: Bool
    let canGenerateIntelligence: Bool
    let onOpen: () -> Void

    private var isTranscriptionRunning: Bool {
        item.importStatus?.isFailed == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                        .fill(AppTheme.brand.opacity(0.12))
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.brand)
                }
                .frame(width: 36, height: 36)
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.audioFileName)
                        .font(.redditSans(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 8)

                trailingStatus
            }

            RecordingMetadataStrip(item: item)

            if !item.combinedTags.isEmpty {
                FlowTags(tags: Array(item.combinedTags.prefix(4)))
            }

            if let importStatus = item.importStatus {
                VStack(alignment: .leading, spacing: 6) {
                    if importStatus.isFailed {
                        Label(importStatus.message, systemImage: "exclamationmark.triangle")
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                            .lineLimit(2)
                    } else {
                        ProgressView(value: importStatus.progress)
                            .progressViewStyle(.linear)
                        Text(importStatus.message)
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(AppTheme.info)
                            .lineLimit(1)
                    }
                }
            } else if canGenerateIntelligence && isAnalyzing {
                Label(localized(L10n.Recordings.analyzing), systemImage: "sparkles")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            } else if let intelligence = item.intelligence {
                RecordingIntelligencePreview(intelligence: intelligence)
            } else if !item.transcriptPreview.isEmpty {
                Text(item.transcriptPreview)
                    .font(.redditSans(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(color: AppTheme.cardShadow, radius: 7, y: 2)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if item.importStatus?.isFailed == true {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .frame(width: 26, height: 26)
        } else if isAnalyzing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
        } else if !isTranscriptionRunning {
            Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }
}

private struct RecordingMetadataStrip: View {
    let item: RecordingItem

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                RecordingMetadataChip(systemImage: "globe", text: item.localizedLanguageName)
                RecordingMetadataChip(systemImage: "text.alignleft", text: "\(item.lineCount)")
                if let location = item.location {
                    RecordingMetadataChip(systemImage: "mappin.and.ellipse") {
                        RecordingLocationNameText(location: location)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct RecordingMetadataChip<Content: View>: View {
    let systemImage: String
    @ViewBuilder var content: Content

    init(systemImage: String, text: String) where Content == Text {
        self.systemImage = systemImage
        content = Text(text)
    }

    init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.secondary.opacity(0.09), in: Capsule())
    }
}

private struct RecordingIntelligencePreview: View {
    let intelligence: RecordingIntelligence

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !intelligence.summary.isEmpty {
                Text(intelligence.summary)
                    .font(.redditSans(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.redditSans(.caption2, weight: .semibold))
                        .foregroundStyle(AppTheme.info)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(AppTheme.info.opacity(0.12), in: Capsule())
                }
            }
        }
        .scrollClipDisabled()
    }
}

struct RecordingDetailView: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var copied = false
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var isAnalyzing = false
    @State private var analysisErrorMessage: String?
    @State private var transcriptionErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var audioFileInfo: RecordingAudioFileInfo?
    @State private var audioFileInfoError: String?
    @State private var isShowingAudioFileInfo = false
    @StateObject private var editLocationProvider = RecordingEditLocationProvider()
    @State private var isShowingRecordingEditSheet = false
    @State private var editRecordingName = ""
    @State private var editRecordingTags: [String] = []
    @State private var editRecordingSummary = ""
    @State private var editRecordingIncludesLocation = false
    @State private var isSavingRecordingEdit = false
    @State private var isShowingSummaryEditSheet = false
    @State private var editedSummaryText = ""
    @State private var isSavingSummaryEdit = false
    @State private var editErrorMessage: String?
    @State private var transcriptLineEditRequest: TranscriptLineEditRequest?
    @State private var editedTranscriptLineText = ""
    @State private var isSavingTranscriptLineEdit = false
    @State private var cachedTranscriptLines: [StoredTranscriptLine] = []
    @State private var scrubbedPlaybackTime: TimeInterval?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var selectedTranslationLanguage: TranscriptionLanguage?
    @State private var translatedTranscriptByLineID: [StoredTranscriptLine.ID: String] = [:]
    @State private var translatedTranscriptCache: [String: [StoredTranscriptLine.ID: String]] = [:]
    @State private var appleSpeechTranscriptionLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @State private var appleTranslationLanguages: [TranscriptionLanguage] = []
    @State private var isTranslatingTranscript = false
    @State private var translationErrorMessage: String?
    @State private var isShowingTranscriptTranslationLanguagePicker = false
    @State private var pendingSpeechLocaleReleaseAction: PendingSpeechLocaleReleaseAction?
    @State private var isShowingAppleSpeechRetranscriptionPicker = false
    @State private var isShowingLocalWhisperRetranscriptionPicker = false
    @AppStorage(RecordingSummaryProvider.selectedDefaultsKey) private var selectedSummaryProviderRawValue = RecordingSummaryProvider.automatic.rawValue
    @State private var selectedDetailPage: RecordingDetailPage = .transcript
    @StateObject private var chatEngine = RecordingChatEngine()

    private static let playerOverlayReadablePadding: CGFloat = 156

    private var currentItem: RecordingItem {
        store.recording(withID: item.id) ?? item
    }

    private var selectedSummaryProvider: RecordingSummaryProvider {
        RecordingSummaryProvider(rawValue: selectedSummaryProviderRawValue) ?? .automatic
    }

    private var transcriptCacheIdentifier: String {
        [
            currentItem.id.uuidString,
            currentItem.transcriptFileName,
            "\(currentItem.lineCount)",
            "\(currentItem.transcriptPreview.hashValue)",
            "\(currentItem.importStatus == nil)"
        ].joined(separator: "-")
    }

    private var isTranscriptionRunning: Bool {
        currentItem.importStatus?.isFailed == false
    }

    private var pendingSpeechLocaleReleaseMessage: String {
        pendingSpeechLocaleReleaseAction?.request.messageText ?? ""
    }

    var body: some View {
        // A page-style TabView clips its pages at the bottom safe area,
        // which letterboxes the content above the home indicator. Plain
        // views in a ZStack extend edge-to-edge like the old single page,
        // and keeping both alive preserves scroll and draft state.
        ZStack {
            transcriptPage
                .opacity(selectedDetailPage == .transcript ? 1 : 0)
                .offset(x: selectedDetailPage == .transcript ? 0 : -44)
                .allowsHitTesting(selectedDetailPage == .transcript)
                .accessibilityHidden(selectedDetailPage != .transcript)

            aiAnalysisPage
                .opacity(selectedDetailPage == .aiAnalysis ? 1 : 0)
                .offset(x: selectedDetailPage == .aiAnalysis ? 0 : 44)
                .allowsHitTesting(selectedDetailPage == .aiAnalysis)
                .accessibilityHidden(selectedDetailPage != .aiAnalysis)
        }
        .animation(.easeInOut(duration: 0.22), value: selectedDetailPage)
        .gesture(detailPageSwipeGesture)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker(localized(L10n.Recordings.detailPages), selection: $selectedDetailPage) {
                Text(L10n.Recordings.transcript).tag(RecordingDetailPage.transcript)
                Text(L10n.Recordings.aiAnalysis).tag(RecordingDetailPage.aiAnalysis)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background {
                // One continuous surface from the status bar down to the
                // rounded bottom edge, so the navigation bar area and this
                // strip cannot render with different tints.
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
            }
        }
        .onChange(of: selectedDetailPage) {
            HapticFeedback.play(.navigation)
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(currentItem.audioFileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticFeedback.play(.navigation)
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text(L10n.Common.back))
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                detailActionsMenu
            }
        }
        .sheet(isPresented: $isShowingAudioFileInfo) {
            NavigationStack {
                ScrollView {
                    audioParametersCard
                        .padding()
                }
                .background(AppTheme.groupedBackground.ignoresSafeArea())
                .navigationTitle(localized(L10n.Recordings.audioParameters))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localized(L10n.Common.done)) {
                            isShowingAudioFileInfo = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingRecordingEditSheet) {
            RecordingEditSheet(
                item: currentItem,
                recordingName: $editRecordingName,
                tags: $editRecordingTags,
                summary: $editRecordingSummary,
                includesLocation: $editRecordingIncludesLocation,
                locationProvider: editLocationProvider,
                isSaving: isSavingRecordingEdit,
                showsTitleGeneration: store.summaryProviderAvailability.hasAnyAvailableProvider,
                onGenerateTitle: {
                    try await store.generateSuggestedTitle(for: currentItem)
                },
                onSave: saveRecordingEdit,
                onCancel: {
                    isShowingRecordingEditSheet = false
                }
            )
            .interactiveDismissDisabled(isSavingRecordingEdit)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onChange(of: editRecordingIncludesLocation) { _, includesLocation in
                if includesLocation, currentItem.location == nil {
                    editLocationProvider.requestLocation()
                } else if !includesLocation {
                    editLocationProvider.reset()
                }
            }
        }
        .sheet(isPresented: $isShowingSummaryEditSheet) {
            RecordingSummaryEditSheet(
                summary: $editedSummaryText,
                isSaving: isSavingSummaryEdit,
                onSave: saveSummaryEdit,
                onCancel: {
                    isShowingSummaryEditSheet = false
                }
            )
            .interactiveDismissDisabled(isSavingSummaryEdit)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $transcriptLineEditRequest) { request in
            TranscriptLineEditSheet(
                timeText: request.timeText,
                text: $editedTranscriptLineText,
                isSaving: isSavingTranscriptLineEdit,
                onSave: saveTranscriptLineEdit,
                onCancel: {
                    transcriptLineEditRequest = nil
                }
            )
            .interactiveDismissDisabled(isSavingTranscriptLineEdit)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingLocalWhisperRetranscriptionPicker) {
            LocalWhisperRetranscriptionPicker(
                recordingLanguageID: currentItem.languageID,
                downloadedModels: downloadedLocalWhisperModels,
                languageOptionsByModelID: localWhisperLanguageOptionsByModelID,
                onCancel: {
                    isShowingLocalWhisperRetranscriptionPicker = false
                },
                onSelect: { language, model in
                    isShowingLocalWhisperRetranscriptionPicker = false
                    retranscribeCurrentItemWithLocalWhisper(language: language, model: model)
                }
            )
        }
        .sheet(isPresented: $isShowingAppleSpeechRetranscriptionPicker) {
            RecordingRetranscriptionLanguagePicker(
                title: localized(L10n.Recordings.retranscribe),
                recordingLanguageID: currentItem.languageID,
                languages: appleSpeechTranscriptionLanguages,
                onCancel: {
                    isShowingAppleSpeechRetranscriptionPicker = false
                },
                onSelect: { language in
                    isShowingAppleSpeechRetranscriptionPicker = false
                    requestCurrentItemRetranscription(language: language)
                }
            )
        }
        .sheet(isPresented: $isShowingTranscriptTranslationLanguagePicker) {
            TranscriptTranslationLanguagePicker(
                selectedLanguageID: selectedTranslationLanguage?.id,
                languages: transcriptTranslationLanguages,
                onSelectOriginal: {
                    clearTranscriptTranslation()
                    isShowingTranscriptTranslationLanguagePicker = false
                },
                onSelectLanguage: { language in
                    requestTranscriptTranslation(to: language)
                    isShowingTranscriptTranslationLanguagePicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            chatEngine.configure(recordingID: currentItem.id)
            Task {
                store.refreshIntelligenceAvailability()
                await refreshAudioFileInfo()
                player.load(item: currentItem, url: store.audioURL(for: currentItem))
            }
        }
        .task(id: transcriptCacheIdentifier) {
            await refreshTranscriptCache()
        }
        .task {
            appleSpeechTranscriptionLanguages = await AppleSpeechTranscriptionSupport.supportedLanguages()
            appleTranslationLanguages = await AppleTranslationLanguages.supportedLanguages()
        }
        .translationTask(translationConfiguration) { session in
            await translateTranscript(using: session)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                player.prepareForBackgroundPlayback()
            }
        }
        .onDisappear {
            if scenePhase == .active {
                player.unload()
            } else {
                player.prepareForBackgroundPlayback()
            }
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
            Text(pendingSpeechLocaleReleaseMessage)
        }
        .alert(
            localized(L10n.Recordings.analysisFailed),
            isPresented: Binding(
                get: { analysisErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        analysisErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(analysisErrorMessage ?? "")
        }
        .alert(
            localized(L10n.Recordings.transcriptionFailed),
            isPresented: Binding(
                get: { transcriptionErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        transcriptionErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(transcriptionErrorMessage ?? "")
        }
        .alert(
            localized(L10n.Recordings.deleteRecording),
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteRequest = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.delete), role: .destructive) {
                if let request = deleteRequest {
                    deleteCurrentItem(request.item)
                    deleteRequest = nil
                }
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(localizedFormat(L10n.Recordings.deleteConfirmationFormat, deleteRequest?.item.audioFileName ?? ""))
        }
        .alert(
            localized(L10n.Recordings.deleteFailed),
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .alert(
            localized(L10n.Recordings.editFailed),
            isPresented: Binding(
                get: { editErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        editErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(editErrorMessage ?? "")
        }
    }

    private var detailActionsMenu: some View {
        let transcriptText = store.transcriptText(for: currentItem)

        return Menu {
            Button {
                prepareRecordingEditSheet()
            } label: {
                Label(localized(L10n.Recordings.editDetails), systemImage: "pencil")
            }
            .disabled(isTranscriptionRunning)

            Button {
                toggleTranscriptLock()
            } label: {
                Label(
                    localized(currentItem.isTranscriptLocked ? L10n.Recordings.unlockTranscript : L10n.Recordings.lockTranscript),
                    systemImage: currentItem.isTranscriptLocked ? "lock.open" : "lock"
                )
            }
            .disabled(isTranscriptionRunning)

            Button {
                isShowingAudioFileInfo = true
            } label: {
                Label(localized(L10n.Recordings.audioParameters), systemImage: "info.circle")
            }

            Divider()

            Menu {
                ShareLink(item: store.audioURL(for: currentItem)) {
                    Label(localized(L10n.Recordings.shareAudio), systemImage: "waveform")
                }

                ShareLink(item: transcriptText) {
                    Label(localized(L10n.Recordings.shareTranscript), systemImage: "text.alignleft")
                }
                .disabled(transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } label: {
                Label(localized(L10n.Recordings.share), systemImage: "square.and.arrow.up")
            }

            Button {
                requestCurrentItemRetranscription()
            } label: {
                Label(localized(L10n.Recordings.retranscribe), systemImage: isTranscriptionRunning ? "hourglass" : "arrow.triangle.2.circlepath")
            }
            .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)

            if transcriber.isOpenAITranscriptionEnabled {
                Menu {
                    Button {
                        retranscribeCurrentItemWithOpenAI(mode: .longForm)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribeWithOpenAILongForm), systemImage: "text.alignleft")
                    }

                    Button {
                        retranscribeCurrentItemWithOpenAI(mode: .segmented)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribeWithOpenAISegmented), systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        retranscribeCurrentItemWithOpenAI(mode: .refinedSegments)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribeWithOpenAIRefinedSegments), systemImage: "wand.and.sparkles")
                    }
                } label: {
                    Label(localized(L10n.Recordings.retranscribeWithOpenAI), systemImage: "cloud")
                }
                .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)
            }

            LocalWhisperRetranscriptionButton(
                downloadedModels: downloadedLocalWhisperModels,
                isDisabled: currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing
            ) {
                isShowingLocalWhisperRetranscriptionPicker = true
            }

            Button {
                HapticFeedback.play(.copy)
                UIPasteboard.general.string = transcriptText
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    copied = false
                }
            } label: {
                Label(
                    copied ? localized(L10n.Recordings.copied) : localized(L10n.Recordings.copyTranscript),
                    systemImage: copied ? "checkmark" : "doc.on.doc"
                )
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: currentItem)
            } label: {
                Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
            }
            .disabled(isTranscriptionRunning)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text(L10n.Common.more))
    }

    private var detailPageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 25)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 50 else {
                    return
                }
                if horizontal < 0, selectedDetailPage == .transcript {
                    selectedDetailPage = .aiAnalysis
                } else if horizontal > 0, selectedDetailPage == .aiAnalysis {
                    selectedDetailPage = .transcript
                }
            }
    }

    private var transcriptPage: some View {
        ZStack {
            AppTheme.groupedBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    transcript
                }
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom)
            }
            .safeAreaInset(edge: .bottom) {
                playerCard
                    .frame(maxWidth: 390)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
        }
    }

    private var aiAnalysisPage: some View {
        RecordingAIAnalysisPage(
            engine: chatEngine,
            isAvailable: store.summaryProviderAvailability.hasAnyAvailableProvider,
            makeContext: {
                RecordingChatContext(
                    transcript: store.transcriptText(for: currentItem),
                    summary: currentItem.intelligence?.summary,
                    languageName: currentItem.localizedLanguageName
                )
            }
        ) {
            if store.intelligenceAvailability.isAvailable || currentItem.intelligence != nil {
                intelligenceCard
            }
        }
    }

    private var header: some View {
        let item = currentItem
        let iCloudSyncStatus = store.iCloudSyncStatus(for: item)

        return VStack(alignment: .leading, spacing: 10) {
            Label(item.audioFileName, systemImage: "waveform")
                .font(.redditSans(.headline, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    RecordingInfoPill(icon: "calendar", text: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    RecordingInfoPill(icon: "clock", text: TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                    RecordingInfoPill(icon: "globe", text: item.localizedLanguageName)
                    RecordingInfoPill(icon: iCloudSyncStatus.systemImage, text: iCloudSyncStatus.displayName)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        RecordingInfoPill(icon: "calendar", text: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        RecordingInfoPill(icon: "clock", text: TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                    }

                    HStack(spacing: 10) {
                        RecordingInfoPill(icon: "globe", text: item.localizedLanguageName)
                        RecordingInfoPill(icon: iCloudSyncStatus.systemImage, text: iCloudSyncStatus.displayName)
                    }
                }
            }

            if !item.combinedTags.isEmpty {
                FlowTags(tags: item.combinedTags)
            }

            if let location = item.location {
                Label {
                    RecordingLocationNameText(location: location)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                }
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var intelligenceCard: some View {
        let item = currentItem

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label(localized(L10n.Recordings.intelligenceSummary), systemImage: "sparkles")
                    .font(.redditSans(.headline))

                Spacer(minLength: 8)

                if store.summaryProviderAvailability.hasAnyAvailableProvider {
                    SummaryAnalysisMenu(
                        selectedProvider: selectedSummaryProvider,
                        providerAvailability: store.summaryProviderAvailability,
                        isDisabled: isAnalyzing,
                        primaryAction: {
                            analyzeCurrentItem(summaryProvider: selectedSummaryProvider)
                        }
                    ) { provider in
                        analyzeCurrentItem(summaryProvider: provider)
                    } label: {
                        HStack(spacing: 6) {
                            if isAnalyzing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(item.intelligence == nil ? localized(L10n.Recordings.analyze) : localized(L10n.Recordings.analyzeAgain))
                                    .font(.redditSans(.caption, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if isAnalyzing {
                Label(localized(L10n.Recordings.analyzing), systemImage: "sparkles")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            } else if let intelligence = item.intelligence {
                if !intelligence.summary.isEmpty {
                    Text(intelligence.summary)
                        .font(.redditSans(.body))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                HapticFeedback.play(.copy)
                                UIPasteboard.general.string = intelligence.summary
                            } label: {
                                Label(localized(L10n.Common.copy), systemImage: "doc.on.doc")
                            }

                            Button {
                                beginSummaryEdit()
                            } label: {
                                Label(localized(L10n.Recordings.editSummary), systemImage: "pencil")
                            }
                        }
                }

                Text(intelligence.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
            } else {
                EmptyStateView(icon: "sparkles", titleResource: L10n.Recordings.noSummary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .fill(AppTheme.cardBackground)
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    private var audioParametersCard: some View {
        let iCloudSyncStatus = store.iCloudSyncStatus(for: currentItem)

        return VStack(alignment: .leading, spacing: 16) {
            Label(localized(L10n.Recordings.audioParameters), systemImage: "info.circle")
                .font(.redditSans(.headline, weight: .bold))

            if let audioFileInfo {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        RecordingAudioMetricTile(icon: "speedometer", titleResource: L10n.Recordings.bitRate, value: audioFileInfo.bitRateText, tint: AppTheme.brand)
                        RecordingAudioMetricTile(icon: "waveform", titleResource: L10n.Recordings.sampleRate, value: audioFileInfo.fileSampleRateText, tint: AppTheme.info)
                        RecordingAudioMetricTile(icon: "speaker.wave.2", titleResource: L10n.Recordings.channels, value: audioFileInfo.channelLayoutText, tint: AppTheme.success)
                        RecordingAudioMetricTile(icon: "timer", titleResource: L10n.Recordings.audioDuration, value: audioFileInfo.durationText, tint: AppTheme.warning)
                    }

                    RecordingAudioParameterGroup(titleResource: L10n.Recordings.technicalDetails) {
                        RecordingAudioParameterRow(icon: "doc.badge.gearshape", titleResource: L10n.Recordings.fileFormat, value: audioFileInfo.containerFormatText)
                        RecordingAudioParameterRow(icon: "cpu", titleResource: L10n.Recordings.encoding, value: audioFileInfo.fileFormatText)
                        RecordingAudioParameterRow(icon: "speedometer", titleResource: L10n.Recordings.averageBitRate, value: audioFileInfo.averageBitRateText)
                        RecordingAudioParameterRow(icon: "slider.horizontal.3", titleResource: L10n.Recordings.processingFormat, value: audioFileInfo.processingFormatText)
                        RecordingAudioParameterRow(icon: "number", titleResource: L10n.Recordings.pcmBitDepth, value: audioFileInfo.bitDepthText)
                        RecordingAudioParameterRow(icon: "square.stack.3d.up", titleResource: L10n.Recordings.audioFrames, value: audioFileInfo.frameCountText, showsDivider: false)
                    }

                    RecordingAudioParameterGroup(titleResource: L10n.Recordings.storage) {
                        RecordingAudioParameterRow(icon: "doc.text", titleResource: L10n.Recordings.fileName, value: audioFileInfo.fileName)
                        RecordingAudioParameterRow(icon: "doc", titleResource: L10n.Recordings.fileSize, value: audioFileInfo.fileSizeText)
                        RecordingAudioParameterRow(icon: iCloudSyncStatus.systemImage, titleResource: L10n.Recordings.iCloudSync, value: iCloudSyncStatus.displayName, showsDivider: false)
                    }
                }
            } else if let audioFileInfoError {
                Label(audioFileInfoError, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(localized(L10n.Recordings.readingAudioParameters), systemImage: "waveform")
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
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

    private var playerCard: some View {
        let displayedTime = scrubbedPlaybackTime ?? player.currentTime
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(TranscriptionLine.formatTimestamp(displayedTime))
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(minWidth: 50, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { scrubbedPlaybackTime ?? player.currentTime },
                        set: { scrubbedPlaybackTime = $0 }
                    ),
                    in: 0...max(player.duration, 1),
                    onEditingChanged: { isEditing in
                        if !isEditing, let scrubbedPlaybackTime {
                            player.seek(to: scrubbedPlaybackTime)
                            self.scrubbedPlaybackTime = nil
                        }
                    }
                )
                .disabled(!player.isLoaded)
                .frame(maxWidth: .infinity)

                Text(TranscriptionLine.formatTimestamp(player.duration))
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 50, alignment: .trailing)
            }

            ZStack {
                HStack(spacing: 20) {
                    PlaybackRoundButton(systemImage: "gobackward.5", title: "-5s") {
                        HapticFeedback.play(.timelineSeek)
                        scrubbedPlaybackTime = nil
                        player.skip(by: -5)
                    }
                    .disabled(!player.isLoaded)

                    PlaybackRoundButton(
                        systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                        titleResource: player.isPlaying ? L10n.Recordings.pause : L10n.Recordings.play,
                        isPrimary: true
                    ) {
                        HapticFeedback.play(.playbackToggle)
                        player.togglePlayback()
                    }
                    .disabled(!player.isLoaded)

                    PlaybackRoundButton(systemImage: "goforward.5", title: "+5s") {
                        HapticFeedback.play(.timelineSeek)
                        scrubbedPlaybackTime = nil
                        player.skip(by: 5)
                    }
                    .disabled(!player.isLoaded)
                }
                .frame(width: 196)

                HStack {
                    Spacer(minLength: 0)
                    playbackSpeedMenu
                }
            }
            .frame(height: 58)

            if let errorText = player.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AppTheme.playbackGlassTint), in: shape)
    }

    private var playbackSpeedMenu: some View {
        Menu {
            ForEach(RecordingPlaybackController.availablePlaybackRates, id: \.self) { rate in
                Button {
                    HapticFeedback.play(.menuSelection)
                    player.setPlaybackRate(rate)
                } label: {
                    Label(
                        RecordingPlaybackController.playbackRateLabel(rate),
                        systemImage: player.playbackRate == rate ? "checkmark" : "speedometer"
                    )
                }
            }
        } label: {
            Text(RecordingPlaybackController.playbackRateLabel(player.playbackRate))
                .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                .lineLimit(1)
            .foregroundStyle(AppTheme.brand)
            .padding(.horizontal, 7)
            .frame(height: 24)
        }
        .buttonStyle(.glass)
        .disabled(!player.isLoaded)
    }

    private var transcript: some View {
        let item = currentItem
        let lines = cachedTranscriptLines
        let currentLineID = StoredTranscriptLine.currentLineID(in: lines, time: player.currentTime)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label(localized(L10n.Recordings.transcript), systemImage: "text.alignleft")
                    .font(.redditSans(.headline))

                if item.isTranscriptLocked {
                    Label(localized(L10n.Recordings.transcriptLocked), systemImage: "lock.fill")
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(AppTheme.warning.opacity(0.12), in: Capsule())
                        .accessibilityHint(localized(L10n.Recordings.transcriptLockedDetail))
                }

                Spacer(minLength: 8)

                transcriptTranslationMenu
                    .disabled(lines.isEmpty || isTranscriptionRunning)
            }

            transcriptTranslationStatus

            if let importStatus = item.importStatus {
                RecordingImportStatusDetail(status: importStatus)
            }

            if lines.isEmpty {
                if item.importStatus == nil {
                    EmptyStateView(icon: "text.badge.xmark", titleResource: L10n.Recordings.noText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        StoredTranscriptLineRow(
                            line: line,
                            translatedText: translatedTranscriptByLineID[line.id],
                            isShowingTranslation: isTranslatingTranscript && selectedTranslationLanguage != nil && translatedTranscriptByLineID[line.id] == nil,
                            isCurrent: line.id == currentLineID
                        ) {
                            HapticFeedback.play(.timelineSeek)
                            scrubbedPlaybackTime = nil
                            player.seek(to: line.startSeconds)
                        } onEdit: {
                            beginTranscriptLineEdit(line)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Color.clear
                .frame(height: Self.playerOverlayReadablePadding)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var transcriptTranslationMenu: some View {
        Button {
            HapticFeedback.play(.navigation)
            isShowingTranscriptTranslationLanguagePicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "translate")
                    .font(.system(size: 12, weight: .semibold))
                Text(selectedTranslationLanguage?.shortName ?? localized(L10n.Recordings.translate))
                    .font(.redditSans(.caption, weight: .bold))
            }
            .foregroundStyle(selectedTranslationLanguage == nil ? AppTheme.info : AppTheme.brand)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background((selectedTranslationLanguage == nil ? AppTheme.info : AppTheme.brand).opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
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
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(translationErrorMessage ?? localizedFormat(L10n.Recordings.translatingToFormat, selectedTranslationLanguage.displayName))
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(translationErrorMessage == nil ? .secondary : AppTheme.warning)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
        }
    }

    private var transcriptTranslationLanguages: [TranscriptionLanguage] {
        appleTranslationLanguages.filter { language in
            !AppleTranslationLanguages.sameBaseLanguage(language.id, currentItem.languageID)
        }
    }

    private func analyzeCurrentItem(summaryProvider: RecordingSummaryProvider) {
        guard store.summaryProviderAvailability.isAvailable(summaryProvider) else {
            HapticFeedback.play(.blocked)
            store.refreshIntelligenceAvailability()
            return
        }
        guard !isAnalyzing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        if selectedTranslationLanguage != nil, isTranslatingTranscript {
            analysisErrorMessage = localized(L10n.Recordings.waitForTranslationBeforeSummary)
            HapticFeedback.play(.blocked)
            return
        }
        let translatedAnalysisInput = translatedTranscriptAnalysisInput()
        if selectedTranslationLanguage != nil, translatedAnalysisInput == nil {
            analysisErrorMessage = localized(L10n.Recordings.noTranslatedTextForSummary)
            HapticFeedback.play(.blocked)
            return
        }

        isAnalyzing = true
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                _ = try await store.analyzeIntelligence(
                    for: item,
                    transcriptOverride: translatedAnalysisInput?.transcript,
                    languageNameOverride: translatedAnalysisInput?.languageName,
                    summaryProvider: summaryProvider
                )
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isAnalyzing = false
        }
    }

    private func translatedTranscriptAnalysisInput() -> (transcript: String, languageName: String)? {
        guard let selectedTranslationLanguage else {
            return nil
        }

        var translatedLines: [String] = []
        for line in cachedTranscriptLines {
            guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard let translatedText = translatedTranscriptByLineID[line.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translatedText.isEmpty else {
                return nil
            }
            translatedLines.append(translatedText)
        }

        guard !translatedLines.isEmpty else {
            return nil
        }

        return (translatedLines.joined(separator: "\n"), selectedTranslationLanguage.displayName)
    }

    private func requestCurrentItemRetranscription() {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        isShowingAppleSpeechRetranscriptionPicker = true
    }

    private func requestCurrentItemRetranscription(language: TranscriptionLanguage) {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    language,
                    preservingLanguageIDs: [transcriber.selectedLanguageID, item.languageID]
                )
                switch preparation {
                case .ready:
                    retranscribeCurrentItem(language: language)
                case .needsRelease(let request):
                    pendingSpeechLocaleReleaseAction = PendingSpeechLocaleReleaseAction(
                        request: request,
                        operation: .retranscribe(item)
                    )
                    HapticFeedback.play(.warning)
                }
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func releaseSpeechLocalesAndContinue(_ pendingAction: PendingSpeechLocaleReleaseAction) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(pendingAction.request)
                if case .retranscribe = pendingAction.operation {
                    retranscribeCurrentItem(language: pendingAction.request.targetLanguage)
                }
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeCurrentItem(language: TranscriptionLanguage) {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.retranscribe(item, language: language)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeCurrentItemWithOpenAI(mode: OpenAIFileTranscriptionMode) {
        guard transcriber.isOpenAITranscriptionEnabled else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        let language = TranscriptionLanguage(id: item.languageID)
        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.retranscribeWithOpenAI(
                    item,
                    language: language,
                    apiKey: transcriber.openAIAPIKey,
                    mode: mode
                )
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeCurrentItemWithLocalWhisper(language: TranscriptionLanguage, model: LocalWhisperModel? = nil) {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.retranscribeWithLocalWhisper(item, language: language, model: model)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func refreshAudioFileInfo() async {
        let item = currentItem
        let url = store.audioURL(for: item)
        do {
            let info = try await Task.detached(priority: .utility) {
                try RecordingAudioFileInfo(url: url)
            }.value
            audioFileInfo = info
            audioFileInfoError = nil
        } catch {
            audioFileInfo = nil
            audioFileInfoError = localizedFormat(L10n.Recordings.audioInfoReadFailedFormat, error.localizedDescription)
        }
    }

    private func refreshTranscriptCache() async {
        let item = currentItem
        let transcriptURL = store.transcriptURL(for: item)
        let lines = await Task.detached(priority: .utility) {
            let text = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
            return StoredTranscriptLine.parse(text)
        }.value

        guard currentItem.id == item.id,
              currentItem.transcriptFileName == item.transcriptFileName else {
            return
        }

        cachedTranscriptLines = lines
        translatedTranscriptByLineID = [:]
        translatedTranscriptCache = translatedTranscriptCache.filter { key, _ in
            key.hasPrefix(transcriptTranslationCachePrefix)
        }

        if let selectedTranslationLanguage {
            requestTranscriptTranslation(to: selectedTranslationLanguage)
        }
    }

    private func beginTranscriptLineEdit(_ line: StoredTranscriptLine) {
        HapticFeedback.play(.menuSelection)
        editedTranscriptLineText = line.text
        transcriptLineEditRequest = TranscriptLineEditRequest(line: line)
    }

    private func saveTranscriptLineEdit() {
        guard let transcriptLineEditRequest,
              !isSavingTranscriptLineEdit else {
            return
        }

        isSavingTranscriptLineEdit = true
        do {
            let updatedItem = try store.updateTranscriptLine(
                for: currentItem,
                lineID: transcriptLineEditRequest.lineID,
                text: editedTranscriptLineText
            )
            cachedTranscriptLines = StoredTranscriptLine.parse(store.transcriptText(for: updatedItem))
            clearTranscriptTranslationState()
            self.transcriptLineEditRequest = nil
            HapticFeedback.play(.recordingSaved)
        } catch {
            editErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
        isSavingTranscriptLineEdit = false
    }

    private func clearTranscriptTranslationState() {
        selectedTranslationLanguage = nil
        translatedTranscriptByLineID = [:]
        translatedTranscriptCache = [:]
        translationErrorMessage = nil
        isTranslatingTranscript = false
        translationConfiguration = nil
    }

    private func toggleTranscriptLock() {
        do {
            _ = try store.setTranscriptLocked(
                for: currentItem,
                isLocked: !currentItem.isTranscriptLocked
            )
            HapticFeedback.play(.menuSelection)
        } catch {
            editErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func requestTranscriptTranslation(to language: TranscriptionLanguage) {
        guard !cachedTranscriptLines.isEmpty else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !AppleTranslationLanguages.sameBaseLanguage(language.id, currentItem.languageID) else {
            clearTranscriptTranslation()
            return
        }

        HapticFeedback.play(.menuSelection)
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

        let sourceLanguage = AppleTranslationLanguages.localeLanguage(for: currentItem.languageID)
        let targetLanguage = AppleTranslationLanguages.localeLanguage(for: language.id)
        let nextConfiguration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
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
        HapticFeedback.play(.menuSelection)
        selectedTranslationLanguage = nil
        translatedTranscriptByLineID = [:]
        translationErrorMessage = nil
        isTranslatingTranscript = false
        translationConfiguration = nil
    }

    private func translateTranscript(using session: TranslationSession) async {
        guard let targetTranslationLanguage = selectedTranslationLanguage,
              !cachedTranscriptLines.isEmpty else {
            isTranslatingTranscript = false
            return
        }

        let cacheKey = transcriptTranslationCacheKey(for: targetTranslationLanguage)
        if let cachedTranslation = translatedTranscriptCache[cacheKey] {
            translatedTranscriptByLineID = cachedTranslation
            isTranslatingTranscript = false
            return
        }

        let lines = cachedTranscriptLines
        let targetLanguageID = targetTranslationLanguage.id
        let requests = lines.map { line in
            TranslationSession.Request(sourceText: line.text, clientIdentifier: line.id)
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
            HapticFeedback.play(.failure)
        }
    }

    private var transcriptTranslationCachePrefix: String {
        [
            currentItem.id.uuidString,
            currentItem.transcriptFileName,
            "\(currentItem.lineCount)",
            "\(currentItem.transcriptPreview.hashValue)"
        ].joined(separator: "|")
    }

    private func transcriptTranslationCacheKey(for language: TranscriptionLanguage) -> String {
        "\(transcriptTranslationCachePrefix)|\(language.id)"
    }

    private func prepareRecordingEditSheet() {
        let item = currentItem
        editRecordingName = (item.audioFileName as NSString).deletingPathExtension
        editRecordingTags = item.combinedTags
        editRecordingSummary = item.intelligence?.summary ?? ""
        editRecordingIncludesLocation = item.location != nil
        editLocationProvider.reset()
        isShowingRecordingEditSheet = true
        HapticFeedback.play(.menuSelection)
    }

    private func beginSummaryEdit() {
        editedSummaryText = currentItem.intelligence?.summary ?? ""
        isShowingSummaryEditSheet = true
        HapticFeedback.play(.menuSelection)
    }

    private func saveRecordingEdit() {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !isSavingRecordingEdit else {
            return
        }

        isSavingRecordingEdit = true
        do {
            let location = editRecordingIncludesLocation
                ? (editLocationProvider.recordingLocation ?? currentItem.location)
                : nil
            let updatedItem = try store.updateDetails(
                for: currentItem,
                proposedName: editRecordingName,
                manualTags: editRecordingTags,
                summary: editRecordingSummary,
                location: location
            )
            HapticFeedback.play(.primaryAction)
            isShowingRecordingEditSheet = false
            player.load(item: updatedItem, url: store.audioURL(for: updatedItem))
            Task {
                await refreshAudioFileInfo()
                await refreshTranscriptCache()
            }
        } catch {
            editErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
        isSavingRecordingEdit = false
    }

    private func saveSummaryEdit() {
        guard !isTranscriptionRunning else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !isSavingSummaryEdit else {
            return
        }

        isSavingSummaryEdit = true
        do {
            let updatedItem = try store.updateDetails(
                for: currentItem,
                proposedName: (currentItem.audioFileName as NSString).deletingPathExtension,
                manualTags: currentItem.manualTags ?? [],
                summary: editedSummaryText,
                location: currentItem.location
            )
            HapticFeedback.play(.primaryAction)
            isShowingSummaryEditSheet = false
            player.load(item: updatedItem, url: store.audioURL(for: updatedItem))
        } catch {
            editErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
        isSavingSummaryEdit = false
    }

    private func deleteCurrentItem(_ item: RecordingItem) {
        do {
            player.unload()
            try store.delete(item)
            HapticFeedback.play(.deleteConfirmed)
            if let onClose {
                onClose()
            } else {
                dismiss()
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }
}

private struct RecordingEditSheet: View {
    let item: RecordingItem
    @Binding var recordingName: String
    @Binding var tags: [String]
    @Binding var summary: String
    @Binding var includesLocation: Bool
    @ObservedObject var locationProvider: RecordingEditLocationProvider
    let isSaving: Bool
    var showsTitleGeneration = false
    var onGenerateTitle: (() async throws -> RecordingTitleSuggestion)? = nil
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var isGeneratingTitle = false
    @State private var titleGenerationErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameSection
                    summarySection
                    tagsEntry
                    durationRow
                    locationSection
                }
                .padding(16)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(L10n.Recordings.editRecordingTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
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
            Label(localized(L10n.Recordings.recordingName), systemImage: "pencil")
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(localized(L10n.Recordings.recordingName), text: $recordingName)
                    .font(.redditSans(.headline, weight: .semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if showsTitleGeneration, onGenerateTitle != nil {
                    Button {
                        generateTitle()
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
                    .disabled(isSaving || isGeneratingTitle)
                    .accessibilityLabel(localized(L10n.Transcription.generateTitleAndTagsAccessibility))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, showsTitleGeneration && onGenerateTitle != nil ? 7 : 12)
            .frame(height: 48)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        }
        .recordingEditSectionSurface()
    }

    private func generateTitle() {
        guard let onGenerateTitle, !isGeneratingTitle, !isSaving else {
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
                tags = RecordingItem.mergedTags(tags, suggestion.tags)
                if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let suggestedSummary = suggestion.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !suggestedSummary.isEmpty {
                    summary = suggestedSummary
                }
                HapticFeedback.play(.analysisComplete)
            } catch {
                titleGenerationErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isGeneratingTitle = false
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized(L10n.Recordings.summary), systemImage: "text.alignleft")
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.Recordings.summaryPlaceholder)
                        .font(.redditSans(.body))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $summary)
                    .font(.redditSans(.body))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 112)
                    .padding(.horizontal, -4)
                    .background(Color.clear)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        }
        .recordingEditSectionSurface()
    }

    private var tagsEntry: some View {
        NavigationLink {
            RecordingMetadataTagsEditor(tags: $tags)
        } label: {
            HStack(spacing: 12) {
                Label(localized(L10n.Recordings.tags), systemImage: "tag")
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
        .recordingEditSectionSurface()
    }

    private var durationRow: some View {
        HStack(spacing: 12) {
            Label(localized(L10n.Recordings.audioDuration), systemImage: "clock")
                .font(.redditSans(.subheadline, weight: .semibold))
            Spacer()
            Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                .font(.redditSans(.subheadline, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .recordingEditSectionSurface()
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $includesLocation) {
                Label(localized(L10n.Recordings.addLocation), systemImage: "location")
                    .font(.redditSans(.subheadline, weight: .semibold))
            }
            .tint(AppTheme.brand)

            if includesLocation {
                RecordingEditLocationPreview(
                    existingLocation: item.location,
                    locationProvider: locationProvider
                )
            }
        }
        .recordingEditSectionSurface()
    }
}

private struct RecordingSummaryEditSheet: View {
    @Binding var summary: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Label(localized(L10n.Recordings.summary), systemImage: "text.alignleft")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L10n.Recordings.summaryPlaceholder)
                            .font(.redditSans(.body))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $summary)
                        .font(.redditSans(.body))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, -4)
                        .background(Color.clear)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(L10n.Recordings.editSummary))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
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
                    .disabled(isSaving)
                }
            }
        }
    }
}

private struct RecordingMetadataTagsEditor: View {
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

private struct RecordingEditLocationPreview: View {
    let existingLocation: RecordingLocation?
    @ObservedObject var locationProvider: RecordingEditLocationProvider

    private var displayedLocation: RecordingLocation? {
        locationProvider.recordingLocation ?? existingLocation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let displayedLocation {
                let coordinate = CLLocationCoordinate2D(
                    latitude: displayedLocation.latitude,
                    longitude: displayedLocation.longitude
                )

                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                ) {
                    Marker(displayedLocation.placeName ?? localized(L10n.Recordings.currentLocation), coordinate: coordinate)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))

                Label {
                    RecordingLocationNameText(location: displayedLocation)
                } icon: {
                    Image(systemName: "building.2")
                }
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(displayedLocation.coordinateText)
                        .monospacedDigit()
                    Spacer()
                    Button(localized(L10n.Recordings.updateCurrentLocation)) {
                        locationProvider.requestLocation()
                    }
                    .font(.redditSans(.caption, weight: .semibold))
                }
                .font(.redditSans(.caption))
                .foregroundStyle(.secondary)
            } else if locationProvider.isDenied {
                Label(localized(L10n.Recordings.locationDenied), systemImage: "location.slash")
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
                .task {
                    locationProvider.requestLocation()
                }
            }
        }
    }
}

@MainActor
private final class RecordingEditLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
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

private extension View {
    func recordingEditSectionSurface() -> some View {
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

private struct RecordingImportStatusDetail: View {
    let status: RecordingImportStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.isFailed {
                Label(status.message, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)
                Label(status.message, systemImage: "waveform")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((status.isFailed ? AppTheme.warning : AppTheme.info).opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
    }
}

private struct RecordingAudioFileInfo: Equatable, Sendable {
    var fileSampleRate: Double
    var processingSampleRate: Double
    var channelCount: UInt32
    var processingChannelCount: UInt32
    var fileExtension: String
    var fileFormatName: String
    var fileCommonFormatName: String
    var processingCommonFormatName: String
    var bitDepth: Int?
    var encoderBitRate: Int?
    var isInterleaved: Bool
    var frameCount: AVAudioFramePosition
    var durationSeconds: TimeInterval
    var fileName: String
    var fileSize: Int64?

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.fileFormat
        let processingFormat = file.processingFormat
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])

        self.fileSampleRate = fileFormat.sampleRate
        self.processingSampleRate = processingFormat.sampleRate
        self.channelCount = fileFormat.channelCount
        self.processingChannelCount = processingFormat.channelCount
        self.fileExtension = url.pathExtension.uppercased()
        self.fileFormatName = Self.formatName(from: fileFormat.settings[AVFormatIDKey])
        self.fileCommonFormatName = Self.commonFormatName(fileFormat.commonFormat)
        self.processingCommonFormatName = Self.commonFormatName(processingFormat.commonFormat)
        self.bitDepth = Self.bitDepth(settings: fileFormat.settings, format: fileFormat)
        self.encoderBitRate = Self.intValue(from: fileFormat.settings[AVEncoderBitRateKey])
        self.isInterleaved = fileFormat.isInterleaved
        self.frameCount = file.length
        self.durationSeconds = processingFormat.sampleRate > 0 ? Double(file.length) / processingFormat.sampleRate : 0
        self.fileName = url.lastPathComponent
        self.fileSize = resourceValues?.fileSize.map { Int64($0) }
    }

    var fileSampleRateText: String {
        Self.sampleRateText(fileSampleRate)
    }

    var channelLayoutText: String {
        switch channelCount {
        case 1:
            return localized(L10n.Recordings.mono)
        case 2:
            return localized(L10n.Recordings.stereo)
        default:
            return localizedFormat(L10n.Recordings.channelCountFormat, Int(channelCount))
        }
    }

    var fileFormatText: String {
        if bitDepth == nil {
            return fileFormatName
        }
        return "\(fileFormatName) / \(fileCommonFormatName)"
    }

    var containerFormatText: String {
        let trimmedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtension.isEmpty else {
            return fileFormatName
        }
        return "\(trimmedExtension) / \(fileFormatName)"
    }

    var bitRateText: String {
        if let encoderBitRate, encoderBitRate > 0 {
            return Self.bitRateText(Double(encoderBitRate))
        }
        return averageBitRateText
    }

    var averageBitRateText: String {
        guard let fileSize,
              durationSeconds.isFinite,
              durationSeconds > 0 else {
            return localized(L10n.Common.unknown)
        }

        return Self.bitRateText(Double(fileSize) * 8 / durationSeconds)
    }

    var processingFormatText: String {
        let channelText: String
        switch processingChannelCount {
        case 1:
            channelText = localized(L10n.Recordings.mono)
        case 2:
            channelText = localized(L10n.Recordings.stereo)
        default:
            channelText = localizedFormat(L10n.Recordings.channelCountFormat, Int(processingChannelCount))
        }

        return "\(Self.sampleRateText(processingSampleRate)) / \(channelText) / \(processingCommonFormatName)"
    }

    var bitDepthText: String {
        guard let bitDepth else {
            return localized(L10n.Common.notApplicable)
        }
        return localizedFormat(L10n.Recordings.bitDepthFormat, bitDepth)
    }

    var durationText: String {
        TranscriptionLine.formatTimestamp(durationSeconds)
    }

    var frameCountText: String {
        Self.integerFormatter.string(from: NSNumber(value: frameCount)) ?? "\(frameCount)"
    }

    var fileSizeText: String {
        guard let fileSize else {
            return localized(L10n.Common.unknown)
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func sampleRateText(_ sampleRate: Double) -> String {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return localized(L10n.Common.unknown)
        }

        let kilohertz = sampleRate / 1_000
        if kilohertz.rounded() == kilohertz {
            return "\(Int(kilohertz)) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    private static func bitRateText(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond.isFinite, bitsPerSecond > 0 else {
            return localized(L10n.Common.unknown)
        }

        let kilobitsPerSecond = bitsPerSecond / 1_000
        if kilobitsPerSecond >= 1_000 {
            return String(format: "%.2f Mbps", kilobitsPerSecond / 1_000)
        }
        if kilobitsPerSecond.rounded() == kilobitsPerSecond {
            return "\(Int(kilobitsPerSecond)) kbps"
        }
        return String(format: "%.1f kbps", kilobitsPerSecond)
    }

    private static func commonFormatName(_ commonFormat: AVAudioCommonFormat) -> String {
        switch commonFormat {
        case .pcmFormatFloat32:
            return "Float32 PCM"
        case .pcmFormatFloat64:
            return "Float64 PCM"
        case .pcmFormatInt16:
            return "Int16 PCM"
        case .pcmFormatInt32:
            return "Int32 PCM"
        case .otherFormat:
            return localized(L10n.Recordings.compressedOrOtherFormat)
        @unknown default:
            return localized(L10n.Common.unknown)
        }
    }

    private static func formatName(from value: Any?) -> String {
        guard let formatID = audioFormatID(from: value) else {
            return localized(L10n.Common.unknown)
        }

        switch fourCharacterCode(formatID) {
        case "lpcm":
            return "Linear PCM"
        case "aac ":
            return "AAC"
        case "alac":
            return "Apple Lossless"
        case "mp4a":
            return "MPEG-4 Audio"
        case "caff":
            return "CAF"
        default:
            return fourCharacterCode(formatID)
        }
    }

    private static func audioFormatID(from value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int {
            return UInt32(value)
        }
        if let value = value as? NSNumber {
            return value.uint32Value
        }
        return nil
    }

    private static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func bitDepth(settings: [String: Any], format: AVAudioFormat) -> Int? {
        if let explicitBitDepth = intValue(from: settings[AVLinearPCMBitDepthKey]) {
            return explicitBitDepth
        }

        guard audioFormatID(from: settings[AVFormatIDKey]) == kAudioFormatLinearPCM else {
            return nil
        }

        switch format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32:
            return 32
        case .pcmFormatFloat64:
            return 64
        case .pcmFormatInt16:
            return 16
        default:
            return nil
        }
    }

    private static func fourCharacterCode(_ rawValue: UInt32) -> String {
        let bytes = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ]

        guard bytes.allSatisfy({ (32...126).contains($0) }) else {
            return "0x\(String(rawValue, radix: 16, uppercase: true))"
        }
        return String(bytes: bytes, encoding: .ascii) ?? "0x\(String(rawValue, radix: 16, uppercase: true))"
    }
}

private struct PlaybackRoundButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let title: Text
    var isPrimary = false
    let action: () -> Void

    init(systemImage: String, title: String, isPrimary: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = Text(verbatim: title)
        self.isPrimary = isPrimary
        self.action = action
    }

    init(systemImage: String, titleResource: LocalizedStringResource, isPrimary: Bool = false, action: @escaping () -> Void) {
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
                                    colors: [
                                        AppTheme.brandSoft,
                                        AppTheme.brand
                                    ],
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
                        .stroke(
                            isPrimary
                                ? Color.white.opacity(colorScheme == .dark ? 0.10 : 0.16)
                                : Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(PlaybackRoundButtonStyle(isPrimary: isPrimary, colorScheme: colorScheme))
        .accessibilityLabel(title)
    }
}

private struct PlaybackRoundButtonStyle: ButtonStyle {
    let isPrimary: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            .scaleEffect(configuration.isPressed ? 0.91 : 1)
            .offset(y: configuration.isPressed ? 3 : 0)
            .shadow(
                color: shadowColor(isPressed: configuration.isPressed),
                radius: configuration.isPressed ? (isPrimary ? 7 : 5) : (isPrimary ? 18 : 10),
                y: configuration.isPressed ? (isPrimary ? 3 : 2) : (isPrimary ? 11 : 6)
            )
            .animation(.snappy(duration: 0.11, extraBounce: 0), value: configuration.isPressed)
    }

    private func shadowColor(isPressed: Bool) -> Color {
        if isPrimary {
            if colorScheme == .dark {
                return AppTheme.brand.opacity(isPressed ? 0.14 : 0.24)
            }
            return AppTheme.brand.opacity(isPressed ? 0.24 : 0.46)
        }
        if colorScheme == .dark {
            return Color.black.opacity(isPressed ? 0.05 : 0.09)
        }
        return Color.black.opacity(isPressed ? 0.08 : 0.16)
    }
}

private struct RecordingAudioParameterRow: View {
    let icon: String
    let title: Text
    let value: String
    var showsDivider = true

    init(icon: String, titleResource: LocalizedStringResource, value: String, showsDivider: Bool = true) {
        self.icon = icon
        self.title = Text(titleResource)
        self.value = value
        self.showsDivider = showsDivider
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.info)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.info.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    title
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.redditSans(.subheadline, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)

            if showsDivider {
                Divider()
                    .padding(.leading, 40)
            }
        }
    }
}

private struct RecordingAudioMetricTile: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                title
                    .font(.redditSans(.caption, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(value)
                .font(.redditSans(.headline, weight: .bold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(AppTheme.cardBorder.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct RecordingAudioParameterGroup<Content: View>: View {
    let title: Text
    let content: Content

    init(titleResource: LocalizedStringResource, @ViewBuilder content: () -> Content) {
        self.title = Text(titleResource)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            title
                .font(.redditSans(.caption, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder.opacity(0.72), lineWidth: 1)
            }
        }
    }
}

private struct StoredTranscriptLine: Identifiable, Hashable {
    let id: String
    let startSeconds: TimeInterval
    let timeText: String
    let text: String

    static func parse(_ transcript: String) -> [StoredTranscriptLine] {
        let lines = transcript
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .compactMap { offset, rawLine -> StoredTranscriptLine? in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("["),
                      let closingBracket = line.firstIndex(of: "]") else {
                    return nil
                }

                let timeText = String(line[line.index(after: line.startIndex)..<closingBracket])
                let textStart = line.index(after: closingBracket)
                let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
                guard let seconds = parseSeconds(timeText), !text.isEmpty else {
                    return nil
                }

                return StoredTranscriptLine(
                    id: "\(offset)-\(timeText)",
                    startSeconds: seconds,
                    timeText: timeText,
                    text: text
                )
            }

        return lines.sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.id < $1.id
            }
            return $0.startSeconds < $1.startSeconds
        }
    }

    static func currentLineID(in lines: [StoredTranscriptLine], time: TimeInterval) -> StoredTranscriptLine.ID? {
        guard !lines.isEmpty else {
            return nil
        }

        var lowerBound = 0
        var upperBound = lines.count
        while lowerBound < upperBound {
            let midIndex = (lowerBound + upperBound) / 2
            if lines[midIndex].startSeconds <= time {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }

        let index = lowerBound - 1
        guard lines.indices.contains(index) else {
            return nil
        }
        return lines[index].id
    }

    private static func parseSeconds(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let minutes = Int(parts[0]),
              let seconds = Int(parts[1]),
              let centiseconds = Int(parts[2]),
              minutes >= 0,
              (0..<60).contains(seconds),
              (0..<100).contains(centiseconds) else {
            return nil
        }

        return TimeInterval(minutes * 60 + seconds) + TimeInterval(centiseconds) / 100
    }
}

private struct StoredTranscriptLineRow: View {
    let line: StoredTranscriptLine
    let translatedText: String?
    let isShowingTranslation: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Text(line.timeText)
                    .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? .white : AppTheme.brand)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(isCurrent ? AppTheme.brand : AppTheme.brand.opacity(0.12), in: Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    Text(translatedText ?? line.text)
                        .font(.redditSans(.body))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if translatedText != nil {
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
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isCurrent ? AppTheme.brand.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                HapticFeedback.play(.copy)
                UIPasteboard.general.string = line.text
            } label: {
                Label(localized(L10n.Common.copy), systemImage: "doc.on.doc")
            }

            Button {
                onEdit()
            } label: {
                Label(localized(L10n.Recordings.editTranscriptLine), systemImage: "pencil")
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let translatedText {
            return "\(line.timeText) \(translatedText) \(line.text)"
        }
        return "\(line.timeText) \(line.text)"
    }
}

@MainActor
final class RecordingPlaybackController: ObservableObject {
    @Published private(set) var currentItem: RecordingItem?
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorText: String?
    @Published private(set) var playbackRate: Float = 1

    private static let playbackGainDecibels: Float = 3
    private static let playbackUITickMilliseconds = 250
    private static let logger = Logger(subsystem: "com.reddownloader.LiveTranscriber", category: "RecordingPlayback")
    static let availablePlaybackRates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    private let audioSessionQueue = DispatchQueue(label: "com.reddownloader.live-transcriber.playback-session", qos: .userInitiated)
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchUnit: AVAudioUnitTimePitch?
    private var gainUnit: AVAudioUnitEQ?
    private var audioFile: AVAudioFile?
    private var playbackTimerTask: Task<Void, Never>?
    private var sampleRate: Double = 44_100
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var playbackScheduleID = 0
    private var playbackCommandID = 0
    private var hasScheduledPlayback = false
    private var needsPlaybackReschedule = true
    private var remoteCommandTargets: [RemoteCommandTarget] = []
    private var isReceivingRemoteControlEvents = false

    init() {
        configureRemoteCommands()
        updateRemoteCommandAvailability(isEnabled: false)
    }

    deinit {
        let targets = remoteCommandTargets
        Task { @MainActor in
            for target in targets {
                target.command.removeTarget(target.token)
            }
        }
    }

    func load(item: RecordingItem, url: URL) {
        guard currentItem?.id != item.id || currentItem?.audioFileName != item.audioFileName || !isLoaded else {
            return
        }

        load(url: url)
        currentItem = item
        updateNowPlayingInfo()
        updateRemoteCommandAvailability(isEnabled: isLoaded)
    }

    func load(url: URL) {
        unload()
        errorText = nil

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorText = localized(L10n.Recordings.recordingFileMissing)
            return
        }

        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            sampleRate = file.processingFormat.sampleRate
            duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            try configurePlaybackEngine(format: file.processingFormat)
            currentTime = 0
            isLoaded = true
            updateNowPlayingInfo()
            updateRemoteCommandAvailability(isEnabled: true)
        } catch {
            errorText = localizedFormat(L10n.Recordings.playbackFailedFormat, error.localizedDescription)
            updateRemoteCommandAvailability(isEnabled: false)
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    static func playbackRateLabel(_ rate: Float) -> String {
        if rate == floor(rate) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }

    func play() {
        guard isLoaded, let playerNode else {
            return
        }

        guard !isPlaying else {
            updateNowPlayingInfo()
            return
        }

        playbackCommandID += 1
        let commandID = playbackCommandID
        Task {
            do {
                try await configurePlaybackSession()
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                beginReceivingRemoteControlEventsIfNeeded()
                try startPlaybackEngineIfNeeded()
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                if currentTime >= duration {
                    currentTime = 0
                    needsPlaybackReschedule = true
                }
                if !hasScheduledPlayback || needsPlaybackReschedule {
                    schedulePlayback(from: currentTime)
                }
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }

                playerNode.play()
                isPlaying = true
                startTimer()
                updateNowPlayingInfo()
            } catch {
                errorText = localizedFormat(L10n.Recordings.playbackStartFailedFormat, error.localizedDescription)
            }
        }
    }

    func pause() {
        playbackCommandID += 1
        let pausedTime = currentPlaybackTime()
        isPlaying = false
        playerNode?.pause()
        audioEngine?.pause()
        currentTime = pausedTime
        stopTimer()
        updateNowPlayingInfo()
        Self.logger.debug("[RecordingPlayback] Paused at \(pausedTime, privacy: .public)")
    }

    func seek(to time: TimeInterval) {
        guard isLoaded else {
            return
        }

        let clampedTime = min(max(time, 0), duration)
        currentTime = clampedTime
        needsPlaybackReschedule = true
        if isPlaying {
            playbackCommandID += 1
            let commandID = playbackCommandID
            schedulePlayback(from: clampedTime)
            if commandID == playbackCommandID {
                playerNode?.play()
            }
        }
        updateNowPlayingInfo()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentPlaybackTime() + seconds)
    }

    func setPlaybackRate(_ rate: Float) {
        let clampedRate = min(max(rate, 0.5), 3)
        guard playbackRate != clampedRate else {
            return
        }

        currentTime = currentPlaybackTime()
        playbackRate = clampedRate
        timePitchUnit?.rate = clampedRate
        updateNowPlayingInfo()
    }

    func unload() {
        playbackCommandID += 1
        playbackScheduleID += 1
        playerNode?.stop()
        playerNode?.reset()
        audioEngine?.stop()
        playerNode = nil
        timePitchUnit = nil
        gainUnit = nil
        audioEngine = nil
        audioFile = nil
        currentItem = nil
        hasScheduledPlayback = false
        needsPlaybackReschedule = true
        isLoaded = false
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimer()
        clearNowPlayingInfo()
        updateRemoteCommandAvailability(isEnabled: false)
        endReceivingRemoteControlEventsIfNeeded()
        Task {
            await deactivatePlaybackSession()
        }
    }

    func prepareForBackgroundPlayback() {
        guard isLoaded else {
            return
        }

        beginReceivingRemoteControlEventsIfNeeded()
        updateRemoteCommandAvailability(isEnabled: true)
        updateNowPlayingInfo()
        Self.logger.debug("[RecordingPlayback] Prepared for background playback playing=\(self.isPlaying, privacy: .public)")
    }

    private func startTimer() {
        stopTimer()
        playbackTimerTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                guard self.isPlaying else {
                    do {
                        try await Task.sleep(for: .milliseconds(Self.playbackUITickMilliseconds))
                    } catch {
                        break
                    }
                    continue
                }

                self.currentTime = min(self.currentPlaybackTime(), self.duration)

                do {
                    try await Task.sleep(for: .milliseconds(Self.playbackUITickMilliseconds))
                } catch {
                    break
                }
            }
        }
    }

    private func stopTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    private func configurePlaybackEngine(format: AVAudioFormat) throws {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = playbackRate
        let equalizer = AVAudioUnitEQ(numberOfBands: 1)
        if let band = equalizer.bands.first {
            band.filterType = .parametric
            band.frequency = 1_000
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        equalizer.globalGain = Self.playbackGainDecibels

        engine.attach(node)
        engine.attach(timePitch)
        engine.attach(equalizer)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        engine.prepare()

        audioEngine = engine
        playerNode = node
        timePitchUnit = timePitch
        gainUnit = equalizer
    }

    private func startPlaybackEngineIfNeeded() throws {
        guard let audioEngine, !audioEngine.isRunning else {
            return
        }
        try audioEngine.start()
    }

    private func schedulePlayback(from time: TimeInterval) {
        guard let audioFile, let playerNode else {
            return
        }

        playbackScheduleID += 1
        let completionID = playbackScheduleID
        playerNode.stop()
        hasScheduledPlayback = false

        let startFrame = framePosition(for: time)
        let remainingFrames = max(audioFile.length - startFrame, 0)
        guard remainingFrames > 0 else {
            finishPlayback()
            return
        }

        scheduledStartFrame = startFrame
        currentTime = Double(startFrame) / sampleRate
        needsPlaybackReschedule = false
        hasScheduledPlayback = true
        let frameCount = AVAudioFrameCount(min(remainingFrames, AVAudioFramePosition(AVAudioFrameCount.max)))
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: frameCount,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] callbackType in
            Task { @MainActor in
                guard let self,
                      callbackType == .dataPlayedBack,
                      self.playbackScheduleID == completionID,
                      self.isPlaying else {
                    return
                }
                self.finishPlayback()
            }
        }
    }

    private func framePosition(for time: TimeInterval) -> AVAudioFramePosition {
        guard sampleRate > 0 else {
            return 0
        }
        let clampedTime = min(max(time, 0), duration)
        let frame = AVAudioFramePosition((clampedTime * sampleRate).rounded(.down))
        return min(max(frame, 0), audioFile?.length ?? frame)
    }

    private func currentPlaybackTime() -> TimeInterval {
        guard isPlaying,
              sampleRate > 0,
              let playerNode,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentTime
        }

        let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
        let frame = min(max(scheduledStartFrame + playedFrames, 0), audioFile?.length ?? scheduledStartFrame)
        return min(Double(frame) / sampleRate, duration)
    }

    private func finishPlayback() {
        playbackCommandID += 1
        playbackScheduleID += 1
        playerNode?.stop()
        playerNode?.reset()
        hasScheduledPlayback = false
        needsPlaybackReschedule = true
        currentTime = duration
        isPlaying = false
        stopTimer()
        updateNowPlayingInfo()
        Task {
            await deactivatePlaybackSession()
        }
    }

    private func configurePlaybackSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(
                        .playback,
                        mode: .spokenAudio,
                        policy: .longFormAudio,
                        options: []
                    )
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deactivatePlaybackSession() async {
        await withCheckedContinuation { continuation in
            audioSessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                continuation.resume(returning: ())
            }
        }
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [5]
        commandCenter.skipBackwardCommand.preferredIntervals = [5]

        remoteCommandTargets = [
            RemoteCommandTarget(command: commandCenter.playCommand, token: commandCenter.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.play()
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.pauseCommand, token: commandCenter.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.pause()
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.togglePlayPauseCommand, token: commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.togglePlayback()
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.stopCommand, token: commandCenter.stopCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.pause()
                    self.seek(to: 0)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.skipForwardCommand, token: commandCenter.skipForwardCommand.addTarget { [weak self] event in
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 5
                Task { @MainActor in
                    self?.skip(by: interval)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.skipBackwardCommand, token: commandCenter.skipBackwardCommand.addTarget { [weak self] event in
                let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 5
                Task { @MainActor in
                    self?.skip(by: -interval)
                }
                return .success
            }),
            RemoteCommandTarget(command: commandCenter.changePlaybackPositionCommand, token: commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    self?.seek(to: event.positionTime)
                }
                return .success
            })
        ]
    }

    private func updateRemoteCommandAvailability(isEnabled: Bool) {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = isEnabled
        commandCenter.pauseCommand.isEnabled = isEnabled
        commandCenter.togglePlayPauseCommand.isEnabled = isEnabled
        commandCenter.stopCommand.isEnabled = isEnabled
        commandCenter.skipForwardCommand.isEnabled = isEnabled
        commandCenter.skipBackwardCommand.isEnabled = isEnabled
        commandCenter.changePlaybackPositionCommand.isEnabled = isEnabled
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlayingInfo() {
        guard isLoaded else {
            clearNowPlayingInfo()
            return
        }

        let elapsedTime = min(max(currentPlaybackTime(), 0), duration)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyArtist: "LiveTranscriber",
            MPMediaItemPropertyAlbumTitle: nowPlayingSubtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate
        ]

        if #available(iOS 10.0, *) {
            info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        Self.logger.debug(
            "[RecordingPlayback] NowPlaying updated title=\(self.nowPlayingTitle, privacy: .public) elapsed=\(elapsedTime, privacy: .public) duration=\(self.duration, privacy: .public) rate=\(self.playbackRate, privacy: .public) playing=\(self.isPlaying, privacy: .public)"
        )
    }

    private func clearNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        Self.logger.debug("[RecordingPlayback] NowPlaying cleared")
    }

    private func beginReceivingRemoteControlEventsIfNeeded() {
        guard !isReceivingRemoteControlEvents else {
            return
        }

        UIApplication.shared.beginReceivingRemoteControlEvents()
        isReceivingRemoteControlEvents = true
        Self.logger.debug("[RecordingPlayback] Began receiving remote control events")
    }

    private func endReceivingRemoteControlEventsIfNeeded() {
        guard isReceivingRemoteControlEvents else {
            return
        }

        UIApplication.shared.endReceivingRemoteControlEvents()
        isReceivingRemoteControlEvents = false
        Self.logger.debug("[RecordingPlayback] Ended receiving remote control events")
    }

    private var nowPlayingTitle: String {
        currentItem?.audioFileName ?? localized(L10n.Recordings.recordingFallback)
    }

    private var nowPlayingSubtitle: String {
        guard let item = currentItem else {
            return localized(L10n.Recordings.recordingPlayback)
        }

        let formattedDate = item.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(item.localizedLanguageName) · \(formattedDate)"
    }
}

private struct RemoteCommandTarget {
    let command: MPRemoteCommand
    let token: Any
}

private struct RecordingInfoPill: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.redditSans(.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

#if DEBUG
#Preview("Recordings") {
    RecordingsView(
        store: RecordingStore(),
        transcriber: LiveTranscriptionManager(),
        incomingImportURL: .constant(nil),
        pendingOpenRecordingID: .constant(nil),
        player: RecordingPlaybackController()
    )
        .font(.redditSans(.body))
        .tint(AppTheme.brand)
}
#endif
