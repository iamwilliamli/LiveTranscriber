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
}
