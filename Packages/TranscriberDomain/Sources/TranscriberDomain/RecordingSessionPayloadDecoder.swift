import Foundation

public enum RecordingSessionPayloadDecoder {
    public static func decode(_ data: Data) throws -> RecordingSession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let session = try? decoder.decode(RecordingSession.self, from: data) {
            return session
        }

        let legacy = try decoder.decode(LegacyRecordingPayload.self, from: data)
        let assets = LegacyRecordingAssetMigration.migrate(
            legacy.assets,
            audioFileName: legacy.audioFileName,
            transcriptFileName: legacy.transcriptFileName,
            durationSeconds: legacy.durationSeconds
        )
        return RecordingSession(
            id: legacy.id,
            createdAt: legacy.createdAt,
            title: legacy.resolvedTitle,
            durationSeconds: legacy.durationSeconds,
            languageIdentifier: legacy.languageID,
            assets: assets,
            primaryAssetID: assets.first(where: {
                $0.id == LegacyRecordingAssetMigration.primaryAudioID
            })?.id
        )
    }
}

private struct LegacyRecordingPayload: Decodable {
    var id: UUID
    var createdAt: Date
    var durationSeconds: Double
    var languageID: String?
    var displayName: String?
    var audioFileName: String
    var transcriptFileName: String
    var assets: [RecordingAsset]?

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case durationSeconds
        case languageID
        case displayName
        case audioFileName
        case transcriptFileName
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        languageID = try container.decodeIfPresent(String.self, forKey: .languageID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        transcriptFileName = try container.decode(String.self, forKey: .transcriptFileName)
        assets = try container.decodeIfPresent([RecordingAsset].self, forKey: .assets)
    }

    var resolvedTitle: String {
        if let title = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        let fallback = (audioFileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? audioFileName : fallback
    }
}
