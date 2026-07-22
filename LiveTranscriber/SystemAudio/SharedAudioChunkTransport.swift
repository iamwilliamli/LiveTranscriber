import AVFoundation
import CoreMedia
import Foundation

enum SharedAudioChunkConstants {
    static let appGroupIdentifier = "group.com.iamwilliamli.LiveTranscriber"
    static let sessionsDirectoryName = "ScreenAudioSessions"
    static let activeMetadataFileName = "active-session.json"
    static let metadataFileName = "metadata.json"
    static let sampleRate = 48_000
    static let channelCount: AVAudioChannelCount = 2
    static let bytesPerPCMFrame = Int(channelCount) * MemoryLayout<Int16>.size
    static let maximumReadyChunkCount = 160
    static let staleSessionAge: TimeInterval = 24 * 60 * 60
}

enum SharedAudioTransportError: LocalizedError {
    case appGroupUnavailable
    case invalidAudioChunk

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return String(localized: LocalizedStringResource(
                "screen_audio.error.app_group",
                defaultValue: "The shared screen-audio container is unavailable. Check the App Group capability and signing profile.",
                table: "Semantic",
                comment: "Error shown when the ReplayKit App Group container is unavailable."
            ))
        case .invalidAudioChunk:
            return String(localized: LocalizedStringResource(
                "screen_audio.error.invalid_chunk",
                defaultValue: "A screen-audio chunk could not be decoded.",
                table: "Semantic",
                comment: "Error shown for a corrupt shared PCM chunk."
            ))
        }
    }
}

enum SharedAudioTransportState: String, Codable, Sendable {
    case waitingForAudio
    case capturing
    case paused
    case finished
    case failed
}

struct SharedAudioSessionMetadata: Codable, Equatable, Sendable {
    var sessionID: UUID
    var state: SharedAudioTransportState
    var sampleRate: Int
    var channelCount: Int
    var latestSequence: UInt64?
    var heartbeat: Date
    var createdAt: Date
    var overrunCount: UInt64
    var droppedChunkCount: UInt64
    var errorMessage: String?

    init(sessionID: UUID = UUID(), now: Date = Date()) {
        self.sessionID = sessionID
        state = .waitingForAudio
        sampleRate = SharedAudioChunkConstants.sampleRate
        channelCount = Int(SharedAudioChunkConstants.channelCount)
        latestSequence = nil
        heartbeat = now
        createdAt = now
        overrunCount = 0
        droppedChunkCount = 0
        errorMessage = nil
    }
}

