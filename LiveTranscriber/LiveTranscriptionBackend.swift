import Foundation
import Security

enum LiveTranscriptionBackend: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleOnDevice
    case localWhisperBeta

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
        case .localWhisperBeta:
            return L10n.TranscriptionBackend.localWhisperBetaTitle
        }
    }

    var detailResource: LocalizedStringResource {
        switch self {
        case .appleOnDevice:
            return L10n.TranscriptionBackend.appleOnDeviceDetail
        case .localWhisperBeta:
            return L10n.TranscriptionBackend.localWhisperBetaDetail
        }
    }

    var requiresAppleSpeech: Bool {
        switch self {
        case .appleOnDevice:
            return true
        case .localWhisperBeta:
            return false
        }
    }

    var usesLocalWhisper: Bool {
        switch self {
        case .appleOnDevice:
            return false
        case .localWhisperBeta:
            return true
        }
    }

    static var defaultBackend: LiveTranscriptionBackend {
        .appleOnDevice
    }
}

/// Removes configuration and credentials left by app versions that offered a
/// direct-to-provider online transcription path. Running this on every launch
/// is intentional and idempotent because that path is no longer available.
enum LegacyOnlineTranscriptionCleanup {
    private static let enabledDefaultsKey = "openai.transcription.enabled"
    private static let keychainService = "com.reddownloader.LiveTranscriber.openai"
    private static let keychainAccounts = ["api-key", "realtime-api-key"]

    static func run() {
        UserDefaults.standard.removeObject(forKey: enabledDefaultsKey)

        for account in keychainAccounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
