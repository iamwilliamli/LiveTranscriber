import Foundation
import TranscriberDomain

struct MacCaptureOutputPlan: Equatable, Sendable {
    var sessionID: UUID
    var directoryURL: URL
    var videoURL: URL
    var systemAudioURL: URL?
    var microphoneAudioURL: URL?
    var manifestURL: URL

    init(
        sessionID: UUID = UUID(),
        directoryURL: URL,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool
    ) {
        self.sessionID = sessionID
        self.directoryURL = directoryURL
        let stem = sessionID.uuidString.lowercased()
        videoURL = directoryURL.appendingPathComponent("\(stem).screen.mp4")
        systemAudioURL = capturesSystemAudio
            ? directoryURL.appendingPathComponent("\(stem).m4a")
            : nil
        microphoneAudioURL = capturesMicrophone
            ? directoryURL.appendingPathComponent("\(stem).microphone.m4a")
            : nil
        manifestURL = directoryURL.appendingPathComponent("\(stem).session.json")
    }

    var outputURLs: [URL] {
        [videoURL, systemAudioURL, microphoneAudioURL, manifestURL].compactMap { $0 }
    }
}

struct MacCaptureResult: Sendable {
    var session: RecordingSession
    var manifestURL: URL
}

enum MacCaptureStorage {
    private static let iCloudContainerIdentifier = "iCloud.com.iamwilliamli.LiveTranscriber"

    static func preferredRecordingsDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let directoryURL: URL
        if let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: iCloudContainerIdentifier
        ) {
            directoryURL = containerURL.appendingPathComponent(
                "Data/Recordings",
                isDirectory: true
            )
        } else if let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            directoryURL = applicationSupportURL
                .appendingPathComponent("LiveTranscriber", isDirectory: true)
                .appendingPathComponent("Recordings", isDirectory: true)
        } else {
            throw MacCaptureError.recordingDirectoryUnavailable
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    static func makeResult(
        plan: MacCaptureOutputPlan,
        startedAt: Date,
        durationSeconds: Double,
        sourceTitle: String,
        fileManager: FileManager = .default
    ) throws -> MacCaptureResult {
        guard isNonemptyFile(plan.videoURL, fileManager: fileManager) else {
            throw MacCaptureError.missingVideoOutput
        }

        var assets: [RecordingAsset] = [
            asset(
                id: "capture.screen-video",
                kind: .screenVideo,
                url: plan.videoURL,
                contentTypeIdentifier: "public.mpeg-4",
                durationSeconds: durationSeconds,
                fileManager: fileManager
            ),
        ]
        if let systemAudioURL = plan.systemAudioURL,
           isNonemptyFile(systemAudioURL, fileManager: fileManager) {
            assets.append(
                asset(
                    id: "capture.system-audio",
                    kind: .systemAudio,
                    url: systemAudioURL,
                    contentTypeIdentifier: "public.mpeg-4-audio",
                    durationSeconds: durationSeconds,
                    fileManager: fileManager
                )
            )
        }
        if let microphoneAudioURL = plan.microphoneAudioURL,
           isNonemptyFile(microphoneAudioURL, fileManager: fileManager) {
            assets.append(
                asset(
                    id: "capture.microphone-audio",
                    kind: .microphoneAudio,
                    url: microphoneAudioURL,
                    contentTypeIdentifier: "public.mpeg-4-audio",
                    durationSeconds: durationSeconds,
                    fileManager: fileManager
                )
            )
        }

        let trimmedSourceTitle = sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedSourceTitle.isEmpty
            ? startedAt.formatted(date: .abbreviated, time: .shortened)
            : "\(trimmedSourceTitle) — \(startedAt.formatted(date: .abbreviated, time: .shortened))"
        let session = RecordingSession(
            id: plan.sessionID,
            createdAt: startedAt,
            title: title,
            durationSeconds: max(durationSeconds, 0),
            assets: assets,
            primaryAssetID: "capture.screen-video"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: plan.manifestURL, options: .atomic)
        return MacCaptureResult(session: session, manifestURL: plan.manifestURL)
    }

    static func removeIncompleteOutputs(
        plan: MacCaptureOutputPlan,
        fileManager: FileManager = .default
    ) {
        for url in plan.outputURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private static func asset(
        id: RecordingAsset.ID,
        kind: RecordingAssetKind,
        url: URL,
        contentTypeIdentifier: String,
        durationSeconds: Double,
        fileManager: FileManager
    ) -> RecordingAsset {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value
        return RecordingAsset(
            id: id,
            kind: kind,
            relativePath: url.lastPathComponent,
            contentTypeIdentifier: contentTypeIdentifier,
            durationSeconds: max(durationSeconds, 0),
            byteCount: byteCount
        )
    }

    private static func isNonemptyFile(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let byteCount = (attributes[.size] as? NSNumber)?.int64Value else {
            return false
        }
        return byteCount > 0
    }
}

enum MacCaptureError: LocalizedError {
    case noSourceSelected
    case recordingDirectoryUnavailable
    case microphonePermissionDenied
    case missingVideoOutput
    case noAudioSamples
    case audioWriterFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSourceSelected:
            return "Choose a screen, app, or window before starting capture."
        case .recordingDirectoryUnavailable:
            return "Live Transcriber could not open a recording directory."
        case .microphonePermissionDenied:
            return "Microphone access is required when microphone capture is enabled."
        case .missingVideoOutput:
            return "ScreenCaptureKit did not produce a playable video file."
        case .noAudioSamples:
            return "No audio samples were captured for this track."
        case .audioWriterFailed(let message):
            return "The audio track could not be written: \(message)"
        }
    }
}
