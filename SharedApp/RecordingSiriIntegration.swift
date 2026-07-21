import AppIntents
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

struct RecordingEntity: AppEntity, IndexedEntity, URLRepresentableEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "siri.recording_entity",
        defaultValue: "Recording",
        table: "Semantic",
        comment: "App Entity type and parameter title for a saved recording."
    ))
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

        return String(localized: L10n.Siri.noSummary)
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

        return String(localized: L10n.Siri.noTranscript)
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

#if HAS_IOS27_SDK
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
#endif

struct ReadRecordingSummaryIntent: AppIntent {
    static let title = LocalizedStringResource(
        "siri.read_summary.title",
        defaultValue: "Read Recording Summary",
        table: "Semantic",
        comment: "Siri intent title for reading a recording summary."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "app_intents.read_recording_summary.description",
        defaultValue: "Reads the saved summary for a recording.",
        table: "Semantic",
        comment: "App Intent description for reading a recording summary."
    ))

    @Parameter(title: LocalizedStringResource(
        "siri.recording_entity",
        defaultValue: "Recording",
        table: "Semantic",
        comment: "App Entity type and parameter title for a saved recording."
    ))
    var recording: RecordingEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Read the summary of \(\.$recording)", table: "Semantic")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = RecordingSiriText.readableDialog(recording.summaryText)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct ReadRecordingTranscriptIntent: AppIntent {
    static let title = LocalizedStringResource(
        "siri.read_transcript.title",
        defaultValue: "Read Recording Transcript",
        table: "Semantic",
        comment: "Siri intent title for reading a recording transcript."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "app_intents.read_recording_transcript.description",
        defaultValue: "Reads the transcript for a recording.",
        table: "Semantic",
        comment: "App Intent description for reading a recording transcript."
    ))

    @Parameter(title: LocalizedStringResource(
        "siri.recording_entity",
        defaultValue: "Recording",
        table: "Semantic",
        comment: "App Entity type and parameter title for a saved recording."
    ))
    var recording: RecordingEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Read the transcript of \(\.$recording)", table: "Semantic")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = RecordingSiriText.readableDialog(recording.transcriptText)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct SearchRecordingsIntent: AppIntent {
    static let title = LocalizedStringResource(
        "siri.search.title",
        defaultValue: "Search Recordings",
        table: "Semantic",
        comment: "Siri intent title for searching recordings."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "app_intents.search_recordings.description",
        defaultValue: "Searches recording titles, summaries, tags, and transcripts.",
        table: "Semantic",
        comment: "App Intent description for searching recordings."
    ))

    @Parameter(title: LocalizedStringResource(
        "siri.search.parameter",
        defaultValue: "Search Text",
        table: "Semantic",
        comment: "Siri search text parameter title."
    ))
    var searchText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search recordings for \(\.$searchText)", table: "Semantic")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[RecordingEntity]> {
        let results = try await RecordingEntityQuery().entities(matching: searchText)
        let dialog: String
        if results.isEmpty {
            dialog = String(localized: L10n.Siri.searchNoMatches)
        } else {
            let titles = results.prefix(5).map(\.title).joined(separator: ", ")
            dialog = String(
                format: String(localized: L10n.Siri.searchMatchesFormat),
                results.count,
                titles
            )
        }
        return .result(value: results, dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct OpenRecordingIntent: OpenIntent, URLRepresentableIntent {
    static let title = LocalizedStringResource(
        "siri.open.title",
        defaultValue: "Open Recording",
        table: "Semantic",
        comment: "Siri intent title for opening a recording."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "app_intents.open_recording.description",
        defaultValue: "Opens a recording in Live Transcriber.",
        table: "Semantic",
        comment: "App Intent description for opening a recording."
    ))

    @Parameter(title: LocalizedStringResource(
        "siri.recording_entity",
        defaultValue: "Recording",
        table: "Semantic",
        comment: "App Entity type and parameter title for a saved recording."
    ))
    var target: RecordingEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)", table: "Semantic")
    }
}

struct LiveTranscriberAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        #if os(macOS)
        AppShortcut(
            intent: StartMacQuickRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Start a transcription in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "control.quick_recording.start",
                defaultValue: "Start Recording",
                table: "Semantic",
                comment: "Shortcuts short title for starting a recording on macOS."
            ),
            systemImageName: "record.circle"
        )
        #endif

        AppShortcut(
            intent: ReadRecordingSummaryIntent(),
            phrases: [
                "Read my recording summary in \(.applicationName)",
                "Read the summary of a recording in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "siri.read_summary.short_title",
                defaultValue: "Read Summary",
                table: "Semantic",
                comment: "Shortcuts short title for reading a recording summary."
            ),
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: ReadRecordingTranscriptIntent(),
            phrases: [
                "Read my recording transcript in \(.applicationName)",
                "Read the transcript of a recording in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "siri.read_transcript.short_title",
                defaultValue: "Read Transcript",
                table: "Semantic",
                comment: "Shortcuts short title for reading a recording transcript."
            ),
            systemImageName: "text.quote"
        )

        AppShortcut(
            intent: SearchRecordingsIntent(),
            phrases: [
                "Search recordings in \(.applicationName)",
                "Find a recording in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "siri.search.short_title",
                defaultValue: "Search Recordings",
                table: "Semantic",
                comment: "Shortcuts short title for searching recordings."
            ),
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
        return String(normalized[..<endIndex])
            + "\n\n"
            + String(localized: L10n.Siri.transcriptTruncated)
    }
}
