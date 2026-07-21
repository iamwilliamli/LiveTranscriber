import Foundation
import TranscriberDomain
import Translation

enum AppleTranslationLanguages {
    static func supportedLanguages() async -> [TranscriptionLanguage] {
        let languages = await LanguageAvailability().supportedLanguages
        return normalizedLanguages(
            languages.compactMap { language in
                guard language.languageCode != nil else {
                    return nil
                }
                return language.minimalIdentifier
            }
        )
    }

    static func localeLanguage(for identifier: String) -> Locale.Language? {
        let language = Locale(identifier: identifier).language
        guard language.languageCode != nil else {
            return nil
        }
        return language
    }

    static func sameBaseLanguage(_ firstIdentifier: String, _ secondIdentifier: String) -> Bool {
        let firstLanguage = Locale(identifier: firstIdentifier).language
        let secondLanguage = Locale(identifier: secondIdentifier).language
        let firstCode = firstLanguage.languageCode?.identifier
        let secondCode = secondLanguage.languageCode?.identifier
        guard let firstCode, let secondCode else {
            return firstIdentifier == secondIdentifier
        }
        guard firstCode == secondCode else {
            return false
        }

        let firstScript = firstLanguage.script?.identifier
        let secondScript = secondLanguage.script?.identifier
        if firstScript != nil || secondScript != nil {
            return firstScript == secondScript
        }

        return true
    }

    private static func normalizedLanguages(_ identifiers: [String]) -> [TranscriptionLanguage] {
        var seenIdentifiers = Set<String>()
        return identifiers.compactMap { identifier -> TranscriptionLanguage? in
            let language = Locale.Language(identifier: identifier)
            guard language.languageCode != nil else {
                return nil
            }

            let normalizedIdentifier = language.minimalIdentifier
            guard seenIdentifiers.insert(normalizedIdentifier).inserted else {
                return nil
            }

            return TranscriptionLanguage(id: normalizedIdentifier)
        }
        .sorted { first, second in
            first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
        }
    }
}
