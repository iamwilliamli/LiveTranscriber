import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

struct RecordingEntity: AppEntity, IndexedEntity, URLRepresentableEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recording")
    static let defaultQuery = RecordingEntityQuery()

    let id: UUID
    let title: String
    let createdAt: Date
    let durationSeconds: Int
    let languageName: String
    let summary: String?
    let transcript: String
    let transcriptPreview: String
    let tags: [String]
    let isTranscriptLocked: Bool

    var displayRepresentation: DisplayRepresentation {
        let subtitleParts = [
            languageName,
            Self.formattedDate(createdAt)
        ].filter { !$0.isEmpty }

        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitleParts.joined(separator: " - "))"
        )
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.contentDescription = summaryText
        attributes.textContent = searchableText
        attributes.keywords = searchableKeywords
        attributes.duration = NSNumber(value: durationSeconds)
        attributes.relatedUniqueIdentifier = id.uuidString
        return attributes
    }

    static var urlRepresentation: EntityURLRepresentation<RecordingEntity> {
        "livetranscriber://recording/\(.id)"
    }

    var summaryText: String {
        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }

        let trimmedPreview = transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreview.isEmpty {
            return trimmedPreview
        }

        return "No summary is available for this recording."
    }

    var transcriptText: String {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranscript.isEmpty {
            return trimmedTranscript
        }

        let trimmedPreview = transcriptPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPreview.isEmpty {
            return trimmedPreview
        }

        return "No transcript is available for this recording."
    }

    private var searchableText: String {
        [
            title,
            Self.formattedDate(createdAt),
            languageName,
            summary ?? "",
            transcriptPreview,
            transcript,
            tags.joined(separator: " ")
        ]
        .joined(separator: "\n\n")
    }

    private var searchableKeywords: [String] {
        var keywords = ["recording", "transcript", "summary", languageName]
        keywords.append(contentsOf: tags)
        return keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct RecordingEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [RecordingEntity] {
        let store = await Self.loadedStore()
        return await MainActor.run {
            identifiers.compactMap { identifier in
                guard let item = store.recording(withID: identifier) else {
                    return nil
                }
                return store.recordingEntity(for: item)
            }
        }
    }

    func entities(matching string: String) async throws -> [RecordingEntity] {
        let trimmedQuery = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await suggestedEntities()
        }

        let store = await Self.loadedStore()
        return await store.recordingEntities(matching: trimmedQuery)
    }

    func suggestedEntities() async throws -> [RecordingEntity] {
        let store = await Self.loadedStore()
        return await Array(store.recordingEntities().prefix(10))
    }

    @MainActor
    private static func loadedStore() async -> RecordingStore {
        let store = RecordingStore()
        await store.reload()
        return store
    }
}

@available(iOS 27.0, macOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
extension RecordingEntityQuery: IndexedEntityQuery {
    func reindexEntities(
        for identifiers: [UUID],
        indexDescription: CSSearchableIndexDescription
    ) async throws {
        let entities = try await entities(for: identifiers)
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }

    func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        let store = await Self.loadedStore()
        let entities = await store.recordingEntities()
        try await CSSearchableIndex.default().indexAppEntities(entities)
    }
}

struct ReadRecordingSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Recording Summary"
    static let description = IntentDescription("Reads the saved summary for a recording.")

    @Parameter(title: "Recording")
    var recording: RecordingEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Read the summary of \(\.$recording)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = RecordingSiriText.readableDialog(recording.summaryText)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct ReadRecordingTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Recording Transcript"
    static let description = IntentDescription("Reads the transcript for a recording.")

    @Parameter(title: "Recording")
    var recording: RecordingEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Read the transcript of \(\.$recording)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = RecordingSiriText.readableDialog(recording.transcriptText)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct SearchRecordingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Recordings"
    static let description = IntentDescription("Searches recording titles, summaries, tags, and transcripts.")

    @Parameter(title: "Search Text")
    var searchText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search recordings for \(\.$searchText)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[RecordingEntity]> {
        let results = try await RecordingEntityQuery().entities(matching: searchText)
        let dialog: String
        if results.isEmpty {
            dialog = "No matching recordings were found."
        } else {
            let titles = results.prefix(5).map(\.title).joined(separator: ", ")
            dialog = "Found \(results.count) matching recording\(results.count == 1 ? "" : "s"): \(titles)."
        }
        return .result(value: results, dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct OpenRecordingIntent: OpenIntent, URLRepresentableIntent {
    static let title: LocalizedStringResource = "Open Recording"
    static let description = IntentDescription("Opens a recording in Live Transcriber.")

    @Parameter(title: "Recording")
    var target: RecordingEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }
}

struct LiveTranscriberAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ReadRecordingSummaryIntent(),
            phrases: [
                "Read my recording summary in \(.applicationName)",
                "Read the summary of a recording in \(.applicationName)"
            ],
            shortTitle: "Read Summary",
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: ReadRecordingTranscriptIntent(),
            phrases: [
                "Read my recording transcript in \(.applicationName)",
                "Read the transcript of a recording in \(.applicationName)"
            ],
            shortTitle: "Read Transcript",
            systemImageName: "text.quote"
        )

        AppShortcut(
            intent: SearchRecordingsIntent(),
            phrases: [
                "Search recordings in \(.applicationName)",
                "Find a recording in \(.applicationName)"
            ],
            shortTitle: "Search Recordings",
            systemImageName: "magnifyingglass"
        )
    }
}

enum RecordingSiriText {
    private static let maxDialogCharacterCount = 3_500

    static func readableDialog(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard normalized.count > maxDialogCharacterCount else {
            return normalized
        }

        let endIndex = normalized.index(normalized.startIndex, offsetBy: maxDialogCharacterCount)
        return String(normalized[..<endIndex]) + "\n\nThe transcript is longer, so I read the beginning. Open the recording to review the rest."
    }
}
