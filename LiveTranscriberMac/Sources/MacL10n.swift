import Foundation

enum MacL10n {
    private static let table = "MacSemantic"

    private static func resource(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        comment: StaticString
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            key,
            defaultValue: defaultValue,
            table: table,
            comment: comment
        )
    }

    static let appName = resource(
        "mac.app.name",
        defaultValue: "Live Transcriber",
        comment: "macOS app name shown in navigation and settings."
    )
    static let workspace = resource(
        "mac.sidebar.workspace",
        defaultValue: "Workspace",
        comment: "Sidebar section title for primary macOS destinations."
    )
    static let library = resource(
        "mac.sidebar.library",
        defaultValue: "Library",
        comment: "Sidebar destination for saved recordings."
    )
    static let capture = resource(
        "mac.sidebar.capture",
        defaultValue: "Capture",
        comment: "Sidebar destination for screen and window capture."
    )
    static let libraryTitle = resource(
        "mac.library.title",
        defaultValue: "Recording Library",
        comment: "Title of the macOS recording library."
    )
    static let libraryReady = resource(
        "mac.library.ready",
        defaultValue: "Mac library foundation is ready",
        comment: "Empty-state title before shared recording storage is connected."
    )
    static let libraryReadyDetail = resource(
        "mac.library.ready_detail",
        defaultValue: "Shared recording access will be connected after the cross-platform domain package is in place.",
        comment: "Empty-state detail before shared recording storage is connected."
    )
    static let loadingLibrary = resource(
        "mac.library.loading",
        defaultValue: "Loading recordings…",
        comment: "Progress label while the macOS recording library loads."
    )
    static let refreshLibrary = resource(
        "mac.library.refresh",
        defaultValue: "Refresh Library",
        comment: "Action that refreshes the macOS recording library."
    )
    static let librarySource = resource(
        "mac.library.source",
        defaultValue: "Library Source",
        comment: "Menu title for choosing the macOS recording library source."
    )
    static let chooseFolder = resource(
        "mac.library.choose_folder",
        defaultValue: "Choose Recording Folder…",
        comment: "Action that lets the user choose a recording folder."
    )
    static let useICloud = resource(
        "mac.library.use_icloud",
        defaultValue: "Use iCloud Library",
        comment: "Action that switches the macOS library back to iCloud."
    )
    static let noRecordings = resource(
        "mac.library.empty",
        defaultValue: "No recordings found",
        comment: "Empty-state title when a recording folder contains no media."
    )
    static let noRecordingsDetail = resource(
        "mac.library.empty_detail",
        defaultValue: "Recordings synced from iPhone will appear here, or you can choose another recording folder.",
        comment: "Empty-state explanation for the macOS recording library."
    )
    static let libraryUnavailable = resource(
        "mac.library.unavailable",
        defaultValue: "Recording library unavailable",
        comment: "Error-state title when the recording library cannot be opened."
    )
    static let preparingPlayback = resource(
        "mac.library.preparing_playback",
        defaultValue: "Preparing playback…",
        comment: "Progress label while a recording downloads or opens."
    )
    static let assets = resource(
        "mac.library.assets",
        defaultValue: "Assets",
        comment: "Heading above a recording's asset list."
    )
    static let transcript = resource(
        "mac.library.transcript",
        defaultValue: "Transcript",
        comment: "Heading above a recording transcript."
    )
    static let noTranscript = resource(
        "mac.library.no_transcript",
        defaultValue: "No transcript is available for this recording.",
        comment: "Placeholder when a recording has no transcript asset."
    )
    static let captureTitle = resource(
        "mac.capture.title",
        defaultValue: "Screen & Window Capture",
        comment: "Title of the macOS capture workspace."
    )
    static let captureDetail = resource(
        "mac.capture.detail",
        defaultValue: "The native capture pipeline will record any selected meeting window, system audio, and an optional microphone track.",
        comment: "Description of the planned macOS ScreenCaptureKit pipeline."
    )
    static let screenCapture = resource(
        "mac.capture.screen",
        defaultValue: "ScreenCaptureKit",
        comment: "Title for the macOS screen capture capability."
    )
    static let screenCaptureDetail = resource(
        "mac.capture.screen_detail",
        defaultValue: "Choose a display or individual app window without coupling capture to one meeting provider.",
        comment: "Detail for the macOS screen capture capability."
    )
    static let audioCapture = resource(
        "mac.capture.audio",
        defaultValue: "Independent audio tracks",
        comment: "Title for macOS system and microphone audio capture."
    )
    static let audioCaptureDetail = resource(
        "mac.capture.audio_detail",
        defaultValue: "Keep system audio and microphone input separate so mixing and transcription remain reversible.",
        comment: "Detail for macOS system and microphone audio capture."
    )
    static let foundationStatus = resource(
        "mac.capture.foundation_status",
        defaultValue: "Capture engine is the next implementation phase",
        comment: "Status shown before the macOS capture engine is implemented."
    )
    static let settingsTitle = resource(
        "mac.settings.title",
        defaultValue: "Settings",
        comment: "Title of the macOS settings window."
    )
    static let foundation = resource(
        "mac.settings.foundation",
        defaultValue: "Foundation",
        comment: "Settings section describing the macOS foundation state."
    )
    static let platform = resource(
        "mac.settings.platform",
        defaultValue: "Platform",
        comment: "Settings label for the app platform."
    )
    static let nativeMacOS = resource(
        "mac.settings.native_macos",
        defaultValue: "Native macOS",
        comment: "Settings value confirming this is a native macOS app."
    )
    static let domainSchema = resource(
        "mac.settings.domain_schema",
        defaultValue: "Domain Schema",
        comment: "Settings label for the shared cross-platform domain schema version."
    )
}
