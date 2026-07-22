#if HAS_IOS27_SDK && !targetEnvironment(simulator)
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@available(iOS 27.0, *)
final class IOS27ScreenCaptureSource: NSObject, SystemAudioSource, SCContentSharingPickerObserver, SCStreamDelegate, @unchecked Sendable {
    let backend: SystemAudioBackend = .screenCaptureKit
    var frameHandler: (@Sendable (SystemAudioPCMFrame) -> Void)?
    var eventHandler: (@Sendable (SystemAudioSourceEvent) -> Void)?

    private let sampleQueue = DispatchQueue(
        label: "com.iamwilliamli.LiveTranscriber.ios27-screen-audio",
        qos: .userInitiated
    )
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var router: IOS27ScreenCaptureAudioRouter?
    private var isStopping = false

    func start() async throws {
        try await MainActor.run {
            let picker = SCContentSharingPicker.shared
            guard picker.isAvailable else {
                throw SystemAudioSessionError.captureUnavailable
            }
            var configuration = SCContentSharingPickerConfiguration()
            configuration.showsMicrophoneControl = false
            configuration.showsCameraControl = false
            picker.defaultConfiguration = configuration
            picker.add(self)
            picker.isActive = true
            eventHandler?(.awaitingUserApproval)
            picker.present()
        }
    }

    func stop() async {
        let activeStream = stateLock.withLock {
            isStopping = true
            let activeStream = stream
            stream = nil
            router = nil
            return activeStream
        }

        if let activeStream {
            try? await activeStream.stopCapture()
        }
        await MainActor.run {
            let picker = SCContentSharingPicker.shared
            picker.isActive = false
            picker.remove(self)
        }
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        eventHandler?(.cancelled)
    }

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { [weak self] in
            await self?.beginCapture(filter: filter)
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        eventHandler?(.failed(error.localizedDescription))
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let shouldReport = stateLock.withLock { !isStopping }
        if shouldReport {
            eventHandler?(.failed(error.localizedDescription))
        }
    }

    private func beginCapture(filter: SCContentFilter) async {
        let alreadyHasStream = stateLock.withLock { stream != nil }
        guard !alreadyHasStream else { return }

        let router = IOS27ScreenCaptureAudioRouter(
            frameHandler: { [weak self] frame in
                self?.frameHandler?(frame)
            },
            eventHandler: { [weak self] event in
                self?.eventHandler?(event)
            }
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.capturesAudio = true
        // iOS 27 devices can reject a 16 kHz mono capture request with
        // kAudioDeviceUnsupportedFormatError (OSStatus "!dat"). Capture in
        // ScreenCaptureKit's native format and normalize after delivery.
        configuration.excludesCurrentProcessAudio = true

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        do {
            try stream.addStreamOutput(
                router,
                type: .audio,
                sampleHandlerQueue: sampleQueue
            )
            stateLock.withLock {
                self.stream = stream
                self.router = router
                isStopping = false
            }
            eventHandler?(.started)
            try await stream.startCapture()
            eventHandler?(.waitingForAudio)
            await MainActor.run {
                SCContentSharingPicker.shared.isActive = false
            }
        } catch {
            stateLock.withLock {
                self.stream = nil
                self.router = nil
            }
            eventHandler?(.failed(error.localizedDescription))
        }
    }
}

@available(iOS 27.0, *)
private final class IOS27ScreenCaptureAudioRouter: NSObject, SCStreamOutput, @unchecked Sendable {
    private let normalizer = SystemAudioPCMNormalizer()
    private let frameHandler: @Sendable (SystemAudioPCMFrame) -> Void
    private let eventHandler: @Sendable (SystemAudioSourceEvent) -> Void
    private var sequence: UInt64 = 0
    private var accumulatedFrames: UInt64 = 0
    private var didReceiveFirstBuffer = false
    private var diagnostics = SystemAudioDiagnostics()

    init(
        frameHandler: @escaping @Sendable (SystemAudioPCMFrame) -> Void,
        eventHandler: @escaping @Sendable (SystemAudioSourceEvent) -> Void
    ) {
        self.frameHandler = frameHandler
        self.eventHandler = eventHandler
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio else { return }
        do {
            let buffer = try normalizer.normalize(sampleBuffer)
            let presentationTime = Double(accumulatedFrames)
                / Double(SharedAudioChunkConstants.sampleRate)
            frameHandler(
                SystemAudioPCMFrame(
                    buffer: buffer,
                    sequence: sequence,
                    presentationTime: presentationTime
                )
            )
            sequence &+= 1
            accumulatedFrames &+= UInt64(buffer.frameLength)
            diagnostics.receivedFrames &+= 1
            if !didReceiveFirstBuffer {
                didReceiveFirstBuffer = true
                eventHandler(.resumed)
            }
            eventHandler(.heartbeat(Date()))
        } catch {
            diagnostics.droppedFrames &+= 1
            diagnostics.lastError = error.localizedDescription
            eventHandler(.diagnostics(diagnostics))
        }
    }
}
#endif
