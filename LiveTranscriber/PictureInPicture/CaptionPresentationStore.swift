import Foundation
import TranscriberDomain

struct CaptionSnapshot: Equatable, Sendable {
    var originalText: String
    var translatedText: String?
    var sourceLanguageID: String
    var targetLanguageID: String?
    var isInterim: Bool
    var sessionState: SystemAudioSessionState

    static let empty = CaptionSnapshot(
        originalText: "",
        translatedText: nil,
        sourceLanguageID: TranscriptionLanguage.defaultLanguageID,
        targetLanguageID: nil,
        isInterim: false,
        sessionState: .idle
    )
}

@MainActor
final class CaptionPresentationStore: ObservableObject {
    @Published private(set) var snapshot: CaptionSnapshot = .empty

    private var finalLines: [TranscriptionLine] = []
    private var interimLine: TranscriptionLine?
    private var translations: [TranscriptionLine.ID: String] = [:]

    func updateTranscript(
        finalLines: [TranscriptionLine],
        interimLine: TranscriptionLine?,
        sourceLanguageID: String
    ) {
        self.finalLines = finalLines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        self.interimLine = interimLine.flatMap { line in
            line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : line
        }
        publish(sourceLanguageID: sourceLanguageID)
    }

    func updateTranslation(
        _ translations: [TranscriptionLine.ID: String],
        targetLanguageID: String?
    ) {
        self.translations = translations
        var updated = snapshot
        updated.targetLanguageID = targetLanguageID
        updated.translatedText = latestTranslatedText
        publishIfChanged(updated)
    }

    func updateSessionState(_ state: SystemAudioSessionState) {
        var updated = snapshot
        updated.sessionState = state
        publishIfChanged(updated)
    }

    func resetTranscript(sourceLanguageID: String) {
        finalLines = []
        interimLine = nil
        translations = [:]
        var updated = snapshot
        updated.originalText = ""
        updated.translatedText = nil
        updated.sourceLanguageID = sourceLanguageID
        updated.targetLanguageID = nil
        updated.isInterim = false
        publishIfChanged(updated)
    }

    private var latestTranslatedText: String? {
        guard let finalLineID = finalLines.last?.id,
              let text = translations[finalLineID]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func publish(sourceLanguageID: String) {
        let finalText = finalLines.last?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let interimText = interimLine?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalText = [finalText, interimText]
            .compactMap { text -> String? in
                guard let text, !text.isEmpty else { return nil }
                return text
            }
            .reduce(into: [String]()) { result, text in
                if result.last != text {
                    result.append(text)
                }
            }
            .joined(separator: "\n")

        var updated = snapshot
        updated.originalText = originalText
        updated.translatedText = latestTranslatedText
        updated.sourceLanguageID = sourceLanguageID
        updated.isInterim = interimLine != nil
        publishIfChanged(updated)
    }

    private func publishIfChanged(_ updated: CaptionSnapshot) {
        guard updated != snapshot else { return }
        snapshot = updated
    }
}
