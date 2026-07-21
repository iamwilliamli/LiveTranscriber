import AVFoundation
import CoreLocation
import CoreTransferable
import MapKit
import MediaPlayer
import OSLog
import PhotosUI
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

private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PhotoLibraryVideoTransfer: Transferable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.fileURL)
        } importing: { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension.lowercased()
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("LiveTranscriber-PhotoVideo-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: temporaryURL)
            return PhotoLibraryVideoTransfer(fileURL: temporaryURL)
        }
    }
}

private enum PhotoLibraryVideoImportError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: L10n.Import.videoUnavailable)
    }
}

private enum VideoImportProgressStage: Equatable {
    case loadingVideo
    case extractingAudio
    case completed

    var titleResource: LocalizedStringResource {
        switch self {
        case .loadingVideo:
            return L10n.Import.loadingVideo
        case .extractingAudio:
            return L10n.Import.extractingAudio
        case .completed:
            return L10n.Import.videoImported
        }
    }

    var systemImage: String {
        switch self {
        case .loadingVideo:
            return "icloud.and.arrow.down"
        case .extractingAudio:
            return "waveform"
        case .completed:
            return "checkmark"
        }
    }

    var order: Int {
        switch self {
        case .loadingVideo:
            return 0
        case .extractingAudio:
            return 1
        case .completed:
            return 2
        }
    }
}

private struct VideoImportProgressState: Equatable {
    var stage: VideoImportProgressStage
    var progress: Double

    init(stage: VideoImportProgressStage, progress: Double) {
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
    }
}

private struct VideoImportProgressRow: View {
    let state: VideoImportProgressState

