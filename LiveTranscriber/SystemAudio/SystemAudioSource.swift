import AVFoundation
import Foundation

enum TranscriptionAudioInput: String, CaseIterable, Identifiable, Sendable {
    case microphone
    case screenAudio

    var id: String { rawValue }
}

enum SystemAudioBackend: String, Equatable, Sendable {
    case replayKitCompatibility
    case screenCaptureKit

    static var preferredForCurrentOS: SystemAudioBackend {
        #if HAS_IOS27_SDK && !targetEnvironment(simulator)
        if #available(iOS 27.0, *) {
            return .screenCaptureKit
        }
        #endif
        return .replayKitCompatibility
    }
}

enum SystemAudioSessionState: Equatable, Sendable {
    case idle
    case awaitingUserApproval
    case waitingForAudio
    case capturing
    case paused
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .failed:
            return false
        case .awaitingUserApproval, .waitingForAudio, .capturing, .paused, .stopping:
            return true
        }
    }
}

struct SystemAudioDiagnostics: Equatable, Sendable {
    var receivedFrames: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var overruns: UInt64 = 0
    var corruptedChunks: UInt64 = 0
    var lastError: String?
}

struct SystemAudioPCMFrame: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let sequence: UInt64
    let presentationTime: TimeInterval
}

enum SystemAudioSourceEvent: Sendable {
    case awaitingUserApproval
    case started
    case waitingForAudio
    case paused
    case resumed
    case heartbeat(Date)
    case diagnostics(SystemAudioDiagnostics)
    case finished
    case cancelled
    case failed(String)
}

protocol SystemAudioSource: AnyObject {
    var backend: SystemAudioBackend { get }
    var frameHandler: (@Sendable (SystemAudioPCMFrame) -> Void)? { get set }
    var eventHandler: (@Sendable (SystemAudioSourceEvent) -> Void)? { get set }

    func start() async throws
    func stop() async
}

@MainActor
final class SystemAudioSessionCoordinator: ObservableObject {
    @Published private(set) var backend = SystemAudioBackend.preferredForCurrentOS
    @Published private(set) var state: SystemAudioSessionState = .idle
    @Published private(set) var lastHeartbeat: Date?
    @Published private(set) var diagnostics = SystemAudioDiagnostics()
    @Published private(set) var completedDraft: RecordingDraft?

    private let transcriber: LiveTranscriptionManager
    private let captionStore: CaptionPresentationStore
    private var source: (any SystemAudioSource)?
    private var noAudioTask: Task<Void, Never>?
    private var isStopping = false
    private var hasReceivedAudio = false

    init(
        transcriber: LiveTranscriptionManager,
        captionStore: CaptionPresentationStore
    ) {
        self.transcriber = transcriber
        self.captionStore = captionStore
        captionStore.updateSessionState(.idle)
    }

    var requiresReplayKitPicker: Bool {
        backend == .replayKitCompatibility
    }

