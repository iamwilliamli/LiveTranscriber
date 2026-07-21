import AVFoundation
import Combine
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class MacScreenCaptureController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case sourceSelected
        case starting
        case recording
        case stopping
        case completed
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var selectedSourceName: String?
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var latestResult: MacCaptureResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var warningMessage: String?
    @Published var capturesSystemAudio = true
    @Published var capturesMicrophone = true

    private let picker = SCContentSharingPicker.shared
    private let sampleQueue = DispatchQueue(
        label: "com.iamwilliamli.LiveTranscriber.mac.capture-audio",
        qos: .userInitiated
    )
    private var selectedFilter: SCContentFilter?
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var sampleRouter: MacCaptureSampleRouter?
    private var activePlan: MacCaptureOutputPlan?
    private var startedAt: Date?
    private var elapsedTask: Task<Void, Never>?
    private var recordingDidFinish = false
    private var recordingFailure: Error?

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
        picker.isActive = false
    }

    var canChooseSource: Bool {
        phase != .starting && phase != .recording && phase != .stopping
    }

    var canStart: Bool {
        selectedFilter != nil
            && (phase == .sourceSelected || phase == .completed || phase == .failed)
    }

    func presentSourcePicker() {
        guard canChooseSource else {
            return
        }
        errorMessage = nil
        picker.isActive = true
        picker.present()
    }

    func startCapture() async {
        guard let selectedFilter else {
            fail(with: MacCaptureError.noSourceSelected)
            return
        }
        guard phase != .starting, phase != .recording, phase != .stopping else {
            return
        }

        phase = .starting
        errorMessage = nil
        warningMessage = nil
        latestResult = nil
        elapsedSeconds = 0
        picker.isActive = false

        do {
            if capturesMicrophone {
                try await authorizeMicrophone()
            }

            let directoryURL = try MacCaptureStorage.preferredRecordingsDirectory()
            let plan = MacCaptureOutputPlan(
                directoryURL: directoryURL,
                capturesSystemAudio: capturesSystemAudio,
                capturesMicrophone: capturesMicrophone
            )
            MacCaptureStorage.removeIncompleteOutputs(plan: plan)

            let systemWriter = plan.systemAudioURL.map(MacCaptureAudioWriter.init)
            let microphoneWriter = plan.microphoneAudioURL.map(MacCaptureAudioWriter.init)
            let sampleRouter = MacCaptureSampleRouter(
                systemAudioWriter: systemWriter,
                microphoneAudioWriter: microphoneWriter
            )
            let streamConfiguration = makeStreamConfiguration(for: selectedFilter)
            let stream = SCStream(
                filter: selectedFilter,
                configuration: streamConfiguration,
                delegate: self
            )

            if capturesSystemAudio {
                try stream.addStreamOutput(
                    sampleRouter,
                    type: .audio,
                    sampleHandlerQueue: sampleQueue
                )
            }
            if capturesMicrophone {
                try stream.addStreamOutput(
                    sampleRouter,
                    type: .microphone,
                    sampleHandlerQueue: sampleQueue
                )
            }

            let recordingConfiguration = SCRecordingOutputConfiguration()
            recordingConfiguration.outputURL = plan.videoURL
            recordingConfiguration.outputFileType = .mp4
            recordingConfiguration.videoCodecType = .h264
            let recordingOutput = SCRecordingOutput(
                configuration: recordingConfiguration,
                delegate: self
            )
            try stream.addRecordingOutput(recordingOutput)

            activePlan = plan
            self.stream = stream
            self.recordingOutput = recordingOutput
            self.sampleRouter = sampleRouter
            startedAt = Date()
            recordingDidFinish = false
            recordingFailure = nil

            try await stream.startCapture()
            if phase == .starting {
                phase = .recording
            }
            startElapsedUpdates()
        } catch {
            await abandonCapture(after: error)
        }
    }

    func stopCapture() async {
        guard phase == .recording || phase == .starting,
              let stream,
              let recordingOutput,
              let activePlan,
              let startedAt else {
            return
        }

        phase = .stopping
        elapsedTask?.cancel()
        elapsedTask = nil

        do {
            try await stream.stopCapture()
            try await waitForRecordingOutputToFinish()
            if let recordingFailure {
                throw recordingFailure
            }

            let systemAudioResult = await finishAudioWriter(sampleRouter?.systemAudioWriter)
            let microphoneAudioResult = await finishAudioWriter(
                sampleRouter?.microphoneAudioWriter
            )
            let audioFailures: [Error] = [
                systemAudioResult,
                microphoneAudioResult,
            ].compactMap { result -> Error? in
                guard case .failure(let error) = result else {
                    return nil
                }
                return error
            }
            if !audioFailures.isEmpty {
                warningMessage = "The video was saved, but one or more separate audio tracks contained no usable samples."
            }

            let recordedDuration = recordingOutput.recordedDuration.seconds
            let fallbackDuration = Date().timeIntervalSince(startedAt)
            let duration = recordedDuration.isFinite && recordedDuration > 0
                ? recordedDuration
                : fallbackDuration
            let result = try MacCaptureStorage.makeResult(
                plan: activePlan,
                startedAt: startedAt,
                durationSeconds: duration,
                sourceTitle: selectedSourceName ?? "Screen Recording"
            )
            latestResult = result
            elapsedSeconds = duration
            phase = .completed
            clearActiveCapture()
            picker.isActive = true
        } catch {
            await abandonCapture(after: error)
        }
    }

    func resetCompletion() {
        latestResult = nil
        errorMessage = nil
        warningMessage = nil
        elapsedSeconds = 0
        phase = selectedFilter == nil ? .idle : .sourceSelected
    }

    private func makeStreamConfiguration(for filter: SCContentFilter) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let sourceWidth = max(Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)), 2)
        let sourceHeight = max(Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)), 2)
        let downscale = min(
            1,
            3_840 / Double(sourceWidth),
            2_160 / Double(sourceHeight)
        )
        configuration.width = Self.evenDimension(Double(sourceWidth) * downscale)
        configuration.height = Self.evenDimension(Double(sourceHeight) * downscale)
        configuration.captureResolution = .best
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.capturesAudio = capturesSystemAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = capturesMicrophone
        if capturesMicrophone {
            configuration.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        }
        configuration.streamName = "Live Transcriber Capture"
        return configuration
    }

    private static func evenDimension(_ value: Double) -> Int {
        let rounded = max(Int(value.rounded(.down)), 2)
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
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
                let recordedSeconds = self.recordingOutput?.recordedDuration.seconds ?? 0
                if recordedSeconds.isFinite, recordedSeconds >= 0 {
                    self.elapsedSeconds = recordedSeconds
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func finishAudioWriter(
        _ writer: MacCaptureAudioWriter?
    ) async -> Result<URL, Error> {
        guard let writer else {
            return .success(URL(fileURLWithPath: "/dev/null"))
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

    private func waitForRecordingOutputToFinish() async throws {
        for _ in 0..<250 {
            if recordingDidFinish {
                return
            }
            if let recordingFailure {
                throw recordingFailure
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw MacCaptureError.audioWriterFailed("Screen recording did not finish in time")
    }

    private func abandonCapture(after error: Error) async {
        phase = .stopping
        elapsedTask?.cancel()
        elapsedTask = nil
        if let stream {
            try? await stream.stopCapture()
        }
        await cancelAudioWriters()
        if let plan = activePlan {
            MacCaptureStorage.removeIncompleteOutputs(plan: plan)
        }
        clearActiveCapture()
        fail(with: error)
        picker.isActive = true
    }

    private func cancelAudioWriters() async {
        let router = sampleRouter
        await withCheckedContinuation { continuation in
            sampleQueue.async {
                router?.systemAudioWriter?.cancel()
                router?.microphoneAudioWriter?.cancel()
                continuation.resume()
            }
        }
    }

    private func clearActiveCapture() {
        stream = nil
        recordingOutput = nil
        sampleRouter = nil
        activePlan = nil
        startedAt = nil
        recordingDidFinish = false
        recordingFailure = nil
    }

    private func fail(with error: Error) {
        errorMessage = error.localizedDescription
        phase = .failed
    }

    private static func sourceName(for filter: SCContentFilter) -> String {
        if #available(macOS 15.2, *) {
            if let window = filter.includedWindows.first {
                let appName = window.owningApplication?.applicationName
                let windowTitle = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return [appName, windowTitle]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " — ")
            }
            if let application = filter.includedApplications.first {
                return application.applicationName
            }
        }

        switch filter.style {
        case .display: return "Display"
        case .window: return "Window"
        case .application: return "Application"
        case .none: return "Selected Content"
        @unknown default: return "Selected Content"
        }
    }
}

extension MacScreenCaptureController: SCContentSharingPickerObserver {
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
            self.latestResult = nil
            self.phase = .sourceSelected
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            self?.fail(with: error)
        }
    }
}

extension MacScreenCaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.phase == .recording || self.phase == .starting else {
                return
            }
            await self.abandonCapture(after: error)
        }
    }
}

extension MacScreenCaptureController: SCRecordingOutputDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self, self.phase == .starting else {
                return
            }
            self.phase = .recording
        }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.recordingFailure = error
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            self?.recordingDidFinish = true
        }
    }
}
