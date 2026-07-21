import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

enum MacCaptureError: LocalizedError {
    case recordingDirectoryUnavailable
    case microphonePermissionDenied
    case noAudioSamples
    case audioWriterFailed(String)

    var errorDescription: String? {
        switch self {
        case .recordingDirectoryUnavailable:
            return String(localized: MacL10n.systemAudioStorageUnavailable)
        case .microphonePermissionDenied:
            return String(localized: MacL10n.systemAudioMicrophonePermissionDenied)
        case .noAudioSamples:
            return String(localized: MacL10n.systemAudioNoSamples)
        case .audioWriterFailed(let message):
            return String(
                format: String(localized: MacL10n.systemAudioWriterFailedFormat),
                message
            )
        }
    }
}

// Every mutable operation is serialized by the system-audio controller's sample queue.
final class MacCaptureAudioWriter: @unchecked Sendable {
    let outputURL: URL

    private var assetWriter: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private(set) var hasWrittenSamples = false
    private var terminalError: Error?

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer), terminalError == nil else {
            return
        }

        do {
            if assetWriter == nil {
                try prepareWriter(using: sampleBuffer)
            }
            guard let assetWriter,
                  let writerInput,
                  assetWriter.status == .writing,
                  writerInput.isReadyForMoreMediaData else {
                return
            }
            if writerInput.append(sampleBuffer) {
                hasWrittenSamples = true
            } else if let error = assetWriter.error {
                terminalError = error
            }
        } catch {
            terminalError = error
        }
    }

    func finish(_ completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        if let terminalError {
            assetWriter?.cancelWriting()
            completion(.failure(terminalError))
            return
        }
        guard hasWrittenSamples,
              let assetWriter,
              let writerInput else {
            completion(.failure(MacCaptureError.noAudioSamples))
            return
        }

        writerInput.markAsFinished()
        assetWriter.finishWriting { [outputURL] in
            if assetWriter.status == .completed {
                completion(.success(outputURL))
            } else {
                completion(
                    .failure(
                        assetWriter.error
                            ?? MacCaptureError.audioWriterFailed("Unknown AVAssetWriter failure")
                    )
                )
            }
        }
    }

    func cancel() {
        writerInput?.markAsFinished()
        assetWriter?.cancelWriting()
    }

    private func prepareWriter(using sampleBuffer: CMSampleBuffer) throws {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                  formatDescription
              )?.pointee else {
            throw MacCaptureError.audioWriterFailed("Missing source audio format")
        }

        let sampleRate = basicDescription.mSampleRate > 0
            ? basicDescription.mSampleRate
            : 48_000
        let channelCount = max(Int(basicDescription.mChannelsPerFrame), 1)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: channelCount == 1 ? 96_000 : 160_000,
        ]

        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: outputSettings,
            sourceFormatHint: formatDescription
        )
        writerInput.expectsMediaDataInRealTime = true
        guard assetWriter.canAdd(writerInput) else {
            throw MacCaptureError.audioWriterFailed("Unsupported source audio format")
        }
        assetWriter.add(writerInput)
        guard assetWriter.startWriting() else {
            throw assetWriter.error
                ?? MacCaptureError.audioWriterFailed("AVAssetWriter did not start")
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        assetWriter.startSession(
            atSourceTime: presentationTime.isNumeric ? presentationTime : .zero
        )
        self.assetWriter = assetWriter
        self.writerInput = writerInput
    }
}

final class MacCaptureSampleRouter: NSObject, SCStreamOutput, @unchecked Sendable {
    let systemAudioWriter: MacCaptureAudioWriter?
    let microphoneAudioWriter: MacCaptureAudioWriter?
    private let systemAudioSampleHandler: (@Sendable (CMSampleBuffer) -> Void)?
    private let stateLock = NSLock()
    private var isPaused = false

    init(
        systemAudioWriter: MacCaptureAudioWriter?,
        microphoneAudioWriter: MacCaptureAudioWriter?,
        systemAudioSampleHandler: (@Sendable (CMSampleBuffer) -> Void)? = nil
    ) {
        self.systemAudioWriter = systemAudioWriter
        self.microphoneAudioWriter = microphoneAudioWriter
        self.systemAudioSampleHandler = systemAudioSampleHandler
    }

    func setPaused(_ paused: Bool) {
        stateLock.lock()
        isPaused = paused
        stateLock.unlock()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        stateLock.lock()
        let shouldDropSample = isPaused
        stateLock.unlock()
        guard !shouldDropSample else {
            return
        }

        switch type {
        case .audio:
            systemAudioWriter?.append(sampleBuffer)
            systemAudioSampleHandler?(sampleBuffer)
        case .microphone:
            microphoneAudioWriter?.append(sampleBuffer)
        case .screen:
            break
        @unknown default:
            break
        }
    }
}
