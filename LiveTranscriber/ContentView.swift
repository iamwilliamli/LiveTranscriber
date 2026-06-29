import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var transcriber = LiveTranscriptionManager()
    @StateObject private var recordingStore = RecordingStore()
    @State private var selectedTab: AppTab = .transcribe
    @State private var incomingRecordingImportURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            TranscriptionView(transcriber: transcriber, recordingStore: recordingStore)
                .tabItem {
                    Label("转录", systemImage: "waveform.and.mic")
                }
                .tag(AppTab.transcribe)

            RecordingsView(
                store: recordingStore,
                transcriber: transcriber,
                incomingImportURL: $incomingRecordingImportURL
            )
                .tabItem {
                    Label("录音文件", systemImage: "folder")
                }
                .tag(AppTab.recordings)

            SettingsView(transcriber: transcriber, recordingStore: recordingStore)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
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

    private func handleOpenedURL(_ url: URL) {
        if handleLiveActivityURL(url) {
            return
        }

        guard isSupportedAudioImportURL(url) else {
            return
        }

        selectedTab = .recordings
        incomingRecordingImportURL = url
        HapticFeedback.play(.importQueued)
    }

    @discardableResult
    private func handleLiveActivityURL(_ url: URL) -> Bool {
        guard url.scheme == "livetranscriber",
              url.host == "stop-recording" else {
            return false
        }

        Task {
            HapticFeedback.play(.recordingStop)
            if let draft = await transcriber.stopRecording(),
               await recordingStore.save(draft) != nil {
                HapticFeedback.play(.recordingSaved)
                await recordingStore.reload()
                transcriber.clearTranscript()
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
