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
        defaultValue: "Record a selected meeting window, system audio, and an optional microphone track with the native macOS capture pipeline.",
        comment: "Description of the macOS ScreenCaptureKit pipeline."
    )
    static let captureSource = resource(
        "mac.capture.source",
        defaultValue: "Screen or Window",
        comment: "Heading for the selected ScreenCaptureKit source."
    )
    static let noCaptureSource = resource(
        "mac.capture.no_source",
        defaultValue: "Nothing selected yet",
        comment: "Placeholder before the user selects screen content."
    )
    static let chooseCaptureSource = resource(
        "mac.capture.choose_source",
        defaultValue: "Choose…",
        comment: "Action that opens the system screen-sharing picker."
    )
    static let captureSourceDetail = resource(
        "mac.capture.source_detail",
        defaultValue: "Use the macOS system picker to select a display, an app, or one meeting window.",
        comment: "Explanation beneath the capture source control."
    )
    static let audioTracks = resource(
        "mac.capture.audio_tracks",
        defaultValue: "Audio Tracks",
        comment: "Heading above system and microphone audio options."
    )
    static let systemAudio = resource(
        "mac.capture.system_audio",
        defaultValue: "System audio",
        comment: "Toggle label for system audio capture."
    )
    static let systemAudioDetail = resource(
        "mac.capture.system_audio_detail",
        defaultValue: "Capture meeting audio and keep a separate AAC track.",
        comment: "Detail for the system audio capture toggle."
    )
    static let microphoneAudio = resource(
        "mac.capture.microphone_audio",
        defaultValue: "Microphone",
        comment: "Toggle label for microphone capture."
    )
    static let microphoneAudioDetail = resource(
        "mac.capture.microphone_audio_detail",
        defaultValue: "Capture your voice as an independent AAC track.",
        comment: "Detail for the microphone capture toggle."
    )
    static let startCapture = resource(
        "mac.capture.start",
        defaultValue: "Start Recording",
        comment: "Action that starts screen capture."
    )
    static let stopCapture = resource(
        "mac.capture.stop",
        defaultValue: "Stop Recording",
        comment: "Action that stops screen capture."
    )
    static let startingCapture = resource(
        "mac.capture.starting",
        defaultValue: "Starting…",
        comment: "Status while ScreenCaptureKit starts."
    )
    static let savingCapture = resource(
        "mac.capture.saving",
        defaultValue: "Saving…",
        comment: "Status while capture files finish writing."
    )
    static let captureIdle = resource(
        "mac.capture.idle",
        defaultValue: "Select something to record",
        comment: "Capture status before a source is selected."
    )
    static let captureReady = resource(
        "mac.capture.ready",
        defaultValue: "Ready to record",
        comment: "Capture status after a source is selected."
    )
    static let captureRecording = resource(
        "mac.capture.recording",
        defaultValue: "Recording",
        comment: "Capture status while recording is active."
    )
    static let captureComplete = resource(
        "mac.capture.complete",
        defaultValue: "Recording saved",
        comment: "Capture status after recording succeeds."
    )
    static let captureFailed = resource(
        "mac.capture.failed",
        defaultValue: "Recording failed",
        comment: "Capture status after recording fails."
    )
    static let captureSaved = resource(
        "mac.capture.saved",
        defaultValue: "Capture saved",
        comment: "Heading in the successful capture card."
    )
    static let savedAssetCount = resource(
        "mac.capture.saved_asset_count",
        defaultValue: "%lld assets",
        comment: "Number of independent files saved for a capture."
    )
    static let openLibrary = resource(
        "mac.capture.open_library",
        defaultValue: "Open in Library",
        comment: "Action that opens a completed capture in the library."
    )
    static let newCapture = resource(
        "mac.capture.new",
        defaultValue: "New Capture",
        comment: "Action that resets the capture screen for another recording."
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
