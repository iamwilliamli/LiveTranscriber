import AVFoundation
import Foundation
import ReplayKit
import SwiftUI

struct ReplayKitBroadcastPicker: UIViewRepresentable {
    static let extensionBundleIdentifier = "com.iamwilliamli.LiveTranscriber.BroadcastUpload"

    func makeUIView(context: Context) -> ReplayKitBroadcastPickerContainerView {
        let container = ReplayKitBroadcastPickerContainerView(
            frame: CGRect(x: 0, y: 0, width: 180, height: 44)
        )
        configure(container.picker)
        return container
    }

    func updateUIView(_ container: ReplayKitBroadcastPickerContainerView, context: Context) {
        configure(container.picker)
        container.setNeedsLayout()
    }

    private func configure(_ picker: RPSystemBroadcastPickerView) {
        picker.preferredExtension = Self.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        // TranscriptionView supplies the visible label. Keep the native picker
        // transparent so its system-owned button can cover the complete capsule.
        picker.tintColor = .clear
        picker.backgroundColor = .clear
    }
}

final class ReplayKitBroadcastPickerContainerView: UIView {
    let picker: RPSystemBroadcastPickerView

    override init(frame: CGRect) {
        picker = RPSystemBroadcastPickerView(frame: frame)
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(picker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds

        // On iOS 26 the picker creates its private button using the initial
        // frame. SwiftUI can resize the representable later without resizing
        // that button, leaving a visible control that cannot be tapped. Keep the
        // system button aligned with the full SwiftUI-provided hit target.
        for subview in picker.subviews {
            subview.frame = picker.bounds
            subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
    }
}

final class ReplayKitSystemAudioSource: SystemAudioSource, @unchecked Sendable {
    let backend: SystemAudioBackend = .replayKitCompatibility
    var frameHandler: (@Sendable (SystemAudioPCMFrame) -> Void)?
    var eventHandler: (@Sendable (SystemAudioSourceEvent) -> Void)?

    private let consumer: SharedAudioChunkConsumer

    init(directory: SharedAudioChunkDirectory? = nil) throws {
        consumer = SharedAudioChunkConsumer(directory: try directory ?? SharedAudioChunkDirectory())
    }

    func start() async throws {
        consumer.frameHandler = { [weak self] frame in
            self?.frameHandler?(frame)
        }
        consumer.eventHandler = { [weak self] event in
            self?.eventHandler?(event)
        }
        try consumer.start()
        eventHandler?(.awaitingUserApproval)
    }

    func stop() async {
        consumer.stop()
    }
}

final class SharedAudioChunkConsumer: @unchecked Sendable {
    var frameHandler: (@Sendable (SystemAudioPCMFrame) -> Void)?
    var eventHandler: (@Sendable (SystemAudioSourceEvent) -> Void)?

    private let directory: SharedAudioChunkDirectory
    private let queue = DispatchQueue(
        label: "com.iamwilliamli.LiveTranscriber.screen-audio-consumer",
        qos: .userInitiated
    )
    private var timer: DispatchSourceTimer?
    private var activeSessionID: UUID?
    private var lastState: SharedAudioTransportState?
    private var expectedSequence: UInt64?
    private var consumedFrameCount: UInt64 = 0
    private var diagnostics = SystemAudioDiagnostics()
    private var isRunning = false
    private var didEmitFinished = false

    init(directory: SharedAudioChunkDirectory) {
        self.directory = directory
    }

    func start() throws {
        try directory.prepare()
        try directory.removeTerminalActiveSession()
        try directory.cleanupExpiredSessions()
        queue.sync {
            guard !isRunning else { return }
            activeSessionID = nil
            lastState = nil
            expectedSequence = nil
            consumedFrameCount = 0
            diagnostics = SystemAudioDiagnostics()
            didEmitFinished = false
            isRunning = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            isRunning = false
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
        }
    }

    private func poll() {
        guard isRunning else { return }

        let metadata: SharedAudioSessionMetadata
        do {
            guard let loadedMetadata = try directory.loadActiveMetadata() else {
                return
            }
            metadata = loadedMetadata
        } catch {
            recordError(error.localizedDescription, corruptedChunk: false)
            return
        }

        if activeSessionID != metadata.sessionID {
            activeSessionID = metadata.sessionID
            lastState = nil
            expectedSequence = nil
            consumedFrameCount = 0
            diagnostics = SystemAudioDiagnostics()
            didEmitFinished = false
            eventHandler?(.started)
        }

        eventHandler?(.heartbeat(metadata.heartbeat))
        diagnostics.overruns = metadata.overrunCount
        diagnostics.droppedFrames = max(diagnostics.droppedFrames, metadata.droppedChunkCount)
        emitStateChangeIfNeeded(metadata)
        consumeReadyChunks(sessionID: metadata.sessionID)

        if metadata.state == .finished,
           (try? directory.readyChunkURLs(sessionID: metadata.sessionID).isEmpty) == true,
           !didEmitFinished {
            didEmitFinished = true
            eventHandler?(.diagnostics(diagnostics))
            eventHandler?(.finished)
            try? directory.removeSession(metadata.sessionID)
        }
    }

    private func emitStateChangeIfNeeded(_ metadata: SharedAudioSessionMetadata) {
        guard metadata.state != lastState else { return }
        lastState = metadata.state
        switch metadata.state {
        case .waitingForAudio:
            eventHandler?(.waitingForAudio)
        case .capturing:
            eventHandler?(.resumed)
        case .paused:
            eventHandler?(.paused)
        case .finished:
            break
        case .failed:
            eventHandler?(.failed(metadata.errorMessage ?? String(localized: L10n.ScreenAudio.captureFailed)))
        }
    }

    private func consumeReadyChunks(sessionID: UUID) {
        let urls: [URL]
        do {
            urls = try directory.readyChunkURLs(sessionID: sessionID)
        } catch {
            recordError(error.localizedDescription, corruptedChunk: false)
            return
        }

        for url in urls {
            guard isRunning else { return }
            guard let sequence = SharedAudioChunkDirectory.sequence(from: url) else {
                diagnostics.corruptedChunks &+= 1
                try? directory.removeChunk(at: url)
                continue
            }

            if let expectedSequence, sequence > expectedSequence {
                diagnostics.droppedFrames &+= sequence - expectedSequence
            }

            do {
                let data = try directory.readChunk(at: url)
                let buffer = try SystemAudioPCMNormalizer.buffer(from: data)
                let presentationTime = Double(consumedFrameCount)
                    / Double(SharedAudioChunkConstants.sampleRate)
                let frame = SystemAudioPCMFrame(
                    buffer: buffer,
                    sequence: sequence,
                    presentationTime: presentationTime
                )
                frameHandler?(frame)
                consumedFrameCount &+= UInt64(buffer.frameLength)
                expectedSequence = sequence &+ 1
                try directory.removeChunk(at: url)
            } catch {
                recordError(error.localizedDescription, corruptedChunk: true)
                try? directory.removeChunk(at: url)
                expectedSequence = sequence &+ 1
            }
        }

        eventHandler?(.diagnostics(diagnostics))
    }

    private func recordError(_ message: String, corruptedChunk: Bool) {
        diagnostics.lastError = message
        if corruptedChunk {
            diagnostics.corruptedChunks &+= 1
        }
        eventHandler?(.diagnostics(diagnostics))
    }
}
