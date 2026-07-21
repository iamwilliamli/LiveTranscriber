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
    static let refreshLibrary = resource(
        "mac.library.refresh",
        defaultValue: "Refresh Library",
        comment: "Action that refreshes the macOS recording library."
    )
    static let noTranscript = resource(
        "mac.library.no_transcript",
        defaultValue: "No transcript is available for this recording.",
        comment: "Placeholder when a recording has no transcript asset."
    )
    static let systemAudioRecording = resource(
        "mac.recording.system_audio",
        defaultValue: "System Audio",
        comment: "Title for recording audio played by apps on the Mac."
    )
    static let microphoneOnly = resource(
        "mac.recording.microphone_only",
        defaultValue: "Microphone Only",
        comment: "Recording input choice that captures only the microphone."
    )
    static let systemAudioOnly = resource(
        "mac.recording.system_audio_only",
        defaultValue: "System Audio Only",
        comment: "Recording input choice that saves only audio from selected Mac content."
    )
    static let microphoneAndSystemAudio = resource(
        "mac.recording.microphone_and_system_audio",
        defaultValue: "Microphone + System Audio",
        comment: "Recording input choice that combines microphone and Mac system audio."
    )
    static let chooseSystemAudioSource = resource(
        "mac.recording.choose_system_audio_source",
        defaultValue: "Choose App, Window, or Display…",
        comment: "Action that selects which Mac content supplies system audio."
    )
    static let systemAudioSource = resource(
        "mac.recording.system_audio_source",
        defaultValue: "System audio source",
        comment: "Label shown beside the selected system-audio source."
    )
    static let systemAudioLiveCaptionNote = resource(
        "mac.recording.system_audio_live_caption_note",
        defaultValue: "The saved audio combines the selected Mac audio with your microphone. Live captions and the waveform follow the selected Mac audio.",
        comment: "Explanation of system-audio recording and live caption behavior."
    )
    static let systemAudioOnlyLiveCaptionNote = resource(
        "mac.recording.system_audio_only_live_caption_note",
        defaultValue: "The recording, live captions, and waveform all use only the selected Mac audio. The microphone is not accessed.",
        comment: "Explanation that system-audio-only mode does not use the microphone."
    )
    static let systemAudioSourceSelectionHint = resource(
        "mac.recording.system_audio_source_selection_hint",
        defaultValue: "A window captures audio from its owning app. Choose a display when you want all Mac audio.",
        comment: "Guidance for choosing a ScreenCaptureKit source for system-audio recording."
    )
    static let systemAudioUnavailable = resource(
        "mac.recording.system_audio_unavailable",
        defaultValue: "System Audio Was Not Recorded",
        comment: "Alert title when system audio fails but a microphone fallback is available."
    )
    static let saveRecoveredSystemAudio = resource(
        "mac.recording.save_recovered_system_audio",
        defaultValue: "Save Recovered System Audio",
        comment: "Action that saves the duplicate system-audio transcription track if the primary system-audio writer fails."
    )
    static let systemAudioMicrophoneMixFallback = resource(
        "mac.recording.system_audio_mix_fallback",
        defaultValue: "The microphone track could not be mixed, so this recording contains system audio only.",
        comment: "Warning shown when system audio succeeds but mixing the microphone track fails."
    )
    static let systemAudioMicrophoneMissing = resource(
        "mac.recording.system_audio_microphone_missing",
        defaultValue: "No microphone samples were captured, so this recording contains system audio only.",
        comment: "Warning shown when a system-audio recording has no microphone samples."
    )
    static let systemAudioNoSamples = resource(
        "mac.recording.system_audio_no_samples",
        defaultValue: "No usable system audio was captured. Choose the app, window, or display that is playing audio and try again.",
        comment: "Error shown when a system-audio recording contains no usable samples."
    )
    static let systemAudioStorageUnavailable = resource(
        "mac.recording.system_audio_storage_unavailable",
        defaultValue: "Live Transcriber could not open temporary storage for the system-audio recording.",
        comment: "Error shown when temporary system-audio recording storage is unavailable."
    )
    static let systemAudioMicrophonePermissionDenied = resource(
        "mac.recording.system_audio_microphone_permission_denied",
        defaultValue: "Microphone access is required to combine your voice with system audio.",
        comment: "Error shown when microphone access is denied for combined system-audio recording."
    )
    static let systemAudioWriterFailedFormat = resource(
        "mac.recording.system_audio_writer_failed.format",
        defaultValue: "The system-audio recording could not be written: %@",
        comment: "System-audio writer error. Parameter: technical error detail."
    )
    static let systemAudioDisplay = resource(
        "mac.recording.system_audio_display",
        defaultValue: "Display",
        comment: "Fallback name for a selected display system-audio source."
    )
    static let systemAudioWindow = resource(
        "mac.recording.system_audio_window",
        defaultValue: "Window",
        comment: "Fallback name for a selected window system-audio source."
    )
    static let systemAudioApplication = resource(
        "mac.recording.system_audio_application",
        defaultValue: "Application",
        comment: "Fallback name for a selected application system-audio source."
    )
    static let systemAudioSelectedContent = resource(
        "mac.recording.system_audio_selected_content",
        defaultValue: "Selected Content",
        comment: "Fallback name for the selected system-audio source."
    )
    static let translationUnavailable = resource(
        "mac.transcription.translation_unavailable",
        defaultValue: "No additional translation languages are available",
        comment: "Disabled-state explanation when Apple Translation offers no target languages."
    )
    static let showAudioInFinder = resource(
        "mac.files.show_audio_in_finder",
        defaultValue: "Show Audio in Finder",
        comment: "Action that reveals one recording audio file in Finder."
    )
    static let openRecordingsFolder = resource(
        "mac.files.open_recordings_folder",
        defaultValue: "Open Recordings Folder",
        comment: "Action that opens the current managed recording directory in Finder."
    )
    static let helpAndFeedback = resource(
        "mac.settings.help_and_feedback",
        defaultValue: "Help",
        comment: "Settings tab containing feedback and app links."
    )
    static let permissionStatus = resource(
        "mac.permissions.status",
        defaultValue: "Current Permission Status",
        comment: "Settings section showing current macOS privacy permission states."
    )
    static let permissionAllowed = resource(
        "mac.permissions.allowed",
        defaultValue: "Allowed",
        comment: "A macOS privacy permission is granted."
    )
    static let permissionNotRequested = resource(
        "mac.permissions.not_requested",
        defaultValue: "Not Requested",
        comment: "A macOS privacy permission has not been requested."
    )
    static let permissionNotGranted = resource(
        "mac.permissions.not_granted",
        defaultValue: "Not Granted",
        comment: "A macOS privacy permission is not currently granted."
    )
    static let permissionDenied = resource(
        "mac.permissions.denied",
        defaultValue: "Denied",
        comment: "A macOS privacy permission is denied."
    )
    static let openSystemSettings = resource(
        "mac.permissions.open_system_settings",
        defaultValue: "Open System Settings",
        comment: "Action that opens the relevant macOS privacy settings pane."
    )
    static let screenRecordingPermission = resource(
        "mac.permissions.screen_recording",
        defaultValue: "Screen Recording",
        comment: "macOS Screen Recording permission name."
    )
    static let screenRecordingPermissionUse = resource(
        "mac.permissions.screen_recording_use",
        defaultValue: "Screen Recording access is used only to record system audio from the display, app, or window you explicitly select.",
        comment: "Privacy explanation for macOS Screen Recording access used by system-audio recording."
    )
    static let menuBarStatusUse = resource(
        "mac.permissions.menu_bar_status_use",
        defaultValue: "The menu-bar item shows transcription status locally and does not send transcript content to a server.",
        comment: "Privacy explanation for the macOS transcription status menu."
    )
    static let remindersPermission = resource(
        "mac.permissions.reminders",
        defaultValue: "Reminders",
        comment: "macOS Reminders permission name."
    )
    static let actionFailed = resource(
        "mac.action.failed",
        defaultValue: "Operation Failed",
        comment: "Generic alert title when a library action fails on macOS."
    )
    static let settingsTitle = resource(
        "mac.settings.title",
        defaultValue: "Settings",
        comment: "Title of the macOS settings window."
    )
    static let generalSettings = resource(
        "mac.settings.general",
        defaultValue: "General",
        comment: "General macOS app settings title."
    )
    static let generalSettingsSubtitle = resource(
        "mac.settings.general.subtitle",
        defaultValue: "App language and interface behavior",
        comment: "Subtitle for general macOS app settings."
    )
    static let appLanguage = resource(
        "mac.settings.app_language",
        defaultValue: "App Language",
        comment: "Setting used to choose the app interface language."
    )
    static let appLanguageDescription = resource(
        "mac.settings.app_language.description",
        defaultValue: "Choose the language used by Live Transcriber. This does not change the transcription language.",
        comment: "Explanation of the app interface language setting."
    )
    static let followSystemLanguage = resource(
        "mac.settings.app_language.system",
        defaultValue: "Follow System",
        comment: "App language option that follows the macOS language."
    )
    static let languageRestartTitle = resource(
        "mac.settings.app_language.restart.title",
        defaultValue: "Restart Live Transcriber?",
        comment: "Alert title after changing the app interface language."
    )
    static let languageRestartMessage = resource(
        "mac.settings.app_language.restart.message",
        defaultValue: "Restart the app to apply the selected language everywhere.",
        comment: "Alert message after changing the app interface language."
    )
    static let languageRestartRequired = resource(
        "mac.settings.app_language.restart.required",
        defaultValue: "Restart required to finish applying this language",
        comment: "Status shown when the selected app language needs an app restart."
    )
    static let restartNow = resource(
        "mac.settings.app_language.restart.now",
        defaultValue: "Restart Now",
        comment: "Action that restarts the app after changing its language."
    )
    static let restartLater = resource(
        "mac.settings.app_language.restart.later",
        defaultValue: "Later",
        comment: "Action that postpones restarting the app after changing its language."
    )
    static let transcriptionStatusIdle = resource(
        "mac.status.transcription.idle",
        defaultValue: "No transcription in progress",
        comment: "Menu-bar status shown when live transcription is idle."
    )
    static let transcriptionLineCountFormat = resource(
        "mac.status.transcription.line_count.format",
        defaultValue: "%lld transcript lines",
        comment: "Menu-bar live transcription line count. Parameter: line count."
    )
    static let showApplication = resource(
        "mac.status.show_application",
        defaultValue: "Show Live Transcriber",
        comment: "Menu-bar action that brings the main app window forward."
    )
}
