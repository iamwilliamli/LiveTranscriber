import Foundation

public enum RecordingAssetKind: String, Codable, CaseIterable, Hashable, Sendable {
    case primaryAudio = "primary_audio"
    case microphoneAudio = "microphone_audio"
    case systemAudio = "system_audio"
    case mixedAudio = "mixed_audio"
    case screenVideo = "screen_video"
    case cameraVideo = "camera_video"
    case transcript
    case thumbnail
    case attachment

    public var isAudio: Bool {
        switch self {
        case .primaryAudio, .microphoneAudio, .systemAudio, .mixedAudio:
            return true
        case .screenVideo, .cameraVideo, .transcript, .thumbnail, .attachment:
            return false
        }
    }

    public var isVideo: Bool {
        self == .screenVideo || self == .cameraVideo
    }
}

public struct RecordingAsset: Codable, Hashable, Identifiable, Sendable {
    public typealias ID = String

    public var id: ID
    public var kind: RecordingAssetKind
    public var relativePath: String
    public var contentTypeIdentifier: String?
    public var durationSeconds: Double?
    public var byteCount: Int64?

    public init(
        id: ID,
        kind: RecordingAssetKind,
        relativePath: String,
        contentTypeIdentifier: String? = nil,
        durationSeconds: Double? = nil,
        byteCount: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.contentTypeIdentifier = contentTypeIdentifier
        self.durationSeconds = durationSeconds
        self.byteCount = byteCount
    }

    public var isSafeRelativePath: Bool {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !(trimmedPath as NSString).isAbsolutePath else {
            return false
        }

        return NSString(string: trimmedPath).pathComponents.allSatisfy { component in
            component != ".." && component != "/"
        }
    }
}

public struct RecordingSession: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public var id: UUID
    public var schemaVersion: Int
    public var createdAt: Date
    public var title: String
    public var durationSeconds: Double
    public var languageIdentifier: String?
    public var assets: [RecordingAsset]
    public var primaryAssetID: RecordingAsset.ID?

    public init(
        id: UUID,
        schemaVersion: Int = RecordingSession.currentSchemaVersion,
        createdAt: Date,
        title: String,
        durationSeconds: Double,
        languageIdentifier: String? = nil,
        assets: [RecordingAsset],
        primaryAssetID: RecordingAsset.ID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.title = title
        self.durationSeconds = durationSeconds
        self.languageIdentifier = languageIdentifier
        self.assets = assets
        self.primaryAssetID = primaryAssetID
    }

    public var primaryAsset: RecordingAsset? {
        if let primaryAssetID,
           let selectedAsset = assets.first(where: { $0.id == primaryAssetID }) {
            return selectedAsset
        }
        return assets.first(where: { $0.kind.isAudio || $0.kind.isVideo })
    }
}

public enum LegacyRecordingAssetMigration {
    public static let primaryAudioID = "legacy.primary-audio"
    public static let transcriptID = "legacy.transcript"

    public static func migrate(
        _ existingAssets: [RecordingAsset]?,
        audioFileName: String,
        transcriptFileName: String,
        durationSeconds: Double
    ) -> [RecordingAsset] {
        var assets = existingAssets ?? []
        upsert(
            id: primaryAudioID,
            kind: .primaryAudio,
            relativePath: audioFileName,
            durationSeconds: max(0, durationSeconds),
            in: &assets
        )
        upsert(
            id: transcriptID,
            kind: .transcript,
            relativePath: transcriptFileName,
            durationSeconds: nil,
            in: &assets
        )
        return assets
    }

    private static func upsert(
        id: RecordingAsset.ID,
        kind: RecordingAssetKind,
        relativePath: String,
        durationSeconds: Double?,
        in assets: inout [RecordingAsset]
    ) {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return
        }

        let existingIndex = assets.firstIndex(where: { $0.id == id })
            ?? assets.firstIndex(where: {
                $0.kind == kind && $0.relativePath == trimmedPath
            })
        if let existingIndex {
            assets[existingIndex].relativePath = trimmedPath
            assets[existingIndex].durationSeconds = durationSeconds
            return
        }

        assets.append(
            RecordingAsset(
                id: id,
                kind: kind,
                relativePath: trimmedPath,
                durationSeconds: durationSeconds
            )
        )
    }
}