final class SharedAudioChunkDirectory: @unchecked Sendable {
    let rootURL: URL
    let sessionsURL: URL

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    convenience init() throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedAudioChunkConstants.appGroupIdentifier
        ) else {
            throw SharedAudioTransportError.appGroupUnavailable
        }
        self.init(rootURL: containerURL)
    }

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        sessionsURL = rootURL.appendingPathComponent(
            SharedAudioChunkConstants.sessionsDirectoryName,
            isDirectory: true
        )
    }

    var activeMetadataURL: URL {
        sessionsURL.appendingPathComponent(SharedAudioChunkConstants.activeMetadataFileName)
    }

    func prepare() throws {
        try fileManager.createDirectory(
            at: sessionsURL,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    func beginSession(now: Date = Date()) throws -> SharedAudioSessionMetadata {
        try prepare()
        let metadata = SharedAudioSessionMetadata(now: now)
        let directoryURL = sessionDirectoryURL(for: metadata.sessionID)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try writeMetadata(metadata)
        return metadata
    }

    func writeMetadata(_ metadata: SharedAudioSessionMetadata) throws {
        try prepare()
        let data = try encoder.encode(metadata)
        let sessionURL = sessionDirectoryURL(for: metadata.sessionID)
        try fileManager.createDirectory(at: sessionURL, withIntermediateDirectories: true)
        try data.write(
            to: sessionURL.appendingPathComponent(SharedAudioChunkConstants.metadataFileName),
            options: .atomic
        )
        try data.write(to: activeMetadataURL, options: .atomic)
    }

    func loadActiveMetadata() throws -> SharedAudioSessionMetadata? {
        guard fileManager.fileExists(atPath: activeMetadataURL.path) else {
            return nil
        }
        return try decoder.decode(
            SharedAudioSessionMetadata.self,
            from: Data(contentsOf: activeMetadataURL)
        )
    }

    func commitChunk(
        _ data: Data,
        sessionID: UUID,
        sequence: UInt64,
        maximumReadyChunks: Int = SharedAudioChunkConstants.maximumReadyChunkCount
    ) throws -> Bool {
        guard !data.isEmpty,
              data.count.isMultiple(of: SharedAudioChunkConstants.bytesPerPCMFrame) else {
            throw SharedAudioTransportError.invalidAudioChunk
        }

        let directoryURL = sessionDirectoryURL(for: sessionID)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard try readyChunkURLs(sessionID: sessionID).count < maximumReadyChunks else {
            return false
        }

        let stem = Self.chunkStem(sequence: sequence)
        let temporaryURL = directoryURL.appendingPathComponent("\(stem).\(UUID().uuidString).tmp")
        let readyURL = directoryURL.appendingPathComponent("\(stem).pcm.ready")
        try data.write(to: temporaryURL)
        do {
            try fileManager.moveItem(at: temporaryURL, to: readyURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
        return true
    }

    func readyChunkURLs(sessionID: UUID) throws -> [URL] {
        let directoryURL = sessionDirectoryURL(for: sessionID)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasSuffix(".pcm.ready") }
        .sorted { lhs, rhs in
            (Self.sequence(from: lhs) ?? .max) < (Self.sequence(from: rhs) ?? .max)
        }
    }

    func readChunk(at url: URL) throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    func removeChunk(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func removeActiveMetadata(ifSessionID sessionID: UUID) throws {
        guard let active = try loadActiveMetadata(), active.sessionID == sessionID else {
            return
        }
        try fileManager.removeItem(at: activeMetadataURL)
    }

    func removeSession(_ sessionID: UUID) throws {
        let url = sessionDirectoryURL(for: sessionID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try? removeActiveMetadata(ifSessionID: sessionID)
    }

    /// Removes a completed session that cannot belong to a newly-started
    /// consumer. Without this cleanup, the iOS 26 ReplayKit path can observe the
    /// previous broadcast's `.finished`/`.failed` marker and immediately stop a
    /// new recording before the broadcast picker countdown has completed.
    func removeTerminalActiveSession() throws {
        guard let metadata = try loadActiveMetadata() else { return }
        switch metadata.state {
        case .finished, .failed:
            try removeSession(metadata.sessionID)
        case .waitingForAudio, .capturing, .paused:
            break
        }
    }

    func cleanupExpiredSessions(
        now: Date = Date(),
        maximumAge: TimeInterval = SharedAudioChunkConstants.staleSessionAge
    ) throws {
        try prepare()
        let activeSessionID = try loadActiveMetadata()?.sessionID
        let entries = try fileManager.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for entry in entries where entry.hasDirectoryPath {
            guard UUID(uuidString: entry.lastPathComponent) != activeSessionID else {
                continue
            }
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey])
            let modificationDate = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modificationDate) > maximumAge {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    func sessionDirectoryURL(for sessionID: UUID) -> URL {
        sessionsURL.appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    static func chunkStem(sequence: UInt64) -> String {
        String(format: "%020llu", sequence)
    }

    static func sequence(from url: URL) -> UInt64? {
        guard let firstComponent = url.lastPathComponent.split(separator: ".").first else {
            return nil
        }
        return UInt64(firstComponent)
    }
}

final class SystemAudioPCMNormalizer: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(
        // AVAudioConverter does not support every integer PCM conversion on
        // every device. Float32 is its canonical processing format; the
        // ReplayKit transport is quantized to Int16 separately below.
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(SharedAudioChunkConstants.sampleRate),
        channels: SharedAudioChunkConstants.channelCount,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    func normalize(_ sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        try normalize(Self.makePCMBuffer(from: sampleBuffer))
    }

    func normalize(_ inputBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard inputBuffer.frameLength > 0 else {
            throw SharedAudioTransportError.invalidAudioChunk
        }

        if Self.formatsMatch(inputBuffer.format, Self.targetFormat) {
            return try Self.copy(inputBuffer)
        }

        let activeConverter: AVAudioConverter
        if let converter, let sourceFormat, Self.formatsMatch(sourceFormat, inputBuffer.format) {
            activeConverter = converter
        } else {
            guard let newConverter = AVAudioConverter(from: inputBuffer.format, to: Self.targetFormat) else {
                throw SharedAudioTransportError.invalidAudioChunk
            }
            converter = newConverter
            sourceFormat = inputBuffer.format
            activeConverter = newConverter
        }

        let capacity = AVAudioFrameCount(max(
            1,
            Int(ceil(
                Double(inputBuffer.frameLength)
                    * Self.targetFormat.sampleRate
                    / inputBuffer.format.sampleRate
            ))
        ))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.targetFormat,
            frameCapacity: capacity
        ) else {
            throw SharedAudioTransportError.invalidAudioChunk
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = activeConverter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if didProvideInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if let conversionError {
            throw conversionError
        }
        guard status != .error, outputBuffer.frameLength > 0 else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        return outputBuffer
    }

    static func data(from normalizedBuffer: AVAudioPCMBuffer) throws -> Data {
        guard formatsMatch(normalizedBuffer.format, targetFormat),
              let sourceChannels = normalizedBuffer.floatChannelData,
              normalizedBuffer.frameLength > 0 else {
            throw SharedAudioTransportError.invalidAudioChunk
        }

        let frameCount = Int(normalizedBuffer.frameLength)
        let channelCount = Int(targetFormat.channelCount)
        var data = Data(count: frameCount * SharedAudioChunkConstants.bytesPerPCMFrame)
        data.withUnsafeMutableBytes { rawBuffer in
            let destination = rawBuffer.bindMemory(to: Int16.self)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    let clamped = max(-1, min(sourceChannels[channel][frame], 1))
                    destination[(frame * channelCount) + channel] = Int16(
                        (clamped * Float(Int16.max)).rounded()
                    )
                }
            }
        }
        return data
    }

    static func buffer(from data: Data) throws -> AVAudioPCMBuffer {
        guard !data.isEmpty,
              data.count.isMultiple(of: SharedAudioChunkConstants.bytesPerPCMFrame) else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        let frameCount = AVAudioFrameCount(
            data.count / SharedAudioChunkConstants.bytesPerPCMFrame
        )
        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount),
              let destinationChannels = buffer.floatChannelData else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        buffer.frameLength = frameCount
        let channelCount = Int(targetFormat.channelCount)
        data.withUnsafeBytes { rawBuffer in
            let source = rawBuffer.bindMemory(to: Int16.self)
            for frame in 0..<Int(frameCount) {
                for channel in 0..<channelCount {
                    destinationChannels[channel][frame] = Float(
                        source[(frame * channelCount) + channel]
                    ) / 32_768
                }
            }
        }
        return buffer
    }

    static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, frameCount <= Int32.max else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        var description = streamDescription.pointee
        guard let format = AVAudioFormat(streamDescription: &description),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
              ) else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        return buffer
    }

    private static func copy(_ source: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ), let sourceData = source.floatChannelData, let destinationData = copy.floatChannelData else {
            throw SharedAudioTransportError.invalidAudioChunk
        }
        copy.frameLength = source.frameLength
        for channel in 0..<Int(source.format.channelCount) {
            destinationData[channel].update(
                from: sourceData[channel],
                count: Int(source.frameLength)
            )
        }
        return copy
    }

    private static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat
            && lhs.sampleRate == rhs.sampleRate
            && lhs.channelCount == rhs.channelCount
            && lhs.isInterleaved == rhs.isInterleaved
    }
}
