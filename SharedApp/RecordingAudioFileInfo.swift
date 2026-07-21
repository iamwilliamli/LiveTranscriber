import AVFoundation
import Foundation

struct RecordingAudioFileInfo: Equatable, Sendable {
    var fileSampleRate: Double
    var processingSampleRate: Double
    var channelCount: UInt32
    var processingChannelCount: UInt32
    var fileExtension: String
    var fileFormatName: String
    var fileCommonFormatName: String
    var processingCommonFormatName: String
    var bitDepth: Int?
    var encoderBitRate: Int?
    var isInterleaved: Bool
    var frameCount: AVAudioFramePosition
    var durationSeconds: TimeInterval
    var fileName: String
    var fileCreationDate: Date?
    var fileSize: Int64?

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let fileFormat = file.fileFormat
        let processingFormat = file.processingFormat
        let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])

        self.fileSampleRate = fileFormat.sampleRate
        self.processingSampleRate = processingFormat.sampleRate
        self.channelCount = fileFormat.channelCount
        self.processingChannelCount = processingFormat.channelCount
        self.fileExtension = url.pathExtension.uppercased()
        self.fileFormatName = Self.formatName(from: fileFormat.settings[AVFormatIDKey])
        self.fileCommonFormatName = Self.commonFormatName(fileFormat.commonFormat)
        self.processingCommonFormatName = Self.commonFormatName(processingFormat.commonFormat)
        self.bitDepth = Self.bitDepth(settings: fileFormat.settings, format: fileFormat)
        self.encoderBitRate = Self.intValue(from: fileFormat.settings[AVEncoderBitRateKey])
        self.isInterleaved = fileFormat.isInterleaved
        self.frameCount = file.length
        self.durationSeconds = processingFormat.sampleRate > 0 ? Double(file.length) / processingFormat.sampleRate : 0
        self.fileName = url.lastPathComponent
        self.fileCreationDate = resourceValues?.creationDate
        self.fileSize = resourceValues?.fileSize.map { Int64($0) }
    }

    var fileSampleRateText: String {
        Self.sampleRateText(fileSampleRate)
    }

    var channelLayoutText: String {
        switch channelCount {
        case 1:
            return localized(L10n.Recordings.mono)
        case 2:
            return localized(L10n.Recordings.stereo)
        default:
            return localizedFormat(L10n.Recordings.channelCountFormat, Int(channelCount))
        }
    }

    var fileFormatText: String {
        if bitDepth == nil {
            return fileFormatName
        }
        return "\(fileFormatName) / \(fileCommonFormatName)"
    }

    var containerFormatText: String {
        let trimmedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtension.isEmpty else {
            return fileFormatName
        }
        return "\(trimmedExtension) / \(fileFormatName)"
    }

    var bitRateText: String {
        if let encoderBitRate, encoderBitRate > 0 {
            return Self.bitRateText(Double(encoderBitRate))
        }
        return averageBitRateText
    }

    var averageBitRateText: String {
        guard let fileSize,
              durationSeconds.isFinite,
              durationSeconds > 0 else {
            return localized(L10n.Common.unknown)
        }

        return Self.bitRateText(Double(fileSize) * 8 / durationSeconds)
    }

    var processingFormatText: String {
        let channelText: String
        switch processingChannelCount {
        case 1:
            channelText = localized(L10n.Recordings.mono)
        case 2:
            channelText = localized(L10n.Recordings.stereo)
        default:
            channelText = localizedFormat(L10n.Recordings.channelCountFormat, Int(processingChannelCount))
        }

        return "\(Self.sampleRateText(processingSampleRate)) / \(channelText) / \(processingCommonFormatName)"
    }

    var bitDepthText: String {
        guard let bitDepth else {
            return localized(L10n.Common.notApplicable)
        }
        return localizedFormat(L10n.Recordings.bitDepthFormat, bitDepth)
    }

    var durationText: String {
        TranscriptionLine.formatTimestamp(durationSeconds)
    }

    var frameCountText: String {
        Self.integerFormatter.string(from: NSNumber(value: frameCount)) ?? "\(frameCount)"
    }

    var fileSizeText: String {
        guard let fileSize else {
            return localized(L10n.Common.unknown)
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var fileCreationDateText: String {
        guard let fileCreationDate else {
            return localized(L10n.Common.unknown)
        }
        return fileCreationDate.formatted(date: .abbreviated, time: .standard)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func sampleRateText(_ sampleRate: Double) -> String {
        guard sampleRate.isFinite, sampleRate > 0 else {
            return localized(L10n.Common.unknown)
        }

        let kilohertz = sampleRate / 1_000
        if kilohertz.rounded() == kilohertz {
            return "\(Int(kilohertz)) kHz"
        }
        return String(format: "%.1f kHz", kilohertz)
    }

    private static func bitRateText(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond.isFinite, bitsPerSecond > 0 else {
            return localized(L10n.Common.unknown)
        }

        let kilobitsPerSecond = bitsPerSecond / 1_000
        if kilobitsPerSecond >= 1_000 {
            return String(format: "%.2f Mbps", kilobitsPerSecond / 1_000)
        }
        if kilobitsPerSecond.rounded() == kilobitsPerSecond {
            return "\(Int(kilobitsPerSecond)) kbps"
        }
        return String(format: "%.1f kbps", kilobitsPerSecond)
    }

    private static func commonFormatName(_ commonFormat: AVAudioCommonFormat) -> String {
        switch commonFormat {
        case .pcmFormatFloat32:
            return "Float32 PCM"
        case .pcmFormatFloat64:
            return "Float64 PCM"
        case .pcmFormatInt16:
            return "Int16 PCM"
        case .pcmFormatInt32:
            return "Int32 PCM"
        case .otherFormat:
            return localized(L10n.Recordings.compressedOrOtherFormat)
        @unknown default:
            return localized(L10n.Common.unknown)
        }
    }

    private static func formatName(from value: Any?) -> String {
        guard let formatID = audioFormatID(from: value) else {
            return localized(L10n.Common.unknown)
        }

        switch fourCharacterCode(formatID) {
        case "lpcm":
            return "Linear PCM"
        case "aac ":
            return "AAC"
        case "alac":
            return "Apple Lossless"
        case "mp4a":
            return "MPEG-4 Audio"
        case "caff":
            return "CAF"
        default:
            return fourCharacterCode(formatID)
        }
    }

    private static func audioFormatID(from value: Any?) -> UInt32? {
        if let value = value as? UInt32 {
            return value
        }
        if let value = value as? Int {
            return UInt32(value)
        }
        if let value = value as? NSNumber {
            return value.uint32Value
        }
        return nil
    }

    private static func intValue(from value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func bitDepth(settings: [String: Any], format: AVAudioFormat) -> Int? {
        if let explicitBitDepth = intValue(from: settings[AVLinearPCMBitDepthKey]) {
            return explicitBitDepth
        }

        guard audioFormatID(from: settings[AVFormatIDKey]) == kAudioFormatLinearPCM else {
            return nil
        }

        switch format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32:
            return 32
        case .pcmFormatFloat64:
            return 64
        case .pcmFormatInt16:
            return 16
        default:
            return nil
        }
    }

    private static func fourCharacterCode(_ rawValue: UInt32) -> String {
        let bytes = [
            UInt8((rawValue >> 24) & 0xff),
            UInt8((rawValue >> 16) & 0xff),
            UInt8((rawValue >> 8) & 0xff),
            UInt8(rawValue & 0xff)
        ]

        guard bytes.allSatisfy({ (32...126).contains($0) }) else {
            return "0x\(String(rawValue, radix: 16, uppercase: true))"
        }
        return String(bytes: bytes, encoding: .ascii) ?? "0x\(String(rawValue, radix: 16, uppercase: true))"
    }
}
