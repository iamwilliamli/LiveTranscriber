import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var transcriber = LiveTranscriptionManager()
    @StateObject private var recordingStore = RecordingStore()

    var body: some View {
        TabView {
            TranscriptionView(transcriber: transcriber, recordingStore: recordingStore)
                .tabItem {
                    Label("转录", systemImage: "waveform.and.mic")
                }

            RecordingsView(store: recordingStore, transcriber: transcriber)
                .tabItem {
                    Label("录音文件", systemImage: "folder")
                }

            SettingsView(transcriber: transcriber, recordingStore: recordingStore)
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
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
            handleLiveActivityURL(url)
        }
    }

    private func handleLiveActivityURL(_ url: URL) {
        guard url.scheme == "livetranscriber",
              url.host == "stop-recording" else {
            return
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
    }
}

#if DEBUG
#Preview("Content") {
    ContentView()
}
#endif
