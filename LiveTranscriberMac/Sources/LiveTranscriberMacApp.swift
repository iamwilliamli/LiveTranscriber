import AppKit
import Combine
import SwiftUI

@main
struct LiveTranscriberMacApp: App {
    @StateObject private var recordingStore = RecordingStore()
    @StateObject private var transcriber = LiveTranscriptionManager()
    @StateObject private var transcriptionStatus = TranscriptionLiveActivityCoordinator.shared
    @StateObject private var router = MacAppRouter()
    @StateObject private var systemAudioCapture = MacSystemAudioCaptureController()
    @AppStorage(MacOnboardingState.completedDefaultsKey) private var hasCompletedOnboarding = false
    @AppStorage(MacAppLanguage.defaultsKey) private var appLanguageRawValue = MacAppLanguage.system.rawValue
    @State private var isShowingLaunchSplash = UserDefaults.standard.bool(
        forKey: MacOnboardingState.completedDefaultsKey
    )

    private var appLanguage: MacAppLanguage {
        MacAppLanguage(rawValue: appLanguageRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ZStack {
                        if !isShowingLaunchSplash {
                            MacRootView()
                                .transition(.opacity)
                        }

                        if isShowingLaunchSplash {
                            LaunchSplashView {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    isShowingLaunchSplash = false
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                } else {
                    MacOnboardingView(transcriber: transcriber) {
                        hasCompletedOnboarding = true
                    }
                }
            }
            .environmentObject(recordingStore)
            .environmentObject(transcriber)
            .environmentObject(router)
            .environmentObject(systemAudioCapture)
            .environment(\.locale, appLanguage.locale)
            .frame(minWidth: 820, minHeight: 560)
            .onOpenURL { url in
                dismissLaunchSplash()
                router.handle(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: MacQuickRecordingIntentState.didRequestStart)) { _ in
                dismissLaunchSplash()
                router.requestedDestination = .transcribe
                router.shouldStartRecording = true
            }
            .task {
                if MacQuickRecordingIntentState.consumePendingStart() {
                    dismissLaunchSplash()
                    router.requestedDestination = .transcribe
                    router.shouldStartRecording = true
                }
            }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            MacSettingsView()
                .environmentObject(recordingStore)
                .environmentObject(transcriber)
                .environment(\.locale, appLanguage.locale)
        }

        MenuBarExtra {
            MacTranscriptionStatusMenu(
                coordinator: transcriptionStatus,
                transcriber: transcriber,
                onStart: {
                    router.requestedDestination = .transcribe
                    router.shouldStartRecording = true
                    activateMainWindow()
                },
                onStop: {
                    router.requestedDestination = .transcribe
                    router.shouldStopRecording = true
                    activateMainWindow()
                }
            )
            .environment(\.locale, appLanguage.locale)
        } label: {
            Image(
                systemName: transcriptionStatus.snapshot?.isRecording == true
                    ? "waveform.circle.fill"
                    : "waveform.circle"
            )
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor
    private func activateMainWindow() {
        dismissLaunchSplash()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func dismissLaunchSplash() {
        guard isShowingLaunchSplash else {
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            isShowingLaunchSplash = false
        }
    }
}
