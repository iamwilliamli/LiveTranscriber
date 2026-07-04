import AVFoundation
import Foundation
import Security

enum LiveTranscriptionBackend: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleOnDevice

    var id: String {
        rawValue
    }

    var title: String {
        String(localized: titleResource)
    }

    var titleResource: LocalizedStringResource {
        switch self {
        case .appleOnDevice:
            return L10n.TranscriptionBackend.appleOnDeviceTitle
        }
    }

    var detailResource: LocalizedStringResource {
        switch self {
        case .appleOnDevice:
            return L10n.TranscriptionBackend.appleOnDeviceDetail
        }
    }

    var requiresAppleSpeech: Bool {
        true
    }

    static var defaultBackend: LiveTranscriptionBackend {
        .appleOnDevice
    }
}

enum OpenAITranscriptionError: LocalizedError {
    case invalidConfiguration
    case missingAPIKey
    case keychainUnavailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return String(localized: L10n.OpenAITranscription.invalidConfiguration)
        case .missingAPIKey:
            return String(localized: L10n.OpenAITranscription.missingAPIKey)
        case .keychainUnavailable:
            return String(localized: L10n.OpenAITranscription.keychainUnavailable)
        case .server(let message):
            return message
        }
    }
}

enum OpenAIAPIKeyStore {
    private static let service = "com.reddownloader.LiveTranscriber.openai"
    private static let account = "api-key"
    private static let legacyAccount = "realtime-api-key"

    static func load() throws -> String {
        if let value = try load(account: account) {
            return value
        }

        if let legacyValue = try load(account: legacyAccount), !legacyValue.isEmpty {
            try save(legacyValue)
            return legacyValue
        }

        return ""
    }

    private static func load(account: String) throws -> String? {
        var query = baseQuery(keychainAccount: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw OpenAITranscriptionError.keychainUnavailable
        }

        return value
    }

    static func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw OpenAITranscriptionError.keychainUnavailable
        }

        var item = baseQuery()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAITranscriptionError.keychainUnavailable
        }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAITranscriptionError.keychainUnavailable
        }

        let legacyStatus = SecItemDelete(baseQuery(keychainAccount: legacyAccount) as CFDictionary)
        guard legacyStatus == errSecSuccess || legacyStatus == errSecItemNotFound else {
            throw OpenAITranscriptionError.keychainUnavailable
        }
    }

    private static func baseQuery(keychainAccount: String = account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}

enum OpenAIFileTranscriptionMode: Equatable {
    case longForm
    case segmented
    case refinedSegments

    private static let longFormModel = "gpt-4o-transcribe"
    private static let whisperModel = "whisper-1"

    var model: String {
        switch self {
        case .longForm:
            return Self.longFormModel
        case .segmented, .refinedSegments:
            return Self.whisperModel
        }
    }

    var responseFormat: String {
        switch self {
        case .longForm, .refinedSegments:
            return "json"
        case .segmented:
            return "verbose_json"
        }
    }
}

struct OpenAITranscriptRefinementSegment: Sendable {
    var startSeconds: Double
    var endSeconds: Double
    var localText: String
}

enum OpenAIFileTranscriptionService {
    private static let minimumRefinementSegmentDuration: Double = 0.35

    static func transcribe(
        audioURL: URL,
        language: TranscriptionLanguage,
        apiKey: String,
        mode: OpenAIFileTranscriptionMode,
        prompt: String? = nil
    ) async throws -> [TranscriptionLine] {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw OpenAITranscriptionError.missingAPIKey
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let bodyURL = try makeMultipartBodyFile(
            audioURL: audioURL,
            language: language,
            mode: mode,
            prompt: prompt,
            boundary: boundary
        )
        defer {
            try? FileManager.default.removeItem(at: bodyURL)
        }

        var request = try makeTranscriptionRequest(apiKey: trimmedAPIKey, boundary: boundary)
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        request.httpBody = nil

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(statusCode) else {
            if let message = serverErrorMessage(from: data) {
                throw OpenAITranscriptionError.server(message)
            }
            throw OpenAIFileTranscriptionError.requestFailed(statusCode)
        }

        return try transcriptionLines(from: data)
    }

