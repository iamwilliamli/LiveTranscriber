import Foundation
import TranscriberDomain

typealias TranscriptionLanguage = TranscriberDomain.TranscriptionLanguage
typealias TranscriptionLine = TranscriberDomain.TranscriptionLine

enum RecordingAudioFormat: String, CaseIterable, Identifiable, Codable {
    case wav
    case m4a

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .wav:
            return "WAV"
        case .m4a:
            return "M4A"
        }
    }

    var detail: String {
        String(localized: detailResource)
    }

    var detailResource: LocalizedStringResource {
        switch self {
        case .wav:
            return L10n.Transcription.wavDetail
        case .m4a:
            return L10n.Transcription.m4aDetail
        }
    }

    var fileExtension: String {
        rawValue
    }

    var badgeText: String {
        title
    }

    static var defaultFormat: RecordingAudioFormat {
        .wav
    }
}
