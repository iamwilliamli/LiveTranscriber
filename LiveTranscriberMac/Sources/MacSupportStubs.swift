import AppKit
import AppIntents
import Foundation
import SwiftUI

/// macOS counterpart of the iOS haptic helper. Maps the strongest feedback
/// events to `NSHapticFeedbackManager` (Force Touch trackpads) and ignores the
/// rest, so shared views can call it unconditionally.
enum HapticFeedback {
    enum Event: Hashable {
        case navigation
        case tabSelection
        case menuSelection
        case primaryAction
        case recordingStart
        case recordingPause
        case recordingResume
        case recordingStop
        case recordingSaved
        case playbackToggle
        case timelineSeek
        case copy
        case importQueued
        case importStart
        case importComplete
        case retranscribeStart
        case retranscribeComplete
        case analysisStart
        case analysisComplete
        case deleteRequested
        case deleteConfirmed
        case blocked
        case warning
        case failure
    }

    static func play(_ event: Event) {
        switch event {
        case .recordingStart, .recordingStop, .recordingSaved, .deleteConfirmed:
            NSHapticFeedbackManager.defaultPerformer.perform(
                .levelChange,
                performanceTime: .default
            )
        case .blocked, .warning, .failure:
            NSHapticFeedbackManager.defaultPerformer.perform(
                .generic,
                performanceTime: .default
            )
        default:
            break
        }
    }
}

struct MacTranscriptionActivitySnapshot: Equatable {
    let startedAt: Date
    let status: String
    let languageName: String
    let latestText: String
    let elapsedSeconds: Int
    let lineCount: Int
    let isRecording: Bool
}

/// Native macOS counterpart of the iOS Live Activity. The shared recording
/// manager publishes the same state into a menu-bar surface so an in-progress
/// transcription remains visible while another app is frontmost.
@MainActor
final class TranscriptionLiveActivityCoordinator: ObservableObject {
    static let shared = TranscriptionLiveActivityCoordinator()

    @Published private(set) var snapshot: MacTranscriptionActivitySnapshot?

    private var dismissalTask: Task<Void, Never>?

    private init() {}

    static func start(
        startedAt: Date,
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int
    ) async {
        shared.dismissalTask?.cancel()
        shared.snapshot = MacTranscriptionActivitySnapshot(
            startedAt: startedAt,
            status: status,
            languageName: languageName,
            latestText: latestText,
            elapsedSeconds: elapsedSeconds,
            lineCount: lineCount,
            isRecording: true
        )
    }

    static func update(
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int,
        isRecording: Bool
    ) async {
        shared.dismissalTask?.cancel()
        shared.snapshot = MacTranscriptionActivitySnapshot(
            startedAt: shared.snapshot?.startedAt
                ?? Date(timeIntervalSinceNow: -TimeInterval(max(elapsedSeconds, 0))),
            status: status,
            languageName: languageName,
            latestText: latestText,
            elapsedSeconds: elapsedSeconds,
            lineCount: lineCount,
            isRecording: isRecording
        )
    }

    static func end(
        status: String,
        languageName: String,
        latestText: String,
        elapsedSeconds: Int,
        lineCount: Int
    ) async {
        shared.dismissalTask?.cancel()
        shared.snapshot = MacTranscriptionActivitySnapshot(
            startedAt: shared.snapshot?.startedAt
                ?? Date(timeIntervalSinceNow: -TimeInterval(max(elapsedSeconds, 0))),
            status: status,
            languageName: languageName,
            latestText: latestText,
            elapsedSeconds: elapsedSeconds,
            lineCount: lineCount,
            isRecording: false
        )
        shared.dismissalTask = Task { @MainActor [weak shared] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            shared?.snapshot = nil
        }
    }
}

struct MacTranscriptionStatusMenu: View {
    @ObservedObject var coordinator: TranscriptionLiveActivityCoordinator
    @ObservedObject var transcriber: LiveTranscriptionManager
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = coordinator.snapshot {
                HStack(spacing: 10) {
                    Image(systemName: snapshot.isRecording ? "record.circle.fill" : "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(snapshot.isRecording ? AppTheme.danger : AppTheme.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: snapshot.status)
                            .font(.headline)
                        Text(verbatim: snapshot.languageName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Text(verbatim: TranscriptionLine.formatTimestamp(Double(snapshot.elapsedSeconds)))
                        .font(.headline.monospacedDigit())
                }

                Divider()

                Text(
                    verbatim: snapshot.latestText.isEmpty
                        ? String(localized: L10n.RecordingStatus.waitingForSpeech)
                        : snapshot.latestText
                )
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

                Label {
                    Text(
                        verbatim: String(
                            format: String(localized: MacL10n.transcriptionLineCountFormat),
                            snapshot.lineCount
                        )
                    )
                } icon: {
                    Image(systemName: "text.bubble")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if snapshot.isRecording {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                if transcriber.isPaused {
                                    await transcriber.resumeRecording()
                                } else {
                                    await transcriber.pauseRecording()
                                }
                            }
                        } label: {
                            Label {
                                Text(transcriber.isPaused ? L10n.Transcription.resume : L10n.Transcription.pause)
                            } icon: {
                                Image(systemName: transcriber.isPaused ? "play.fill" : "pause.fill")
                            }
                        }

                        Button(role: .destructive, action: onStop) {
                            Label {
                                Text(L10n.Transcription.stop)
                            } icon: {
                                Image(systemName: "stop.fill")
                            }
                        }
                    }
                }
            } else {
                Label {
                    Text(MacL10n.transcriptionStatusIdle)
                } icon: {
                    Image(systemName: "waveform")
                }
                .foregroundStyle(.secondary)

                Button(action: onStart) {
                    Label {
                        Text(L10n.Transcription.startRecording)
                    } icon: {
                        Image(systemName: "mic.fill")
                    }
                }
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            } label: {
                Label {
                    Text(MacL10n.showApplication)
                } icon: {
                    Image(systemName: "macwindow")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(width: 330)
    }
}

enum MacQuickRecordingIntentState {
    static let didRequestStart = Notification.Name("MacQuickRecordingIntentState.didRequestStart")
    private static let pendingDefaultsKey = "MacQuickRecordingIntentState.pendingStart"

    static func requestStart() {
        UserDefaults.standard.set(true, forKey: pendingDefaultsKey)
        NotificationCenter.default.post(name: didRequestStart, object: nil)
    }

    static func consumePendingStart() -> Bool {
        let isPending = UserDefaults.standard.bool(forKey: pendingDefaultsKey)
        if isPending {
            UserDefaults.standard.removeObject(forKey: pendingDefaultsKey)
        }
        return isPending
    }
}

struct StartMacQuickRecordingIntent: AppIntent {
    static let title = LocalizedStringResource(
        "control.quick_recording.start",
        defaultValue: "Start Recording",
        table: "Semantic",
        comment: "macOS shortcut action that opens Live Transcriber and starts recording."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "control.quick_recording.description",
        defaultValue: "Open Live Transcriber and start recording.",
        table: "Semantic",
        comment: "Description of the macOS quick recording shortcut."
    ))
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        MacQuickRecordingIntentState.requestStart()
        return .result()
    }
}