    static func refineSegments(
        audioURL: URL,
        segments: [OpenAITranscriptRefinementSegment],
        language: TranscriptionLanguage,
        apiKey: String,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [TranscriptionLine] {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw OpenAITranscriptionError.missingAPIKey
        }

        let validSegments = segments
            .map { segment in
                OpenAITranscriptRefinementSegment(
                    startSeconds: max(segment.startSeconds, 0),
                    endSeconds: max(segment.endSeconds, segment.startSeconds),
                    localText: normalizedTranscriptText(segment.localText)
                )
            }
            .filter { !$0.localText.isEmpty }

        guard !validSegments.isEmpty else {
            throw OpenAIFileTranscriptionError.noRefinementSegments
        }

        progressHandler(0)
        var refinedLines: [TranscriptionLine] = []
        refinedLines.reserveCapacity(validSegments.count)

        for (index, segment) in validSegments.enumerated() {
            try Task.checkCancellation()

            let text: String
            if let segmentAudioURL = try await exportAudioSegment(audioURL: audioURL, segment: segment) {
                defer {
                    try? FileManager.default.removeItem(at: segmentAudioURL)
                }
                do {
                    let lines = try await transcribe(
                        audioURL: segmentAudioURL,
                        language: language,
                        apiKey: trimmedAPIKey,
                        mode: .refinedSegments
                    )
                    let refinedText = normalizedTranscriptText(lines.plainTranscriptText)
                    text = refinedText.isEmpty ? segment.localText : refinedText
                } catch OpenAIFileTranscriptionError.emptyTranscript {
                    text = segment.localText
                }
            } else {
                text = segment.localText
            }

            if !text.isEmpty {
                refinedLines.append(
                    TranscriptionLine(startSeconds: segment.startSeconds, text: text, isFinal: true)
                )
            }
            progressHandler(Double(index + 1) / Double(validSegments.count))
        }

        guard !refinedLines.isEmpty else {
            throw OpenAIFileTranscriptionError.emptyTranscript
        }

        return refinedLines
    }

    private static func makeTranscriptionRequest(apiKey: String, boundary: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            throw OpenAITranscriptionError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func makeMultipartBodyFile(
        audioURL: URL,
        language: TranscriptionLanguage,
        mode: OpenAIFileTranscriptionMode,
        prompt: String?,
        boundary: String
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-transcription-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: bodyURL)
        defer {
            try? outputHandle.close()
        }

        writeField(name: "model", value: mode.model, boundary: boundary, to: outputHandle)
        writeField(name: "response_format", value: mode.responseFormat, boundary: boundary, to: outputHandle)
        if mode == .segmented {
            writeField(name: "timestamp_granularities[]", value: "segment", boundary: boundary, to: outputHandle)
        }
        writeField(name: "temperature", value: "0.2", boundary: boundary, to: outputHandle)
        if let languageCode = language.locale.language.languageCode?.identifier, !languageCode.isEmpty {
            writeField(name: "language", value: languageCode, boundary: boundary, to: outputHandle)
        }
        let promptText = normalizedPromptText(prompt)
        if !promptText.isEmpty {
            writeField(name: "prompt", value: promptText, boundary: boundary, to: outputHandle)
        }
        try writeFile(audioURL, fieldName: "file", boundary: boundary, to: outputHandle)
        writeString("--\(boundary)--\r\n", to: outputHandle)

        return bodyURL
    }

    private static func exportAudioSegment(
        audioURL: URL,
        segment: OpenAITranscriptRefinementSegment
    ) async throws -> URL? {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw OpenAIFileTranscriptionError.segmentExportFailed
        }

