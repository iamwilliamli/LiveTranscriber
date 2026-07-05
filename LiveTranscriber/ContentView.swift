import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var transcriber = LiveTranscriptionManager()
    @StateObject private var recordingStore = RecordingStore()
    @StateObject private var recordingPlayer = RecordingPlaybackController()
    @State private var selectedTab: AppTab = .transcribe
    @State private var incomingRecordingImportURL: URL?
    @State private var pendingOpenRecordingID: RecordingItem.ID?
    @State private var pendingRecordingDraftFromLiveActivity: RecordingDraft?
    @State private var pendingDeepLinkSpeechLocaleReleaseRequest: SpeechLocaleReleaseRequest?
    @State private var speechLocaleErrorMessage: String?
    @AppStorage(OnboardingState.completedDefaultsKey) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainTabs
            } else {
                OnboardingIntroView(transcriber: transcriber) {
                    withAnimation(.easeInOut(duration: 0.32)) {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .font(.redditSans(.body))
        .tint(AppTheme.brand)
        .onOpenURL { url in
            handleOpenedURL(url)
        }
        .alert(
            String(localized: L10n.SpeechText.releaseOldLanguagesTitle),
            isPresented: Binding(
                get: { pendingDeepLinkSpeechLocaleReleaseRequest != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeepLinkSpeechLocaleReleaseRequest = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.SpeechText.releaseOldLanguagesAction), role: .destructive) {
                if let pendingDeepLinkSpeechLocaleReleaseRequest {
                    releaseSpeechLocalesAndStartRecording(pendingDeepLinkSpeechLocaleReleaseRequest)
                }
                pendingDeepLinkSpeechLocaleReleaseRequest = nil
            }
            Button(String(localized: L10n.Common.cancel), role: .cancel) {}
        } message: {
            Text(pendingDeepLinkSpeechLocaleReleaseRequest?.messageText ?? "")
        }
        .alert(
            String(localized: L10n.SpeechText.localeSetupFailed),
            isPresented: Binding(
                get: { speechLocaleErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        speechLocaleErrorMessage = nil
                    }
                }
            )
        ) {
            Button(String(localized: L10n.Common.ok), role: .cancel) {}
        } message: {
            Text(speechLocaleErrorMessage ?? "")
        }
    }

    private var mainTabs: some View {
        TabView(selection: tabSelection) {
            Tab(String(localized: L10n.App.transcribeTab), systemImage: "waveform.and.mic", value: AppTab.transcribe) {
                TranscriptionView(
                    transcriber: transcriber,
                    recordingStore: recordingStore,
                    externalPendingRecordingDraft: $pendingRecordingDraftFromLiveActivity
                )
            }

            Tab(String(localized: L10n.App.recordingsTab), systemImage: "folder", value: AppTab.recordings) {
                RecordingsView(
                    store: recordingStore,
                    transcriber: transcriber,
                    incomingImportURL: $incomingRecordingImportURL,
                    pendingOpenRecordingID: $pendingOpenRecordingID,
                    player: recordingPlayer
                )
            }

            Tab(String(localized: L10n.App.settingsTab), systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(transcriber: transcriber, recordingStore: recordingStore)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await recordingStore.reload()
            await transcriber.refreshSupportedLanguages()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await recordingStore.reload()
            }
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
        case "recording":
            guard let idString = url.pathComponents.dropFirst().first,
                  let id = UUID(uuidString: idString) else {
                return false
            }
            selectedTab = .recordings
            pendingOpenRecordingID = id
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

        guard transcriber.selectedTranscriptionBackend.requiresAppleSpeech else {
            HapticFeedback.play(.recordingStart)
            Task {
                await transcriber.startRecording()
            }
            return
        }

        Task {
            do {
                let preparation = try await transcriber.prepareSpeechLocaleForUse(
                    transcriber.selectedLanguage,
                    preservingLanguageIDs: [transcriber.selectedLanguageID]
                )
                switch preparation {
                case .ready:
                    HapticFeedback.play(.recordingStart)
                    await transcriber.startRecording()
                case .needsRelease(let request):
                    selectedTab = .transcribe
                    pendingDeepLinkSpeechLocaleReleaseRequest = request
                    HapticFeedback.play(.warning)
                }
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
        }
    }

    private func releaseSpeechLocalesAndStartRecording(_ request: SpeechLocaleReleaseRequest) {
        Task {
            do {
                try await transcriber.releaseSpeechLocalesAndReserveTarget(request)
                selectedTab = .transcribe
                HapticFeedback.play(.recordingStart)
                await transcriber.startRecording()
            } catch {
                speechLocaleErrorMessage = error.localizedDescription
                HapticFeedback.play(.failure)
            }
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
