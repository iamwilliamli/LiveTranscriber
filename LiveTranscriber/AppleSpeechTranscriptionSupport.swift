import Foundation
import Speech
import TranscriberDomain

enum AppleSpeechTranscriptionSupport {
    static func supportedLanguages() async -> [TranscriptionLanguage] {
        await normalizedLanguages(SpeechTranscriber.supportedLocales)
    }

    static func resolvedLocale(for language: TranscriptionLanguage) async -> Locale {
        let preferredLocale = Locale(identifier: language.id)
        return await SpeechTranscriber.supportedLocale(equivalentTo: preferredLocale) ?? preferredLocale
    }

    static func equivalentLanguage(
        for languageID: String,
        in languages: [TranscriptionLanguage]
    ) async -> TranscriptionLanguage? {
        let preferredLocale = Locale(identifier: languageID)
        if let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: preferredLocale),
           let language = matchingLanguage(for: speechLocale, in: languages) {
            return language
        }
        return nil
    }

    private static func normalizedLanguages(_ locales: [Locale]) -> [TranscriptionLanguage] {
        var seenIdentifiers = Set<String>()
        return locales.compactMap { locale -> TranscriptionLanguage? in
            let identifier = normalizedIdentifier(for: locale)
            guard !identifier.isEmpty, seenIdentifiers.insert(identifier).inserted else {
                return nil
            }
            return TranscriptionLanguage(id: identifier)
        }
        .sorted { first, second in
            first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
        }
    }

    private static func matchingLanguage(
        for locale: Locale,
        in languages: [TranscriptionLanguage]
    ) -> TranscriptionLanguage? {
        let identifier = normalizedIdentifier(for: locale)
        if let exact = languages.first(where: { $0.id == identifier }) {
            return exact
        }

        let language = locale.language
        return languages.first { candidate in
            let candidateLanguage = candidate.locale.language
            guard candidateLanguage.languageCode?.identifier == language.languageCode?.identifier else {
                return false
            }
            return candidateLanguage.region?.identifier == language.region?.identifier
                || candidateLanguage.script?.identifier == language.script?.identifier
        }
    }

    private static func normalizedIdentifier(for locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-")
    }
}
