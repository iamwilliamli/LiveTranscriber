import AVFoundation
import Combine
import CoreMedia
import Foundation
import ScreenCaptureKit

struct MacSystemAudioCaptureResult: Sendable {
    let audioURL: URL
    let stagingDirectoryURL: URL
    let startedAt: Date
    let durationSeconds: Double
    let sourceName: String
}

/// Captures audio from a user-selected display, app, or window. The saved
/// output is a normal M4A recording: system audio and microphone audio are
/// mixed together when both tracks contain samples.
@MainActor
final class MacSystemAudioCaptureController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case sourceSelected
        case starting
        case recording
        case stopping
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var selectedSourceName: String?
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var warningMessage: String?

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(
        label: "com.iamwilliamli.LiveTranscriber.mac.system-audio",
        qos: .userInitiated
    )
    private var selectedFilter: SCContentFilter?
    private var stream: SCStream?
    private var sampleRouter: MacCaptureSampleRouter?
    private var systemAudioWriter: MacCaptureAudioWriter?
    private var microphoneAudioWriter: MacCaptureAudioWriter?
    private var stagingDirectoryURL: URL?
    private var startedAt: Date?
    private var activeSegmentStartedAt: Date?
    private var accumulatedActiveDuration: TimeInterval = 0
    private var elapsedTask: Task<Void, Never>?
    private var includesMicrophone = false

    override init() {
        super.init()
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [
            .singleDisplay,
            .singleWindow,
            .singleApplication,
        ]
        configuration.allowsChangingSelectedContent = false
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            configuration.excludedBundleIDs = [bundleIdentifier]
        }
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        picker.add(self)
        picker.isActive = true
    }

    deinit {
        elapsedTask?.cancel()
        picker.remove(self)
    }

    var hasSelectedSource: Bool {
        selectedFilter != nil
    }

    var isCapturing: Bool {
        phase == .starting || phase == .recording || phase == .stopping
    }

    var canChooseSource: Bool {
        !isCapturing
    }

    func presentSourcePicker() {
        guard canChooseSource else {
            return
        }
        errorMessage = nil
        picker.isActive = true
        picker.present()
    }

    @discardableResult
    func startCapture(
        includesMicrophone: Bool,
        systemAudioSampleHandler: (@Sendable (CMSampleBuffer) -> Void)? = nil
    ) async -> Bool {
        guard let selectedFilter else {
            presentSourcePicker()
            return false
        }
        guard !isCapturing else {
            return false
        }

        phase = .starting
        errorMessage = nil
        warningMessage = nil
        elapsedSeconds = 0
        isPaused = false
        accumulatedActiveDuration = 0
        picker.isActive = false

        do {
            if includesMicrophone {
                try await authorizeMicrophone()
            }
            let directoryURL = try Self.makeStagingDirectory()
            let stem = UUID().uuidString.lowercased()
            let systemAudioURL = directoryURL.appendingPathComponent("\(stem).system.m4a")
            let microphoneAudioURL = directoryURL.appendingPathComponent("\(stem).microphone.m4a")
            let systemAudioWriter = MacCaptureAudioWriter(outputURL: systemAudioURL)
            let microphoneAudioWriter = includesMicrophone
                ? MacCaptureAudioWriter(outputURL: microphoneAudioURL)
                : nil
            let sampleRouter = MacCaptureSampleRouter(
                systemAudioWriter: systemAudioWriter,
                microphoneAudioWriter: microphoneAudioWriter,
                systemAudioSampleHandler: systemAudioSampleHandler
            )
            let stream = SCStream(
                filter: selectedFilter,
                configuration: Self.makeStreamConfiguration(
                    includesMicrophone: includesMicrophone
                ),
                delegate: self
            )
            try stream.addStreamOutput(
                sampleRouter,
                type: .audio,
                sampleHandlerQueue: sampleQueue
            )
            if includesMicrophone {
                try stream.addStreamOutput(
                    sampleRouter,
                    type: .microphone,
                    sampleHandlerQueue: sampleQueue
                )
            }

            self.stream = stream
            self.sampleRouter = sampleRouter
            self.systemAudioWriter = systemAudioWriter
            self.microphoneAudioWriter = microphoneAudioWriter
            self.includesMicrophone = includesMicrophone
            stagingDirectoryURL = directoryURL
            let now = Date()
            startedAt = now
            activeSegmentStartedAt = now

            try await stream.startCapture()
            phase = .recording
            startElapsedUpdates()
            return true
        } catch {
            await abandonCapture(after: error)
            return false
        }
    }

    func pauseCapture() {
        guard phase == .recording, !isPaused else {
            return
        }
        if let activeSegmentStartedAt {
            accumulatedActiveDuration += Date().timeIntervalSince(activeSegmentStartedAt)
        }
        activeSegmentStartedAt = nil
        isPaused = true
        sampleRouter?.setPaused(true)
        elapsedSeconds = accumulatedActiveDuration
    }

    func resumeCapture() {
        guard phase == .recording, isPaused else {
            return
        }
        isPaused = false
        activeSegmentStartedAt = Date()
        sampleRouter?.setPaused(false)
    }

    func stopCapture() async -> MacSystemAudioCaptureResult? {
        guard phase == .recording || phase == .starting,
              let stream,
              let stagingDirectoryURL,
              let startedAt else {
            return nil
        }

        phase = .stopping
        finalizeActiveDuration()
        elapsedTask?.cancel()
        elapsedTask = nil
        sampleRouter?.setPaused(false)

        do {
            try await stream.stopCapture()
            let systemResult = await finishAudioWriter(systemAudioWriter)
            guard case .success(let systemAudioURL) = systemResult else {
                if case .failure(let error) = systemResult {
                    throw error
                }
                throw MacCaptureError.noAudioSamples
            }

            let outputURL: URL
            if !includesMicrophone {
                outputURL = systemAudioURL
            } else if case .success(let microphoneAudioURL) = await finishAudioWriter(
                microphoneAudioWriter
            ) {
                let mixedURL = stagingDirectoryURL.appendingPathComponent("recording.m4a")
                do {
                    try await MacSystemAudioMixer.mix(
                        systemAudioURL: systemAudioURL,
                        microphoneAudioURL: microphoneAudioURL,
                        outputURL: mixedURL
                    )
                    try? FileManager.default.removeItem(at: systemAudioURL)
                    try? FileManager.default.removeItem(at: microphoneAudioURL)
                    outputURL = mixedURL
                } catch {
                    warningMessage = String(localized: MacL10n.systemAudioMicrophoneMixFallback)
                    try? FileManager.default.removeItem(at: microphoneAudioURL)
                    outputURL = systemAudioURL
                }
            } else {
                warningMessage = String(localized: MacL10n.systemAudioMicrophoneMissing)
                outputURL = systemAudioURL
            }

            let duration = await Self.durationSeconds(of: outputURL)
            let result = MacSystemAudioCaptureResult(
                audioURL: outputURL,
                stagingDirectoryURL: stagingDirectoryURL,
                startedAt: startedAt,
                durationSeconds: duration > 0 ? duration : accumulatedActiveDuration,
                sourceName: selectedSourceName ?? String(localized: MacL10n.systemAudioSelectedContent)
            )
            clearActiveCapture()
            phase = .sourceSelected
            picker.isActive = true
            return result
        } catch {
            await abandonCapture(after: error)
            return nil
        }
    }

    func discardStagingDirectory(_ directoryURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    static func makeStreamConfiguration(
        includesMicrophone: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = includesMicrophone
        if includesMicrophone {
            configuration.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        }
        configuration.streamName = "Live Transcriber System Audio"
        return configuration
    }

    private func authorizeMicrophone() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw MacCaptureError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw MacCaptureError.microphonePermissionDenied
        @unknown default:
            throw MacCaptureError.microphonePermissionDenied
        }
    }

    private func startElapsedUpdates() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if let activeSegmentStartedAt = self.activeSegmentStartedAt {
                    self.elapsedSeconds = self.accumulatedActiveDuration
                        + Date().timeIntervalSince(activeSegmentStartedAt)
                } else {
                    self.elapsedSeconds = self.accumulatedActiveDuration
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func finalizeActiveDuration() {
        if let activeSegmentStartedAt {
            accumulatedActiveDuration += Date().timeIntervalSince(activeSegmentStartedAt)
        }
        activeSegmentStartedAt = nil
        elapsedSeconds = accumulatedActiveDuration
        isPaused = false
    }

    private func finishAudioWriter(
        _ writer: MacCaptureAudioWriter?
    ) async -> Result<URL, Error> {
        guard let writer else {
            return .failure(MacCaptureError.noAudioSamples)
        }
        return await withCheckedContinuation { continuation in
            sampleQueue.async {
                writer.finish { result in
                    if case .failure = result {
                        try? FileManager.default.removeItem(at: writer.outputURL)
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func abandonCapture(after error: Error) async {
        elapsedTask?.cancel()
        elapsedTask = nil
        if let stream {
            try? await stream.stopCapture()
        }
        await cancelAudioWriters()
        if let stagingDirectoryURL {
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
        }
        clearActiveCapture()
        errorMessage = error.localizedDescription
        phase = .failed
        picker.isActive = true
    }

    private func cancelAudioWriters() async {
        let systemAudioWriter = systemAudioWriter
        let microphoneAudioWriter = microphoneAudioWriter
        await withCheckedContinuation { continuation in
            sampleQueue.async {
                systemAudioWriter?.cancel()
                microphoneAudioWriter?.cancel()
                continuation.resume()
            }
        }
    }

    private func clearActiveCapture() {
        stream = nil
        sampleRouter = nil
        systemAudioWriter = nil
        microphoneAudioWriter = nil
        stagingDirectoryURL = nil
        startedAt = nil
        activeSegmentStartedAt = nil
        accumulatedActiveDuration = 0
        isPaused = false
        includesMicrophone = false
    }

    private static func makeStagingDirectory() throws -> URL {
        guard let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw MacCaptureError.recordingDirectoryUnavailable
        }
        let directoryURL = cachesURL
            .appendingPathComponent("LiveTranscriber", isDirectory: true)
            .appendingPathComponent("SystemAudioStaging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }

    private static func durationSeconds(of url: URL) async -> Double {
        let duration = try? await AVURLAsset(url: url).load(.duration).seconds
        guard let duration, duration.isFinite, duration > 0 else {
            return 0
        }
        return duration
    }

    private static func sourceName(for filter: SCContentFilter) -> String {
        if let window = filter.includedWindows.first {
            let appName = window.owningApplication?.applicationName
            let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = [appName, windowTitle]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            if !title.isEmpty {
                return title
            }
        }
        if let application = filter.includedApplications.first {
            return application.applicationName
        }
        switch filter.style {
        case .display:
            return String(localized: MacL10n.systemAudioDisplay)
        case .window:
            return String(localized: MacL10n.systemAudioWindow)
        case .application:
            return String(localized: MacL10n.systemAudioApplication)
        case .none:
            return String(localized: MacL10n.systemAudioSelectedContent)
        @unknown default:
            return String(localized: MacL10n.systemAudioSelectedContent)
        }
    }
}

extension MacSystemAudioCaptureController: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {}

    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.canChooseSource else {
                return
            }
            self.selectedFilter = filter
            self.selectedSourceName = Self.sourceName(for: filter)
            self.errorMessage = nil
            self.phase = .sourceSelected
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.errorMessage = error.localizedDescription
            self?.phase = .failed
        }
    }
}

extension MacSystemAudioCaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .recording || self.phase == .starting else {
                return
            }
            await self.abandonCapture(after: error)
        }
    }
}

enum MacSystemAudioMixer {
    static func mix(
        systemAudioURL: URL,
        microphoneAudioURL: URL,
        outputURL: URL
    ) async throws {
        let composition = AVMutableComposition()
        for sourceURL in [systemAudioURL, microphoneAudioURL] {
            let asset = AVURLAsset(url: sourceURL)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first,
                  let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                throw MacCaptureError.noAudioSamples
            }
            let sourceTimeRange = try await sourceTrack.load(.timeRange)
            try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: .zero)
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw MacCaptureError.audioWriterFailed("Could not create the system-audio mixer")
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = composition.tracks(withMediaType: .audio).map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0.85, at: .zero)
            return parameters
        }
        exporter.audioMix = audioMix
        try? FileManager.default.removeItem(at: outputURL)
        try await exporter.export(to: outputURL, as: .m4a)
    }
}