        let startSeconds = min(max(segment.startSeconds, 0), duration)
        let endSeconds = min(max(segment.endSeconds, startSeconds), duration)
        guard endSeconds - startSeconds >= minimumRefinementSegmentDuration else {
            return nil
        }

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = tracks.first else {
            throw OpenAIFileTranscriptionError.segmentExportFailed
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw OpenAIFileTranscriptionError.segmentExportFailed
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: endSeconds - startSeconds, preferredTimescale: 600)
        )
        try compositionTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-refine-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw OpenAIFileTranscriptionError.segmentExportFailed
        }
        exporter.shouldOptimizeForNetworkUse = true

        try await exporter.export(to: outputURL, as: .m4a)
        return outputURL
    }

    private static func writeField(
        name: String,
        value: String,
        boundary: String,
        to handle: FileHandle
    ) {
        writeString("--\(boundary)\r\n", to: handle)
        writeString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: handle)
        writeString("\(value)\r\n", to: handle)
    }

    private static func writeFile(
        _ audioURL: URL,
        fieldName: String,
        boundary: String,
        to outputHandle: FileHandle
    ) throws {
        let filename = audioURL.lastPathComponent.isEmpty ? "recording.wav" : audioURL.lastPathComponent
        writeString("--\(boundary)\r\n", to: outputHandle)
        writeString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n", to: outputHandle)
        writeString("Content-Type: \(contentType(for: audioURL))\r\n\r\n", to: outputHandle)

        let inputHandle = try FileHandle(forReadingFrom: audioURL)
        defer {
            try? inputHandle.close()
        }

        while true {
            let chunk = inputHandle.readData(ofLength: 256 * 1024)
            guard !chunk.isEmpty else {
                break
            }
            outputHandle.write(chunk)
        }

        writeString("\r\n", to: outputHandle)
    }

    private static func writeString(_ value: String, to handle: FileHandle) {
        handle.write(Data(value.utf8))
    }

    private static func contentType(for audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "flac":
            return "audio/flac"
        case "mp3", "mpga", "mpeg":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "ogg":
            return "audio/ogg"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private static func transcriptionLines(from data: Data) throws -> [TranscriptionLine] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIFileTranscriptionError.invalidResponse
        }

        if let segments = object["segments"] as? [[String: Any]] {
            let lines = segments.compactMap { segment -> TranscriptionLine? in
                let text = normalizedTranscriptText(segment["text"] as? String)
                guard !text.isEmpty else {
                    return nil
                }
                let startSeconds = segment["start"] as? Double ?? 0
                return TranscriptionLine(startSeconds: startSeconds, text: text, isFinal: true)
            }
            if !lines.isEmpty {
                return lines
            }
        }

        let text = normalizedTranscriptText(object["text"] as? String)
        guard !text.isEmpty else {
            throw OpenAIFileTranscriptionError.emptyTranscript
        }

        return [TranscriptionLine(startSeconds: 0, text: text, isFinal: true)]
    }

    private static func normalizedTranscriptText(_ text: String?) -> String {
        guard let text else {
            return ""
        }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPromptText(_ text: String?) -> String {
        String(normalizedTranscriptText(text).prefix(1_500))
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        return nil
    }
}

enum OpenAIFileTranscriptionError: LocalizedError {
    case requestFailed(Int)
    case invalidResponse
    case emptyTranscript
    case noRefinementSegments
    case segmentExportFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed(let statusCode):
            return String(
                format: String(localized: L10n.OpenAITranscription.fileTranscriptionFailedFormat),
                statusCode
            )
        case .invalidResponse:
            return String(localized: L10n.OpenAITranscription.invalidFileTranscriptionResponse)
        case .emptyTranscript:
            return String(localized: L10n.Import.noRecognizedText)
        case .noRefinementSegments:
            return String(localized: L10n.OpenAITranscription.noRefinementSegments)
        case .segmentExportFailed:
            return String(localized: L10n.OpenAITranscription.segmentExportFailed)
        }
    }
}
