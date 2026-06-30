import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var transcriber = LiveTranscriptionManager()
    @StateObject private var recordingStore = RecordingStore()
    @StateObject private var recordingPlayer = RecordingPlaybackController()
    @State private var selectedTab: AppTab = .transcribe
    @State private var incomingRecordingImportURL: URL?
    @State private var pendingRecordingDraftFromLiveActivity: RecordingDraft?

    var body: some View {
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
                    incomingImportURL: $incomingRecordingImportURL,
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
        incomingRecordingImportURL = url
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
}

private enum AppTab: Hashable {
    case transcribe
    case recordings
    case settings
}

#if DEBUG
#Preview("Content") {
    ContentView()
}
#endif