    private var tint: Color {
        state.stage == .completed ? AppTheme.success : AppTheme.info
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    .fill(tint.opacity(0.12))

                Image(systemName: state.stage.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(state.stage.titleResource)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(state.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.redditSans(.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .animation(.linear(duration: 0.16), value: state.progress)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(
            color: AppTheme.cardShadow,
            radius: AppTheme.cardShadowRadius,
            y: AppTheme.cardShadowYOffset
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(state.progress, format: .percent.precision(.fractionLength(0))))
    }
}

private func loadPhotoLibraryVideo(
    from item: PhotosPickerItem,
    progressHandler: @escaping @MainActor @Sendable (Double) -> Void
) async throws -> PhotoLibraryVideoTransfer {
    let stream = AsyncThrowingStream<PhotoLibraryVideoTransfer, Error> { continuation in
        let transferProgress = item.loadTransferable(type: PhotoLibraryVideoTransfer.self) { result in
            switch result {
            case .success(let video):
                guard let video else {
                    continuation.finish(throwing: PhotoLibraryVideoImportError.unavailable)
                    return
                }
                continuation.yield(video)
                continuation.finish()
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }

        let monitoringTask = Task { @MainActor in
            while !Task.isCancelled {
                progressHandler(transferProgress.fractionCompleted)
                if transferProgress.isFinished || transferProgress.isCancelled {
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        continuation.onTermination = { @Sendable termination in
            monitoringTask.cancel()
            if case .cancelled = termination {
                transferProgress.cancel()
            }
        }
    }

    for try await video in stream {
        return video
    }
    throw PhotoLibraryVideoImportError.unavailable
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ManualGeminiJSONImportSheet: View {
    @Binding var jsonText: String
    let errorMessage: String?
    let onPaste: () -> Void
    let onImport: () -> Void
    let onCancel: () -> Void
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppTheme.purple)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(L10n.Recordings.manualGeminiImportInstructions)
                            .font(.redditSans(.subheadline))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            if jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(L10n.Recordings.manualGeminiJSONPlaceholder)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }

                            TextEditor(text: $jsonText)
                                .font(.system(.footnote, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .scrollContentBackground(.hidden)
                                .focused($isEditorFocused)
                        }
                        .frame(minHeight: 290)
                        .padding(10)
                        .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                                .stroke(AppTheme.cardBorder, lineWidth: 1)
                        }

                        Button(action: onPaste) {
                            Label(localized(L10n.Recordings.manualGeminiPasteClipboard), systemImage: "doc.on.clipboard")
                                .font(.redditSans(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.redditSans(.subheadline, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                    }
                }
                .padding()
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(L10n.Recordings.manualGeminiImportJSON))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(L10n.Common.cancel), action: onCancel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(localized(L10n.Recordings.manualGeminiImportTranscript), action: onImport)
                        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
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

private struct Qwen3ASRRetranscriptionButton: View {
    let isAvailable: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(localized(L10n.Recordings.retranscribeWithQwen3ASR), systemImage: "waveform.badge.magnifyingglass")
        }
        .disabled(isDisabled || !isAvailable)
        .accessibilityHint(isAvailable ? "" : localized(L10n.Qwen3ASR.modelRequired))
    }
}

private struct MOSSLocalRetranscriptionButton: View {
    let isAvailable: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(localized(L10n.Recordings.retranscribeWithMOSS), systemImage: "person.2")
        }
        .disabled(isDisabled || !isAvailable)
        .accessibilityHint(isAvailable ? "" : localized(L10n.MOSSLocal.modelRequired))
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
    @State private var analyzingRecordingID: RecordingItem.ID?
    @State private var analysisErrorMessage: String?
    @State private var showsImporter = false
    @State private var showsVideoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var videoImportProgressState: VideoImportProgressState?
    @State private var importErrorMessage: String?
    @State private var transcriptionErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var pendingSpeechLocaleReleaseAction: PendingSpeechLocaleReleaseAction?
    @State private var appleSpeechRetranscriptionRequest: AppleSpeechRetranscriptionRequest?
    @State private var appleSpeechTranscriptionLanguages: [TranscriptionLanguage] = TranscriptionLanguage.fallbackOptions
    @State private var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    @State private var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]
    @State private var isQwen3ASRAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
    @State private var isMOSSLocalAvailable = MOSSLocalModelManager.currentStatus().isAvailable
    @State private var localWhisperRetranscriptionRequest: LocalWhisperRetranscriptionRequest?
    @State private var searchText = ""
    @State private var navigationPath: [RecordingNavigationDestination] = []
    @State private var isShowingNewCategorySheet = false
    @State private var newCategoryName = ""
    @State private var newCategoryErrorMessage: String?
    @State private var newCategoryAssignmentItem: RecordingItem?
    @State private var editCategoryName = ""
    @State private var editCategoryIconName = RecordingCategoryAppearance.defaultValue.iconName
    @State private var editCategoryColor = RecordingCategoryAppearance.defaultValue.color
    @State private var editCategoryErrorMessage: String?
    @State private var editCategoryTarget: RecordingCategoryFolder?
    @State private var deleteCategoryTarget: RecordingCategoryFolder?
    @State private var addRecordingsCategoryTarget: RecordingCategoryFolder?
    @State private var isShowingCategoryOrganizer = false
    @State private var isShowingRecordingsMap = false
    @AppStorage("Recordings.customCategoriesJSON") private var customCategoriesJSON = "[]"
    @AppStorage(RecordingCategoryAppearanceCatalog.defaultsKey) private var categoryAppearancesJSON = "{}"
    @AppStorage(RecordingSummaryProvider.selectedDefaultsKey) private var selectedSummaryProviderRawValue = RecordingSummaryProvider.automatic.rawValue

    private static let uncategorizedCategoryID = "__uncategorized__"

    private var selectedSummaryProvider: RecordingSummaryProvider {
        RecordingSummaryProvider(rawValue: selectedSummaryProviderRawValue) ?? .automatic
    }

    private var customCategoryNames: [String] {
        guard let data = customCategoriesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return RecordingCategoryCatalog.normalized(decoded)
    }

    private var categoryNames: [String] {
        RecordingCategoryCatalog.normalized(store.recordings.compactMap(\.categoryName) + customCategoryNames)
    }

    private var categoryAppearances: [String: RecordingCategoryAppearance] {
        RecordingCategoryAppearanceCatalog.decode(categoryAppearancesJSON)
    }

    private var categoryFolders: [RecordingCategoryFolder] {
        var folders = categoryNames.map { categoryName in
            RecordingCategoryFolder(
                id: categoryName,
                name: categoryName,
                count: store.recordings.filter { $0.categoryName == categoryName }.count,
                isUncategorized: false,
                appearance: categoryAppearances[categoryName.normalizedForRecordingSearch] ?? .defaultValue
            )
        }

        let uncategorizedCount = store.recordings.filter { $0.categoryName == nil }.count
        if uncategorizedCount > 0 {
            folders.append(
                RecordingCategoryFolder(
                    id: Self.uncategorizedCategoryID,
                    name: localized(L10n.Recordings.uncategorized),
                    count: uncategorizedCount,
                    isUncategorized: true,
                    appearance: .defaultValue
                )
            )
        }

        return folders.sorted { lhs, rhs in
            if lhs.isUncategorized != rhs.isUncategorized {
                return !lhs.isUncategorized
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var searchResultRecordings: [RecordingItem] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else {
            return []
        }
        return store.recordings.filter { recording($0, matches: query) }
    }

    private var isSearchingCategoryRoot: Bool {
        !normalizedSearchText(searchText).isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            recordingsList
                .navigationTitle(localized(L10n.Recordings.title))
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    recordingsToolbar
                }
                .navigationDestination(for: RecordingNavigationDestination.self) { destination in
                    navigationDestinationView(for: destination)
                }
                .onInteractiveNavigationPopGesture {
                    HapticFeedback.play(.navigation)
                }
        }
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
            Task {
                await refreshLocalWhisperMenuOptions()
            }
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
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .photosPicker(
            isPresented: $showsVideoPicker,
            selection: $selectedVideoItem,
            matching: .videos
        )
        .onChange(of: selectedVideoItem) { _, newItem in
            guard let newItem else {
                return
            }
            importVideoFromPhotos(newItem)
        }
        .sheet(isPresented: $isShowingRecordingsMap) {
            RecordingMapView(store: store, transcriber: transcriber, player: player)
        }
        .sheet(isPresented: $isShowingNewCategorySheet) {
            RecordingCategoryNameSheet(
                titleResource: L10n.Recordings.newCategory,
                iconSystemImage: "folder.badge.plus",
                categoryName: $newCategoryName,
                errorMessage: newCategoryErrorMessage,
                onSave: createCategory,
                onCancel: {
                    isShowingNewCategorySheet = false
                    newCategoryAssignmentItem = nil
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingCategoryOrganizer) {
            RecordingCategoryOrganizerSheet(
                store: store,
                onUpdateCategory: updateRecordingCategory,
                onDone: {
                    isShowingCategoryOrganizer = false
                }
            )
        }
        .sheet(item: $editCategoryTarget) { _ in
            RecordingCategoryEditSheet(
                categoryName: $editCategoryName,
                iconName: $editCategoryIconName,
                iconColor: $editCategoryColor,
                errorMessage: editCategoryErrorMessage,
                onSave: saveCategoryEdits,
                onCancel: {
                    editCategoryTarget = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $addRecordingsCategoryTarget) { folder in
            RecordingCategoryAddRecordingsSheet(
                folder: folder,
                store: store,
                onAdd: { item in
                    updateRecordingCategory(item, folder.categoryAssignmentName)
                },
                onDone: {
                    addRecordingsCategoryTarget = nil
                }
            )
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
            localized(L10n.Recordings.deleteCategory),
            isPresented: Binding(
                get: { deleteCategoryTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteCategoryTarget = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.delete), role: .destructive) {
                if let target = deleteCategoryTarget {
                    performDeleteCategory(target)
                    deleteCategoryTarget = nil
                }
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(
                localizedFormat(
                    L10n.Recordings.deleteCategoryConfirmationFormat,
                    deleteCategoryTarget?.name ?? "",
                    deleteCategoryTarget?.count ?? 0
                )
            )
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
    private func navigationDestinationView(for destination: RecordingNavigationDestination) -> some View {
        switch destination {
        case .category(let id):
            if let folder = categoryFolder(for: id) {
                RecordingCategoryDetailList(
                    folder: folder,
                    store: store,
                    transcriber: transcriber,
                    player: player,
                    downloadedLocalWhisperModels: downloadedLocalWhisperModels,
                    localWhisperLanguageOptionsByModelID: localWhisperLanguageOptionsByModelID,
                    isQwen3ASRAvailable: isQwen3ASRAvailable,
                    isMOSSLocalAvailable: isMOSSLocalAvailable,
                    analyzingRecordingID: analyzingRecordingID,
                    onOpen: { item in
                        openRecording(item)
                    },
                    onAnalyze: { item, provider in
                        analyze(item, summaryProvider: provider)
                    },
                    onDeleteRequest: { item in
                        deleteRequest = RecordingDeleteRequest(item: item)
                    },
                    onRequestRetranscription: { item in
                        appleSpeechRetranscriptionRequest = AppleSpeechRetranscriptionRequest(item: item)
                    },
                    onRequestNewCategory: { item in
                        beginNewCategory(assigning: item)
                    },
                    onUpdateCategory: updateRecordingCategory,
                    onRetranscribeWithLocalWhisper: { item in
                        localWhisperRetranscriptionRequest = LocalWhisperRetranscriptionRequest(item: item)
                    },
                    onRetranscribeWithQwen3ASR: retranscribeWithQwen3ASR,
                    onRetranscribeWithMOSS: retranscribeWithMOSS,
                    onAddRecordings: { folder in
                        addRecordingsCategoryTarget = folder
                    }
                )
            } else {
                EmptyStateView(icon: "folder", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.groupedBackground)
            }
        case .recording(let id, let transcriptLineID):
            if let item = store.recording(withID: id) {
                RecordingDetailView(
                    item: item,
                    store: store,
                    transcriber: transcriber,
                    player: player,
                    downloadedLocalWhisperModels: downloadedLocalWhisperModels,
                    localWhisperLanguageOptionsByModelID: localWhisperLanguageOptionsByModelID,
                    isQwen3ASRAvailable: isQwen3ASRAvailable,
                    isMOSSLocalAvailable: isMOSSLocalAvailable,
                    initialTranscriptLineID: transcriptLineID
                )
            } else {
                EmptyStateView(icon: "exclamationmark.triangle", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.groupedBackground)
            }
        }
    }

    @ViewBuilder
    private var recordingsList: some View {
        List {
            if let videoImportProgressState {
                VideoImportProgressRow(state: videoImportProgressState)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isSearchingCategoryRoot {
                if searchResultRecordings.isEmpty && videoImportProgressState == nil {
                    EmptyStateView(icon: "magnifyingglass", titleResource: L10n.Recordings.noSearchResults)
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(searchResultRecordings) { item in
                        searchResultRecordingRow(item)
                    }
                }
            } else if categoryFolders.isEmpty && videoImportProgressState == nil {
                EmptyStateView(icon: "folder", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(categoryFolders) { folder in
                    categoryFolderRow(folder)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: videoImportProgressState != nil)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
    }

    @ToolbarContentBuilder
    private var recordingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                if isImporting && videoImportProgressState == nil {
                    ProgressView()
                        .controlSize(.small)
                }

                categoryManagementMenu

                HStack(spacing: 10) {
                    Button {
                        HapticFeedback.play(.navigation)
                        isShowingRecordingsMap = true
                    } label: {
                        Image(systemName: "map")
                            .frame(width: 32, height: 28)
                    }
                    .accessibilityLabel(Text(L10n.Recordings.map))

                    Menu {
                        Button {
                            HapticFeedback.play(.primaryAction)
                            showsImporter = true
                        } label: {
                            Label(localized(L10n.Recordings.importAudioFile), systemImage: "waveform")
                        }

                        Button {
                            HapticFeedback.play(.primaryAction)
                            showsVideoPicker = true
                        } label: {
                            Label(localized(L10n.Recordings.importVideoFromPhotos), systemImage: "video.badge.plus")
                        }
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

    private var categoryManagementMenu: some View {
        Menu {
            Button {
                beginNewCategory()
            } label: {
                Label(localized(L10n.Recordings.newCategory), systemImage: "folder.badge.plus")
            }

            Button {
                isShowingCategoryOrganizer = true
                HapticFeedback.play(.menuSelection)
            } label: {
                Label(localized(L10n.Recordings.organize), systemImage: "square.grid.2x2")
            }
            .disabled(store.recordings.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 32, height: 28)
        }
        .accessibilityLabel(Text(L10n.Common.more))
    }

    private func categoryFolderRow(_ folder: RecordingCategoryFolder) -> some View {
        Button {
            HapticFeedback.play(.navigation)
            navigationPath.append(.category(folder.id))
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                        .fill((folder.isUncategorized ? Color.secondary : folder.appearance.color).opacity(0.12))
                    Image(systemName: folder.isUncategorized ? "tray" : folder.appearance.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(folder.isUncategorized ? AnyShapeStyle(.secondary) : AnyShapeStyle(folder.appearance.color))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name)
                        .font(.redditSans(.headline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(localizedFormat(L10n.Recordings.categoryCountFormat, folder.count))
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(AppTheme.cardBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .contextMenu {
            if !folder.isUncategorized {
                Button {
                    beginEditCategory(folder)
                } label: {
                    Label(localized(L10n.Recordings.modifyCategory), systemImage: "slider.horizontal.3")
                }

                Button(role: .destructive) {
                    requestDeleteCategory(folder)
                } label: {
                    Label(localized(L10n.Recordings.deleteCategory), systemImage: "trash")
                }
            }
        }
    }

    private func searchResultRecordingRow(_ item: RecordingItem) -> some View {
        let isTranscriptionRunning = item.importStatus?.isFailed == false
        let isTranscriptionActionDisabled = item.isTranscriptLocked
            || isTranscriptionRunning
            || transcriber.isRecording
            || transcriber.isPreparing
        let searchMatch = transcriptSearchMatch(for: item)

        return RecordingRow(
            item: item,
            isAnalyzing: analyzingRecordingID == item.id,
            canGenerateIntelligence: store.intelligenceAvailability.isAvailable,
            searchMatch: searchMatch
        ) {
            openRecording(item, initialTranscriptLineID: searchMatch?.lineID)
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

            RecordingCategoryMenu(
                selection: item.categoryName,
                categories: categoryNames,
                onRequestNewCategory: {
                    beginNewCategory(assigning: item)
                },
                onSelect: { categoryName in
                    updateRecordingCategory(item, categoryName)
                }
            ) {
                Label(localized(L10n.Recordings.moveToCategory), systemImage: "folder")
            }

            if store.summaryProviderAvailability.hasAnyAvailableProvider {
                Button {
                    analyze(item, summaryProvider: .automatic)
                } label: {
                    Label(localized(L10n.Recordings.analyze), systemImage: "sparkles")
                }
                .disabled(analyzingRecordingID != nil)
            }

            Button {
                appleSpeechRetranscriptionRequest = AppleSpeechRetranscriptionRequest(item: item)
            } label: {
                Label(localized(L10n.Recordings.retranscribe), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isTranscriptionActionDisabled)

            LocalWhisperRetranscriptionButton(
                downloadedModels: downloadedLocalWhisperModels,
                isDisabled: isTranscriptionActionDisabled
            ) {
                localWhisperRetranscriptionRequest = LocalWhisperRetranscriptionRequest(item: item)
            }

            Qwen3ASRRetranscriptionButton(
                isAvailable: isQwen3ASRAvailable,
                isDisabled: isTranscriptionActionDisabled
            ) {
                retranscribeWithQwen3ASR(item)
            }

            MOSSLocalRetranscriptionButton(
                isAvailable: isMOSSLocalAvailable,
                isDisabled: isTranscriptionActionDisabled
            ) {
                retranscribeWithMOSS(item)
            }

            Button(role: .destructive) {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: item)
            } label: {
                Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: item)
            } label: {
                Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if store.summaryProviderAvailability.hasAnyAvailableProvider {
                Button {
                    analyze(item, summaryProvider: .automatic)
                } label: {
                    Label(localized(L10n.Recordings.analyze), systemImage: "sparkles")
                }
                .tint(AppTheme.info)
                .disabled(analyzingRecordingID != nil)
            }
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
        isQwen3ASRAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
        isMOSSLocalAvailable = MOSSLocalModelManager.currentStatus().isAvailable
    }

    private func queueImport(from url: URL) {
        guard !isImporting else {
            HapticFeedback.play(.blocked)
            return
        }

        navigationPath.removeAll()
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

    private func importVideoFromPhotos(_ item: PhotosPickerItem) {
        guard !isImporting else {
            selectedVideoItem = nil
            HapticFeedback.play(.blocked)
            return
        }

        navigationPath.removeAll()
        isImporting = true
        updateVideoImportProgress(stage: .loadingVideo, progress: 0)
        HapticFeedback.play(.importStart)

        Task {
            var temporaryVideoURL: URL?
            defer {
                if let temporaryVideoURL {
                    try? FileManager.default.removeItem(at: temporaryVideoURL)
                }
                selectedVideoItem = nil
                isImporting = false
                withAnimation(.snappy(duration: 0.28, extraBounce: 0)) {
                    videoImportProgressState = nil
                }
            }

            do {
                let video = try await loadPhotoLibraryVideo(from: item) { progress in
                    updateVideoImportProgress(
                        stage: .loadingVideo,
                        progress: progress * 0.42
                    )
                }
                temporaryVideoURL = video.fileURL
                updateVideoImportProgress(stage: .extractingAudio, progress: 0.42)
                _ = try await store.importVideoRecording(from: video.fileURL) { progress in
                    updateVideoImportProgress(
                        stage: .extractingAudio,
                        progress: 0.42 + progress * 0.56
                    )
                }
                updateVideoImportProgress(stage: .completed, progress: 1)
                HapticFeedback.play(.importComplete)
                try? await Task.sleep(for: .milliseconds(450))
            } catch {
                importErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func updateVideoImportProgress(stage: VideoImportProgressStage, progress: Double) {
        let previousState = videoImportProgressState
        if let previousState, stage.order < previousState.stage.order {
            return
        }
        let clampedProgress = min(max(progress, 0), 1)
        let monotonicProgress = max(previousState?.progress ?? 0, clampedProgress)
        let nextState = VideoImportProgressState(stage: stage, progress: monotonicProgress)

        if previousState?.stage != stage || previousState == nil {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                videoImportProgressState = nextState
            }
        } else {
            videoImportProgressState = nextState
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

    private func openRecording(
        _ item: RecordingItem,
        initialTranscriptLineID: StoredTranscriptLine.ID? = nil
    ) {
        HapticFeedback.play(.navigation)
        navigationPath.append(
            .recording(item.id, transcriptLineID: initialTranscriptLineID)
        )
    }

    private func consumePendingOpenRecordingIDIfNeeded() {
        guard let id = pendingOpenRecordingID,
              let item = store.recording(withID: id) else {
            return
        }

        pendingOpenRecordingID = nil
        openRecording(item)
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

    private func retranscribeWithQwen3ASR(_ item: RecordingItem) {
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
                try await store.retranscribeWithQwen3ASR(
                    item,
                    language: TranscriptionLanguage(id: item.languageID)
                )
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeWithMOSS(_ item: RecordingItem) {
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
                try await store.retranscribeWithMOSS(item)
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
            navigationPath.removeAll { destination in
                if case .recording(let id, _) = destination, id == item.id {
                    return true
                }
                return false
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

    private func transcriptSearchMatch(for item: RecordingItem) -> RecordingTranscriptSearchMatch? {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedQuery = normalizedSearchText(query)
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        let transcript = store.transcriptText(for: item)
        guard let line = StoredTranscriptLine.parse(transcript).first(where: { line in
            normalizedSearchText("[\(line.timeText)] \(line.text)").contains(normalizedQuery)
        }) else {
            return nil
        }

        return RecordingTranscriptSearchMatch(
            lineID: line.id,
            timeText: line.timeText,
            text: line.text,
            query: query
        )
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.normalizedForRecordingSearch
    }

    private func categoryFolder(for id: String) -> RecordingCategoryFolder? {
        categoryFolders.first { $0.id == id }
    }

    private func beginNewCategory(assigning item: RecordingItem? = nil) {
        newCategoryName = ""
        newCategoryErrorMessage = nil
        newCategoryAssignmentItem = item
        isShowingNewCategorySheet = true
        HapticFeedback.play(.menuSelection)
    }

    private func createCategory() {
        let cleanedName = RecordingItem.normalizedCategoryName(newCategoryName) ?? ""
        guard !cleanedName.isEmpty else {
            newCategoryErrorMessage = localized(L10n.Recordings.categoryNamePlaceholder)
            HapticFeedback.play(.failure)
            return
        }

        let newKey = cleanedName.normalizedForRecordingSearch
        if let existingName = categoryNames.first(where: { $0.normalizedForRecordingSearch == newKey }) {
            if let item = newCategoryAssignmentItem {
                updateRecordingCategory(item, existingName)
            } else {
                navigationPath.append(.category(existingName))
            }
            isShowingNewCategorySheet = false
            newCategoryErrorMessage = nil
            newCategoryAssignmentItem = nil
            HapticFeedback.play(.navigation)
            return
        }

        guard !isReservedCategoryName(cleanedName) else {
            newCategoryErrorMessage = localized(L10n.Recordings.categoryExists)
            HapticFeedback.play(.failure)
            return
        }

        RecordingCategoryCatalog.register(cleanedName)
        if let item = newCategoryAssignmentItem {
            updateRecordingCategory(item, cleanedName)
        } else {
            navigationPath.append(.category(cleanedName))
        }
        newCategoryName = ""
        newCategoryErrorMessage = nil
        newCategoryAssignmentItem = nil
        isShowingNewCategorySheet = false
        HapticFeedback.play(.primaryAction)
    }

    private func beginEditCategory(_ folder: RecordingCategoryFolder) {
        editCategoryName = folder.name
        editCategoryIconName = folder.appearance.iconName
        editCategoryColor = folder.appearance.color
        editCategoryErrorMessage = nil
        editCategoryTarget = folder
        HapticFeedback.play(.menuSelection)
    }

    private func saveCategoryEdits() {
        guard let target = editCategoryTarget else {
            return
        }

        let cleanedName = RecordingItem.normalizedCategoryName(editCategoryName) ?? ""
        guard !cleanedName.isEmpty else {
            editCategoryErrorMessage = localized(L10n.Recordings.categoryNamePlaceholder)
            HapticFeedback.play(.failure)
            return
        }

        let oldKey = target.name.normalizedForRecordingSearch
        let newKey = cleanedName.normalizedForRecordingSearch
        if newKey != oldKey,
           categoryNames.contains(where: { $0.normalizedForRecordingSearch == newKey }) {
            editCategoryErrorMessage = localized(L10n.Recordings.categoryExists)
            HapticFeedback.play(.failure)
            return
        }
        guard !isReservedCategoryName(cleanedName) else {
            editCategoryErrorMessage = localized(L10n.Recordings.categoryExists)
            HapticFeedback.play(.failure)
            return
        }

        do {
            if cleanedName != target.name {
                _ = try store.renameCategory(named: target.name, to: cleanedName)
                RecordingCategoryCatalog.rename(target.name, to: cleanedName)
                navigationPath = navigationPath.map { destination in
                    if case .category(let id) = destination, id == target.id {
                        return .category(cleanedName)
                    }
                    return destination
                }
            }

            RecordingCategoryAppearanceCatalog.set(
                RecordingCategoryAppearance(iconName: editCategoryIconName, color: editCategoryColor),
                for: cleanedName,
                removing: target.name
            )
            editCategoryTarget = nil
            HapticFeedback.play(.primaryAction)
        } catch {
            editCategoryErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func requestDeleteCategory(_ folder: RecordingCategoryFolder) {
        HapticFeedback.play(.deleteRequested)
        if folder.count == 0 {
            performDeleteCategory(folder)
        } else {
            deleteCategoryTarget = folder
        }
    }

    private func performDeleteCategory(_ folder: RecordingCategoryFolder) {
        do {
            _ = try store.removeCategory(named: folder.name)
            RecordingCategoryCatalog.remove(folder.name)
            RecordingCategoryAppearanceCatalog.remove(folder.name)
            navigationPath.removeAll { destination in
                if case .category(let id) = destination, id == folder.id {
                    return true
                }
                return false
            }
            HapticFeedback.play(.primaryAction)
        } catch {
            transcriptionErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func updateRecordingCategory(_ item: RecordingItem, _ categoryName: String?) {
        do {
            _ = try store.updateCategory(for: item, categoryName: categoryName)
            if let categoryName {
                RecordingCategoryCatalog.register(categoryName)
            }
            HapticFeedback.play(.menuSelection)
        } catch {
            transcriptionErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func isReservedCategoryName(_ name: String) -> Bool {
        name.normalizedForRecordingSearch == localized(L10n.Recordings.uncategorized).normalizedForRecordingSearch
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

/// Central store for the user's category names. Recording assignments live on
/// `RecordingItem.categoryName`; this registry additionally keeps categories
/// that currently have no recordings, and is the single place that mutates
/// the persisted list so create/rename/delete stay consistent across entry
/// points (folder list, organizer, edit sheet, save sheet).
enum RecordingCategoryCatalog {
    static let customCategoriesDefaultsKey = "Recordings.customCategoriesJSON"

    static func customNames() -> [String] {
        guard let json = UserDefaults.standard.string(forKey: customCategoriesDefaultsKey),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return normalized(decoded)
    }

    static func allNames(recordings: [RecordingItem]) -> [String] {
        normalized(recordings.compactMap(\.categoryName) + customNames())
    }

    static func register(_ name: String?) {
        guard let cleaned = RecordingItem.normalizedCategoryName(name ?? "") else {
            return
        }
        write(customNames() + [cleaned])
    }

    static func remove(_ name: String) {
        let key = name.normalizedForRecordingSearch
        write(customNames().filter { $0.normalizedForRecordingSearch != key })
    }

    static func rename(_ oldName: String, to newName: String) {
        let oldKey = oldName.normalizedForRecordingSearch
        write(customNames().filter { $0.normalizedForRecordingSearch != oldKey } + [newName])
    }

    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for name in names {
            guard let cleaned = RecordingItem.normalizedCategoryName(name) else {
                continue
            }
            let key = cleaned.normalizedForRecordingSearch
            guard seen.insert(key).inserted else {
                continue
            }
            normalized.append(cleaned)
        }

        return normalized.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func write(_ names: [String]) {
        let cleaned = normalized(names)
        guard let data = try? JSONEncoder().encode(cleaned),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: customCategoriesDefaultsKey)
        RecordingCategoryCloudSync.shared.localStateDidChange()
    }
}

private struct RecordingCategoryAppearance: Codable, Hashable {
    static let defaultValue = RecordingCategoryAppearance(
        iconName: "folder.fill",
        red: 0.96,
        green: 0.22,
        blue: 0.10
    )

    static let availableIconNames = [
        "folder.fill",
        "briefcase.fill",
        "book.closed.fill",
        "graduationcap.fill",
        "person.2.fill",
        "bubble.left.and.bubble.right.fill",
        "mic.fill",
        "waveform",
        "lightbulb.fill",
        "star.fill",
        "heart.fill",
        "gamecontroller.fill",
        "music.note",
        "film.fill",
        "airplane",
        "house.fill",
        "building.2.fill",
        "calendar",
        "checklist",
        "tag.fill"
    ]

    let iconName: String
    let red: Double
    let green: Double
    let blue: Double

    init(iconName: String, red: Double, green: Double, blue: Double) {
        self.iconName = Self.availableIconNames.contains(iconName)
            ? iconName
            : "folder.fill"
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(iconName: String, color: Color) {
        let resolvedColor = UIColor(color)
        var red: CGFloat = 0.96
        var green: CGFloat = 0.22
        var blue: CGFloat = 0.10
        var alpha: CGFloat = 1
        resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(
            iconName: iconName,
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var normalized: RecordingCategoryAppearance {
        RecordingCategoryAppearance(iconName: iconName, red: red, green: green, blue: blue)
    }
}

private enum RecordingCategoryAppearanceCatalog {
    static let defaultsKey = "Recordings.categoryAppearancesJSON"

    static func decode(_ json: String) -> [String: RecordingCategoryAppearance] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: RecordingCategoryAppearance].self, from: data) else {
            return [:]
        }
        return decoded.mapValues(\.normalized)
    }

    static func all() -> [String: RecordingCategoryAppearance] {
        decode(UserDefaults.standard.string(forKey: defaultsKey) ?? "{}")
    }

    static func appearance(for categoryName: String) -> RecordingCategoryAppearance {
        all()[categoryName.normalizedForRecordingSearch] ?? .defaultValue
    }

    static func set(
        _ appearance: RecordingCategoryAppearance,
        for categoryName: String,
        removing oldCategoryName: String? = nil
    ) {
        var appearances = all()
        if let oldCategoryName {
            appearances.removeValue(forKey: oldCategoryName.normalizedForRecordingSearch)
        }
        appearances[categoryName.normalizedForRecordingSearch] = appearance.normalized
        write(appearances)
    }

    static func remove(_ categoryName: String) {
        var appearances = all()
        appearances.removeValue(forKey: categoryName.normalizedForRecordingSearch)
        write(appearances)
    }

    private static func write(_ appearances: [String: RecordingCategoryAppearance]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(appearances),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        UserDefaults.standard.set(json, forKey: defaultsKey)
        RecordingCategoryCloudSync.shared.localStateDidChange()
    }
}

private struct RecordingCategoryCloudSnapshot: Codable {
    var schemaVersion: Int
    var updatedAt: Date
    var categoryNames: [String]
    var appearances: [String: RecordingCategoryAppearance]
}

/// Keeps the small category catalog in iCloud KVS while `@AppStorage` remains
/// the immediate local source for SwiftUI. Recording assignments continue to
/// sync through the CloudKit-backed `RecordingIndexRecord`.
final class RecordingCategoryCloudSync: @unchecked Sendable {
    static let shared = RecordingCategoryCloudSync()

    private static let snapshotKey = "Recordings.categoryCatalog.cloudSnapshot.v1"
    private static let localRevisionDefaultsKey = "Recordings.categoryCatalog.localRevision.v1"

    private let cloudStore: NSUbiquitousKeyValueStore
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(
        subsystem: "com.reddownloader.LiveTranscriber",
        category: "CategoryCloudSync"
    )
    private var isEnabled = false
    private var changeObserver: NSObjectProtocol?

    private init(
        cloudStore: NSUbiquitousKeyValueStore = .default,
        defaults: UserDefaults = .standard
    ) {
        self.cloudStore = cloudStore
        self.defaults = defaults
        encoder.outputFormatting = [.sortedKeys]
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }

        isEnabled = enabled
        if enabled {
            changeObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloudStore,
                queue: .main
            ) { [weak self] notification in
                self?.handleCloudStoreChange(notification)
            }
            cloudStore.synchronize()
            reconcileInitialState()
        } else if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }

    func localStateDidChange() {
        let revision = Date()
        defaults.set(revision.timeIntervalSince1970, forKey: Self.localRevisionDefaultsKey)
        guard isEnabled else {
            return
        }
        publishLocalState(updatedAt: revision)
    }

    private func reconcileInitialState() {
        let remoteSnapshot = cloudSnapshot()
        let localRevision = localRevisionDate()

        if let remoteSnapshot {
            if let localRevision,
               localRevision > remoteSnapshot.updatedAt,
               hasExplicitLocalState {
                publishLocalState(updatedAt: localRevision)
            } else if localRevision == nil, hasLocalCatalogData {
                let mergedSnapshot = merging(remoteSnapshotWithLocalState: remoteSnapshot)
                apply(mergedSnapshot)
                publishLocalState(updatedAt: mergedSnapshot.updatedAt)
            } else {
                apply(remoteSnapshot)
            }
        } else if hasExplicitLocalState {
            let revision = localRevision ?? Date()
            publishLocalState(updatedAt: revision)
        }
    }

    private func handleCloudStoreChange(_ notification: Notification) {
        guard isEnabled else {
            return
        }
        if let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
           !changedKeys.contains(Self.snapshotKey) {
            return
        }
        guard let remoteSnapshot = cloudSnapshot() else {
            return
        }

        if localRevisionDate() == nil, hasLocalCatalogData {
            let mergedSnapshot = merging(remoteSnapshotWithLocalState: remoteSnapshot)
            apply(mergedSnapshot)
            publishLocalState(updatedAt: mergedSnapshot.updatedAt)
            return
        }

        if let localRevision = localRevisionDate(),
           localRevision > remoteSnapshot.updatedAt {
            publishLocalState(updatedAt: localRevision)
            return
        }
        apply(remoteSnapshot)
    }

    private var hasExplicitLocalState: Bool {
        localRevisionDate() != nil || hasLocalCatalogData
    }

    private var hasLocalCatalogData: Bool {
        !RecordingCategoryCatalog.customNames().isEmpty
            || !RecordingCategoryAppearanceCatalog.all().isEmpty
    }

    private func localRevisionDate() -> Date? {
        let value = defaults.double(forKey: Self.localRevisionDefaultsKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private func publishLocalState(updatedAt: Date) {
        let snapshot = RecordingCategoryCloudSnapshot(
            schemaVersion: 1,
            updatedAt: updatedAt,
            categoryNames: RecordingCategoryCatalog.customNames(),
            appearances: RecordingCategoryAppearanceCatalog.all()
        )
        do {
            let data = try encoder.encode(snapshot)
            cloudStore.set(data, forKey: Self.snapshotKey)
            cloudStore.synchronize()
            logger.debug(
                "Published category snapshot categories=\(snapshot.categoryNames.count, privacy: .public) appearances=\(snapshot.appearances.count, privacy: .public)"
            )
        } catch {
            logger.error("Failed to encode category snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func merging(
        remoteSnapshotWithLocalState remoteSnapshot: RecordingCategoryCloudSnapshot
    ) -> RecordingCategoryCloudSnapshot {
        var appearances = RecordingCategoryAppearanceCatalog.all()
        appearances.merge(remoteSnapshot.appearances.mapValues(\.normalized)) { _, remote in
            remote
        }
        return RecordingCategoryCloudSnapshot(
            schemaVersion: 1,
            updatedAt: Date(),
            categoryNames: RecordingCategoryCatalog.normalized(
                remoteSnapshot.categoryNames + RecordingCategoryCatalog.customNames()
            ),
            appearances: appearances
        )
    }

    private func cloudSnapshot() -> RecordingCategoryCloudSnapshot? {
        guard let data = cloudStore.data(forKey: Self.snapshotKey) else {
            return nil
        }
        do {
            let snapshot = try decoder.decode(RecordingCategoryCloudSnapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                return nil
            }
            return snapshot
        } catch {
            logger.error("Failed to decode category snapshot: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func apply(_ snapshot: RecordingCategoryCloudSnapshot) {
        let categoryNames = RecordingCategoryCatalog.normalized(snapshot.categoryNames)
        let appearances = snapshot.appearances.mapValues(\.normalized)

        do {
            let namesData = try encoder.encode(categoryNames)
            let appearancesData = try encoder.encode(appearances)
            guard let namesJSON = String(data: namesData, encoding: .utf8),
                  let appearancesJSON = String(data: appearancesData, encoding: .utf8) else {
                return
            }

            defaults.set(namesJSON, forKey: RecordingCategoryCatalog.customCategoriesDefaultsKey)
            defaults.set(appearancesJSON, forKey: RecordingCategoryAppearanceCatalog.defaultsKey)
            defaults.set(snapshot.updatedAt.timeIntervalSince1970, forKey: Self.localRevisionDefaultsKey)
            logger.debug(
                "Applied category snapshot categories=\(categoryNames.count, privacy: .public) appearances=\(appearances.count, privacy: .public)"
            )
        } catch {
            logger.error("Failed to apply category snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct RecordingCategoryFolder: Identifiable, Hashable {
    let id: String
    let name: String
    let count: Int
    let isUncategorized: Bool
    let appearance: RecordingCategoryAppearance

    /// Matching key used for membership and counting, so "Work" and "work"
    /// land in the same folder instead of one of them becoming invisible.
    var matchKey: String? {
        isUncategorized ? nil : id.normalizedForRecordingSearch
    }

    var categoryAssignmentName: String? {
        isUncategorized ? nil : name
    }
}

private enum RecordingNavigationDestination: Hashable {
    case category(String)
    case recording(RecordingItem.ID, transcriptLineID: StoredTranscriptLine.ID?)
}

private extension Array where Element == RecordingNavigationDestination {
    var containsRecordingDetail: Bool {
        contains { destination in
            if case .recording = destination {
                return true
            }
            return false
        }
    }
}

private struct RecordingCategoryDetailList: View {
    let folder: RecordingCategoryFolder
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    let downloadedLocalWhisperModels: [LocalWhisperModel]
    let localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]]
    let isQwen3ASRAvailable: Bool
    let isMOSSLocalAvailable: Bool
    let analyzingRecordingID: RecordingItem.ID?
    let onOpen: (RecordingItem) -> Void
    let onAnalyze: (RecordingItem, RecordingSummaryProvider) -> Void
    let onDeleteRequest: (RecordingItem) -> Void
    let onRequestRetranscription: (RecordingItem) -> Void
    let onRequestNewCategory: (RecordingItem) -> Void
    let onUpdateCategory: (RecordingItem, String?) -> Void
    let onRetranscribeWithLocalWhisper: (RecordingItem) -> Void
    let onRetranscribeWithQwen3ASR: (RecordingItem) -> Void
    let onRetranscribeWithMOSS: (RecordingItem) -> Void
    let onAddRecordings: (RecordingCategoryFolder) -> Void

    private var categories: [String] {
        RecordingCategoryCatalog.allNames(recordings: store.recordings)
    }

    private var recordings: [RecordingItem] {
        store.recordings.filter { item in
            if folder.isUncategorized {
                return item.categoryName == nil
            }
            return item.categoryName?.normalizedForRecordingSearch == folder.matchKey
        }
    }

    var body: some View {
        List {
            if recordings.isEmpty {
                EmptyStateView(icon: "waveform", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(recordings) { item in
                    let isTranscriptionRunning = item.importStatus?.isFailed == false
                    let isTranscriptionActionDisabled = item.isTranscriptLocked
                        || isTranscriptionRunning
                        || transcriber.isRecording
                        || transcriber.isPreparing

                    RecordingRow(
                        item: item,
                        isAnalyzing: analyzingRecordingID == item.id,
                        canGenerateIntelligence: store.intelligenceAvailability.isAvailable
                    ) {
                        onOpen(item)
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

                        RecordingCategoryMenu(
                            selection: item.categoryName,
                            categories: categories,
                            onRequestNewCategory: {
                                onRequestNewCategory(item)
                            },
                            onSelect: { categoryName in
                                onUpdateCategory(item, categoryName)
                            }
                        ) {
                            Label(localized(L10n.Recordings.moveToCategory), systemImage: "folder")
                        }

                        if store.summaryProviderAvailability.hasAnyAvailableProvider {
                            Button {
                                onAnalyze(item, .automatic)
                            } label: {
                                Label(localized(L10n.Recordings.analyze), systemImage: "sparkles")
                        }
                        .disabled(analyzingRecordingID != nil)
                    }

                    Button {
                        onRequestRetranscription(item)
                    } label: {
                        Label(localized(L10n.Recordings.retranscribe), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isTranscriptionActionDisabled)

                    LocalWhisperRetranscriptionButton(
                        downloadedModels: downloadedLocalWhisperModels,
                        isDisabled: isTranscriptionActionDisabled
                    ) {
                        onRetranscribeWithLocalWhisper(item)
                    }

                    Qwen3ASRRetranscriptionButton(
                        isAvailable: isQwen3ASRAvailable,
                        isDisabled: isTranscriptionActionDisabled
                    ) {
                        onRetranscribeWithQwen3ASR(item)
                    }

                    MOSSLocalRetranscriptionButton(
                        isAvailable: isMOSSLocalAvailable,
                        isDisabled: isTranscriptionActionDisabled
                    ) {
                        onRetranscribeWithMOSS(item)
                    }

                        Button(role: .destructive) {
                            HapticFeedback.play(.deleteRequested)
                            onDeleteRequest(item)
                        } label: {
                            Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            HapticFeedback.play(.deleteRequested)
                            onDeleteRequest(item)
                        } label: {
                            Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if store.summaryProviderAvailability.hasAnyAvailableProvider {
                            Button {
                                onAnalyze(item, .automatic)
                            } label: {
                                Label(localized(L10n.Recordings.analyze), systemImage: "sparkles")
                            }
                            .tint(AppTheme.info)
                            .disabled(analyzingRecordingID != nil)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppTheme.groupedBackground)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticFeedback.play(.menuSelection)
                    onAddRecordings(folder)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text(L10n.Recordings.addRecordingsToCategory))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 8)
        }
    }
}

private struct RecordingCategoryNameSheet: View {
    let titleResource: LocalizedStringResource
    let iconSystemImage: String
    @Binding var categoryName: String
    let errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    private var trimmedName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label(localized(titleResource), systemImage: iconSystemImage)
                    .font(.redditSans(.headline, weight: .semibold))

                TextField(localized(L10n.Recordings.categoryNamePlaceholder), text: $categoryName)
                    .font(.redditSans(.body, weight: .semibold))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.redditSans(.caption, weight: .semibold))
                        .foregroundStyle(AppTheme.warning)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(titleResource))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(localized(L10n.Common.save)) {
                        onSave()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

private struct RecordingCategoryEditSheet: View {
    @Binding var categoryName: String
    @Binding var iconName: String
    @Binding var iconColor: Color
    let errorMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    private let iconColumns = [
        GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 10)
    ]

    private var trimmedName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewName: String {
        trimmedName.isEmpty ? localized(L10n.Recordings.categoryName) : trimmedName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(iconColor.opacity(0.14))

                            Image(systemName: iconName)
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(iconColor)
                        }
                        .frame(width: 58, height: 58)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(previewName)
                                .font(.redditSans(.title3, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(L10n.Recordings.modifyCategory)
                                .font(.redditSans(.caption))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                            .stroke(AppTheme.cardBorder, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Recordings.categoryName)
                            .font(.redditSans(.caption, weight: .bold))
                            .foregroundStyle(.secondary)

                        TextField(localized(L10n.Recordings.categoryNamePlaceholder), text: $categoryName)
                            .font(.redditSans(.body, weight: .semibold))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .frame(height: 48)
                            .background(
                                AppTheme.elevatedBackground,
                                in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                            )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.Recordings.categoryIcon)
                            .font(.redditSans(.caption, weight: .bold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: iconColumns, spacing: 10) {
                            ForEach(RecordingCategoryAppearance.availableIconNames, id: \.self) { candidate in
                                Button {
                                    HapticFeedback.play(.menuSelection)
                                    iconName = candidate
                                } label: {
                                    Image(systemName: candidate)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(candidate == iconName ? .white : iconColor)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 46)
                                        .background(
                                            candidate == iconName ? iconColor : AppTheme.elevatedBackground,
                                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .stroke(
                                                    candidate == iconName ? iconColor : AppTheme.cardBorder.opacity(0.7),
                                                    lineWidth: candidate == iconName ? 2 : 1
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(L10n.Recordings.categoryIcon))
                                .accessibilityValue(candidate)
                            }
                        }
                    }

                    ColorPicker(selection: $iconColor, supportsOpacity: false) {
                        HStack(spacing: 10) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(iconColor)
                                .frame(width: 28, height: 28)
                                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text(L10n.Recordings.categoryIconColor)
                                .font(.redditSans(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(12)
                    .background(
                        AppTheme.elevatedBackground,
                        in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                    )

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(Text(L10n.Recordings.modifyCategory))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(localized(L10n.Common.save)) {
                        onSave()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}

private struct RecordingCategoryOrganizerSheet: View {
    @ObservedObject var store: RecordingStore
    let onUpdateCategory: (RecordingItem, String?) -> Void
    let onDone: () -> Void

    private var categories: [String] {
        RecordingCategoryCatalog.allNames(recordings: store.recordings)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.recordings) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text((item.audioFileName as NSString).deletingPathExtension)
                                .font(.redditSans(.subheadline, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(item.categoryName ?? localized(L10n.Recordings.uncategorized))
                                .font(.redditSans(.caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        RecordingCategoryMenu(
                            selection: item.categoryName,
                            categories: categories,
                            onSelect: { categoryName in
                                onUpdateCategory(item, categoryName)
                            }
                        ) {
                            Image(systemName: "folder")
                                .frame(width: 32, height: 28)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(localized(L10n.Recordings.organize))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized(L10n.Common.done)) {
                        onDone()
                    }
                }
            }
        }
    }
}

private struct RecordingCategoryAddRecordingsSheet: View {
    let folder: RecordingCategoryFolder
    @ObservedObject var store: RecordingStore
    let onAdd: (RecordingItem) -> Void
    let onDone: () -> Void
    @State private var searchText = ""

    private var candidateRecordings: [RecordingItem] {
        let query = searchText.normalizedForRecordingSearch
        let candidates = store.recordings.filter { item in
            if folder.isUncategorized {
                return item.categoryName != nil
            }
            return item.categoryName?.normalizedForRecordingSearch != folder.matchKey
        }

        guard !query.isEmpty else {
            return candidates
        }
        return candidates.filter { item in
            store.normalizedSearchText(for: item).contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidateRecordings.isEmpty {
                    EmptyStateView(
                        icon: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "checkmark.folder" : "magnifyingglass",
                        titleResource: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.Recordings.noRecordingsToAdd : L10n.Recordings.noSearchResults
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(candidateRecordings) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text((item.audioFileName as NSString).deletingPathExtension)
                                    .font(.redditSans(.subheadline, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(item.categoryName ?? localized(L10n.Recordings.uncategorized))
                                    .font(.redditSans(.caption))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button {
                                onAdd(item)
                            } label: {
                                Label(localized(L10n.Recordings.addToCategory), systemImage: "plus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(localizedFormat(L10n.Recordings.addRecordingsToCategoryFormat, folder.name))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(L10n.Recordings.searchPrompt)
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized(L10n.Common.done)) {
                        onDone()
                    }
                }
            }
        }
    }
}

/// Shared category chooser: uncategorized, every known category, and a
/// "New Category" option, so all assignment entry points behave the same.
struct RecordingCategoryMenu<MenuLabel: View>: View {
    let selection: String?
    let categories: [String]
    var onRequestNewCategory: (() -> Void)?
    let onSelect: (String?) -> Void
    @ViewBuilder let menuLabel: () -> MenuLabel

    @State private var isShowingNewCategoryAlert = false
    @State private var newCategoryName = ""

    private var selectionKey: String? {
        selection?.normalizedForRecordingSearch
    }

    var body: some View {
        Menu {
            Button {
                HapticFeedback.play(.menuSelection)
                onSelect(nil)
            } label: {
                Label(localized(L10n.Recordings.uncategorized), systemImage: selection == nil ? "checkmark" : "tray")
            }

            if !categories.isEmpty {
                Divider()

                ForEach(categories, id: \.self) { category in
                    let appearance = RecordingCategoryAppearanceCatalog.appearance(for: category)

                    Button {
                        HapticFeedback.play(.menuSelection)
                        onSelect(category)
                    } label: {
                        Label(
                            category,
                            systemImage: category.normalizedForRecordingSearch == selectionKey
                                ? "checkmark"
                                : appearance.iconName
                        )
                    }
                }
            }

            Divider()

            Button {
                HapticFeedback.play(.menuSelection)
                if let onRequestNewCategory {
                    DispatchQueue.main.async {
                        onRequestNewCategory()
                    }
                } else {
                    newCategoryName = ""
                    isShowingNewCategoryAlert = true
                }
            } label: {
                Label(localized(L10n.Recordings.newCategory), systemImage: "folder.badge.plus")
            }
        } label: {
            menuLabel()
        }
        .alert(localized(L10n.Recordings.newCategory), isPresented: $isShowingNewCategoryAlert) {
            TextField(localized(L10n.Recordings.categoryNamePlaceholder), text: $newCategoryName)
            Button(localized(L10n.Common.save)) {
                if let cleanedName = RecordingItem.normalizedCategoryName(newCategoryName) {
                    HapticFeedback.play(.primaryAction)
                    onSelect(cleanedName)
                }
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        }
    }
}

struct RecordingMapView: View {
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPoint: RecordingMapPoint?
    @State private var selectedRecording: RecordingItem?
    @State private var interactiveNavigationPopHasPlayedHaptic = false
    @State private var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    @State private var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]
    @State private var isQwen3ASRAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
    @State private var isMOSSLocalAvailable = MOSSLocalModelManager.currentStatus().isAvailable

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
                isQwen3ASRAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
                isMOSSLocalAvailable = MOSSLocalModelManager.currentStatus().isAvailable
            }
            .navigationDestination(item: $selectedRecording) { item in
                RecordingDetailView(
                    item: item,
                    store: store,
                    transcriber: transcriber,
                    player: player,
                    downloadedLocalWhisperModels: downloadedLocalWhisperModels,
                    localWhisperLanguageOptionsByModelID: localWhisperLanguageOptionsByModelID,
                    isQwen3ASRAvailable: isQwen3ASRAvailable,
                    isMOSSLocalAvailable: isMOSSLocalAvailable
                )
            }
            .onInteractiveNavigationPopGesture(
                onBegan: {
                    interactiveNavigationPopHasPlayedHaptic = true
                    HapticFeedback.play(.navigation)
                },
                onCancelled: {
                    interactiveNavigationPopHasPlayedHaptic = false
                }
            )
            .onChange(of: selectedRecording?.id) { _, newValue in
                if newValue == nil {
                    if interactiveNavigationPopHasPlayedHaptic {
                        interactiveNavigationPopHasPlayedHaptic = false
                    } else {
                        HapticFeedback.play(.navigation)
                    }
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
        let divisor = Foundation.pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private struct RecordingTranscriptSearchMatch {
    let lineID: StoredTranscriptLine.ID
    let timeText: String
    let text: String
    let highlightedText: AttributedString

    init(lineID: StoredTranscriptLine.ID, timeText: String, text: String, query: String) {
        self.lineID = lineID
        self.timeText = timeText
        self.text = text
        highlightedText = Self.highlighted(text, query: query)
    }

    private static func highlighted(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else {
            return result
        }

        if applyHighlight(query, to: &result) {
            return result
        }

        for term in query.split(whereSeparator: \.isWhitespace).map(String.init) where !term.isEmpty {
            _ = applyHighlight(term, to: &result)
        }
        return result
    }

    @discardableResult
    private static func applyHighlight(_ term: String, to text: inout AttributedString) -> Bool {
        var searchStart = text.startIndex
        var foundMatch = false

        while searchStart < text.endIndex,
              let range = text[searchStart...].range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
              ) {
            text[range].backgroundColor = AppTheme.warning.opacity(0.30)
            text[range].foregroundColor = Color.primary
            text[range].font = .redditSans(.subheadline, weight: .bold)
            searchStart = range.upperBound
            foundMatch = true
        }

        return foundMatch
    }
}

private struct RecordingTranscriptSearchMatchView: View {
    let match: RecordingTranscriptSearchMatch

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(match.timeText)
                .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                .foregroundStyle(AppTheme.info)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(AppTheme.info.opacity(0.12), in: Capsule())

            Text(match.highlightedText)
                .font(.redditSans(.subheadline))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            AppTheme.info.opacity(0.055),
            in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                .stroke(AppTheme.info.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.timeText) \(match.text)")
    }
}

private struct RecordingRow: View {
    let item: RecordingItem
    let isAnalyzing: Bool
    let canGenerateIntelligence: Bool
    var searchMatch: RecordingTranscriptSearchMatch? = nil
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
            } else if let searchMatch {
                RecordingTranscriptSearchMatchView(match: searchMatch)
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
        .shadow(
            color: AppTheme.cardShadow,
            radius: AppTheme.cardShadowRadius,
            y: AppTheme.cardShadowYOffset
        )
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
                if let projectName = item.projectName {
                    RecordingMetadataChip(systemImage: "briefcase", text: projectName)
                }
                if let categoryName = item.categoryName {
                    let appearance = RecordingCategoryAppearanceCatalog.appearance(for: categoryName)
                    RecordingMetadataChip(
                        systemImage: appearance.iconName,
                        text: categoryName,
                        tint: appearance.color
                    )
                }
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
    let tint: Color?
    @ViewBuilder var content: Content

    init(systemImage: String, text: String, tint: Color? = nil) where Content == Text {
        self.systemImage = systemImage
        self.tint = tint
        content = Text(text)
    }

    init(systemImage: String, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? Color.secondary)
            content
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(tint ?? Color.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background((tint ?? Color.secondary).opacity(0.09), in: Capsule())
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

private struct MeetingAnalysisSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.redditSans(.caption, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MeetingAnalysisBulletRow: View {
    let title: String
    let metadata: String
    var actionTitle: String?
    var actionSystemImage: String?
    var isActionDisabled = false
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(AppTheme.brand)
                .frame(width: 5, height: 5)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.redditSans(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !metadata.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(metadata)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let action, let actionTitle, let actionSystemImage {
                Spacer(minLength: 8)

                Button(action: action) {
                    Image(systemName: actionSystemImage)
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .disabled(isActionDisabled)
                .accessibilityLabel(Text(actionTitle))
            }
        }
    }
}

private struct ReminderDraftRequest: Identifiable {
    let id = UUID()
    let drafts: [ReminderDraft]
}

private struct ReminderDraftReviewSheet: View {
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
        NavigationStack {
            List {
                Section {
                    ForEach($drafts) { $draft in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField(localized(L10n.Recordings.reminderTitle), text: $draft.title)
                                .font(.redditSans(.subheadline, weight: .semibold))
                                .textInputAutocapitalization(.sentences)

                            Toggle(isOn: $draft.hasDueDate) {
                                Label(localized(L10n.Recordings.reminderDueDate), systemImage: "calendar")
                                    .font(.redditSans(.caption, weight: .semibold))
                            }

                            if draft.hasDueDate {
                                DatePicker(
                                    localized(L10n.Recordings.reminderDueDate),
                                    selection: Binding(
                                        get: { draft.dueDate ?? Date() },
                                        set: { draft.dueDate = $0 }
                                    ),
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .labelsHidden()
                                .datePickerStyle(.compact)
                            }

                            TextEditor(text: $draft.notes)
                                .font(.redditSans(.caption))
                                .frame(minHeight: 72)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(AppTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete { offsets in
                        drafts.remove(atOffsets: offsets)
                    }
                } footer: {
                    Text(L10n.Recordings.reminderReviewFooter)
                }
            }
            .navigationTitle(localized(L10n.Recordings.reviewReminders))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
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
                    .disabled(isSaving || validDrafts.isEmpty)
                }
            }
        }
    }
}

struct RecordingDetailView: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @ObservedObject var player: RecordingPlaybackController
    var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]
    var isQwen3ASRAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
    var isMOSSLocalAvailable = MOSSLocalModelManager.currentStatus().isAvailable
    var initialTranscriptLineID: String? = nil
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var copied = false
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var isAnalyzing = false
    @State private var isAnalyzingMeeting = false
    @State private var isAnalyzingAudioEvents = false
    @State private var isAddingReminders = false
    @State private var reminderDraftRequest: ReminderDraftRequest?
    @State private var reminderBannerMessage: String?
    @State private var reminderBannerIsVisible = false
    @State private var reminderBannerTask: Task<Void, Never>?
    @State private var analysisErrorMessage: String?
    @State private var transcriptionErrorMessage: String?
    @State private var exportErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var audioFileInfo: RecordingAudioFileInfo?
    @State private var audioFileInfoError: String?
    @State private var isShowingAudioFileInfo = false
    @State private var isShowingAudioEventsSheet = false
    @StateObject private var editLocationProvider = RecordingEditLocationProvider()
    @State private var isShowingRecordingEditSheet = false
    @State private var editRecordingName = ""
    @State private var editRecordingLanguageID = ""
    @State private var editRecordingCategory = ""
    @State private var editRecordingKeyPoints = ""
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
    @State private var editedTranscriptLineSpeakerID: String?
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
    @State private var exportShareItem: ShareSheetItem?
    @State private var pendingSpeechLocaleReleaseAction: PendingSpeechLocaleReleaseAction?
    @State private var isShowingAppleSpeechRetranscriptionPicker = false
    @State private var isShowingLocalWhisperRetranscriptionPicker = false
    @State private var isShowingGeminiProcessingConfirmation = false
    @State private var isShowingGeminiRestoreConfirmation = false
    @State private var isShowingManualGeminiJSONImport = false
    @State private var manualGeminiJSONText = ""
    @State private var manualGeminiImportErrorMessage: String?
    @AppStorage(RecordingSummaryProvider.selectedDefaultsKey) private var selectedSummaryProviderRawValue = RecordingSummaryProvider.automatic.rawValue
    @State private var selectedDetailPage: RecordingDetailPage = .transcript
    @StateObject private var chatEngine = RecordingChatEngine()


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
            "\(currentItem.importStatus == nil)",
            currentItem.speakerDiarization.map {
                "\($0.schemaVersion)-\($0.segments.count)-\($0.generatedAt.timeIntervalSinceReferenceDate)"
            } ?? "no-speaker-diarization"
        ].joined(separator: "-")
    }

    private var transcriptSpeakerEditOptions: [TranscriptSpeakerEditOption] {
        TranscriptSpeakerPresentation.makePresentations(for: cachedTranscriptLines).map { speaker in
            TranscriptSpeakerEditOption(
                id: speaker.id,
                displayName: speaker.displayName,
                tint: speaker.tint
            )
        }
    }

    private var newTranscriptSpeakerEditOption: TranscriptSpeakerEditOption {
        let presentations = TranscriptSpeakerPresentation.makePresentations(for: cachedTranscriptLines)
        let comparisonKeys = Set(presentations.map { speaker in
            speaker.id.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        })
        var nextNumber = presentations
            .compactMap { TranscriptSpeakerNaming.numberedIndex($0.id) }
            .max()
            .map { $0 + 1 } ?? 0

        while comparisonKeys.contains(
            "Speaker \(nextNumber)".folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        ) {
            nextNumber += 1
        }

        return TranscriptSpeakerEditOption(
            id: "Speaker \(nextNumber)",
            displayName: localizedFormat(
                L10n.Recordings.transcriptSpeakerFormat,
                presentations.count + 1
            ),
            tint: TranscriptSpeakerPalette.tint(for: presentations.count)
        )
    }

    private var initialTranscriptScrollTarget: StoredTranscriptLine.ID? {
        guard let initialTranscriptLineID,
              cachedTranscriptLines.contains(where: { $0.id == initialTranscriptLineID }) else {
            return nil
        }
        return initialTranscriptLineID
    }

    private var initialTranscriptPlaybackTarget: StoredTranscriptLine? {
        guard player.isLoaded,
              player.currentItem?.id == currentItem.id,
              let initialTranscriptLineID else {
            return nil
        }
        return cachedTranscriptLines.first { $0.id == initialTranscriptLineID }
    }

    private var isTranscriptionRunning: Bool {
        currentItem.importStatus?.isFailed == false
    }

    private var pendingSpeechLocaleReleaseMessage: String {
        pendingSpeechLocaleReleaseAction?.request.messageText ?? ""
    }

    @ViewBuilder
    private var reminderAddedBanner: some View {
        if let reminderBannerMessage {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.success)

                Text(reminderBannerMessage)
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
            .offset(y: reminderBannerIsVisible ? 0 : -74)
            .opacity(reminderBannerIsVisible ? 1 : 0)
        }
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

            reminderAddedBanner
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .zIndex(20)
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
                    bottomLeadingRadius: AppTheme.navigationBarCornerRadius,
                    bottomTrailingRadius: AppTheme.navigationBarCornerRadius,
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
        .toolbar(.hidden, for: .tabBar)
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
        .onDisappear {
            hideReminderAddedBanner()
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
        .sheet(isPresented: $isShowingAudioEventsSheet) {
            NavigationStack {
                ScrollView {
                    audioEventsSheetContent
                        .padding()
                }
                .background(AppTheme.groupedBackground.ignoresSafeArea())
                .navigationTitle(localized(L10n.Recordings.audioEvents))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if currentItem.audioEventAnalysis != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(localized(L10n.Recordings.analyzeAudioEventsAgain)) {
                                analyzeCurrentAudioEvents()
                            }
                            .disabled(isAnalyzingAudioEvents)
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localized(L10n.Common.done)) {
                            isShowingAudioEventsSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingRecordingEditSheet) {
            RecordingEditSheet(
                item: currentItem,
                recordingName: $editRecordingName,
                languageID: $editRecordingLanguageID,
                categoryName: $editRecordingCategory,
                keyPoints: $editRecordingKeyPoints,
                tags: $editRecordingTags,
                summary: $editRecordingSummary,
                includesLocation: $editRecordingIncludesLocation,
                locationProvider: editLocationProvider,
                isSaving: isSavingRecordingEdit,
                languageOptions: TranscriptionLanguage.baseLanguageOptions(
                    from: appleSpeechTranscriptionLanguages,
                    including: editRecordingLanguageID
                ),
                availableCategories: RecordingCategoryCatalog.allNames(recordings: store.recordings),
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
        .sheet(item: $reminderDraftRequest) { request in
            ReminderDraftReviewSheet(
                initialDrafts: request.drafts,
                isSaving: isAddingReminders,
                onSave: saveReminderDrafts,
                onCancel: {
                    reminderDraftRequest = nil
                }
            )
            .interactiveDismissDisabled(isAddingReminders)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $transcriptLineEditRequest) { request in
            TranscriptLineEditSheet(
                timeText: request.timeText,
                text: $editedTranscriptLineText,
                selectedSpeakerID: $editedTranscriptLineSpeakerID,
                speakerOptions: transcriptSpeakerEditOptions,
                newSpeakerOption: newTranscriptSpeakerEditOption,
                showsSpeakerEditor: true,
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
        .sheet(isPresented: $isShowingManualGeminiJSONImport) {
            ManualGeminiJSONImportSheet(
                jsonText: $manualGeminiJSONText,
                errorMessage: manualGeminiImportErrorMessage,
                onPaste: pasteManualGeminiJSONFromClipboard,
                onImport: importManualGeminiJSON,
                onCancel: dismissManualGeminiJSONImport
            )
            .interactiveDismissDisabled(false)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $exportShareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
                .ignoresSafeArea()
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
            localized(L10n.Recordings.processWithGemini),
            isPresented: $isShowingGeminiProcessingConfirmation
        ) {
            Button(localized(L10n.Recordings.uploadAndProcess)) {
                processCurrentItemWithGemini()
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(L10n.Recordings.geminiProcessingConfirmation)
        }
        .alert(
            localized(L10n.Recordings.restoreBeforeGemini),
            isPresented: $isShowingGeminiRestoreConfirmation
        ) {
            Button(localized(L10n.Recordings.restoreTranscript)) {
                restoreCurrentTranscriptBeforeGemini()
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(L10n.Recordings.restoreBeforeGeminiConfirmation)
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
            localized(L10n.Recordings.exportFailed),
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        exportErrorMessage = nil
                    }
                }
            )
        ) {
            Button(localized(L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
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

                Menu {
                    Button {
                        exportCurrentTranscript(as: .txt)
                    } label: {
                        Label(localized(L10n.Recordings.exportTXT), systemImage: "doc.text")
                    }

                    Button {
                        exportCurrentTranscript(as: .markdown)
                    } label: {
                        Label(localized(L10n.Recordings.exportMarkdown), systemImage: "doc.richtext")
                    }

                    Button {
                        exportCurrentTranscript(as: .srt)
                    } label: {
                        Label(localized(L10n.Recordings.exportSRT), systemImage: "captions.bubble")
                    }

                    Button {
                        exportCurrentTranscript(as: .vtt)
                    } label: {
                        Label(localized(L10n.Recordings.exportVTT), systemImage: "captions.bubble.fill")
                    }

                    Button {
                        exportCurrentTranscript(as: .json)
                    } label: {
                        Label(localized(L10n.Recordings.exportJSON), systemImage: "curlybraces")
                    }
                } label: {
                    Label(localized(L10n.Recordings.exportTranscript), systemImage: "square.and.arrow.up.on.square")
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

            Menu {
                Button {
                    shareCurrentAudioWithGeminiApp()
                } label: {
                    Label(localized(L10n.Recordings.manualGeminiShareAndCopyPrompt), systemImage: "square.and.arrow.up")
                }
                .disabled(isTranscriptionRunning)

                Button {
                    prepareManualGeminiJSONImport()
                } label: {
                    Label(localized(L10n.Recordings.manualGeminiImportJSON), systemImage: "doc.on.clipboard")
                }
                .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)
            } label: {
                Label(localized(L10n.Recordings.manualGemini), systemImage: "sparkles")
            }

            if store.summaryProviderAvailability.isGeminiCloudAvailable {
                Button {
                    HapticFeedback.play(.menuSelection)
                    isShowingGeminiProcessingConfirmation = true
                } label: {
                    Label(localized(L10n.Recordings.processWithGemini), systemImage: "cloud")
                }
                .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)
            }

            if store.hasGeminiTranscriptBackup(for: currentItem) {
                Button {
                    HapticFeedback.play(.menuSelection)
                    isShowingGeminiRestoreConfirmation = true
                } label: {
                    Label(localized(L10n.Recordings.restoreBeforeGemini), systemImage: "arrow.uturn.backward")
                }
                .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)
            }

            LocalWhisperRetranscriptionButton(
                downloadedModels: downloadedLocalWhisperModels,
                isDisabled: currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing
            ) {
                isShowingLocalWhisperRetranscriptionPicker = true
            }

            Qwen3ASRRetranscriptionButton(
                isAvailable: isQwen3ASRAvailable,
                isDisabled: currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing
            ) {
                retranscribeCurrentItemWithQwen3ASR()
            }

            MOSSLocalRetranscriptionButton(
                isAvailable: isMOSSLocalAvailable,
                isDisabled: currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing
            ) {
                retranscribeCurrentItemWithMOSS()
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
        ScrollViewReader { scrollProxy in
            ZStack {
                AppTheme.groupedBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if currentItem.keyPoints != nil {
                            keyPointsCard
                        }
                        transcript
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom)
                }
                .safeAreaInset(edge: .bottom) {
                    playerCard(transcriptScrollProxy: scrollProxy)
                        .frame(maxWidth: 390)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                }
                .task(id: initialTranscriptScrollTarget) {
                    guard let lineID = initialTranscriptScrollTarget else {
                        return
                    }

                    await Task.yield()
                    scrollTranscript(to: lineID, using: scrollProxy)
                }
                .task(id: initialTranscriptPlaybackTarget) {
                    guard let line = initialTranscriptPlaybackTarget else {
                        return
                    }

                    scrubbedPlaybackTime = nil
                    player.seek(to: line.startSeconds)
                }
            }
        }
    }

    private func scrollTranscript(
        to lineID: StoredTranscriptLine.ID,
        using scrollProxy: ScrollViewProxy
    ) {
        guard !accessibilityReduceMotion else {
            scrollProxy.scrollTo(lineID, anchor: .center)
            return
        }

        withAnimation(.snappy(duration: 0.34, extraBounce: 0)) {
            scrollProxy.scrollTo(lineID, anchor: .center)
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
            if store.summaryProviderAvailability.hasAnyAvailableProvider || currentItem.meetingAnalysis != nil {
                meetingAnalysisCard
            }
        }
    }

    private var header: some View {
        let item = currentItem
        let iCloudSyncStatus = store.iCloudSyncStatus(for: item)
        let displayDuration = player.duration > 0
            ? player.duration
            : Double(item.durationSeconds)

        return VStack(alignment: .leading, spacing: 0) {
            RetroRecordingDisplay(
                statusText: localized(L10n.Recordings.recordingPlayback),
                title: item.audioFileName,
                audioURL: store.audioURL(for: item),
                player: player,
                scrubbedTime: scrubbedPlaybackTime,
                duration: displayDuration
            )

            VStack(alignment: .leading, spacing: 10) {
                RecordingDetailFactsGrid(
                    createdAtText: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                    durationText: TranscriptionLine.formatTimestamp(Double(item.durationSeconds)),
                    languageText: item.localizedLanguageName,
                    iCloudSyncStatus: iCloudSyncStatus
                )

                if !item.combinedTags.isEmpty
                    || item.projectName != nil
                    || item.categoryName != nil
                    || item.location != nil {
                    RecordingDetailContextStrip(
                        tags: item.combinedTags,
                        projectName: item.projectName,
                        categoryName: item.categoryName,
                        location: item.location
                    )
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyPointsCard: some View {
        guard let keyPoints = currentItem.keyPoints else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Label(localized(L10n.Recordings.keyPoints), systemImage: "list.bullet.clipboard")
                    .font(.redditSans(.headline, weight: .semibold))

                Text(keyPoints)
                    .font(.redditSans(.body))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            HapticFeedback.play(.copy)
                            UIPasteboard.general.string = keyPoints
                        } label: {
                            Label(localized(L10n.Common.copy), systemImage: "doc.on.doc")
                        }
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
        )
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

    private var meetingAnalysisCard: some View {
        let item = currentItem

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Label(localized(L10n.Recordings.meetingAnalysis), systemImage: "checklist")
                    .font(.redditSans(.headline))

                Spacer(minLength: 8)

                if store.summaryProviderAvailability.hasAnyAvailableProvider {
                    SummaryAnalysisMenu(
                        selectedProvider: selectedSummaryProvider,
                        providerAvailability: store.summaryProviderAvailability,
                        isDisabled: isAnalyzingMeeting,
                        primaryAction: {
                            analyzeCurrentMeeting(summaryProvider: selectedSummaryProvider)
                        }
                    ) { provider in
                        analyzeCurrentMeeting(summaryProvider: provider)
                    } label: {
                        HStack(spacing: 6) {
                            if isAnalyzingMeeting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(item.meetingAnalysis == nil ? localized(L10n.Recordings.analyzeMeeting) : localized(L10n.Recordings.analyzeMeetingAgain))
                                    .font(.redditSans(.caption, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if isAnalyzingMeeting {
                Label(localized(L10n.Recordings.analyzingMeeting), systemImage: "checklist")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
            } else if let analysis = item.meetingAnalysis {
                if let summary = meetingSummaryText(for: analysis) {
                    MeetingAnalysisSection(title: localized(L10n.Recordings.meetingSummary), systemImage: "text.bubble") {
                        MeetingAnalysisBulletRow(
                            title: summary,
                            metadata: ""
                        )
                    }
                }

                if !analysis.actionItems.isEmpty {
                    MeetingAnalysisSection(title: localized(L10n.Recordings.actionItems), systemImage: "checkmark.circle") {
                        ForEach(analysis.actionItems) { item in
                            MeetingAnalysisBulletRow(
                                title: item.task,
                                metadata: [item.owner, item.dueDate].compactMap(\.self).joined(separator: " · "),
                                actionTitle: localized(L10n.Recordings.addActionItemToReminders),
                                actionSystemImage: "plus.circle",
                                isActionDisabled: isAddingReminders
                            ) {
                                addActionItemsToReminders([item])
                            }
                        }

                    }
                }

                if !analysis.decisions.isEmpty {
                    MeetingAnalysisSection(title: localized(L10n.Recordings.decisions), systemImage: "checkmark.seal") {
                        ForEach(analysis.decisions) { decision in
                            MeetingAnalysisBulletRow(
                                title: decision.decision,
                                metadata: decision.rationale ?? ""
                            )
                        }
                    }
                }

                if !analysis.openQuestions.isEmpty {
                    MeetingAnalysisSection(title: localized(L10n.Recordings.openQuestions), systemImage: "questionmark.circle") {
                        ForEach(analysis.openQuestions) { question in
                            MeetingAnalysisBulletRow(
                                title: question.question,
                                metadata: question.owner ?? ""
                            )
                        }
                    }
                }

                Text(analysis.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button {
                            HapticFeedback.play(.copy)
                            UIPasteboard.general.string = meetingAnalysisPlainText(analysis)
                        } label: {
                            Label(localized(L10n.Common.copy), systemImage: "doc.on.doc")
                        }
                    }
            } else {
                EmptyStateView(icon: "checklist", titleResource: L10n.Recordings.noMeetingAnalysis)
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

    private func audioEventRow(_ event: RecordingAudioEvent) -> some View {
        Button {
            HapticFeedback.play(.timelineSeek)
            player.seek(to: event.startTime)
            scrubbedPlaybackTime = nil
            isShowingAudioEventsSheet = false
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.localizedLabel)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(localizedFormat(L10n.Recordings.audioEventConfidenceFormat, event.confidence * 100))
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                }

                Text(audioEventTimeRangeText(event))
                    .font(.redditSans(.caption, weight: .bold))
                    .foregroundStyle(AppTheme.info)
                    .lineLimit(1)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(AppTheme.info.opacity(0.12), in: Capsule())
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func audioEventTimeRangeText(_ event: RecordingAudioEvent) -> String {
        let start = TranscriptionLine.formatTimestamp(event.startTime)
        let end = TranscriptionLine.formatTimestamp(event.endTime)
        return "\(start)-\(end)"
    }

    private var audioEventsSheetContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isAnalyzingAudioEvents {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.Recordings.analyzingAudioEvents)
                        .font(.redditSans(.subheadline, weight: .semibold))
                }
                .foregroundStyle(AppTheme.info)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            } else if let analysis = currentItem.audioEventAnalysis, !analysis.events.isEmpty {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(analysis.events) { event in
                        audioEventRow(event)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))

                Text(analysis.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 12) {
                    EmptyStateView(icon: "waveform.badge.magnifyingglass", titleResource: L10n.Recordings.noAudioEvents)
                        .frame(maxWidth: .infinity)
                        .frame(height: 112)

                    Button {
                        analyzeCurrentAudioEvents()
                    } label: {
                        Label(localized(L10n.Recordings.analyzeAudioEvents), systemImage: "waveform.badge.magnifyingglass")
                            .font(.redditSans(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzingAudioEvents)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
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
                        RecordingAudioParameterRow(icon: "calendar", titleResource: L10n.Recordings.fileCreationDate, value: audioFileInfo.fileCreationDateText)
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

    private func playerCard(transcriptScrollProxy: ScrollViewProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        let timeLabelWidth: CGFloat = 56

        return VStack(spacing: 5) {
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 60.0,
                    paused: !player.isPlaying || scrubbedPlaybackTime != nil
                )
            ) { _ in
                let displayedTime = scrubbedPlaybackTime ?? player.presentationTime()

                HStack(alignment: .center, spacing: 8) {
                    Text(TranscriptionLine.formatTimestamp(displayedTime))
                        .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: timeLabelWidth, alignment: .leading)

                    RecordingTimelineScrubber(
                        currentTime: displayedTime,
                        duration: player.duration,
                        scrubbedTime: $scrubbedPlaybackTime,
                        audioEvents: currentItem.audioEventAnalysis?.events ?? [],
                        isEnabled: player.isLoaded,
                        onSeek: { time in
                            HapticFeedback.play(.timelineSeek)
                            player.seek(to: time)
                        },
                        onEventTap: { event in
                            HapticFeedback.play(.timelineSeek)
                            scrubbedPlaybackTime = nil
                            player.seek(to: event.startTime)
                        }
                    )
                    .frame(maxWidth: .infinity)

                    Text(TranscriptionLine.formatTimestamp(player.duration))
                        .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: timeLabelWidth, alignment: .trailing)
                }
            }

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
            .frame(maxWidth: .infinity)
            .frame(height: 58)

            HStack(spacing: 8) {
                audioEventsTimelineControl
                transcriptSyncControl(scrollProxy: transcriptScrollProxy)
                playbackSpeedMenu
            }

            if let errorText = player.errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .font(.redditSans(.caption))
                    .foregroundStyle(AppTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AppTheme.playbackGlassTint), in: shape)
    }

    private func transcriptSyncControl(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            syncTranscriptToPlayback(using: scrollProxy)
        } label: {
            PlaybackUtilityControlLabel(tint: AppTheme.info) {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!player.isLoaded || cachedTranscriptLines.isEmpty)
        .accessibilityLabel(Text(L10n.Recordings.syncCurrentTranscript))
    }

    private func syncTranscriptToPlayback(using scrollProxy: ScrollViewProxy) {
        let playbackTime = scrubbedPlaybackTime ?? player.presentationTime()
        let lineID = StoredTranscriptLine.currentLineID(
            in: cachedTranscriptLines,
            time: playbackTime
        ) ?? cachedTranscriptLines.first?.id

        guard let lineID else {
            HapticFeedback.play(.blocked)
            return
        }

        HapticFeedback.play(.navigation)
        guard !accessibilityReduceMotion else {
            scrollProxy.scrollTo(lineID, anchor: .center)
            return
        }

        withAnimation(.snappy(duration: 0.34, extraBounce: 0)) {
            scrollProxy.scrollTo(lineID, anchor: .center)
        }
    }

    private var audioEventsTimelineControl: some View {
        Button {
            if currentItem.audioEventAnalysis == nil {
                analyzeCurrentAudioEvents()
            } else {
                isShowingAudioEventsSheet = true
            }
        } label: {
            PlaybackUtilityControlLabel(tint: AppTheme.info) {
                HStack(spacing: 6) {
                    if isAnalyzingAudioEvents {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))

                        if let eventCount = currentItem.audioEventAnalysis?.events.count {
                            Text(eventCount.formatted(.number.notation(.compactName)))
                                .font(.redditSans(.caption2, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!player.isLoaded || isAnalyzingAudioEvents)
        .accessibilityLabel(Text(L10n.Recordings.audioEvents))
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
            PlaybackUtilityControlLabel(tint: AppTheme.info) {
                Text(RecordingPlaybackController.playbackRateLabel(player.playbackRate))
                    .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(!player.isLoaded)
    }

    private var transcript: some View {
        let item = currentItem
        let lines = cachedTranscriptLines
        let currentLineID = StoredTranscriptLine.currentLineID(in: lines, time: player.currentTime)
        let speakers = TranscriptSpeakerPresentation.makePresentations(for: lines)
        let speakerByID = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0) })
        let showsSpeakerDistinction = speakers.count > 1

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

            if showsSpeakerDistinction {
                TranscriptSpeakerLegend(speakers: speakers)
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
                            speaker: showsSpeakerDistinction ? line.speaker.flatMap { speakerByID[$0] } : nil,
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
                        .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func exportCurrentTranscript(as format: TranscriptExportFormat) {
        do {
            let url = try TranscriptExportService.export(
                item: currentItem,
                transcript: store.transcriptText(for: currentItem),
                format: format
            )
            exportShareItem = ShareSheetItem(url: url)
            HapticFeedback.play(.primaryAction)
        } catch {
            exportErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func shareCurrentAudioWithGeminiApp() {
        let prompt = GeminiCloudService.manualTranscriptionPrompt(
            languageName: currentItem.localizedLanguageName
        )
        UIPasteboard.general.string = prompt
        exportShareItem = ShareSheetItem(url: store.audioURL(for: currentItem))
        HapticFeedback.play(.primaryAction)
    }

    private func prepareManualGeminiJSONImport() {
        manualGeminiJSONText = ""
        manualGeminiImportErrorMessage = nil
        isShowingManualGeminiJSONImport = true
        HapticFeedback.play(.menuSelection)
    }

    private func pasteManualGeminiJSONFromClipboard() {
        guard let clipboardText = UIPasteboard.general.string,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            manualGeminiImportErrorMessage = localized(L10n.Recordings.manualGeminiClipboardEmpty)
            HapticFeedback.play(.blocked)
            return
        }

        manualGeminiJSONText = clipboardText
        manualGeminiImportErrorMessage = nil
        HapticFeedback.play(.copy)
    }

    private func importManualGeminiJSON() {
        do {
            _ = try store.importManualGeminiTranscriptionJSON(
                manualGeminiJSONText,
                for: currentItem
            )
            manualGeminiImportErrorMessage = nil
            manualGeminiJSONText = ""
            isShowingManualGeminiJSONImport = false
            HapticFeedback.play(.retranscribeComplete)
        } catch {
            manualGeminiImportErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func dismissManualGeminiJSONImport() {
        manualGeminiImportErrorMessage = nil
        manualGeminiJSONText = ""
        isShowingManualGeminiJSONImport = false
    }

    private func analyzeCurrentMeeting(summaryProvider: RecordingSummaryProvider) {
        guard store.summaryProviderAvailability.isAvailable(summaryProvider) else {
            HapticFeedback.play(.blocked)
            store.refreshIntelligenceAvailability()
            return
        }
        guard !isAnalyzingMeeting else {
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

        isAnalyzingMeeting = true
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                _ = try await store.analyzeMeeting(
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
            isAnalyzingMeeting = false
        }
    }

    private func analyzeCurrentAudioEvents() {
        guard !isAnalyzingAudioEvents else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        isAnalyzingAudioEvents = true
        HapticFeedback.play(.analysisStart)
        Task {
            do {
                _ = try await store.analyzeAudioEvents(for: item)
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isAnalyzingAudioEvents = false
        }
    }

    private func meetingAnalysisPlainText(_ analysis: RecordingMeetingAnalysis) -> String {
        var sections: [String] = []

        if let summary = meetingSummaryText(for: analysis) {
            sections.append("\(localized(L10n.Recordings.meetingSummary))\n- \(summary)")
        }

        if !analysis.actionItems.isEmpty {
            let lines = analysis.actionItems.map { item in
                let metadata = [item.owner, item.dueDate].compactMap(\.self).joined(separator: " · ")
                return metadata.isEmpty ? "- \(item.task)" : "- \(item.task) (\(metadata))"
            }
            sections.append("\(localized(L10n.Recordings.actionItems))\n\(lines.joined(separator: "\n"))")
        }

        if !analysis.decisions.isEmpty {
            let lines = analysis.decisions.map { item in
                if let rationale = item.rationale, !rationale.isEmpty {
                    return "- \(item.decision) - \(rationale)"
                }
                return "- \(item.decision)"
            }
            sections.append("\(localized(L10n.Recordings.decisions))\n\(lines.joined(separator: "\n"))")
        }

        if !analysis.openQuestions.isEmpty {
            let lines = analysis.openQuestions.map { item in
                if let owner = item.owner, !owner.isEmpty {
                    return "- \(item.question) (\(owner))"
                }
                return "- \(item.question)"
            }
            sections.append("\(localized(L10n.Recordings.openQuestions))\n\(lines.joined(separator: "\n"))")
        }

        return sections.joined(separator: "\n\n")
    }

    private func meetingSummaryText(for analysis: RecordingMeetingAnalysis) -> String? {
        if let summary = analysis.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }

        return meetingSummaryFromMarkdown(analysis.markdownNotes)
    }

    private func meetingSummaryFromMarkdown(_ markdown: String) -> String? {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var isInsideSummary = false
        var summaryLines: [String] = []
        let summaryHeadings: Set<String> = ["summary", "meeting summary", "摘要", "会议摘要", "會議摘要"]
        let sectionHeadings = summaryHeadings.union([
            "action items",
            "actions",
            "todo",
            "todos",
            "decisions",
            "open questions",
            "questions",
            "待办事项",
            "待辦事項",
            "行动项",
            "行動項",
            "决策点",
            "決策點",
            "待确认问题",
            "待確認問題"
        ])

        for line in lines {
            let normalizedLine = line
                .trimmingCharacters(in: CharacterSet(charactersIn: "#*-•:： "))
                .localizedLowercase
            let isKnownHeading = sectionHeadings.contains(normalizedLine)
            let isHeading = isKnownHeading
                || line.hasPrefix("#")
                || line.hasSuffix(":")
                || line.hasSuffix("：")

            if isHeading, summaryHeadings.contains(normalizedLine) {
                isInsideSummary = true
                continue
            }

            if isInsideSummary, isHeading {
                break
            }

            if isInsideSummary {
                let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
                if !cleaned.isEmpty {
                    summaryLines.append(cleaned)
                }
            }
        }

        let summary = summaryLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    private func addActionItemsToReminders(_ actionItems: [RecordingActionItem]) {
        guard !isAddingReminders else {
            HapticFeedback.play(.blocked)
            return
        }

        let drafts = actionItems
            .filter { !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ReminderDraft(actionItem: $0, recordingTitle: currentItem.audioFileName) }
        guard !drafts.isEmpty else {
            analysisErrorMessage = localized(L10n.Recordings.reminderNoActionItems)
            HapticFeedback.play(.blocked)
            return
        }

        reminderDraftRequest = ReminderDraftRequest(drafts: drafts)
        HapticFeedback.play(.menuSelection)
    }

    private func saveReminderDrafts(_ drafts: [ReminderDraft]) {
        guard !isAddingReminders else {
            HapticFeedback.play(.blocked)
            return
        }
        guard !drafts.isEmpty else {
            analysisErrorMessage = localized(L10n.Recordings.reminderNoActionItems)
            HapticFeedback.play(.blocked)
            return
        }

        isAddingReminders = true
        HapticFeedback.play(.primaryAction)

        Task {
            do {
                let count = try await ReminderExportService.addDrafts(drafts)
                showReminderAddedBanner(localizedFormat(L10n.Recordings.addedRemindersFormat, count))
                reminderDraftRequest = nil
                HapticFeedback.play(.analysisComplete)
            } catch {
                analysisErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isAddingReminders = false
        }
    }

    private func showReminderAddedBanner(_ message: String) {
        reminderBannerTask?.cancel()
        reminderBannerMessage = message
        reminderBannerIsVisible = false

        withAnimation(.snappy(duration: 0.24, extraBounce: 0.03)) {
            reminderBannerIsVisible = true
        }

        reminderBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            withAnimation(.easeInOut(duration: 0.22)) {
                reminderBannerIsVisible = false
            }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else {
                return
            }
            reminderBannerMessage = nil
            reminderBannerTask = nil
        }
    }

    private func hideReminderAddedBanner() {
        reminderBannerTask?.cancel()
        reminderBannerTask = nil
        withAnimation(.easeInOut(duration: 0.18)) {
            reminderBannerIsVisible = false
        }
        reminderBannerMessage = nil
    }

    private func translatedTranscriptAnalysisInput() -> (transcript: String, languageName: String)? {
        guard let selectedTranslationLanguage else {
            return nil
        }

        var translatedLines: [String] = []
        for line in cachedTranscriptLines {
            guard !line.spokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            guard let translatedText = translatedTranscriptByLineID[line.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !translatedText.isEmpty else {
                return nil
            }
            if let speaker = line.speaker {
                translatedLines.append("\(speaker): \(translatedText)")
            } else {
                translatedLines.append(translatedText)
            }
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

    private func processCurrentItemWithGemini() {
        guard !isTranscriptionRunning,
              !transcriber.isRecording,
              !transcriber.isPreparing else {
            HapticFeedback.play(.blocked)
            return
        }

        let item = currentItem
        HapticFeedback.play(.retranscribeStart)
        Task {
            do {
                try await store.processWithGeminiCloud(item)
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func restoreCurrentTranscriptBeforeGemini() {
        do {
            _ = try store.restoreTranscriptBeforeGemini(for: currentItem)
            HapticFeedback.play(.menuSelection)
        } catch {
            transcriptionErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
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

    private func retranscribeCurrentItemWithQwen3ASR() {
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
                try await store.retranscribeWithQwen3ASR(
                    item,
                    language: TranscriptionLanguage(id: item.languageID)
                )
                HapticFeedback.play(.retranscribeComplete)
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func retranscribeCurrentItemWithMOSS() {
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
                try await store.retranscribeWithMOSS(item)
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
        let speakerDiarization = item.speakerDiarization
        let lines = await Task.detached(priority: .utility) {
            let text = (try? String(contentsOf: transcriptURL, encoding: .utf8)) ?? ""
            return StoredTranscriptLine.parse(text, speakerDiarization: speakerDiarization)
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
        editedTranscriptLineText = line.spokenText
        editedTranscriptLineSpeakerID = line.speaker
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
                text: editedTranscriptLineText,
                speaker: editedTranscriptLineSpeakerID
            )
            cachedTranscriptLines = StoredTranscriptLine.parse(
                store.transcriptText(for: updatedItem),
                speakerDiarization: updatedItem.speakerDiarization
            )
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
        editRecordingLanguageID = TranscriptionLanguage(id: item.languageID).baseLanguage.id
        editRecordingCategory = item.categoryName ?? ""
        editRecordingKeyPoints = item.keyPoints ?? ""
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
                projectName: currentItem.projectName,
                categoryName: editRecordingCategory,
                keyPoints: editRecordingKeyPoints,
                location: location,
                language: TranscriptionLanguage(id: editRecordingLanguageID).baseLanguage
            )
            RecordingCategoryCatalog.register(editRecordingCategory)
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
                projectName: currentItem.projectName,
                categoryName: currentItem.categoryName,
                keyPoints: currentItem.keyPoints,
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
    @Binding var languageID: String
    @Binding var categoryName: String
    @Binding var keyPoints: String
    @Binding var tags: [String]
    @Binding var summary: String
    @Binding var includesLocation: Bool
    @ObservedObject var locationProvider: RecordingEditLocationProvider
    let isSaving: Bool
    var languageOptions: [TranscriptionLanguage] = []
    var availableCategories: [String] = []
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
                    languageSection
                    categorySection
                    keyPointsSection
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

    private var categorySection: some View {
        let appearance = categoryName.isEmpty
            ? nil
            : RecordingCategoryAppearanceCatalog.appearance(for: categoryName)

        return VStack(alignment: .leading, spacing: 8) {
            Label(localized(L10n.Recordings.categoryName), systemImage: "folder")
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
                    Image(systemName: appearance?.iconName ?? "tray")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            appearance.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary)
                        )

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
        .recordingEditSectionSurface()
    }

    private var languageSection: some View {
        let selectedLanguage = languageOptions.first(where: { $0.id == languageID })
            ?? TranscriptionLanguage(id: languageID).baseLanguage

        return VStack(alignment: .leading, spacing: 8) {
            Label(localized(L10n.Settings.transcriptionLanguage), systemImage: "globe")
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)

            Menu {
                ForEach(languageOptions) { language in
                    Button {
                        languageID = language.id
                        HapticFeedback.play(.menuSelection)
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == languageID ? "checkmark" : "globe"
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.info)

                    Text(selectedLanguage.displayName)
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
                .background(
                    AppTheme.elevatedBackground,
                    in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSaving || languageOptions.isEmpty)
        }
        .recordingEditSectionSurface()
    }

    private var keyPointsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized(L10n.Recordings.keyPoints), systemImage: "list.bullet.clipboard")
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
    var fileCreationDate: Date?
    var fileSize: Int64?

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.fileFormat
        let processingFormat = file.processingFormat
        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])

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
        self.fileCreationDate = resourceValues?.creationDate
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

    var fileCreationDateText: String {
        guard let fileCreationDate else {
            return localized(L10n.Common.unknown)
        }
        return fileCreationDate.formatted(date: .abbreviated, time: .standard)
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

private struct RecordingTimelineScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var scrubbedTime: TimeInterval?
    let audioEvents: [RecordingAudioEvent]
    let isEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onEventTap: (RecordingAudioEvent) -> Void

    @State private var isScrubbing = false

    private var displayedTime: TimeInterval {
        min(max(scrubbedTime ?? currentTime, 0), effectiveDuration)
    }

    private var effectiveDuration: TimeInterval {
        max(duration, 1)
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
                        .shadow(color: AppTheme.brand.opacity(isScrubbing ? 0.24 : 0.14), radius: isScrubbing ? 8 : 4, y: isScrubbing ? 4 : 2)
                        .offset(x: thumbX - thumbSize / 2, y: trackCenterY - thumbSize / 2)
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
        .accessibilityLabel(Text(L10n.Recordings.audioEvents))
        .accessibilityValue(Text(TranscriptionLine.formatTimestamp(displayedTime)))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else {
                return
            }
            let step: TimeInterval = 5
            switch direction {
            case .increment:
                onSeek(min(displayedTime + step, duration))
            case .decrement:
                onSeek(max(displayedTime - step, 0))
            @unknown default:
                break
            }
        }
    }

    private func audioEventCallout(_ event: RecordingAudioEvent, thumbX: CGFloat, trackWidth: CGFloat) -> some View {
        let width = min(trackWidth, 178)
        let x = min(max(thumbX - width / 2, 0), max(trackWidth - width, 0))

        return HStack(spacing: 6) {
            Text(event.localizedLabel)
                .font(.redditSans(.caption2, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(audioEventTimeRangeText(event))
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
        .offset(x: x, y: 0)
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
                let time = time(for: value.location.x, trackWidth: trackWidth)
                let tapDistance = hypot(value.translation.width, value.translation.height)
                scrubbedTime = nil
                withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                    isScrubbing = false
                }
                if tapDistance < 4, let event = activeAudioEvent(at: time) {
                    onEventTap(event)
                    return
                }
                onSeek(time)
            }
    }

    private func activeAudioEvent(at time: TimeInterval) -> RecordingAudioEvent? {
        var closestEvent: RecordingAudioEvent?
        var closestDistance = TimeInterval.infinity

        for event in audioEvents where time >= event.startTime - 0.45 && time <= event.endTime + 0.45 {
            let eventDistance = distance(from: time, to: event)
            if eventDistance < closestDistance
                || (eventDistance == closestDistance && event.confidence > (closestEvent?.confidence ?? 0)) {
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
        let markerX = min(max(CGFloat(event.startTime / effectiveDuration) * trackWidth, 0), trackWidth)
        let rawWidth = CGFloat(max(event.duration, 0.1) / effectiveDuration) * trackWidth
        let remainingWidth = max(trackWidth - markerX, 3)
        let markerWidth = min(max(rawWidth, 4), remainingWidth)
        return CGRect(x: markerX, y: 0, width: markerWidth, height: markerHeight)
    }

    private func markerOpacity(for event: RecordingAudioEvent) -> Double {
        min(max(0.28 + event.confidence * 0.58, 0.34), 0.88)
    }

    private func audioEventTimeRangeText(_ event: RecordingAudioEvent) -> String {
        let start = TranscriptionLine.formatTimestamp(event.startTime)
        let end = TranscriptionLine.formatTimestamp(event.endTime)
        return "\(start)-\(end)"
    }
}

private struct PlaybackUtilityControlLabel<Content: View>: View {
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

private struct PlaybackUtilityButtonStyle: ButtonStyle {
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
    let speaker: String?
    let spokenText: String

    static func parse(
        _ transcript: String,
        speakerDiarization: RecordingSpeakerDiarization? = nil
    ) -> [StoredTranscriptLine] {
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
                    text: text,
                    speaker: nil,
                    spokenText: text
                )
            }

        let sortedLines = lines.sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.id < $1.id
            }
            return $0.startSeconds < $1.startSeconds
        }

        return applyingSpeakerMetadata(to: sortedLines, speakerDiarization: speakerDiarization)
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

    private static func applyingSpeakerMetadata(
        to lines: [StoredTranscriptLine],
        speakerDiarization: RecordingSpeakerDiarization?
    ) -> [StoredTranscriptLine] {
        let segments = (speakerDiarization?.segments ?? []).sorted {
            if $0.startSeconds == $1.startSeconds {
                return $0.endSeconds < $1.endSeconds
            }
            return $0.startSeconds < $1.startSeconds
        }
        var nextSegmentIndex = 0

        return lines.enumerated().map { offset, line in
            let matchedSegment: RecordingSpeakerSegment?
            if segments.count == lines.count {
                matchedSegment = segments[offset]
            } else if segments.indices.contains(nextSegmentIndex) {
                while segments.indices.contains(nextSegmentIndex + 1),
                      abs(segments[nextSegmentIndex + 1].startSeconds - line.startSeconds)
                        < abs(segments[nextSegmentIndex].startSeconds - line.startSeconds) {
                    nextSegmentIndex += 1
                }

                if abs(segments[nextSegmentIndex].startSeconds - line.startSeconds) <= 0.75 {
                    matchedSegment = segments[nextSegmentIndex]
                    nextSegmentIndex += 1
                } else {
                    matchedSegment = nil
                }
            } else {
                matchedSegment = nil
            }

            let expectedSpeaker = TranscriptSpeakerNaming.normalizedID(matchedSegment?.speaker)
            let parsedContent = speakerContent(from: line.text, expectedSpeaker: expectedSpeaker)
            let speaker = expectedSpeaker ?? parsedContent.speaker
            let spokenText = parsedContent.spokenText.trimmingCharacters(in: .whitespacesAndNewlines)

            return StoredTranscriptLine(
                id: line.id,
                startSeconds: line.startSeconds,
                timeText: line.timeText,
                text: line.text,
                speaker: speaker,
                spokenText: spokenText.isEmpty ? line.text : spokenText
            )
        }
    }

    private static func speakerContent(
        from text: String,
        expectedSpeaker: String?
    ) -> (speaker: String?, spokenText: String) {
        if let expectedSpeaker {
            for separator in [":", "："] {
                let prefix = expectedSpeaker + separator
                if let range = text.range(of: prefix, options: [.anchored, .caseInsensitive]) {
                    return (
                        expectedSpeaker,
                        String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
            return (expectedSpeaker, text)
        }

        guard let separatorIndex = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return (nil, text)
        }
        let candidate = String(text[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard TranscriptSpeakerNaming.numberedIndex(candidate) != nil else {
            return (nil, text)
        }

        return (
            candidate,
            String(text[text.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

private enum TranscriptSpeakerNaming {
    static func normalizedID(_ speaker: String?) -> String? {
        guard let speaker else {
            return nil
        }
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func numberedIndex(_ speaker: String) -> Int? {
        let parts = speaker.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              parts[0].caseInsensitiveCompare("Speaker") == .orderedSame,
              let index = Int(parts[1]),
              index >= 0 else {
            return nil
        }
        return index
    }

    static func displayName(for speaker: String, presentationIndex: Int) -> String {
        guard numberedIndex(speaker) != nil else {
            return speaker
        }
        return localizedFormat(L10n.Recordings.transcriptSpeakerFormat, presentationIndex + 1)
    }
}

private struct TranscriptSpeakerPresentation: Identifiable {
    let id: String
    let displayName: String
    let paletteIndex: Int

    var tint: Color {
        TranscriptSpeakerPalette.tint(for: paletteIndex)
    }

    static func makePresentations(for lines: [StoredTranscriptLine]) -> [TranscriptSpeakerPresentation] {
        var seen = Set<String>()
        var speakers: [TranscriptSpeakerPresentation] = []

        for speaker in lines.compactMap(\.speaker) {
            let comparisonKey = speaker.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            guard seen.insert(comparisonKey).inserted else {
                continue
            }

            speakers.append(
                TranscriptSpeakerPresentation(
                    id: speaker,
                    displayName: TranscriptSpeakerNaming.displayName(
                        for: speaker,
                        presentationIndex: speakers.count
                    ),
                    paletteIndex: speakers.count
                )
            )
        }
        return speakers
    }
}

private enum TranscriptSpeakerPalette {
    private static let colors: [Color] = [
        AppTheme.info,
        AppTheme.purple,
        AppTheme.success,
        AppTheme.brand,
        Color.teal,
        Color.pink,
        AppTheme.warning,
        Color.indigo
    ]

    static func tint(for index: Int) -> Color {
        colors[index % colors.count]
    }
}

private struct TranscriptSpeakerLegend: View {
    let speakers: [TranscriptSpeakerPresentation]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label(
                    localizedFormat(L10n.Recordings.transcriptSpeakersDetectedFormat, speakers.count),
                    systemImage: "person.2.fill"
                )
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

                        Text(speaker.displayName)
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(.primary)
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

private struct StoredTranscriptLineRow: View {
    let line: StoredTranscriptLine
    let speaker: TranscriptSpeakerPresentation?
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

                            Text(speaker.displayName)
                                .font(.redditSans(.caption2, weight: .bold))
                                .foregroundStyle(speaker.tint)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(speaker.tint.opacity(0.10), in: Capsule())
                        .accessibilityHidden(true)
                    }

                    Text(translatedText ?? line.spokenText)
                        .font(.redditSans(.body))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if translatedText != nil {
                        Text(line.spokenText)
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
            .padding(.vertical, speaker == nil ? 4 : 7)
            .padding(.leading, speaker == nil ? 6 : 10)
            .padding(.trailing, 6)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
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

    private var rowBackground: Color {
        if isCurrent {
            return AppTheme.brand.opacity(0.08)
        }
        return speaker?.tint.opacity(0.055) ?? .clear
    }

    private var accessibilityText: String {
        let speakerText = speaker.map { "\($0.displayName) " } ?? ""
        if let translatedText {
            return "\(speakerText)\(line.timeText) \(translatedText) \(line.spokenText)"
        }
        return "\(speakerText)\(line.timeText) \(line.spokenText)"
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

    private let audioSessionOwner = UUID()
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
                guard commandID == playbackCommandID, isLoaded else {
                    return
                }
                try await configurePlaybackSession()
                guard commandID == playbackCommandID, isLoaded else {
                    await deactivatePlaybackSession()
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

    func presentationTime() -> TimeInterval {
        min(max(currentPlaybackTime(), 0), duration)
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
        try await AppAudioSessionCoordinator.shared.activatePlayback(owner: audioSessionOwner)
    }

    private func deactivatePlaybackSession() async {
        await AppAudioSessionCoordinator.shared.deactivatePlayback(owner: audioSessionOwner)
    }

    private func configureRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.skipForwardCommand.preferredIntervals = [5]
        commandCenter.skipBackwardCommand.preferredIntervals = [5]
        commandCenter.changePlaybackRateCommand.supportedPlaybackRates = Self.availablePlaybackRates.map { NSNumber(value: $0) }

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
            }),
            RemoteCommandTarget(command: commandCenter.changePlaybackRateCommand, token: commandCenter.changePlaybackRateCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackRateCommandEvent else {
                    return .commandFailed
                }
                Task { @MainActor in
                    self?.setPlaybackRate(event.playbackRate)
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
        commandCenter.changePlaybackRateCommand.isEnabled = isEnabled
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
        Self.logger.debug(
            "[RecordingPlayback] NowPlaying updated title=\(self.nowPlayingTitle, privacy: .public) elapsed=\(elapsedTime, privacy: .public) duration=\(self.duration, privacy: .public) rate=\(self.playbackRate, privacy: .public) playing=\(self.isPlaying, privacy: .public)"
        )
    }

    private func clearNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
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

private struct RetroRecordingDisplay: View {
    @State private var waveformSamples: [CGFloat] = []

    let statusText: String
    let title: String
    let audioURL: URL
    @ObservedObject var player: RecordingPlaybackController
    let scrubbedTime: TimeInterval?
    let duration: TimeInterval

    private let displayRed = Color(red: 0.94, green: 0.08, blue: 0.13)

    private func playbackProgress(for currentTime: TimeInterval) -> CGFloat {
        guard duration > 0 else {
            return 0
        }
        return CGFloat(min(max(currentTime / duration, 0), 1))
    }

    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.020, blue: 0.022)

            RetroDotMatrixGrid()
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    RetroPlaybackStatusMark(color: displayRed, isActive: player.isPlaying)
                        .accessibilityHidden(true)

                    Text(statusText)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.56))

                    Spacer(minLength: 8)

                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .minimumScaleFactor(0.72)

                TimelineView(
                    .animation(
                        minimumInterval: 1.0 / 60.0,
                        paused: !player.isPlaying || scrubbedTime != nil
                    )
                ) { _ in
                    let currentTime = min(
                        max(scrubbedTime ?? player.presentationTime(), 0),
                        duration
                    )

                    VStack(spacing: 8) {
                        RetroPixelWaveform(
                            samples: waveformSamples,
                            progress: playbackProgress(for: currentTime),
                            playheadColor: displayRed,
                            isActive: player.isPlaying
                        )
                        .frame(height: 106)
                        .accessibilityHidden(true)

                        RetroDotMatrixTime(
                            text: Self.displayTimestamp(currentTime),
                            accessibilityText: "\(TranscriptionLine.formatTimestamp(currentTime)) / \(TranscriptionLine.formatTimestamp(duration))"
                        )
                        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 52)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .frame(height: 226)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(Color.black.opacity(0.88), lineWidth: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                .padding(3)
        }
        .task(id: audioURL) {
            waveformSamples = []
            let samples = await RecordingDisplayWaveformSampler.samples(
                from: audioURL,
                sampleCount: 96
            )
            guard !Task.isCancelled else {
                return
            }
            waveformSamples = samples
        }
    }

    private static func displayTimestamp(_ time: TimeInterval) -> String {
        let safeSeconds = max(Int(time.rounded(.down)), 0)
        let hours = safeSeconds / 3_600
        let minutes = (safeSeconds % 3_600) / 60
        let seconds = safeSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private enum RetroDisplayMetrics {
    static let gridPitch: CGFloat = 4.6
    static let backgroundDotSize: CGFloat = 2.15
    static let activeDotSize: CGFloat = 2.7
}

private struct RetroDotMatrixGrid: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let pitch = RetroDisplayMetrics.gridPitch
            let dotSize = RetroDisplayMetrics.backgroundDotSize
            var y: CGFloat = 1.4

            while y < size.height {
                var x: CGFloat = 1.4
                while x < size.width {
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: dotSize,
                        height: dotSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 0.45),
                        with: .color(Color.white.opacity(0.065))
                    )
                    x += pitch
                }
                y += pitch
            }
        }
    }
}

private struct RetroPlaybackStatusMark: View {
    let color: Color
    let isActive: Bool

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, _ in
            let squareSize: CGFloat = 3.8
            let gap: CGFloat = 1.5

            for row in 0..<2 {
                for column in 0..<2 {
                    let rect = CGRect(
                        x: CGFloat(column) * (squareSize + gap),
                        y: CGFloat(row) * (squareSize + gap),
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 0.55),
                        with: .color(color.opacity(isActive ? 1 : 0.52))
                    )
                }
            }
        }
        .frame(width: 9.1, height: 9.1)
    }
}

private struct RetroDotMatrixTime: View {
    let text: String
    let accessibilityText: String

    private static let glyphRows: [Character: [String]] = [
        "0": ["0111110", "1100011", "1000001", "1000001", "1000001", "1000001", "1000001", "1000001", "1000001", "1100011", "0111110"],
        "1": ["0011000", "0111000", "1011000", "0011000", "0011000", "0011000", "0011000", "0011000", "0011000", "0011000", "1111111"],
        "2": ["0111110", "1100011", "0000001", "0000001", "0000010", "0001100", "0110000", "1000000", "1000000", "1000000", "1111111"],
        "3": ["1111110", "0000011", "0000001", "0000001", "0000010", "0011110", "0000010", "0000001", "0000001", "1100011", "0111110"],
        "4": ["0000110", "0001110", "0010110", "0100110", "1000110", "1000110", "1111111", "0000110", "0000110", "0000110", "0000110"],
        "5": ["1111111", "1000000", "1000000", "1000000", "1111110", "0000011", "0000001", "0000001", "0000001", "1100011", "0111110"],
        "6": ["0011110", "0110000", "1100000", "1000000", "1111110", "1100011", "1000001", "1000001", "1000001", "1100011", "0111110"],
        "7": ["1111111", "0000011", "0000010", "0000100", "0001000", "0010000", "0010000", "0100000", "0100000", "1000000", "1000000"],
        "8": ["0111110", "1100011", "1000001", "1000001", "1100011", "0111110", "1100011", "1000001", "1000001", "1100011", "0111110"],
        "9": ["0111110", "1100011", "1000001", "1000001", "1100011", "0111111", "0000001", "0000001", "0000011", "0000110", "0111100"],
        ":": ["00", "00", "11", "11", "00", "00", "00", "11", "11", "00", "00"]
    ]

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let glyphs = text.compactMap { Self.glyphRows[$0] }
            guard !glyphs.isEmpty else {
                return
            }

            let glyphWidths = glyphs.map { $0.first?.count ?? 0 }
            let totalColumns = glyphWidths.reduce(0, +) + max(glyphs.count - 1, 0)
            let rowCount = glyphs.map(\.count).max() ?? 0
            guard totalColumns > 0, rowCount > 0 else {
                return
            }

            let horizontalPitch = max((size.width - 4) / CGFloat(totalColumns), 1)
            let verticalPitch = max((size.height - 2) / CGFloat(rowCount), 1)
            let pitch = min(horizontalPitch, verticalPitch)
            let dotSize = max(pitch * 0.66, 1.35)
            let contentWidth = CGFloat(totalColumns - 1) * pitch + dotSize
            let contentHeight = CGFloat(rowCount - 1) * pitch + dotSize
            let originX = (size.width - contentWidth) / 2
            let originY = (size.height - contentHeight) / 2
            var glyphColumn = 0

            for (glyphIndex, rows) in glyphs.enumerated() {
                let width = glyphWidths[glyphIndex]

                for (row, pattern) in rows.enumerated() {
                    for (column, value) in pattern.enumerated() where value == "1" {
                        let rect = CGRect(
                            x: originX + CGFloat(glyphColumn + column) * pitch,
                            y: originY + CGFloat(row) * pitch,
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: dotSize * 0.12),
                            with: .color(Color.white.opacity(0.96))
                        )
                    }
                }

                glyphColumn += width + 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }
}

private enum RecordingDisplayWaveformSampler {
    private static let maximumFramesPerSample: AVAudioFrameCount = 8_192

    static func samples(from url: URL, sampleCount: Int) async -> [CGFloat] {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }

            do {
                return try loadSamples(from: url, sampleCount: sampleCount)
            } catch {
                return []
            }
        }.value
    }

    private static func loadSamples(from url: URL, sampleCount: Int) throws -> [CGFloat] {
        let resolvedSampleCount = max(sampleCount, 1)
        let audioFile = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        let fileLength = audioFile.length

        guard fileLength > 0,
              format.channelCount > 0 else {
            return []
        }

        var levels = [Double](repeating: 0, count: resolvedSampleCount)

        for index in 0..<resolvedSampleCount {
            if Task.isCancelled {
                return []
            }

            let bucketStart = fileLength * AVAudioFramePosition(index) / AVAudioFramePosition(resolvedSampleCount)
            let bucketEnd = fileLength * AVAudioFramePosition(index + 1) / AVAudioFramePosition(resolvedSampleCount)
            let bucketLength = max(bucketEnd - bucketStart, 1)
            let framesToRead = AVAudioFrameCount(
                min(bucketLength, AVAudioFramePosition(maximumFramesPerSample))
            )
            let centeredStart = bucketStart + max(
                (bucketLength - AVAudioFramePosition(framesToRead)) / 2,
                0
            )

            audioFile.framePosition = min(centeredStart, max(fileLength - 1, 0))

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesToRead
            ) else {
                continue
            }

            try audioFile.read(into: buffer, frameCount: framesToRead)

            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                continue
            }

            let channelCount = Int(format.channelCount)
            let frameCount = Int(buffer.frameLength)
            var sumOfSquares = 0.0
            var peak = 0.0
            var valueCount = 0

            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let value = Double(samples[frame])
                    guard value.isFinite else {
                        continue
                    }
                    let magnitude = abs(value)
                    sumOfSquares += value * value
                    peak = max(peak, magnitude)
                    valueCount += 1
                }
            }

            guard valueCount > 0 else {
                continue
            }

            let rms = sqrt(sumOfSquares / Double(valueCount))
            levels[index] = rms * 0.82 + peak * 0.18
        }

        let audibleLevels = levels.filter { $0 > 0 }.sorted()
        guard !audibleLevels.isEmpty else {
            return [CGFloat](repeating: 0, count: resolvedSampleCount)
        }

        let percentileIndex = min(
            Int((Double(audibleLevels.count - 1) * 0.92).rounded(.down)),
            audibleLevels.count - 1
        )
        let referenceLevel = max(audibleLevels[percentileIndex], 0.000_001)

        return levels.map { level in
            guard level > 0 else {
                return 0
            }
            let normalized = min(level / referenceLevel, 1)
            return CGFloat(pow(normalized, 0.55))
        }
    }
}

private struct RetroPixelWaveform: View {
    let samples: [CGFloat]
    let progress: CGFloat
    let playheadColor: Color
    let isActive: Bool

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let centerY = size.height / 2
            let pitch = RetroDisplayMetrics.gridPitch
            let pixelSize = RetroDisplayMetrics.activeDotSize
            let maximumHalfRows = max(Int((size.height / 2 - pitch) / pitch), 1)
            let drawableWidth = max(size.width - pixelSize, 0)
            let columnCount = max(Int((drawableWidth / pitch).rounded(.down)) + 1, 2)
            let columnPitch = drawableWidth / CGFloat(columnCount - 1)
            let rawPlayheadX = min(max(progress, 0), 1) * size.width
            let lineX = min(
                max(rawPlayheadX, pixelSize / 2),
                max(size.width - pixelSize / 2, pixelSize / 2)
            )

            for index in 0..<columnCount {
                let x = pixelSize / 2 + CGFloat(index) * columnPitch
                let sample = interpolatedSample(at: index, columnCount: columnCount)
                let halfRows = max(
                    Int((min(max(sample, 0), 1) * CGFloat(maximumHalfRows)).rounded()),
                    0
                )
                let waveformOpacity = x <= rawPlayheadX ? 0.94 : 0.34

                for row in -halfRows...halfRows {
                    let y = centerY + CGFloat(row) * pitch
                    let rect = CGRect(
                        x: x - pixelSize / 2,
                        y: y - pixelSize / 2,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: pixelSize * 0.14),
                        with: .color(Color.white.opacity(waveformOpacity))
                    )
                }
            }

            var playheadY = pixelSize / 2 + pitch * 2
            while playheadY <= size.height - pixelSize / 2 {
                let rect = CGRect(
                    x: lineX - pixelSize / 2,
                    y: playheadY - pixelSize / 2,
                    width: pixelSize,
                    height: pixelSize
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: pixelSize * 0.14),
                    with: .color(playheadColor.opacity(isActive ? 1 : 0.74))
                )
                playheadY += pitch
            }

            for row in 0..<2 {
                for column in 0..<2 {
                    let horizontalOffset = (CGFloat(column) - 0.5) * pitch
                    let center = CGPoint(
                        x: rawPlayheadX + horizontalOffset,
                        y: pixelSize / 2 + CGFloat(row) * pitch
                    )
                    let rect = CGRect(
                        x: center.x - pixelSize / 2,
                        y: center.y - pixelSize / 2,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: pixelSize * 0.14),
                        with: .color(playheadColor.opacity(isActive ? 1 : 0.74))
                    )
                }
            }
        }
    }

    private func interpolatedSample(at column: Int, columnCount: Int) -> CGFloat {
        guard let firstSample = samples.first else {
            return 0
        }
        guard samples.count > 1, columnCount > 1 else {
            return firstSample
        }

        let position = CGFloat(column) / CGFloat(columnCount - 1) * CGFloat(samples.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, samples.count - 1)
        let fraction = position - CGFloat(lowerIndex)
        return samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * fraction
    }
}

private struct RecordingDetailFactsGrid: View {
    let createdAtText: String
    let durationText: String
    let languageText: String
    let iCloudSyncStatus: RecordingICloudSyncStatus

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading),
        GridItem(.flexible(minimum: 0), spacing: 8, alignment: .leading)
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
            return Color(uiColor: .secondaryLabel)
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            RecordingDetailFactCell(
                systemImage: "calendar",
                text: createdAtText,
                tint: Color(uiColor: .secondaryLabel)
            )
            RecordingDetailFactCell(
                systemImage: "clock",
                text: durationText,
                tint: Color(uiColor: .secondaryLabel)
            )
            RecordingDetailFactCell(
                systemImage: "globe",
                text: languageText,
                tint: AppTheme.info
            )
            RecordingDetailFactCell(
                systemImage: iCloudSyncStatus.systemImage,
                text: iCloudSyncStatus.displayName,
                tint: iCloudTint
            )
        }
    }
}

private struct RecordingDetailFactCell: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 15)

            Text(text)
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct RecordingDetailContextStrip: View {
    private struct EdgeFade: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    @State private var edgeFade = EdgeFade()

    let tags: [String]
    let projectName: String?
    let categoryName: String?
    let location: RecordingLocation?

    private static let edgeFadeWidth: CGFloat = 14

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if let projectName {
                    RecordingDetailContextChip(
                        systemImage: "briefcase.fill",
                        text: projectName,
                        tint: AppTheme.brand
                    )
                }

                if let categoryName {
                    RecordingDetailContextChip(
                        systemImage: "folder.fill",
                        text: categoryName,
                        tint: AppTheme.purple
                    )
                }

                ForEach(tags, id: \.self) { tag in
                    RecordingDetailContextChip(
                        systemImage: nil,
                        text: tag,
                        tint: AppTheme.info
                    )
                }

                if let location {
                    RecordingDetailContextChip(
                        systemImage: "mappin.and.ellipse",
                        tint: AppTheme.success
                    ) {
                        RecordingLocationNameText(location: location)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .onScrollGeometryChange(for: EdgeFade.self) { geometry in
            let leadingOffset = max(
                geometry.contentOffset.x + geometry.contentInsets.leading,
                0
            )
            let maximumOffset = max(
                geometry.contentSize.width
                    + geometry.contentInsets.leading
                    + geometry.contentInsets.trailing
                    - geometry.containerSize.width,
                0
            )
            let trailingOffset = max(maximumOffset - leadingOffset, 0)

            return EdgeFade(
                leading: min(leadingOffset / Self.edgeFadeWidth, 1),
                trailing: min(trailingOffset / Self.edgeFadeWidth, 1)
            )
        } action: { _, newValue in
            edgeFade = newValue
        }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(1 - Double(edgeFade.leading)),
                        .black
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.edgeFadeWidth)

                Rectangle()
                    .fill(.black)

                LinearGradient(
                    colors: [
                        .black,
                        Color.black.opacity(1 - Double(edgeFade.trailing))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.edgeFadeWidth)
            }
        }
    }
}

private struct RecordingDetailContextChip<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String?
    let tint: Color
    @ViewBuilder var content: Content

    init(systemImage: String?, text: String, tint: Color) where Content == Text {
        self.systemImage = systemImage
        self.tint = tint
        content = Text(text)
    }

    init(systemImage: String?, tint: Color, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }

            content
                .font(.redditSans(.caption2, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background {
            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.055 : 0))

                Capsule()
                    .fill(tint.opacity(colorScheme == .dark ? 0.15 : 0.10))
            }
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    tint.opacity(colorScheme == .dark ? 0.42 : 0.09),
                    lineWidth: colorScheme == .dark ? 0.8 : 0.5
                )
        }
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
