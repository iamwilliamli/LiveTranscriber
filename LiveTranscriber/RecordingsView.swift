import AVFoundation
import CoreLocation
import CoreTransferable
import MapKit
import MediaPlayer
import OSLog
import PhotosUI
import SwiftUI
import TranscriberDomain
import Translation
import UIKit
import UniformTypeIdentifiers

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

private struct RecordingTabBarVisibilityController: UIViewControllerRepresentable {
    let isHidden: Bool
    let reducesMotion: Bool

    func makeUIViewController(context: Context) -> ObserverViewController {
        let viewController = ObserverViewController()
        viewController.updateVisibility(isHidden: isHidden, reducesMotion: reducesMotion)
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: ObserverViewController,
        context: Context
    ) {
        uiViewController.updateVisibility(isHidden: isHidden, reducesMotion: reducesMotion)
    }

    @MainActor
    final class ObserverViewController: UIViewController {
        private var desiredVisibilityIsHidden = false
        private var reducesMotion = false
        private var transitionTargetIsHidden: Bool?
        private var visibilityAnimator: UIViewPropertyAnimator?
        private var transitionSnapshot: UIView?

        override func loadView() {
            let view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
            self.view = view
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applyVisibilityIfPossible()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyVisibilityIfPossible()
        }

        func updateVisibility(isHidden: Bool, reducesMotion: Bool) {
            desiredVisibilityIsHidden = isHidden
            self.reducesMotion = reducesMotion
            applyVisibilityIfPossible()

            // SwiftUI can attach the representable before its UIKit parent
            // chain is complete. Retry once on the next main-loop turn.
            DispatchQueue.main.async { [weak self] in
                self?.applyVisibilityIfPossible()
            }
        }

        private func applyVisibilityIfPossible() {
            guard let tabBarController = containingTabBarController() else {
                return
            }

            if transitionTargetIsHidden == desiredVisibilityIsHidden {
                return
            }

            let isReversingActiveTransition = transitionTargetIsHidden != nil
            if isReversingActiveTransition {
                stopVisibilityAnimation()
            }

            if tabBarController.isTabBarHidden == desiredVisibilityIsHidden {
                if isReversingActiveTransition,
                   !desiredVisibilityIsHidden,
                   !reducesMotion {
                    animateTabBarIn(in: tabBarController)
                } else {
                    resetVisualState(of: tabBarController.tabBar)
                }
                return
            }

            if desiredVisibilityIsHidden {
                animateTabBarOut(in: tabBarController)
            } else {
                animateTabBarIn(in: tabBarController)
            }
        }

        private func animateTabBarIn(in tabBarController: UITabBarController) {
            let tabBar = tabBarController.tabBar
            let wasHidden = tabBarController.isTabBarHidden

            stopVisibilityAnimation()
            tabBarController.setTabBarHidden(false, animated: false)
            tabBarController.view.layoutIfNeeded()
            tabBar.layoutIfNeeded()

            if wasHidden {
                UIView.performWithoutAnimation {
                    tabBar.transform = reducesMotion
                        ? .identity
                        : entranceTransform(for: tabBar)
                    tabBar.alpha = 0
                }
            }

            transitionTargetIsHidden = false
            let animator: UIViewPropertyAnimator
            if reducesMotion {
                animator = UIViewPropertyAnimator(
                    duration: 0.16,
                    curve: .easeOut
                ) {
                    tabBar.alpha = 1
                }
            } else {
                animator = UIViewPropertyAnimator(
                    duration: 0.50,
                    dampingRatio: 0.82
                ) {
                    tabBar.transform = .identity
                    tabBar.alpha = 1
                }
            }
            animator.isInterruptible = true
            animator.addCompletion { [weak self, weak tabBar] position in
                guard let self else {
                    return
                }
                if position == .end {
                    tabBar?.transform = .identity
                    tabBar?.alpha = 1
                }
                self.visibilityAnimator = nil
                self.transitionTargetIsHidden = nil
            }
            visibilityAnimator = animator
            animator.startAnimation()
        }

        private func animateTabBarOut(in tabBarController: UITabBarController) {
            let tabBar = tabBarController.tabBar

            stopVisibilityAnimation()
            tabBarController.view.layoutIfNeeded()
            tabBar.layoutIfNeeded()

            let snapshot = tabBar.snapshotView(afterScreenUpdates: false)
            let snapshotFrame = tabBar.convert(tabBar.bounds, to: tabBarController.view)
            snapshot?.frame = snapshotFrame
            snapshot?.alpha = tabBar.alpha
            snapshot?.isUserInteractionEnabled = false

            // Release the tab bar's safe area immediately so the recording
            // player lays out at its final position from the first frame.
            UIView.performWithoutAnimation {
                tabBarController.setTabBarHidden(true, animated: false)
                resetVisualState(of: tabBar)
                tabBarController.view.layoutIfNeeded()
            }

            guard let snapshot else {
                transitionTargetIsHidden = nil
                return
            }

            tabBarController.view.addSubview(snapshot)
            transitionSnapshot = snapshot
            transitionTargetIsHidden = true

            let animator: UIViewPropertyAnimator
            if reducesMotion {
                animator = UIViewPropertyAnimator(
                    duration: 0.14,
                    curve: .easeIn
                ) {
                    snapshot.alpha = 0
                }
            } else {
                let exitTransform = entranceTransform(for: snapshot)
                animator = UIViewPropertyAnimator(
                    duration: 0.22,
                    curve: .easeIn
                ) {
                    snapshot.transform = exitTransform
                    snapshot.alpha = 0
                }
            }
            animator.isInterruptible = true
            animator.addCompletion { [weak self, weak snapshot] _ in
                guard let self else {
                    return
                }

                snapshot?.removeFromSuperview()
                self.transitionSnapshot = nil
                self.visibilityAnimator = nil
                self.transitionTargetIsHidden = nil
            }
            visibilityAnimator = animator
            animator.startAnimation()
        }

        private func entranceTransform(for view: UIView) -> CGAffineTransform {
            let verticalTravel = max(view.bounds.height + 12, 72)
            return CGAffineTransform(translationX: 0, y: verticalTravel)
                .scaledBy(x: 0.965, y: 0.965)
        }

        private func stopVisibilityAnimation() {
            guard let visibilityAnimator else {
                return
            }
            visibilityAnimator.stopAnimation(false)
            visibilityAnimator.finishAnimation(at: .current)
            self.visibilityAnimator = nil
            transitionSnapshot?.removeFromSuperview()
            transitionSnapshot = nil
            transitionTargetIsHidden = nil
        }

        private func resetVisualState(of tabBar: UITabBar) {
            tabBar.transform = .identity
            tabBar.alpha = 1
        }

        private func containingTabBarController() -> UITabBarController? {
            var ancestor: UIViewController? = self
            while let viewController = ancestor {
                if let tabBarController = viewController as? UITabBarController {
                    return tabBarController
                }
                if let tabBarController = viewController.tabBarController {
                    return tabBarController
                }
                ancestor = viewController.parent
            }
            return nil
        }
    }
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
                // These gestures observe the same hold without replacing the
                // Menu's own recognizer, so taps still run the primary action.
                .simultaneousGesture(analysisMenuChargeGesture)
                .simultaneousGesture(analysisMenuPresentationGesture)
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