    func startSession() async {
        guard !state.isActive, !transcriber.isRecording, !transcriber.isPreparing else {
            return
        }

        backend = SystemAudioBackend.preferredForCurrentOS
        state = .awaitingUserApproval
        captionStore.updateSessionState(state)
        diagnostics = SystemAudioDiagnostics()
        lastHeartbeat = nil
        completedDraft = nil
        hasReceivedAudio = false
        isStopping = false

        await transcriber.startRecording(
            inputSource: .externalAudio(
                sampleRate: Double(SharedAudioChunkConstants.sampleRate),
                channelCount: SharedAudioChunkConstants.channelCount
            )
        )
        guard transcriber.isRecording,
              let inputHandler = transcriber.externalAudioPCMHandler() else {
            fail(transcriber.errorText ?? String(localized: L10n.ScreenAudio.couldNotPrepare))
            return
        }

        do {
            let newSource = try makeSource()
            newSource.frameHandler = { [weak self] frame in
                inputHandler(
                    frame.buffer,
                    AVAudioTime(
                        sampleTime: AVAudioFramePosition(
                            (frame.presentationTime * frame.buffer.format.sampleRate).rounded()
                        ),
                        atRate: frame.buffer.format.sampleRate
                    )
                )
                Task { @MainActor [weak self] in
                    self?.didReceive(frame)
                }
            }
            newSource.eventHandler = { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handle(event)
                }
            }
            source = newSource
            try await newSource.start()
        } catch {
            await discardPreparedRecording()
            fail(error.localizedDescription)
        }
    }

    @discardableResult
    func stopSession() async -> RecordingDraft? {
        guard state.isActive || transcriber.isRecording else {
            return nil
        }

        isStopping = true
        noAudioTask?.cancel()
        noAudioTask = nil
        state = .stopping
        captionStore.updateSessionState(state)
        let activeSource = source
        source = nil
        await activeSource?.stop()
        let draft = await transcriber.stopRecording()
        finishSessionState()
        return draft
    }

    func cancelSession() async {
        guard state.isActive || transcriber.isRecording || transcriber.isPreparing else {
            finishSessionState()
            return
        }

        isStopping = true
        noAudioTask?.cancel()
        noAudioTask = nil
        let activeSource = source
        source = nil
        await activeSource?.stop()
        await discardPreparedRecording()
        finishSessionState()
    }

    func takeCompletedDraft() -> RecordingDraft? {
        defer { completedDraft = nil }
        return completedDraft
    }

    private func makeSource() throws -> any SystemAudioSource {
        switch backend {
        case .replayKitCompatibility:
            return try ReplayKitSystemAudioSource()
        case .screenCaptureKit:
            #if HAS_IOS27_SDK && !targetEnvironment(simulator)
            if #available(iOS 27.0, *) {
                return IOS27ScreenCaptureSource()
            }
            #endif
            throw SystemAudioSessionError.unsupportedBackend
        }
    }

    private func didReceive(_ frame: SystemAudioPCMFrame) {
        hasReceivedAudio = true
        diagnostics.receivedFrames &+= 1
        lastHeartbeat = Date()
        if state != .capturing {
            state = .capturing
            captionStore.updateSessionState(state)
        }
        noAudioTask?.cancel()
        noAudioTask = nil
    }

    private func handle(_ event: SystemAudioSourceEvent) async {
        switch event {
        case .awaitingUserApproval:
            state = .awaitingUserApproval
        case .started, .waitingForAudio:
            state = .waitingForAudio
            scheduleNoAudioDiagnostic()
        case .paused:
            state = .paused
        case .resumed:
            state = hasReceivedAudio ? .capturing : .waitingForAudio
        case .heartbeat(let date):
            lastHeartbeat = date
        case .diagnostics(let updatedDiagnostics):
            diagnostics = updatedDiagnostics
        case .finished:
            guard !isStopping else { return }
            await finishFromSource()
            return
        case .cancelled:
            guard !isStopping else { return }
            await cancelSession()
            return
        case .failed(let message):
            guard !isStopping else { return }
            await discardPreparedRecording()
            fail(message)
            return
        }
        captionStore.updateSessionState(state)
    }

    private func finishFromSource() async {
        isStopping = true
        noAudioTask?.cancel()
        noAudioTask = nil
        state = .stopping
        captionStore.updateSessionState(state)
        let activeSource = source
        source = nil
        await activeSource?.stop()
        completedDraft = await transcriber.stopRecording()
        finishSessionState()
    }

    private func scheduleNoAudioDiagnostic() {
        noAudioTask?.cancel()
        noAudioTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self,
                  !Task.isCancelled,
                  !self.hasReceivedAudio,
                  self.state == .waitingForAudio else {
                return
            }
            self.diagnostics.lastError = String(localized: L10n.ScreenAudio.noAudioCaptured)
        }
    }

    private func discardPreparedRecording() async {
        if let draft = await transcriber.stopRecording(reportingEmptyInputError: false) {
            try? FileManager.default.removeItem(at: draft.audioURL)
        }
    }

    private func finishSessionState() {
        noAudioTask?.cancel()
        noAudioTask = nil
        source = nil
        state = .idle
        captionStore.updateSessionState(.idle)
        isStopping = false
        hasReceivedAudio = false
    }

    private func fail(_ message: String) {
        diagnostics.lastError = message
        state = .failed(message)
        captionStore.updateSessionState(state)
        source = nil
        isStopping = false
        hasReceivedAudio = false
    }
}

enum SystemAudioSessionError: LocalizedError {
    case appGroupUnavailable
    case unsupportedBackend
    case invalidAudioChunk
    case captureUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return String(localized: L10n.ScreenAudio.appGroupUnavailable)
        case .unsupportedBackend:
            return String(localized: L10n.ScreenAudio.unsupported)
        case .invalidAudioChunk:
            return String(localized: L10n.ScreenAudio.invalidChunk)
        case .captureUnavailable:
            return String(localized: L10n.ScreenAudio.captureUnavailable)
        }
    }
}
