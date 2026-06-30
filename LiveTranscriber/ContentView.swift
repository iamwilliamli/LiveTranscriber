import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var transcriber = LiveTranscriptionManager()
    @StateObject private var recordingStore = RecordingStore()
    @StateObject private var recordingPlayer = RecordingPlaybackController()
    @State private var selectedTab: AppTab = .transcribe
    @State private var pendingRecordingDraftFromLiveActivity: RecordingDraft?
    @State private var selectedRecordingForDetail: RecordingItem?
    @State private var recordingsSearchText = ""
    @State private var showsRecordingImporter = false
    @State private var isImportingRecording = false
    @State private var pendingRecordingImport: PendingRecordingImport?
    @State private var recordingImportErrorMessage: String?
    @State private var isShowingRecordingsMap = false

    var body: some View {
        NavigationStack {
            TabView(selection: tabSelection) {
                Tab("转录", systemImage: "waveform.and.mic", value: AppTab.transcribe) {
                    TranscriptionView(
                        transcriber: transcriber,
                        recordingStore: recordingStore,
                        externalPendingRecordingDraft: $pendingRecordingDraftFromLiveActivity
                    )
                }

                Tab("录音文件", systemImage: "folder", value: AppTab.recordings) {
                    RecordingsView(
                        store: recordingStore,
                        transcriber: transcriber,
                        searchText: $recordingsSearchText,
                        selectedRecording: $selectedRecordingForDetail,
                        player: recordingPlayer
                    )
                }

                Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView(transcriber: transcriber, recordingStore: recordingStore)
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .font(.redditSans(.body))
            .tint(AppTheme.brand)
            .toolbar(selectedTab == .transcribe ? .hidden : .visible, for: .navigationBar)
            .navigationTitle(rootNavigationTitle)
            .navigationBarTitleDisplayMode(selectedTab == .settings ? .inline : .large)
            .toolbar {
                if selectedTab == .recordings {
                    recordingsToolbar
                }
            }
            .navigationDestination(item: $selectedRecordingForDetail) { item in
                RecordingDetailView(
                    item: item,
                    store: recordingStore,
                    transcriber: transcriber,
                    player: recordingPlayer
                )
            }
        }
        .fileImporter(
            isPresented: $showsRecordingImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleRecordingImportResult(result)
        }
        .sheet(isPresented: $isShowingRecordingsMap) {
            RecordingMapView(store: recordingStore, transcriber: transcriber, player: recordingPlayer)
        }
        .confirmationDialog(
            "选择转录语言",
            isPresented: Binding(
                get: { pendingRecordingImport != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingRecordingImport = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRecordingImport {
                ForEach(transcriber.supportedLanguages) { language in
                    Button {
                        importRecording(from: pendingRecordingImport.url, language: language)
                    } label: {
                        Label(
                            language.displayName,
                            systemImage: language.id == transcriber.selectedLanguageID ? "checkmark" : "globe"
                        )
                    }
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("导入录音")
        }
        .alert(
            "导入失败",
            isPresented: Binding(
                get: { recordingImportErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        recordingImportErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(recordingImportErrorMessage ?? "")
        }
        .task {
            await recordingStore.reload()
            await transcriber.refreshSupportedLanguages()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await recordingStore.reload()
            }
        }
        .onOpenURL { url in
            handleOpenedURL(url)
        }
    }

    private var tabSelection: Binding<AppTab> {
        Binding {
            selectedTab
        } set: { newTab in
            guard newTab != selectedTab else {
                return
            }

            selectedTab = newTab
            HapticFeedback.play(.tabSelection)
        }
    }

    private func handleOpenedURL(_ url: URL) {
        if handleAppRouteURL(url) {
            return
        }

        if handleLiveActivityURL(url) {
            return
        }

        guard isSupportedAudioImportURL(url) else {
            return
        }

        selectedTab = .recordings
        queueRecordingImport(from: url)
    }

    @discardableResult
    private func handleAppRouteURL(_ url: URL) -> Bool {
        guard url.scheme == "livetranscriber",
              let host = url.host else {
            return false
        }

        switch host {
        case "record", "transcribe":
            selectedTab = .transcribe
            if shouldStartRecording(from: url) {
                startRecordingFromDeepLink()
                return true
            }
        case "recordings", "files":
            selectedTab = .recordings
        case "settings":
            selectedTab = .settings
        default:
            return false
        }

        HapticFeedback.play(.menuSelection)
        return true
    }

    private func shouldStartRecording(from url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        return components.queryItems?.contains { item in
            item.name == "start" && item.value != "0"
        } ?? false
    }

    private func startRecordingFromDeepLink() {
        guard !transcriber.isRecording, !transcriber.isPreparing else {
            HapticFeedback.play(.menuSelection)
            return
        }

        HapticFeedback.play(.recordingStart)
        Task {
            await transcriber.startRecording()
        }
    }

    @discardableResult
    private func handleLiveActivityURL(_ url: URL) -> Bool {
        guard url.scheme == "livetranscriber",
              url.host == "stop-recording" else {
            return false
        }

        Task {
            HapticFeedback.play(.recordingStop)
            if let draft = await transcriber.stopRecording() {
                selectedTab = .transcribe
                pendingRecordingDraftFromLiveActivity = draft
            } else {
                HapticFeedback.play(.warning)
            }
        }
        return true
    }

    private func isSupportedAudioImportURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let supportedExtensions: Set<String> = ["wav", "m4a", "mp3", "aac", "aif", "aiff", "caf"]
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private var rootNavigationTitle: LocalizedStringKey {
        switch selectedTab {
        case .transcribe:
            return ""
        case .recordings:
            return "录音文件"
        case .settings:
            return "设置"
        }
    }

    @ToolbarContentBuilder
    private var recordingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                if isImportingRecording {
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
                    .accessibilityLabel("地图")

                    Divider()
                        .frame(height: 18)
                        .fixedSize()

                    Button {
                        HapticFeedback.play(.primaryAction)
                        showsRecordingImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 32, height: 28)
                    }
                    .disabled(isImportingRecording || pendingRecordingImport != nil || transcriber.isRecording || transcriber.isPreparing)
                    .accessibilityLabel("导入录音")
                }
                .fixedSize()
            }
        }
    }

    private func handleRecordingImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                HapticFeedback.play(.warning)
                return
            }
            queueRecordingImport(from: url)
        case .failure(let error):
            recordingImportErrorMessage = error.localizedDescription
            HapticFeedback.play(.failure)
        }
    }

    private func queueRecordingImport(from url: URL) {
        guard !isImportingRecording else {
            HapticFeedback.play(.blocked)
            return
        }

        selectedRecordingForDetail = nil
        pendingRecordingImport = PendingRecordingImport(url: url)
        HapticFeedback.play(.importQueued)
    }

    private func importRecording(from url: URL, language: TranscriptionLanguage) {
        guard !isImportingRecording else {
            HapticFeedback.play(.blocked)
            return
        }

        pendingRecordingImport = nil
        isImportingRecording = true
        HapticFeedback.play(.importStart)
        Task {
            do {
                _ = try await recordingStore.importRecording(
                    from: url,
                    language: language,
                    loudnessProcessingEnabled: transcriber.isLoudnessProcessingEnabled
                )
                HapticFeedback.play(.importComplete)
            } catch {
                recordingImportErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
            isImportingRecording = false
        }
    }
}

private enum AppTab: Hashable {
    case transcribe
    case recordings
    case settings
}

private struct PendingRecordingImport: Identifiable {
    let id = UUID()
    let url: URL
}

#if DEBUG
#Preview("Content") {
    ContentView()
}
#endif