    private var analysisMenuChargeGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18, maximumDistance: 14)
            .onEnded { _ in
                guard !isDisabled, providerAvailability.hasAnyAvailableProvider else {
                    return
                }
                HapticFeedback.play(.analysisMenuCharge)
                HapticFeedback.prepare(.analysisMenuPresented)
            }
    }

    private var analysisMenuPresentationGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.48, maximumDistance: 14)
            .onEnded { _ in
                guard !isDisabled, providerAvailability.hasAnyAvailableProvider else {
                    return
                }
                HapticFeedback.play(.analysisMenuPresented)
            }
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
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    @Binding var incomingImportURL: URL?
    @Binding var pendingOpenRecordingID: RecordingItem.ID?
    let player: RecordingPlaybackController
    @State private var deleteRequest: RecordingDeleteRequest?
    @State private var deletingRecordingIDs: Set<RecordingItem.ID> = []
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
    @State private var cachedSearchResults: [CachedRecordingSearchResult] = []
    @State private var isUpdatingSearchResults = false
    @State private var searchRevision = 0
    @State private var navigationPath: [RecordingNavigationDestination] = []
    @State private var navigationPopHasPlayedHaptic = false
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
        let names = categoryNames
        let appearances = categoryAppearances
        var countsByCategoryKey: [String: Int] = [:]
        countsByCategoryKey.reserveCapacity(names.count)
        for categoryName in names {
            countsByCategoryKey[categoryName.normalizedForRecordingSearch] = 0
        }

        var uncategorizedCount = 0
        for recording in store.recordings {
            guard let categoryName = recording.categoryName else {
                uncategorizedCount += 1
                continue
            }
            let key = categoryName.normalizedForRecordingSearch
            if countsByCategoryKey[key] != nil {
                countsByCategoryKey[key, default: 0] += 1
            }
        }

        var folders = names.map { categoryName in
            let key = categoryName.normalizedForRecordingSearch
            return RecordingCategoryFolder(
                id: categoryName,
                name: categoryName,
                count: countsByCategoryKey[key, default: 0],
                isUncategorized: false,
                appearance: appearances[key] ?? .defaultValue
            )
        }

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

    private var searchRequest: RecordingSearchRequest {
        RecordingSearchRequest(query: searchText, revision: searchRevision)
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
                .onInteractiveNavigationPopGesture(
                    onBegan: {
                        playNavigationPopHapticIfNeeded()
                    },
                    onCancelled: {
                        navigationPopHasPlayedHaptic = false
                    }
                )
        }
        .background(alignment: .topLeading) {
            RecordingTabBarVisibilityController(
                isHidden: navigationPath.containsRecordingDetail,
                reducesMotion: accessibilityReduceMotion
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onChange(of: navigationPath.count) { oldCount, newCount in
            guard newCount < oldCount else {
                return
            }
            if navigationPopHasPlayedHaptic {
                navigationPopHasPlayedHaptic = false
            } else {
                HapticFeedback.play(.navigation)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(L10n.Recordings.searchPrompt)
        )
        .task(id: searchRequest) {
            await updateSearchResults(for: searchRequest)
        }
        .task {
            await transcriber.refreshSupportedLanguages()
            appleSpeechTranscriptionLanguages = await AppleSpeechTranscriptionSupport.supportedLanguages()
            await refreshLocalWhisperMenuOptions()
            await store.reload()
            store.refreshIntelligenceAvailability()
            consumePendingOpenRecordingIDIfNeeded()
        }
        .onAppear {
            HapticFeedback.prepare(.navigation)
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
            searchRevision += 1
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
                    performConfirmedDelete(request.item)
                }
            }
            Button(localized(L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(localizedFormat(L10n.Recordings.deleteConfirmationFormat, deleteRequest?.item.displayName ?? ""))
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
                    analyzingRecordingID: analyzingRecordingID,
                    deletingRecordingIDs: deletingRecordingIDs,
                    onOpen: { item in
                        openRecording(item)
                    },
                    onDeleteRequest: { item in
                        deleteRequest = RecordingDeleteRequest(item: item)
                    },
                    onRequestNewCategory: { item in
                        beginNewCategory(assigning: item)
                    },
                    onUpdateCategory: updateRecordingCategory,
                    onAddRecordings: { folder in
                        addRecordingsCategoryTarget = folder
                    }
                )
                .onNavigationPopWillBegin {
                    playNavigationPopHapticIfNeeded()
                }
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
                .onNavigationPopWillBegin {
                    playNavigationPopHapticIfNeeded()
                }
            } else {
                EmptyStateView(icon: "exclamationmark.triangle", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.groupedBackground)
            }
        }
    }

    @ViewBuilder
    private var recordingsList: some View {
        let folders = categoryFolders

        List {
            if let videoImportProgressState {
                VideoImportProgressRow(state: videoImportProgressState)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isSearchingCategoryRoot {
                if isUpdatingSearchResults {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else if cachedSearchResults.isEmpty && videoImportProgressState == nil {
                    EmptyStateView(icon: "magnifyingglass", titleResource: L10n.Recordings.noSearchResults)
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(cachedSearchResults) { result in
                        searchResultRecordingRow(
                            result.item,
                            searchMatch: result.transcriptMatch
                        )
                    }
                }
            } else if folders.isEmpty && videoImportProgressState == nil {
                EmptyStateView(icon: "folder", titleResource: L10n.Recordings.noRecordings)
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(folders) { folder in
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
            .shadow(
                color: AppTheme.cardShadow,
                radius: AppTheme.cardShadowRadius,
                y: AppTheme.cardShadowYOffset
            )
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

    private func searchResultRecordingRow(
        _ item: RecordingItem,
        searchMatch: RecordingTranscriptSearchMatch?
    ) -> some View {
        let isDeleting = deletingRecordingIDs.contains(item.id)

        return RecordingRow(
            item: item,
            isAnalyzing: analyzingRecordingID == item.id,
            canGenerateIntelligence: store.intelligenceAvailability.isAvailable,
            searchMatch: searchMatch,
            canTerminateTranscription: store.canTerminateTranscription(for: item.id),
            onDismissImportStatus: {
                store.dismissFailedImportStatus(for: item.id)
            },
            onTerminateTranscription: {
                HapticFeedback.play(.warning)
                store.terminateTranscription(for: item.id)
            }
        ) {
            openRecording(item, initialTranscriptLineID: searchMatch?.lineID)
        }
        .opacity(isDeleting ? 0 : 1)
        .allowsHitTesting(!isDeleting)
        .accessibilityHidden(isDeleting)
        .animation(.easeOut(duration: 0.1), value: isDeleting)
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

            Button(role: .destructive) {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: item)
            } label: {
                Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: item)
            } label: {
                Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
            }
            .tint(AppTheme.danger)
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

    private func playNavigationPopHapticIfNeeded() {
        guard !navigationPopHasPlayedHaptic else {
            return
        }
        navigationPopHasPlayedHaptic = true
        HapticFeedback.play(.navigation)
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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

    private func performConfirmedDelete(_ item: RecordingItem) {
        // Let UIKit retire the alert and any swipe/context-menu snapshot before
        // SwiftUI starts moving List rows. Updating both in one transaction can
        // leave the deleted row's snapshot floating over the reflow animation.
        deleteRequest = nil

        Task { @MainActor in
            do {
                try await Task.sleep(
                    for: accessibilityReduceMotion ? .milliseconds(80) : .milliseconds(220)
                )
            } catch {
                return
            }

            guard store.recording(withID: item.id) != nil else {
                return
            }

            if accessibilityReduceMotion {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    delete(item)
                }
                return
            }

            withAnimation(.easeOut(duration: 0.1)) {
                _ = deletingRecordingIDs.insert(item.id)
            }
            try? await Task.sleep(for: .milliseconds(110))

            withAnimation(.snappy(duration: 0.2, extraBounce: 0)) {
                delete(item)
            }

            try? await Task.sleep(for: .milliseconds(220))
            deletingRecordingIDs.remove(item.id)
        }
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
            cachedSearchResults.removeAll { $0.item.id == item.id }
            try store.delete(item)
            HapticFeedback.play(.deleteConfirmed)
        } catch {
            deleteErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func normalizedSearchText(_ text: String) -> String {
        text.normalizedForRecordingSearch
    }

    private func updateSearchResults(for request: RecordingSearchRequest) async {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearchText(query).isEmpty else {
            cachedSearchResults = []
            isUpdatingSearchResults = false
            return
        }

        cachedSearchResults = []
        isUpdatingSearchResults = true

        do {
            try await Task.sleep(for: .milliseconds(180))
        } catch {
            return
        }

        let results = await store.searchRecordings(matching: query)
        guard !Task.isCancelled, request == searchRequest else {
            return
        }

        cachedSearchResults = results.compactMap { result in
            guard let item = store.recording(withID: result.recordingID) else {
                return nil
            }
            let transcriptMatch = result.transcriptMatch.map { match in
                RecordingTranscriptSearchMatch(
                    lineID: match.lineID,
                    timeText: match.timeText,
                    text: match.text,
                    query: query
                )
            }
            return CachedRecordingSearchResult(
                item: item,
                transcriptMatch: transcriptMatch
            )
        }
        isUpdatingSearchResults = false
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
    let originalSpeakerID: String?

    var id: String {
        lineID
    }

    init(line: StoredTranscriptLine) {
        lineID = line.id
        timeText = line.timeText
        originalSpeakerID = line.speaker
    }

    init(line: TranscriptionLine) {
        lineID = line.id.uuidString
        timeText = line.timestampText
        originalSpeakerID = nil
    }
}

private struct RecordingDeleteRequest: Identifiable {
    let item: RecordingItem

    var id: RecordingItem.ID {
        item.id
    }
}

/// Local cache for CloudKit-backed category records. Recording assignments use
/// `RecordingItem.categoryID`; `categoryName` is only a resolved display value.
/// Keeping the UUID stable means renaming a category never rewrites every
/// recording and cannot race a second device's metadata refresh.

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
    let analyzingRecordingID: RecordingItem.ID?
    let deletingRecordingIDs: Set<RecordingItem.ID>
    let onOpen: (RecordingItem) -> Void
    let onDeleteRequest: (RecordingItem) -> Void
    let onRequestNewCategory: (RecordingItem) -> Void
    let onUpdateCategory: (RecordingItem, String?) -> Void
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
                    let isDeleting = deletingRecordingIDs.contains(item.id)

                    RecordingRow(
                        item: item,
                        isAnalyzing: analyzingRecordingID == item.id,
                        canGenerateIntelligence: store.intelligenceAvailability.isAvailable,
                        canTerminateTranscription: store.canTerminateTranscription(for: item.id),
                        onDismissImportStatus: {
                            store.dismissFailedImportStatus(for: item.id)
                        },
                        onTerminateTranscription: {
                            HapticFeedback.play(.warning)
                            store.terminateTranscription(for: item.id)
                        }
                    ) {
                        onOpen(item)
                    }
                    .opacity(isDeleting ? 0 : 1)
                    .allowsHitTesting(!isDeleting)
                    .accessibilityHidden(isDeleting)
                    .animation(.easeOut(duration: 0.1), value: isDeleting)
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

                        Button(role: .destructive) {
                            HapticFeedback.play(.deleteRequested)
                            onDeleteRequest(item)
                        } label: {
                            Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            HapticFeedback.play(.deleteRequested)
                            onDeleteRequest(item)
                        } label: {
                            Label(localized(L10n.Recordings.deleteRecording), systemImage: "trash")
                        }
                        .tint(AppTheme.danger)
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
    @FocusState private var isNameFocused: Bool

    private var trimmedName: String {
        categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                EditorSheetSection(
                    title: localized(titleResource),
                    systemImage: iconSystemImage,
                    tint: AppTheme.brand
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Recordings.categoryName)
                            .font(.redditSans(.caption, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField(localized(L10n.Recordings.categoryNamePlaceholder), text: $categoryName)
                            .font(.redditSans(.body, weight: .semibold))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isNameFocused)
                            .padding(.horizontal, 13)
                            .frame(height: 50)
                            .editorSheetInputSurface(tint: AppTheme.brand)
                            .submitLabel(.done)
                            .onSubmit {
                                guard !trimmedName.isEmpty else {
                                    return
                                }
                                onSave()
                            }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.redditSans(.caption, weight: .semibold))
                                .foregroundStyle(AppTheme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
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
        .onAppear {
            isNameFocused = true
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
                    .padding(16)
                    .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(AppTheme.subtleBorder, lineWidth: 1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.Recordings.categoryName)
                            .font(.redditSans(.caption, weight: .bold))
                            .foregroundStyle(.secondary)

                        TextField(localized(L10n.Recordings.categoryNamePlaceholder), text: $categoryName)
                            .font(.redditSans(.body, weight: .semibold))
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 13)
                            .frame(height: 50)
                            .editorSheetInputSurface(tint: iconColor)
                    }
                    .recordingEditSectionSurface()

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
                    .recordingEditSectionSurface()

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
                    .recordingEditSectionSurface()

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
                            Text(item.displayName)
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
                                Text(item.displayName)
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
    let player: RecordingPlaybackController
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
        title = item.displayName
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

private struct RecordingSearchRequest: Equatable {
    let query: String
    let revision: Int
}

private struct CachedRecordingSearchResult: Identifiable {
    let item: RecordingItem
    let transcriptMatch: RecordingTranscriptSearchMatch?

    var id: RecordingItem.ID {
        item.id
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
    let canTerminateTranscription: Bool
    let onDismissImportStatus: () -> Void
    let onTerminateTranscription: () -> Void
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
                    Text(item.displayName)
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
                        RecordingFailedImportStatusRow(
                            message: importStatus.message,
                            onDismiss: onDismissImportStatus
                        )
                    } else if canTerminateTranscription {
                        RecordingActiveImportStatusRow(
                            status: importStatus,
                            onTerminate: onTerminateTranscription
                        )
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
    private struct EdgeFade: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    @State private var edgeFade = EdgeFade()

    let tags: [String]

    private static let edgeFadeWidth: CGFloat = 14

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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach($drafts) { $draft in
                        EditorSheetSection(
                            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? localized(L10n.Recordings.reminderTitle)
                                : draft.title,
                            systemImage: "bell.badge.fill",
                            tint: AppTheme.info
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center, spacing: 8) {
                                    TextField(localized(L10n.Recordings.reminderTitle), text: $draft.title)
                                        .font(.redditSans(.subheadline, weight: .semibold))
                                        .textInputAutocapitalization(.sentences)
                                        .textFieldStyle(.plain)
                                        .padding(.horizontal, 13)
                                        .frame(minHeight: 48)
                                        .editorSheetInputSurface(tint: AppTheme.info)

                                    Button(role: .destructive) {
                                        drafts.removeAll { $0.id == draft.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .frame(width: 42, height: 42)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel(Text(L10n.Common.delete))
                                }

                                Toggle(isOn: $draft.hasDueDate) {
                                    Label(localized(L10n.Recordings.reminderDueDate), systemImage: "calendar")
                                        .font(.redditSans(.subheadline, weight: .semibold))
                                }
                                .tint(AppTheme.info)

                                if draft.hasDueDate {
                                    DatePicker(
                                        localized(L10n.Recordings.reminderDueDate),
                                        selection: Binding(
                                            get: { draft.dueDate ?? Date() },
                                            set: { draft.dueDate = $0 }
                                        ),
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                    .datePickerStyle(.compact)
                                }

                                VStack(alignment: .leading, spacing: 7) {
                                    Text(L10n.Recordings.meetingNotes)
                                        .font(.redditSans(.caption, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    TextEditor(text: $draft.notes)
                                        .font(.redditSans(.body))
                                        .lineSpacing(3)
                                        .frame(minHeight: 92)
                                        .scrollContentBackground(.hidden)
                                        .padding(10)
                                        .editorSheetInputSurface()
                                }
                            }
                        }
                    }

                    Text(L10n.Recordings.reminderReviewFooter)
                        .font(.redditSans(.caption))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .disabled(isSaving)
            .background(AppTheme.groupedBackground.ignoresSafeArea())
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

private struct RecordingPlaybackObservationBoundary<Content: View>: View {
    @ObservedObject var player: RecordingPlaybackController
    private let content: () -> Content

    init(
        player: RecordingPlaybackController,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.player = player
        self.content = content
    }

    var body: some View {
        content()
    }
}

private struct RecordingPlaybackAmbientBackground: View {
    @ObservedObject var player: RecordingPlaybackController
    let recordingID: RecordingItem.ID

    private var ambientState: AmbientActivityState {
        guard player.isLoaded,
              player.currentItem?.id == recordingID else {
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
        AmbientActivityBackground(state: ambientState)
    }
}

private struct PlaybackSyncedTranscriptRows: View {
    private static let initialRenderCount = 80
    private static let subsequentRenderCount = 240

    let recordingID: RecordingItem.ID
    let lines: [StoredTranscriptLine]
    let initialLineID: StoredTranscriptLine.ID?
    let speakerByID: [String: TranscriptSpeakerPresentation]
    let showsSpeakerDistinction: Bool
    let translatedTranscriptByLineID: [StoredTranscriptLine.ID: String]
    let showsPendingTranslation: Bool
    let player: RecordingPlaybackController
    let onSeek: (StoredTranscriptLine) -> Void
    let onEdit: (StoredTranscriptLine) -> Void

    @State private var currentLineID: StoredTranscriptLine.ID?
    @State private var renderedLineCount = 0

    private var renderRevision: String {
        [
            recordingID.uuidString,
            String(lines.count),
            lines.first?.id ?? "none",
            lines.last?.id ?? "none",
            initialLineID ?? "none"
        ].joined(separator: "-")
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(lines.prefix(renderedLineCount)) { line in
                StoredTranscriptLineRow(
                    line: line,
                    speaker: showsSpeakerDistinction ? line.speaker.flatMap { speakerByID[$0] } : nil,
                    translatedText: translatedTranscriptByLineID[line.id],
                    isShowingTranslation: showsPendingTranslation
                        && translatedTranscriptByLineID[line.id] == nil,
                    isCurrent: line.id == currentLineID,
                    onTap: {
                        onSeek(line)
                    },
                    onEdit: {
                        onEdit(line)
                    }
                )
                .id(line.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateCurrentLine(at: player.currentTime)
        }
        .onChange(of: lines) { _, _ in
            updateCurrentLine(at: player.currentTime)
        }
        .onReceive(player.$currentTime) { time in
            updateCurrentLine(at: time)
        }
        .onReceive(player.$currentItem) { loadedItem in
            guard loadedItem?.id == recordingID else {
                currentLineID = nil
                return
            }
            updateCurrentLine(at: player.currentTime)
        }
        .task(id: renderRevision) {
            await renderLinesInBatches()
        }
    }

    private func renderLinesInBatches() async {
        let requiredLineCount = initialLineID.flatMap { lineID in
            lines.firstIndex(where: { $0.id == lineID }).map { $0 + 1 }
        } ?? 0
        let firstCount = min(
            lines.count,
            max(Self.initialRenderCount, requiredLineCount)
        )
        publishRenderedLineCount(firstCount)

        while renderedLineCount < lines.count {
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            publishRenderedLineCount(
                min(lines.count, renderedLineCount + Self.subsequentRenderCount)
            )
        }
    }

    private func publishRenderedLineCount(_ count: Int) {
        guard count != renderedLineCount else {
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            renderedLineCount = count
        }
    }

    private func updateCurrentLine(at time: TimeInterval) {
        let nextLineID: StoredTranscriptLine.ID?
        if player.isLoaded, player.currentItem?.id == recordingID {
            nextLineID = StoredTranscriptLine.currentLineID(in: lines, time: time)
        } else {
            nextLineID = nil
        }

        guard nextLineID != currentLineID else {
            return
        }
        currentLineID = nextLineID
    }
}

private enum RecordingAudioPreparationStatus: Equatable {
    case checking
    case downloading
    case preparing
    case available
    case failed(String)
}

struct RecordingDetailView: View {
    let item: RecordingItem
    @ObservedObject var store: RecordingStore
    @ObservedObject var transcriber: LiveTranscriptionManager
    let player: RecordingPlaybackController
    var downloadedLocalWhisperModels: [LocalWhisperModel] = []
    var localWhisperLanguageOptionsByModelID: [String: [TranscriptionLanguage]] = [:]
    var isQwen3ASRAvailable = Qwen3ASRModelManager.currentStatus().isAvailable
    var isMOSSLocalAvailable = MOSSLocalModelManager.currentStatus().isAvailable
    var initialTranscriptLineID: String? = nil
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(AudioEventDisplayConfiguration.confidenceThresholdDefaultsKey)
    private var audioEventConfidenceThreshold = AudioEventDisplayConfiguration.defaultConfidenceThreshold
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
    @State private var audioPreparationStatus: RecordingAudioPreparationStatus = .checking
    @State private var isShowingAudioFileInfo = false
    @State private var isShowingAudioEventsSheet = false
    @State private var audioEventsInitialScrollTargetID: RecordingAudioEvent.ID?
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
    @State private var editedTranscriptSpeakerApplyScope: TranscriptSpeakerApplyScope = .matchingFollowing
    @State private var isSavingTranscriptLineEdit = false
    @State private var isShowingTranscriptSpeakerListEdit = false
    @State private var editedTranscriptSpeakerNames: [String: String] = [:]
    @State private var isSavingTranscriptSpeakerNames = false
    @State private var cachedTranscriptText = ""
    @State private var cachedTranscriptLines: [StoredTranscriptLine] = []
    @State private var cachedTranscriptSpeakers: [TranscriptSpeakerPresentation] = []
    @State private var scrubbedPlaybackTime: TimeInterval?
    @State private var isTranscriptFollowEnabled = false
    @State private var followedTranscriptLineID: StoredTranscriptLine.ID?
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
    @AppStorage(ManualGeminiDeveloperConfiguration.enabledDefaultsKey) private var isManualGeminiEnabled = false
    @State private var selectedDetailPage: RecordingDetailPage = .transcript
    @State private var hasLoadedAIAnalysisPage = false
    @StateObject private var chatEngine = RecordingChatEngine()


    private var currentItem: RecordingItem {
        store.recording(withID: item.id) ?? item
    }

    private var currentItemDisplayTitle: String {
        currentItem.displayName
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

    private var playbackCacheIdentifier: String {
        "\(currentItem.id.uuidString)-\(currentItem.audioFileName)"
    }

    private var transcriptSpeakerEditOptions: [TranscriptSpeakerEditOption] {
        cachedTranscriptSpeakers.map { speaker in
            TranscriptSpeakerEditOption(
                id: speaker.id,
                displayName: speaker.displayName,
                tint: speaker.tint
            )
        }
    }

    private var newTranscriptSpeakerEditOption: TranscriptSpeakerEditOption {
        let presentations = cachedTranscriptSpeakers
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
            RecordingPlaybackAmbientBackground(
                player: player,
                recordingID: currentItem.id
            )

            transcriptPage
                .opacity(selectedDetailPage == .transcript ? 1 : 0)
                .offset(x: selectedDetailPage == .transcript ? 0 : -44)
                .allowsHitTesting(selectedDetailPage == .transcript)
                .accessibilityHidden(selectedDetailPage != .transcript)

            if hasLoadedAIAnalysisPage || selectedDetailPage == .aiAnalysis {
                aiAnalysisPage
                    .opacity(selectedDetailPage == .aiAnalysis ? 1 : 0)
                    .offset(x: selectedDetailPage == .aiAnalysis ? 0 : 44)
                    .allowsHitTesting(selectedDetailPage == .aiAnalysis)
                    .accessibilityHidden(selectedDetailPage != .aiAnalysis)
            }

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
        .onChange(of: selectedDetailPage) { _, page in
            if page == .aiAnalysis {
                hasLoadedAIAnalysisPage = true
            }
            HapticFeedback.play(.navigation)
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(currentItemDisplayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ViewThatFits(in: .horizontal) {
                    detailNavigationTitle
                        .frame(width: 240)
                        .clipped()
                    detailNavigationTitle
                        .frame(width: 208)
                        .clipped()
                    detailNavigationTitle
                        .frame(width: 176)
                        .clipped()
                }
            }

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
                ScrollViewReader { proxy in
                    ScrollView {
                        audioEventsSheetContent
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .background(AppTheme.groupedBackground.ignoresSafeArea())
                    .task(id: audioEventsInitialScrollTargetID) {
                        guard let targetID = audioEventsInitialScrollTargetID else {
                            return
                        }

                        await Task.yield()
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if currentItem.audioEventAnalysis != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                HapticFeedback.play(.menuSelection)
                                analyzeCurrentAudioEvents()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .tint(AppTheme.info)
                            .disabled(isAnalyzingAudioEvents)
                            .accessibilityLabel(Text(L10n.Recordings.analyzeAudioEventsAgain))
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(L10n.Recordings.audioEvents)
                                .font(.redditSans(.headline, weight: .bold))

                            Text(audioEventsToolbarSubtitle)
                                .font(.redditSans(.caption2, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            HapticFeedback.play(.navigation)
                            isShowingAudioEventsSheet = false
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .tint(.primary)
                        .accessibilityLabel(Text(L10n.Common.done))
                    }
                }
            }
            .presentationDetents([.height(audioEventsCompactHeight), .large])
            .presentationContentInteraction(.scrolls)
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
                languageOptions: recordingEditLanguageOptions,
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
                originalSpeakerID: request.originalSpeakerID,
                followingSpeakerSegmentCount: followingTranscriptLines(
                    matching: request.originalSpeakerID,
                    after: request.lineID
                ).count,
                speakerApplyScope: $editedTranscriptSpeakerApplyScope,
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
        .sheet(isPresented: $isShowingTranscriptSpeakerListEdit) {
            TranscriptSpeakerListEditSheet(
                speakers: cachedTranscriptSpeakers,
                namesBySpeakerID: $editedTranscriptSpeakerNames,
                isSaving: isSavingTranscriptSpeakerNames,
                onSave: saveTranscriptSpeakerNames,
                onCancel: {
                    isShowingTranscriptSpeakerListEdit = false
                }
            )
            .interactiveDismissDisabled(isSavingTranscriptSpeakerNames)
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
            HapticFeedback.prepare(.navigation)
            chatEngine.configure(recordingID: currentItem.id)
            updatePlayerNowPlayingTranscript()
            store.refreshIntelligenceAvailability()
        }
        .task(id: playbackCacheIdentifier) {
            await preparePlayback()
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
            Text(localizedFormat(L10n.Recordings.deleteConfirmationFormat, deleteRequest?.item.displayName ?? ""))
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
        let transcriptText = cachedTranscriptText
        let isTranscriptionActionDisabled = currentItem.isTranscriptLocked
            || isTranscriptionRunning
            || transcriber.isRecording
            || transcriber.isPreparing

        return Menu {
            Button {
                prepareRecordingEditSheet()
            } label: {
                Label(localized(L10n.Recordings.editDetails), systemImage: "pencil")
            }
            .disabled(isTranscriptionRunning)
            .tint(Color.primary)

            Button {
                toggleTranscriptLock()
            } label: {
                Label(
                    localized(currentItem.isTranscriptLocked ? L10n.Recordings.unlockTranscript : L10n.Recordings.lockTranscript),
                    systemImage: currentItem.isTranscriptLocked ? "lock.open" : "lock"
                )
            }
            .disabled(isTranscriptionRunning)
            .tint(Color.primary)

            Button {
                isShowingAudioFileInfo = true
            } label: {
                Label(localized(L10n.Recordings.audioParameters), systemImage: "info.circle")
            }
            .tint(Color.primary)

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
            .tint(Color.primary)

            Menu {
                Button {
                    requestCurrentItemRetranscription()
                } label: {
                    Label(
                        localized(L10n.Recordings.retranscribe),
                        systemImage: isTranscriptionRunning ? "hourglass" : "waveform"
                    )
                }
                .disabled(isTranscriptionActionDisabled)

                LocalWhisperRetranscriptionButton(
                    downloadedModels: downloadedLocalWhisperModels,
                    isDisabled: isTranscriptionActionDisabled
                ) {
                    isShowingLocalWhisperRetranscriptionPicker = true
                }

                Qwen3ASRRetranscriptionButton(
                    isAvailable: isQwen3ASRAvailable,
                    isDisabled: isTranscriptionActionDisabled
                ) {
                    retranscribeCurrentItemWithQwen3ASR()
                }

                MOSSLocalRetranscriptionButton(
                    isAvailable: isMOSSLocalAvailable,
                    isDisabled: isTranscriptionActionDisabled
                ) {
                    retranscribeCurrentItemWithMOSS()
                }
            } label: {
                Label(
                    localized(L10n.Recordings.transcribeMenu),
                    systemImage: "waveform.badge.magnifyingglass"
                )
            }
            .tint(Color.primary)

            if isManualGeminiEnabled {
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
                .tint(Color.primary)
            }

            if store.summaryProviderAvailability.isGeminiCloudAvailable {
                Button {
                    HapticFeedback.play(.menuSelection)
                    isShowingGeminiProcessingConfirmation = true
                } label: {
                    Label(localized(L10n.Recordings.processWithGemini), systemImage: "cloud")
                }
                .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)
                .tint(Color.primary)
            }

            if store.hasGeminiTranscriptBackup(for: currentItem) {
                Button {
                    HapticFeedback.play(.menuSelection)
                    isShowingGeminiRestoreConfirmation = true
                } label: {
                    Label(localized(L10n.Recordings.restoreBeforeGemini), systemImage: "arrow.uturn.backward")
                }
                .disabled(currentItem.isTranscriptLocked || isTranscriptionRunning || transcriber.isRecording || transcriber.isPreparing)
                .tint(Color.primary)
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
            .tint(Color.primary)

            Divider()

            Button(role: .destructive) {
                HapticFeedback.play(.deleteRequested)
                deleteRequest = RecordingDeleteRequest(item: currentItem)
            } label: {
                Label {
                    Text(L10n.Recordings.deleteRecording)
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(AppTheme.danger)
                }
            }
            .disabled(isTranscriptionRunning)
            .tint(AppTheme.danger)
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.primary)
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
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
                        .offset(y: 12)
                }
                .onReceive(player.$currentTime) { time in
                    followTranscriptIfNeeded(
                        at: time,
                        using: scrollProxy
                    )
                }
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .interacting,
                          isTranscriptFollowEnabled else {
                        return
                    }
                    isTranscriptFollowEnabled = false
                    followedTranscriptLineID = nil
                }
                .task(id: initialTranscriptScrollTarget) {
                    guard let lineID = initialTranscriptScrollTarget else {
                        return
                    }

                    await Task.yield()
                    scrollTranscript(to: lineID, using: scrollProxy)
                    if let line = cachedTranscriptLines.first(where: { $0.id == lineID }) {
                        scrubbedPlaybackTime = nil
                        player.seek(to: line.startSeconds)
                    }
                }
            }
        }
    }

    private var detailNavigationTitle: some View {
        VStack(spacing: 1) {
            Text(currentItemDisplayTitle)
                .font(.redditSans(.subheadline, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let summary = currentItem.singleLineSummary {
                RecordingSummaryMarquee(text: summary)
            }
        }
        .accessibilityElement(children: .combine)
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
                    transcript: cachedTranscriptText,
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

        return VStack(alignment: .leading, spacing: 0) {
            RetroRecordingDisplay(
                statusText: localized(L10n.Recordings.recordingPlayback),
                title: item.displayFileName,
                audioURL: store.audioURL(for: item),
                player: player,
                scrubbedTime: scrubbedPlaybackTime,
                duration: Double(item.durationSeconds)
            )

            VStack(alignment: .leading, spacing: 10) {
                RecordingDetailFactsGrid(
                    createdAtText: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                    durationText: TranscriptionLine.formatTimestamp(Double(item.durationSeconds)),
                    languageText: item.localizedLanguageName,
                    iCloudSyncStatus: iCloudSyncStatus,
                    audioPreparationStatus: displayedAudioPreparationStatus
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
                SummarySkeletonView(isAnimated: true)
            } else if let intelligence = item.intelligence,
                      !intelligence.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

                Text(intelligence.generatedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.redditSans(.caption2))
                    .foregroundStyle(.secondary)
            } else {
                SummarySkeletonView(isAnimated: false)
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
                MeetingAnalysisSkeletonView(isAnimated: true)
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
                MeetingAnalysisSkeletonView(isAnimated: false)
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
        let isFocused = event.id == audioEventsInitialScrollTargetID
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Button {
            HapticFeedback.play(.timelineSeek)
            player.seek(to: event.startTime)
            scrubbedPlaybackTime = nil
            isShowingAudioEventsSheet = false
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppTheme.info.opacity(isFocused ? 0.18 : 0.10))

                    Image(systemName: audioEventSymbolName(event))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.info)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text(event.localizedLabel)
                        .font(.redditSans(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 10) {
                        Label {
                            Text(
                                localizedFormat(
                                    L10n.Recordings.audioEventConfidenceFormat,
                                    event.confidence * 100
                                )
                            )
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                        }

                        Label {
                            Text(TranscriptionLine.formatTimestamp(event.duration))
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                    }
                    .font(.redditSans(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Label {
                    Text(audioEventTimeRangeText(event))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.redditSans(.caption2, weight: .bold))
                .foregroundStyle(AppTheme.info)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(AppTheme.info.opacity(isFocused ? 0.16 : 0.10), in: Capsule())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape
                    .fill(
                        isFocused
                            ? AppTheme.info.opacity(0.075)
                            : AppTheme.cardBackground
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        isFocused
                            ? AppTheme.info.opacity(0.30)
                            : AppTheme.cardBorder.opacity(0.72),
                        lineWidth: isFocused ? 1 : 0.75
                    )
            }
            .shadow(
                color: Color.black.opacity(isFocused ? 0.07 : 0.045),
                radius: isFocused ? 9 : 6,
                y: isFocused ? 4 : 2
            )
        }
        .buttonStyle(PlaybackAudioEventRowButtonStyle())
        .accessibilityHint(Text(audioEventTimeRangeText(event)))
    }

    private func audioEventTimeRangeText(_ event: RecordingAudioEvent) -> String {
        let start = TranscriptionLine.formatTimestamp(event.startTime)
        let end = TranscriptionLine.formatTimestamp(event.endTime)
        return "\(start)-\(end)"
    }

    private var audioEventsSheetContent: some View {
        let events = visibleAudioEvents

        return VStack(alignment: .leading, spacing: 14) {
            if isAnalyzingAudioEvents {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.info.opacity(0.10))

                        ProgressView()
                            .controlSize(.regular)
                            .tint(AppTheme.info)
                    }
                    .frame(width: 52, height: 52)

                    Text(L10n.Recordings.analyzingAudioEvents)
                        .font(.redditSans(.headline, weight: .semibold))
                }
                .foregroundStyle(AppTheme.info)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
                .background(
                    AppTheme.cardBackground,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            } else if let analysis = currentItem.audioEventAnalysis, !events.isEmpty {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { event in
                        audioEventRow(event)
                            .id(event.id)
                    }
                }

                Label {
                    Text(
                        analysis.generatedAt,
                        format: .dateTime.year().month().day().hour().minute()
                    )
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.redditSans(.caption2, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            } else {
                VStack(spacing: 18) {
                    ContentUnavailableView {
                        Label(
                            localized(L10n.Recordings.noAudioEvents),
                            systemImage: "waveform.badge.magnifyingglass"
                        )
                    } description: {
                        Text(L10n.Recordings.noAudioEventsDetected)
                    }

                    Button {
                        HapticFeedback.play(.menuSelection)
                        analyzeCurrentAudioEvents()
                    } label: {
                        Label(localized(L10n.Recordings.analyzeAudioEvents), systemImage: "waveform.badge.magnifyingglass")
                            .font(.redditSans(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzingAudioEvents)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(
                    AppTheme.cardBackground,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
        }
    }

    private var audioEventsToolbarSubtitle: String {
        if isAnalyzingAudioEvents {
            return localized(L10n.Recordings.analyzingAudioEvents)
        }

        let eventCount = visibleAudioEvents.count.formatted()
        let threshold = audioEventConfidenceThreshold.formatted(
            .percent.precision(.fractionLength(0))
        )
        return "\(eventCount) · >\(threshold)"
    }

    private var audioEventsCompactHeight: CGFloat {
        let visibleRowCount = min(max(visibleAudioEvents.count, 1), 3)
        return min(300 + CGFloat(visibleRowCount) * 84, 552)
    }

    private func audioEventSymbolName(_ event: RecordingAudioEvent) -> String {
        let identifier = event.sourceIdentifier.lowercased()

        if identifier.contains("alarm")
            || identifier.contains("bell")
            || identifier.contains("siren")
            || identifier.contains("phone") {
            return "bell.badge.fill"
        }
        if identifier.contains("applause")
            || identifier.contains("clap")
            || identifier.contains("cheer") {
            return "hands.clap.fill"
        }
        if identifier.contains("music") || identifier.contains("sing") {
            return "music.note"
        }
        if identifier.contains("cat") {
            return "cat.fill"
        }
        if identifier.contains("dog") {
            return "dog.fill"
        }
        if identifier.contains("cough") || identifier.contains("sneeze") {
            return "waveform.path.ecg"
        }
        if identifier.contains("engine") || identifier.contains("vehicle") {
            return "car.fill"
        }
        if identifier.contains("footstep") {
            return "figure.walk"
        }
        if identifier.contains("knock") {
            return "hand.tap.fill"
        }
        if identifier.contains("laugh") {
            return "face.smiling.fill"
        }
        if identifier.contains("rain") || identifier.contains("water") {
            return "drop.fill"
        }
        if identifier.contains("thunder") {
            return "cloud.bolt.rain.fill"
        }
        if identifier.contains("typing") {
            return "keyboard.fill"
        }
        if identifier.contains("wind") {
            return "wind"
        }
        return "waveform"
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
        RecordingPlaybackObservationBoundary(player: player) {
            playerCardContent(transcriptScrollProxy: transcriptScrollProxy)
        }
    }

    private func playerCardContent(transcriptScrollProxy: ScrollViewProxy) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let timeLabelWidth: CGFloat = 52

        return VStack(spacing: 2) {
            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 60.0,
                    paused: !player.isPlaying || scrubbedPlaybackTime != nil
                )
            ) { _ in
                let displayedTime = scrubbedPlaybackTime ?? player.presentationTime()

                HStack(alignment: .playbackTimelineTrack, spacing: 8) {
                    Text(TranscriptionLine.formatTimestamp(displayedTime))
                        .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: timeLabelWidth, alignment: .leading)

                    RecordingTimelineScrubber(
                        currentTime: displayedTime,
                        duration: player.duration,
                        scrubbedTime: $scrubbedPlaybackTime,
                        audioEvents: visibleAudioEvents,
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
                    .alignmentGuide(.playbackTimelineTrack) { _ in
                        RecordingTimelineLayout.trackCenterY
                    }

                    Text(TranscriptionLine.formatTimestamp(player.duration))
                        .font(.redditSans(.caption2, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(width: timeLabelWidth, alignment: .trailing)
                }
            }
            .padding(.horizontal, 2)

            playbackControlRow(transcriptScrollProxy: transcriptScrollProxy)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // Glass renders the player surface, but it does not make every
            // visually covered point an interaction target. Keep taps in the
            // gaps between controls from reaching transcript rows underneath.
            shape
                .fill(Color.black.opacity(0.001))
                .contentShape(.interaction, shape)
                .onTapGesture {}
                .accessibilityHidden(true)
        }
        .contentShape(.interaction, shape)
        .glassEffect(.regular.tint(AppTheme.playbackGlassTint), in: shape)
        .overlay {
            shape
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
    }

    @ViewBuilder
    private func playbackControlRow(transcriptScrollProxy: ScrollViewProxy) -> some View {
        ViewThatFits(in: .horizontal) {
            ZStack {
                HStack(spacing: 0) {
                    playbackAccessoryControls(transcriptScrollProxy: transcriptScrollProxy)
                    Spacer(minLength: 0)
                    playbackPreferenceControls
                }

                playbackTransportControls
            }
            .frame(minWidth: 348)

            HStack(spacing: 0) {
                playbackAccessoryControls(transcriptScrollProxy: transcriptScrollProxy)
                Spacer(minLength: 0)
                playbackTransportControls
                Spacer(minLength: 0)
                playbackPreferenceControls
            }
        }
    }

    private func playbackAccessoryControls(
        transcriptScrollProxy: ScrollViewProxy
    ) -> some View {
        HStack(spacing: 6) {
            audioEventsTimelineControl
            transcriptFollowControl(scrollProxy: transcriptScrollProxy)
        }
    }

    private var playbackPreferenceControls: some View {
        HStack(spacing: 6) {
            silenceSkippingControl
            playbackSpeedMenu
        }
    }

    private var playbackTransportControls: some View {
        HStack(spacing: 12) {
            PlaybackRoundButton(
                systemImage: "gobackward.5",
                title: "-5s",
                rotationDirection: .counterClockwise
            ) {
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

            PlaybackRoundButton(
                systemImage: "goforward.5",
                title: "+5s",
                rotationDirection: .clockwise
            ) {
                HapticFeedback.play(.timelineSeek)
                scrubbedPlaybackTime = nil
                player.skip(by: 5)
            }
            .disabled(!player.isLoaded)
        }
    }

    private var displayedAudioPreparationStatus: RecordingAudioPreparationStatus {
        if case .available = audioPreparationStatus,
           !player.isLoaded,
           let errorText = player.errorText {
            return .failed(errorText)
        }
        return audioPreparationStatus
    }

    private func transcriptFollowControl(scrollProxy: ScrollViewProxy) -> some View {
        Button {
            let isEnabling = !isTranscriptFollowEnabled
            HapticFeedback.play(isEnabling ? .toggleOn : .toggleOff)
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                isTranscriptFollowEnabled = isEnabling
            }
            followedTranscriptLineID = nil
            if isEnabling {
                followTranscriptIfNeeded(
                    at: scrubbedPlaybackTime ?? player.presentationTime(),
                    using: scrollProxy,
                    force: true
                )
            }
        } label: {
            PlaybackUtilityControlLabel(
                tint: isTranscriptFollowEnabled ? AppTheme.info : .primary,
                width: 42,
                isSelected: isTranscriptFollowEnabled
            ) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle())
        .disabled(!player.isLoaded || cachedTranscriptLines.isEmpty)
        .accessibilityLabel(Text(L10n.Recordings.followTranscript))
        .accessibilityValue(
            Text(
                isTranscriptFollowEnabled
                    ? L10n.ICloud.enabled
                    : L10n.ICloud.disabled
            )
        )
    }

    private func followTranscriptIfNeeded(
        at playbackTime: TimeInterval,
        using scrollProxy: ScrollViewProxy,
        force: Bool = false
    ) {
        guard isTranscriptFollowEnabled else {
            return
        }
        let lineID = StoredTranscriptLine.currentLineID(
            in: cachedTranscriptLines,
            time: playbackTime
        ) ?? cachedTranscriptLines.first?.id

        guard let lineID,
              force || followedTranscriptLineID != lineID else {
            return
        }
        followedTranscriptLineID = lineID
        guard !accessibilityReduceMotion else {
            scrollProxy.scrollTo(lineID, anchor: .center)
            return
        }

        withAnimation(.snappy(duration: 0.30, extraBounce: 0)) {
            scrollProxy.scrollTo(lineID, anchor: .center)
        }
    }

    private var audioEventsTimelineControl: some View {
        Button {
            if currentItem.audioEventAnalysis == nil {
                analyzeCurrentAudioEvents()
            } else {
                let playbackTime = scrubbedPlaybackTime ?? player.presentationTime()
                audioEventsInitialScrollTargetID = nearestAudioEvent(
                    to: playbackTime,
                    in: visibleAudioEvents
                )?.id
                isShowingAudioEventsSheet = true
            }
        } label: {
            PlaybackUtilityControlLabel(tint: currentItem.audioEventAnalysis == nil ? .primary : AppTheme.info, width: 42) {
                HStack(spacing: 6) {
                    if isAnalyzingAudioEvents {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))

                        if currentItem.audioEventAnalysis != nil {
                            Text(visibleAudioEvents.count.formatted(.number.notation(.compactName)))
                                .font(.redditSans(.caption2, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle(showsDepthShadow: true))
        .disabled(!player.isLoaded || isAnalyzingAudioEvents)
        .accessibilityLabel(Text(L10n.Recordings.audioEvents))
    }

    private var visibleAudioEvents: [RecordingAudioEvent] {
        guard let events = currentItem.audioEventAnalysis?.events else {
            return []
        }

        return events
            .filter { $0.confidence > audioEventConfidenceThreshold }
            .sorted { lhs, rhs in
                if lhs.startTime != rhs.startTime {
                    return lhs.startTime < rhs.startTime
                }
                if lhs.endTime != rhs.endTime {
                    return lhs.endTime < rhs.endTime
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func nearestAudioEvent(
        to playbackTime: TimeInterval,
        in events: [RecordingAudioEvent]
    ) -> RecordingAudioEvent? {
        events.min { lhs, rhs in
            let lhsDistance = audioEventDistance(from: playbackTime, to: lhs)
            let rhsDistance = audioEventDistance(from: playbackTime, to: rhs)

            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            return lhs.endTime < rhs.endTime
        }
    }

    private func audioEventDistance(
        from playbackTime: TimeInterval,
        to event: RecordingAudioEvent
    ) -> TimeInterval {
        if playbackTime >= event.startTime, playbackTime <= event.endTime {
            return 0
        }
        return min(
            abs(playbackTime - event.startTime),
            abs(playbackTime - event.endTime)
        )
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
            PlaybackUtilityControlLabel(tint: .primary, width: 42) {
                Text(RecordingPlaybackController.playbackRateLabel(player.playbackRate))
                    .font(.redditSans(.caption2, weight: .bold).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle(showsDepthShadow: true))
        .disabled(!player.isLoaded)
    }

    private var silenceSkippingControl: some View {
        Button {
            let isEnabling = !player.isSilenceSkippingEnabled
            HapticFeedback.play(isEnabling ? .toggleOn : .toggleOff)
            withAnimation(.snappy(duration: 0.18, extraBounce: 0)) {
                player.toggleSilenceSkipping()
            }
        } label: {
            PlaybackUtilityControlLabel(
                tint: player.isSilenceSkippingEnabled ? AppTheme.info : .primary,
                width: 42,
                isSelected: player.isSilenceSkippingEnabled
            ) {
                if player.isPreparingSilenceAnalysis {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(PlaybackUtilityButtonStyle())
        .disabled(!player.isLoaded)
        .accessibilityLabel(Text(L10n.Recordings.skipSilence))
        .accessibilityValue(
            Text(
                player.isSilenceSkippingEnabled
                    ? L10n.ICloud.enabled
                    : L10n.ICloud.disabled
            )
        )
    }

    private var transcript: some View {
        let item = currentItem
        let lines = cachedTranscriptLines
        let speakers = cachedTranscriptSpeakers
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
                        .frame(height: 30)
                        .background(AppTheme.warning.opacity(0.12), in: Capsule())
                        .accessibilityHint(localized(L10n.Recordings.transcriptLockedDetail))
                }

                Spacer(minLength: 8)

                transcriptTranslationMenu
                    .disabled(lines.isEmpty || isTranscriptionRunning)
            }

            if showsSpeakerDistinction {
                TranscriptSpeakerLegend(
                    speakers: speakers,
                    onEditSpeakers: item.isTranscriptLocked ? nil : beginTranscriptSpeakerListEdit
                )
            }

            transcriptTranslationStatus

            if let importStatus = item.importStatus {
                RecordingImportStatusDetail(
                    status: importStatus,
                    canTerminateTranscription: store.canTerminateTranscription(for: item.id),
                    onDismiss: {
                        store.dismissFailedImportStatus(for: item.id)
                    },
                    onTerminate: {
                        HapticFeedback.play(.warning)
                        store.terminateTranscription(for: item.id)
                    }
                )
            }

            if lines.isEmpty {
                if item.importStatus == nil {
                    EmptyStateView(icon: "text.badge.xmark", titleResource: L10n.Recordings.noText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                }
            } else {
                PlaybackSyncedTranscriptRows(
                    recordingID: item.id,
                    lines: lines,
                    initialLineID: initialTranscriptScrollTarget,
                    speakerByID: speakerByID,
                    showsSpeakerDistinction: showsSpeakerDistinction,
                    translatedTranscriptByLineID: translatedTranscriptByLineID,
                    showsPendingTranslation: isTranslatingTranscript && selectedTranslationLanguage != nil,
                    player: player,
                    onSeek: { line in
                        HapticFeedback.play(.timelineSeek)
                        scrubbedPlaybackTime = nil
                        player.seek(to: line.startSeconds)
                    },
                    onEdit: { line in
                        beginTranscriptLineEdit(line)
                    }
                )
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

    private var recordingEditLanguageOptions: [TranscriptionLanguage] {
        let whisperLanguages = LocalWhisperTranscriptionService.supportedLanguages(
            for: LocalWhisperTranscriptionService.defaultModel
        )

        return TranscriptionLanguage.baseLanguageOptions(
            from: whisperLanguages + appleTranslationLanguages + appleSpeechTranscriptionLanguages,
            including: editRecordingLanguageID
        )
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
                transcript: cachedTranscriptText,
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
            .map { ReminderDraft(actionItem: $0, recordingTitle: currentItem.displayName) }
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
            } catch {
                transcriptionErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func preparePlayback() async {
        let item = currentItem
        audioPreparationStatus = .checking
        audioFileInfo = nil
        audioFileInfoError = nil

        do {
            let url = try await store.prepareAudioURL(for: item) { state in
                guard currentItem.id == item.id,
                      currentItem.audioFileName == item.audioFileName else {
                    return
                }
                switch state {
                case .checking:
                    audioPreparationStatus = .checking
                case .downloading:
                    audioPreparationStatus = .downloading
                case .available:
                    audioPreparationStatus = .preparing
                }
            }
            guard !Task.isCancelled,
                  currentItem.id == item.id,
                  currentItem.audioFileName == item.audioFileName else {
                return
            }

            audioPreparationStatus = .preparing
            await player.loadPrepared(item: item, url: url)
            guard !Task.isCancelled,
                  currentItem.id == item.id,
                  currentItem.audioFileName == item.audioFileName else {
                return
            }
            guard player.isLoaded,
                  player.currentItem?.id == item.id else {
                audioPreparationStatus = .failed(
                    player.errorText
                        ?? localizedFormat(
                            L10n.Recordings.playbackFailedFormat,
                            String(localized: L10n.Recordings.recordingFileMissing)
                        )
                )
                return
            }

            audioPreparationStatus = .available
            updatePlayerNowPlayingTranscript(for: item.id)
            player.prewarmPlaybackSession()
            await refreshAudioFileInfo(for: item, at: url)
        } catch is CancellationError {
            return
        } catch {
            guard currentItem.id == item.id,
                  currentItem.audioFileName == item.audioFileName else {
                return
            }
            audioPreparationStatus = .failed(error.localizedDescription)
            audioFileInfoError = error.localizedDescription
        }
    }

    private func refreshAudioFileInfo(for item: RecordingItem, at url: URL) async {
        guard !Task.isCancelled else {
            return
        }
        do {
            let info = try await Task.detached(priority: .utility) {
                try RecordingAudioFileInfo(url: url)
            }.value
            guard !Task.isCancelled,
                  currentItem.id == item.id,
                  currentItem.audioFileName == item.audioFileName else {
                return
            }
            audioFileInfo = info
            audioFileInfoError = nil
        } catch {
            guard currentItem.id == item.id,
                  currentItem.audioFileName == item.audioFileName else {
                return
            }
            audioFileInfo = nil
            audioFileInfoError = localizedFormat(L10n.Recordings.audioInfoReadFailedFormat, error.localizedDescription)
        }
    }

    private func refreshTranscriptCache() async {
        let item = currentItem
        let speakerDiarization = item.speakerDiarization
        let text = await store.loadTranscriptText(for: item)
        guard !Task.isCancelled else {
            return
        }
        let lines = await Task.detached(priority: .utility) {
            return StoredTranscriptLine.parse(text, speakerDiarization: speakerDiarization)
        }.value

        guard currentItem.id == item.id,
              currentItem.transcriptFileName == item.transcriptFileName else {
            return
        }

        let speakers = TranscriptSpeakerPresentation.makePresentations(for: lines)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cachedTranscriptText = text
            cachedTranscriptLines = lines
            cachedTranscriptSpeakers = speakers
        }
        updatePlayerNowPlayingTranscript()
        translatedTranscriptByLineID = [:]
        translatedTranscriptCache = translatedTranscriptCache.filter { key, _ in
            key.hasPrefix(transcriptTranslationCachePrefix)
        }

        if let selectedTranslationLanguage {
            requestTranscriptTranslation(to: selectedTranslationLanguage)
        }
    }

    private func updatePlayerNowPlayingTranscript(for recordingID: UUID? = nil) {
        player.setNowPlayingTranscript(
            for: recordingID ?? currentItem.id,
            cues: cachedTranscriptLines.map { line in
                (startTime: line.startSeconds, text: line.spokenText)
            }
        )
    }

    private func beginTranscriptLineEdit(_ line: StoredTranscriptLine) {
        HapticFeedback.play(.menuSelection)
        editedTranscriptLineText = line.spokenText
        editedTranscriptLineSpeakerID = line.speaker
        editedTranscriptSpeakerApplyScope = .matchingFollowing
        transcriptLineEditRequest = TranscriptLineEditRequest(line: line)
    }

    private func beginTranscriptSpeakerListEdit() {
        guard !cachedTranscriptSpeakers.isEmpty else {
            return
        }
        HapticFeedback.play(.menuSelection)
        editedTranscriptSpeakerNames = Dictionary(
            uniqueKeysWithValues: cachedTranscriptSpeakers.map {
                ($0.id, $0.displayName)
            }
        )
        isShowingTranscriptSpeakerListEdit = true
    }

    private func saveTranscriptSpeakerNames() {
        guard !isSavingTranscriptSpeakerNames else {
            return
        }

        let renamedSpeakers = Dictionary(
            uniqueKeysWithValues: cachedTranscriptSpeakers.compactMap { speaker in
                let name = (editedTranscriptSpeakerNames[speaker.id] ?? speaker.displayName)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return name == speaker.displayName ? nil : (speaker.id, name)
            }
        )
        guard !renamedSpeakers.isEmpty else {
            isShowingTranscriptSpeakerListEdit = false
            return
        }

        isSavingTranscriptSpeakerNames = true
        do {
            let updatedItem = try store.renameTranscriptSpeakers(
                for: currentItem,
                namesBySpeakerID: renamedSpeakers
            )
            let updatedTranscriptText = store.transcriptText(for: updatedItem)
            let updatedLines = StoredTranscriptLine.parse(
                updatedTranscriptText,
                speakerDiarization: updatedItem.speakerDiarization
            )
            cachedTranscriptText = updatedTranscriptText
            cachedTranscriptLines = updatedLines
            cachedTranscriptSpeakers = TranscriptSpeakerPresentation.makePresentations(
                for: updatedLines
            )
            updatePlayerNowPlayingTranscript()
            clearTranscriptTranslationState()
            isShowingTranscriptSpeakerListEdit = false
            HapticFeedback.play(.recordingSaved)
        } catch {
            editErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
        isSavingTranscriptSpeakerNames = false
    }

    private func saveTranscriptLineEdit() {
        guard let transcriptLineEditRequest,
              !isSavingTranscriptLineEdit else {
            return
        }

        let speakerChanged = !transcriptSpeakerIDsMatch(
            transcriptLineEditRequest.originalSpeakerID,
            editedTranscriptLineSpeakerID
        )
        let followingLines = speakerChanged && editedTranscriptSpeakerApplyScope == .matchingFollowing
            ? followingTranscriptLines(
                matching: transcriptLineEditRequest.originalSpeakerID,
                after: transcriptLineEditRequest.lineID
            )
            : []

        performTranscriptLineEdit(applyingSpeakerTo: followingLines)
    }

    private func followingTranscriptLines(
        matching originalSpeakerID: String?,
        after lineID: String
    ) -> [StoredTranscriptLine] {
        guard let originalSpeakerID = TranscriptSpeakerNaming.normalizedID(originalSpeakerID),
              let editedLineIndex = cachedTranscriptLines.firstIndex(where: { $0.id == lineID }) else {
            return []
        }

        return cachedTranscriptLines.dropFirst(editedLineIndex + 1).filter {
            transcriptSpeakerIDsMatch($0.speaker, originalSpeakerID)
        }
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
        applyingSpeakerTo followingLines: [StoredTranscriptLine]
    ) {
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
                speaker: editedTranscriptLineSpeakerID,
                followingLines: followingLines.map {
                    (lineID: $0.id, text: $0.spokenText)
                }
            )
            let updatedTranscriptText = store.transcriptText(for: updatedItem)
            let updatedLines = StoredTranscriptLine.parse(
                updatedTranscriptText,
                speakerDiarization: updatedItem.speakerDiarization
            )
            cachedTranscriptText = updatedTranscriptText
            cachedTranscriptLines = updatedLines
            cachedTranscriptSpeakers = TranscriptSpeakerPresentation.makePresentations(
                for: updatedLines
            )
            updatePlayerNowPlayingTranscript()
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
        editRecordingName = item.displayName
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
            updatePlayerNowPlayingTranscript(for: updatedItem.id)
            let updatedAudioURL = store.audioURL(for: updatedItem)
            Task {
                await refreshAudioFileInfo(for: updatedItem, at: updatedAudioURL)
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
                proposedName: currentItem.displayName,
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
            updatePlayerNowPlayingTranscript(for: updatedItem.id)
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

    private var hasChanges: Bool {
        let originalLanguageID = TranscriptionLanguage(id: item.languageID).baseLanguage.id
        return recordingName != item.displayName
            || languageID != originalLanguageID
            || categoryName != (item.categoryName ?? "")
            || keyPoints != (item.keyPoints ?? "")
            || tags != item.combinedTags
            || summary != (item.intelligence?.summary ?? "")
            || includesLocation != (item.location != nil)
            || locationProvider.recordingLocation != nil
    }

    private var canSave: Bool {
        !isSaving
            && hasChanges
            && !recordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(localized(L10n.Recordings.editRecordingTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized(L10n.Common.cancel)) {
                        onCancel()
                    }
                    .disabled(isSaving)
                    .tint(.primary)
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
                    .disabled(!canSave)
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
    }

    private var primaryInformationCard: some View {
        let selectedLanguage = languageOptions.first(where: { $0.id == languageID })
            ?? TranscriptionLanguage(id: languageID).baseLanguage
        let appearance = categoryName.isEmpty
            ? nil
            : RecordingCategoryAppearanceCatalog.appearance(for: categoryName)

        return VStack(alignment: .leading, spacing: 0) {
            recordingEditFieldHeader(
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

                if showsTitleGeneration, onGenerateTitle != nil {
                    Button {
                        generateTitle()
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
                    .disabled(isSaving || isGeneratingTitle)
                    .accessibilityLabel(
                        localized(L10n.Transcription.generateTitleAndTagsAccessibility)
                    )
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, showsTitleGeneration && onGenerateTitle != nil ? 8 : 13)
            .frame(minHeight: 52)
            .recordingEditInputSurface(
                isFocused: focusedField == .name,
                tint: AppTheme.brand
            )
            .padding(.top, 10)
            .padding(.bottom, 14)

            recordingEditDivider

            Button {
                focusedField = nil
                isShowingLanguagePicker = true
                HapticFeedback.play(.menuSelection)
            } label: {
                recordingEditSelectionRow(
                    title: L10n.Settings.transcriptionLanguage,
                    value: selectedLanguage.displayName,
                    systemImage: "globe",
                    tint: AppTheme.info,
                    trailingSystemImage: "chevron.right"
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving || languageOptions.isEmpty)

            recordingEditDivider

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
                recordingEditSelectionRow(
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
        .recordingEditGroupedSurface()
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            recordingEditTextArea(
                title: L10n.Recordings.summary,
                placeholder: L10n.Recordings.summaryPlaceholder,
                text: $summary,
                field: .summary,
                systemImage: "text.alignleft",
                tint: AppTheme.purple,
                minimumHeight: 92
            )

            Divider()
                .overlay(AppTheme.subtleBorder)

            recordingEditTextArea(
                title: L10n.Recordings.keyPoints,
                placeholder: L10n.Recordings.keyPointsPlaceholder,
                text: $keyPoints,
                field: .keyPoints,
                systemImage: "list.bullet.clipboard",
                tint: AppTheme.warning,
                minimumHeight: 80
            )
        }
        .recordingEditGroupedSurface()
    }

    private var recordingEditDivider: some View {
        Divider()
            .overlay(AppTheme.subtleBorder)
            .padding(.leading, 42)
    }

    private func recordingEditFieldHeader(
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

    private func recordingEditSelectionRow(
        title: LocalizedStringResource,
        value: String,
        systemImage: String,
        tint: Color,
        trailingSystemImage: String
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

            Image(systemName: trailingSystemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func recordingEditTextArea(
        title: LocalizedStringResource,
        placeholder: LocalizedStringResource,
        text: Binding<String>,
        field: FocusedField,
        systemImage: String,
        tint: Color,
        minimumHeight: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            recordingEditFieldHeader(
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
            .recordingEditInputSurface(
                isFocused: focusedField == field,
                tint: tint
            )
        }
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

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                RecordingMetadataTagsEditor(tags: $tags)
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

                        recordingEditTagPreview
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

            recordingEditDivider

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

                Text(TranscriptionLine.formatTimestamp(Double(item.durationSeconds)))
                    .font(
                        .redditSans(.subheadline, weight: .semibold)
                            .monospacedDigit()
                    )
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 58)
            .accessibilityElement(children: .combine)

            recordingEditDivider

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

                RecordingEditLocationPreview(
                    existingLocation: item.location,
                    locationProvider: locationProvider
                )
            }
        }
        .recordingEditGroupedSurface()
    }

    @ViewBuilder
    private var recordingEditTagPreview: some View {
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
}

private struct RecordingSummaryEditSheet: View {
    @Binding var summary: String
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isSummaryFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                EditorSheetSection(
                    title: localized(L10n.Recordings.summary),
                    systemImage: "text.alignleft",
                    tint: AppTheme.purple
                ) {
                    ZStack(alignment: .topLeading) {
                        if summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(L10n.Recordings.summaryPlaceholder)
                                .font(.redditSans(.body))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 17)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $summary)
                            .font(.redditSans(.body))
                            .lineSpacing(4)
                            .scrollContentBackground(.hidden)
                            .focused($isSummaryFocused)
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
                            .editorSheetInputSurface()
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "character.cursor.ibeam")
                        Text(summary.count.formatted())
                            .monospacedDigit()
                    }
                    .font(.redditSans(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .top)
            }
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
        .onAppear {
            isSummaryFocused = true
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

private struct RecordingEditInputSurfaceModifier: ViewModifier {
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
    func recordingEditGroupedSurface() -> some View {
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

    func recordingEditInputSurface(
        isFocused: Bool,
        tint: Color
    ) -> some View {
        modifier(
            RecordingEditInputSurfaceModifier(
                isFocused: isFocused,
                tint: tint
            )
        )
    }

    func recordingEditSectionSurface() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppTheme.subtleBorder, lineWidth: 1)
            }
    }
}

private struct RecordingImportStatusDetail: View {
    let status: RecordingImportStatus
    let canTerminateTranscription: Bool
    let onDismiss: () -> Void
    let onTerminate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.isFailed {
                RecordingFailedImportStatusRow(
                    message: status.message,
                    onDismiss: onDismiss
                )
            } else if canTerminateTranscription {
                RecordingActiveImportStatusRow(
                    status: status,
                    onTerminate: onTerminate
                )
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

private struct RecordingFailedImportStatusRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            RecordingStatusDismissButton(action: onDismiss)
        }
        .frame(minHeight: 30)
    }
}

private struct RecordingActiveImportStatusRow: View {
    let status: RecordingImportStatus
    let onTerminate: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: status.progress)
                    .progressViewStyle(.linear)

                Label(status.message, systemImage: "waveform")
                    .font(.redditSans(.caption, weight: .semibold))
                    .foregroundStyle(AppTheme.info)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RecordingStatusDismissButton(
                tint: AppTheme.info,
                accessibilityLabel: L10n.Recordings.stopTranscription,
                action: onTerminate
            )
        }
        .frame(minHeight: 30)
    }
}

private struct RecordingStatusDismissButton: View {
    let tint: Color
    let accessibilityLabel: LocalizedStringResource
    let action: () -> Void

    init(
        tint: Color = AppTheme.warning,
        accessibilityLabel: LocalizedStringResource = L10n.Common.close,
        action: @escaping () -> Void
    ) {
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private enum RecordingTimelineLayout {
    static let height: CGFloat = 48
    static let trackCenterY: CGFloat = 27
}

private struct PlaybackTimelineTrackAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

private extension VerticalAlignment {
    static let playbackTimelineTrack = VerticalAlignment(PlaybackTimelineTrackAlignment.self)
}

private struct RecordingTimelineScrubber: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let currentTime: TimeInterval
    let duration: TimeInterval
    @Binding var scrubbedTime: TimeInterval?
    let audioEvents: [RecordingAudioEvent]
    let isEnabled: Bool
    let onSeek: (TimeInterval) -> Void
    let onEventTap: (RecordingAudioEvent) -> Void

    @State private var isScrubbing = false
    @State private var hapticAudioEventID: RecordingAudioEvent.ID?
    @State private var previousHapticScrubTime: TimeInterval?

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
                let trackCenterY = RecordingTimelineLayout.trackCenterY
                let trackHeight: CGFloat = 6
                let eventMarkerHeight: CGFloat = 2
                let focusedEvent = isScrubbing
                    ? activeAudioEvent(at: displayedTime)
                    : audioEvent(containing: displayedTime)

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .top) {
                        if let focusedEvent {
                            Text(focusedEvent.localizedLabel)
                                .font(.redditSans(.caption2, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.76))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .transition(
                                    accessibilityReduceMotion
                                        ? .opacity
                                        : .asymmetric(
                                            insertion: .opacity.combined(with: .offset(x: 0, y: 2)),
                                            removal: .opacity
                                        )
                                )
                                .id(focusedEvent.id)
                        }
                    }
                    .frame(width: width, height: 18, alignment: .top)
                    .allowsHitTesting(false)
                    .animation(
                        accessibilityReduceMotion ? nil : .easeOut(duration: 0.16),
                        value: focusedEvent?.id
                    )

                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: trackHeight)
                        .offset(y: trackCenterY - trackHeight / 2)

                    Capsule()
                        .fill(AppTheme.brand.opacity(isEnabled ? 0.88 : 0.34))
                        .frame(width: max(thumbX, 0), height: trackHeight)
                        .offset(y: trackCenterY - trackHeight / 2)

                    Canvas(opaque: false, rendersAsynchronously: true) { context, _ in
                        for event in audioEvents {
                            let rect = markerRect(
                                for: event,
                                trackWidth: width,
                                markerHeight: eventMarkerHeight
                            )
                            let playedWidth = min(max(thumbX - rect.minX, 0), rect.width)

                            if playedWidth > 0 {
                                let playedRect = CGRect(
                                    x: rect.minX,
                                    y: rect.minY,
                                    width: playedWidth,
                                    height: rect.height
                                )
                                context.fill(
                                    Path(roundedRect: playedRect, cornerRadius: eventMarkerHeight / 2),
                                    with: .color(Color.white.opacity(isEnabled ? 0.30 : 0.14))
                                )
                            }

                            if playedWidth < rect.width {
                                let unplayedRect = CGRect(
                                    x: rect.minX + playedWidth,
                                    y: rect.minY,
                                    width: rect.width - playedWidth,
                                    height: rect.height
                                )
                                context.fill(
                                    Path(roundedRect: unplayedRect, cornerRadius: eventMarkerHeight / 2),
                                    with: .color(AppTheme.info.opacity(isEnabled ? 0.46 : 0.20))
                                )
                            }
                        }
                    }
                    .frame(width: width, height: eventMarkerHeight)
                    .offset(y: trackCenterY - eventMarkerHeight / 2)
                    .allowsHitTesting(false)

                    if let focusedEvent {
                        let rect = focusedMarkerRect(
                            for: focusedEvent,
                            trackWidth: width,
                            markerHeight: trackHeight
                        )
                        let playedWidth = min(max(thumbX - rect.minX, 0), rect.width)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(AppTheme.info.opacity(isEnabled ? 0.92 : 0.38))

                            if playedWidth > 0 {
                                Rectangle()
                                    .fill(Color.white.opacity(isEnabled ? 0.74 : 0.30))
                                    .frame(width: playedWidth)
                            }

                            Capsule()
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.6)
                        }
                        .clipShape(Capsule())
                        .frame(width: rect.width, height: trackHeight)
                        .shadow(
                            color: AppTheme.info.opacity(isEnabled ? 0.24 : 0),
                            radius: 4
                        )
                        .position(x: rect.midX, y: trackCenterY)
                        .transaction { transaction in
                            // This marker is tied to an absolute timeline
                            // coordinate. Animating its offset makes SwiftUI
                            // interpolate from the ZStack's top-left origin.
                            transaction.animation = nil
                        }
                    }

                    Circle()
                        .fill(isEnabled ? AppTheme.brand : Color.secondary.opacity(0.55))
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: AppTheme.brand.opacity(isScrubbing ? 0.24 : 0.14), radius: isScrubbing ? 8 : 4, y: isScrubbing ? 4 : 2)
                        .offset(x: thumbX - thumbSize / 2, y: trackCenterY - thumbSize / 2)
                        .animation(.snappy(duration: 0.16, extraBounce: 0), value: isScrubbing)
                }
                .frame(width: width, height: RecordingTimelineLayout.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(timelineGesture(trackWidth: width))
            }
        }
        .frame(height: RecordingTimelineLayout.height)
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

    private func timelineGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else {
                    return
                }
                if !isScrubbing {
                    HapticFeedback.prepare(.timelineAudioEvent)
                    hapticAudioEventID = nil
                    previousHapticScrubTime = nil
                    withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
                        isScrubbing = true
                    }
                }
                let scrubTime = time(for: value.location.x, trackWidth: trackWidth)
                scrubbedTime = scrubTime
                let dragDistance = hypot(value.translation.width, value.translation.height)
                if dragDistance >= 2 {
                    updateAudioEventHaptic(at: scrubTime)
                }
            }
            .onEnded { value in
                guard isEnabled else {
                    return
                }
                let time = time(for: value.location.x, trackWidth: trackWidth)
                let tapDistance = hypot(value.translation.width, value.translation.height)
                scrubbedTime = nil
                hapticAudioEventID = nil
                previousHapticScrubTime = nil
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

    private func updateAudioEventHaptic(at time: TimeInterval) {
        let focusedEvent = activeAudioEvent(at: time)
        let focusedEventID = focusedEvent?.id

        if focusedEventID != hapticAudioEventID {
            hapticAudioEventID = focusedEventID
            if focusedEventID != nil {
                HapticFeedback.play(.timelineAudioEvent)
                previousHapticScrubTime = time
                return
            }
        }

        if focusedEvent == nil,
           let previousTime = previousHapticScrubTime,
           let crossedEvent = audioEventCrossedEntering(
               from: previousTime,
               to: time
           ),
           crossedEvent.id != hapticAudioEventID {
            hapticAudioEventID = crossedEvent.id
            HapticFeedback.play(.timelineAudioEvent)
        }

        previousHapticScrubTime = time
    }

    private func audioEventCrossedEntering(
        from previousTime: TimeInterval,
        to currentTime: TimeInterval
    ) -> RecordingAudioEvent? {
        if currentTime > previousTime {
            return audioEvents.first {
                $0.startTime > previousTime
                    && $0.startTime <= currentTime
            }
        }
        if currentTime < previousTime {
            return audioEvents.reversed().first {
                $0.endTime < previousTime
                    && $0.endTime >= currentTime
            }
        }
        return nil
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

    private func audioEvent(containing time: TimeInterval) -> RecordingAudioEvent? {
        audioEvents
            .filter { time >= $0.startTime && time <= $0.endTime }
            .max { $0.confidence < $1.confidence }
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
        let remainingWidth = max(trackWidth - markerX, 2)
        let markerWidth = min(max(rawWidth, 2), remainingWidth)
        return CGRect(x: markerX, y: 0, width: markerWidth, height: markerHeight)
    }

    private func focusedMarkerRect(
        for event: RecordingAudioEvent,
        trackWidth: CGFloat,
        markerHeight: CGFloat
    ) -> CGRect {
        let marker = markerRect(
            for: event,
            trackWidth: trackWidth,
            markerHeight: markerHeight
        )
        let width = min(max(marker.width, markerHeight), trackWidth)
        let x = min(max(marker.midX - width / 2, 0), max(trackWidth - width, 0))
        return CGRect(x: x, y: 0, width: width, height: markerHeight)
    }

}

private struct PlaybackUtilityControlLabel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color
    let width: CGFloat
    let isSelected: Bool
    let content: Content

    init(
        tint: Color,
        width: CGFloat,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.width = width
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .foregroundStyle(tint)
            .frame(width: width, height: 42)
            .background {
                Capsule()
                    .fill(
                        isSelected
                            ? tint.opacity(colorScheme == .dark ? 0.18 : 0.13)
                            : AppTheme.raisedControlBackground.opacity(
                                colorScheme == .dark ? 0.48 : 0.78
                            )
                    )
            }
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? tint.opacity(colorScheme == .dark ? 0.46 : 0.34)
                            : Color.white.opacity(
                                colorScheme == .dark ? 0.11 : 0.24
                            ),
                        lineWidth: 0.8
                    )
            }
            .contentShape(Capsule())
            .animation(
                .snappy(duration: 0.18, extraBounce: 0),
                value: isSelected
            )
    }
}

private struct PlaybackAudioEventRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                accessibilityReduceMotion
                    ? 1
                    : configuration.isPressed ? 0.985 : 1
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                accessibilityReduceMotion
                    ? nil
                    : .snappy(duration: 0.12, extraBounce: 0),
                value: configuration.isPressed
            )
    }
}

private struct PlaybackUtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var showsDepthShadow = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Capsule()
                    .fill(AppTheme.hdrWhite.opacity(0.14))
                    .overlay {
                        Capsule()
                            .stroke(AppTheme.hdrWhite.opacity(0.42), lineWidth: 0.8)
                    }
                    .shadow(
                        color: AppTheme.hdrWhite.opacity(0.28),
                        radius: 8
                    )
                    .blendMode(.plusLighter)
                    .opacity(configuration.isPressed && isEnabled ? 1 : 0)
                    .animation(
                        accessibilityReduceMotion
                            ? nil
                            : configuration.isPressed
                                ? .easeOut(duration: 0.14)
                                : .easeInOut(duration: 0.20),
                        value: configuration.isPressed
                    )
                    .allowsHitTesting(false)
            }
            .compositingGroup()
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(accessibilityReduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .shadow(
                color: showsDepthShadow
                    ? utilityShadowColor(isPressed: configuration.isPressed)
                    : .clear,
                radius: configuration.isPressed ? 3 : 7,
                y: configuration.isPressed ? 1 : 4
            )
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.11, extraBounce: 0),
                value: configuration.isPressed
            )
    }

    private func utilityShadowColor(isPressed: Bool) -> Color {
        if colorScheme == .dark {
            return Color.black.opacity(isPressed ? 0.04 : 0.08)
        }
        return Color.black.opacity(isPressed ? 0.06 : 0.12)
    }
}

private struct PlaybackRoundButton: View {
    enum RotationDirection {
        case clockwise
        case counterClockwise
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var rotationEffectTrigger = 0

    let systemImage: String
    let title: Text
    var isPrimary = false
    var rotationDirection: RotationDirection?
    let action: () -> Void

    init(
        systemImage: String,
        title: String,
        isPrimary: Bool = false,
        rotationDirection: RotationDirection? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = Text(verbatim: title)
        self.isPrimary = isPrimary
        self.rotationDirection = rotationDirection
        self.action = action
    }

    init(
        systemImage: String,
        titleResource: LocalizedStringResource,
        isPrimary: Bool = false,
        rotationDirection: RotationDirection? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.title = Text(titleResource)
        self.isPrimary = isPrimary
        self.rotationDirection = rotationDirection
        self.action = action
    }

    var body: some View {
        Button {
            if rotationDirection != nil {
                rotationEffectTrigger &+= 1
            }
            action()
        } label: {
            animatedSymbol
                .contentTransition(.symbolEffect(.replace))
                .frame(width: isPrimary ? 56 : 44, height: isPrimary ? 56 : 44)
                .foregroundStyle(isPrimary ? .white : .primary)
                .background {
                    if isPrimary {
                        Circle()
                            .fill(AppTheme.brand)
                            .opacity(colorScheme == .dark ? 0.88 : 1)
                    } else {
                        Circle()
                            .fill(AppTheme.raisedControlBackground)
                            .opacity(colorScheme == .dark ? 0.48 : 0.82)
                    }
                }
                .overlay {
                    Circle()
                        .stroke(
                            isPrimary
                                ? Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24)
                                : Color.white.opacity(colorScheme == .dark ? 0.11 : 0.24),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(PlaybackRoundButtonStyle(isPrimary: isPrimary, colorScheme: colorScheme))
        .animation(.snappy(duration: 0.18, extraBounce: 0), value: systemImage)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var animatedSymbol: some View {
        let symbol = Image(systemName: systemImage)
            .font(.system(size: isPrimary ? 21 : 17, weight: .semibold))

        if accessibilityReduceMotion {
            symbol
        } else {
            switch rotationDirection {
            case .clockwise:
                symbol
                    .symbolEffect(
                        .rotate.clockwise.byLayer,
                        options: .nonRepeating.speed(1.65),
                        value: rotationEffectTrigger
                    )
            case .counterClockwise:
                symbol
                    .symbolEffect(
                        .rotate.counterClockwise.byLayer,
                        options: .nonRepeating.speed(1.65),
                        value: rotationEffectTrigger
                    )
            case nil:
                symbol
            }
        }
    }
}

private struct PlaybackRoundButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.isEnabled) private var isEnabled

    let isPrimary: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Circle()
                    .fill(
                        isPrimary
                            ? AppTheme.hdrBrand
                            : AppTheme.hdrWhite.opacity(0.16)
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                AppTheme.hdrWhite.opacity(isPrimary ? 0.70 : 0.46),
                                lineWidth: isPrimary ? 1 : 0.8
                            )
                    }
                    .shadow(
                        color: isPrimary
                            ? AppTheme.hdrBrand.opacity(0.58)
                            : AppTheme.hdrWhite.opacity(0.30),
                        radius: isPrimary ? 12 : 8
                    )
                    .blendMode(.plusLighter)
                    .opacity(configuration.isPressed && isEnabled ? 1 : 0)
                    .animation(
                        accessibilityReduceMotion
                            ? nil
                            : configuration.isPressed
                                ? .easeOut(duration: 0.14)
                                : .easeInOut(duration: 0.20),
                        value: configuration.isPressed
                    )
                    .allowsHitTesting(false)
            }
            .compositingGroup()
            .opacity(isEnabled ? 1 : 0.46)
            .scaleEffect(accessibilityReduceMotion ? 1 : (configuration.isPressed ? 0.95 : 1))
            .shadow(
                color: shadowColor(isPressed: configuration.isPressed),
                radius: configuration.isPressed ? (isPrimary ? 5 : 3) : (isPrimary ? 12 : 7),
                y: configuration.isPressed ? (isPrimary ? 2 : 1) : (isPrimary ? 7 : 4)
            )
            .animation(
                accessibilityReduceMotion ? nil : .snappy(duration: 0.12, extraBounce: 0),
                value: configuration.isPressed
            )
    }

    private func shadowColor(isPressed: Bool) -> Color {
        if isPrimary {
            if colorScheme == .dark {
                return AppTheme.brand.opacity(isPressed ? 0.12 : 0.20)
            }
            return AppTheme.brand.opacity(isPressed ? 0.20 : 0.34)
        }
        if colorScheme == .dark {
            return Color.black.opacity(isPressed ? 0.04 : 0.08)
        }
        return Color.black.opacity(isPressed ? 0.06 : 0.12)
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

private struct TranscriptSpeakerLegend: View {
    private struct EdgeFade: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var edgeFade = EdgeFade()

    let speakers: [TranscriptSpeakerPresentation]
    let onEditSpeakers: (() -> Void)?

    private static let edgeFadeWidth: CGFloat = 14

    private var editActionTransition: AnyTransition {
        guard !accessibilityReduceMotion else {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .leading)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .leading))
        )
    }

    private var editActionAnimation: Animation {
        accessibilityReduceMotion
            ? .easeOut(duration: 0.14)
            : .snappy(duration: 0.20, extraBounce: 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Label(
                        localizedFormat(L10n.Recordings.transcriptSpeakersDetectedFormat, speakers.count),
                        systemImage: "person.2.fill"
                    )
                    .foregroundStyle(.secondary)

                    if let onEditSpeakers {
                        HStack(spacing: 8) {
                            Divider()
                                .frame(height: 14)

                            Button {
                                HapticFeedback.play(.menuSelection)
                                onEditSpeakers()
                            } label: {
                                Text(L10n.Common.edit)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                        .transition(editActionTransition)
                    }
                }
                .font(.redditSans(.caption, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(AppTheme.elevatedBackground, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(AppTheme.subtleBorder, lineWidth: 1)
                }
                .animation(editActionAnimation, value: onEditSpeakers != nil)

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
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 1)
        }
        .onScrollGeometryChange(for: EdgeFade.self) { geometry in
            let leadingOffset = max(geometry.visibleRect.minX, 0)
            let trailingOffset = max(
                geometry.contentSize.width - geometry.visibleRect.maxX,
                0
            )

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(.leading, 6)
            .padding(.trailing, 6)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
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

private struct RecordingDetailFactsGrid: View {
    let createdAtText: String
    let durationText: String
    let languageText: String
    let iCloudSyncStatus: RecordingICloudSyncStatus
    let audioPreparationStatus: RecordingAudioPreparationStatus

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
            return AppTheme.privacy
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
            RecordingDetailStorageFactCell(
                iCloudSyncStatus: iCloudSyncStatus,
                iCloudTint: iCloudTint,
                audioPreparationStatus: audioPreparationStatus
            )
        }
    }
}

private struct RecordingDetailStorageFactCell: View {
    let iCloudSyncStatus: RecordingICloudSyncStatus
    let iCloudTint: Color
    let audioPreparationStatus: RecordingAudioPreparationStatus

    private var displayText: String {
        switch audioPreparationStatus {
        case .downloading:
            return localized(L10n.Recordings.downloadingRecordingFromICloud)
        case .failed(let message):
            return message
        case .checking, .preparing, .available:
            return iCloudSyncStatus.displayName
        }
    }

    private var displaySystemImage: String {
        switch audioPreparationStatus {
        case .downloading:
            return "icloud.and.arrow.down"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .checking, .preparing, .available:
            return iCloudSyncStatus.systemImage
        }
    }

    private var displayTint: Color {
        switch audioPreparationStatus {
        case .downloading:
            return AppTheme.brand
        case .failed:
            return AppTheme.danger
        case .checking, .preparing, .available:
            return iCloudTint
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: displaySystemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(displayTint)
                .frame(width: 15)

            Text(displayText)
                .font(.redditSans(.caption, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .recordingDetailFactSurface()
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
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .recordingDetailFactSurface()
    }
}

private struct RecordingDetailFactSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        content
            .background {
                shape
                    .fill(
                        AppTheme.cardBackground.opacity(
                            colorScheme == .dark ? 0.86 : 0.82
                        )
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.68),
                        lineWidth: 0.75
                    )
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.045),
                radius: 4,
                y: 1.5
            )
    }
}

private extension View {
    func recordingDetailFactSurface() -> some View {
        modifier(RecordingDetailFactSurfaceModifier())
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
            let leadingOffset = max(geometry.visibleRect.minX, 0)
            let trailingOffset = max(
                geometry.contentSize.width - geometry.visibleRect.maxX,
                0
            )

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
        .frame(maxWidth: .infinity, alignment: .leading)
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
