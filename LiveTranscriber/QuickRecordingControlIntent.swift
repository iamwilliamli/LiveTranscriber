import AppIntents
import Foundation
import UIKit

enum QuickRecordingControlL10n {
    static let title = LocalizedStringResource(
        "control.quick_recording.title",
        defaultValue: "Quick Recording",
        table: "ControlCenter",
        comment: "Display name for the Control Center and Lock Screen quick recording control."
    )
    static let description = LocalizedStringResource(
        "control.quick_recording.description",
        defaultValue: "Open Live Transcriber and start recording.",
        table: "ControlCenter",
        comment: "Description for the Control Center quick recording control."
    )
    static let startRecording = LocalizedStringResource(
        "control.quick_recording.start",
        defaultValue: "Start Recording",
        table: "ControlCenter",
        comment: "Action label for starting a recording from a system control."
    )
    static let destination = LocalizedStringResource(
        "control.quick_recording.destination",
        defaultValue: "Recording",
        table: "ControlCenter",
        comment: "App intent destination representing the live recording screen."
    )
}

enum HomeWidgetL10n {
    private static func resource(
        _ key: StaticString,
        defaultValue: String.LocalizationValue,
        comment: StaticString
    ) -> LocalizedStringResource {
        LocalizedStringResource(
            key,
            defaultValue: defaultValue,
            table: "ControlCenter",
            comment: comment
        )
    }

    static let appName = resource("widget.home.app_name", defaultValue: "Live Transcriber", comment: "Home Screen widget display name.")
    static let configurationDescription = resource("widget.home.configuration_description", defaultValue: "Start recording, open saved files, and change recording settings.", comment: "Home Screen widget configuration description.")
    static let start = resource("widget.home.start", defaultValue: "Start", comment: "Short start recording action in the Home Screen widget.")
    static let recording = resource("widget.home.recording", defaultValue: "Recording", comment: "Recording label in the small Home Screen widget.")
    static let liveTranscript = resource("widget.home.live_transcript", defaultValue: "Live transcript", comment: "Live transcript capability label in the Home Screen widget.")
    static let quickActions = resource("widget.home.quick_actions", defaultValue: "Quick Actions", comment: "Quick actions heading in the medium Home Screen widget.")
    static let quickActionsDescription = resource("widget.home.quick_actions_description", defaultValue: "Start recording or jump to saved files.", comment: "Quick actions description in the medium Home Screen widget.")
    static let files = resource("widget.home.files", defaultValue: "Files", comment: "Saved recordings action in the Home Screen widget.")
    static let settings = resource("widget.home.settings", defaultValue: "Settings", comment: "Settings action in the Home Screen widget.")
    static let recordingControls = resource("widget.home.recording_controls", defaultValue: "Recording Controls", comment: "Recording controls heading in the large Home Screen widget.")
    static let recordingControlsDescription = resource("widget.home.recording_controls_description", defaultValue: "Start recording, open saved files, import audio, or adjust recording settings.", comment: "Recording controls description in the large Home Screen widget.")
    static let stereoAudio = resource("widget.home.stereo_audio", defaultValue: "Stereo audio", comment: "Stereo audio capability label in the Home Screen widget.")
    static let savedFiles = resource("widget.home.saved_files", defaultValue: "Saved Files", comment: "Saved files action in the large Home Screen widget.")
    static let brandLive = resource("widget.home.brand_live", defaultValue: "Live", comment: "First line of the Live Transcriber brand in the Home Screen widget.")
    static let brandTranscriber = resource("widget.home.brand_transcriber", defaultValue: "Transcriber", comment: "Second line of the Live Transcriber brand in the Home Screen widget.")
    static let activityStatus = resource("widget.live_activity.status", defaultValue: "Status", comment: "Status heading in the recording Live Activity.")
    static let activityTranscript = resource("widget.live_activity.transcript", defaultValue: "Transcript", comment: "Transcript heading in the recording Live Activity.")
    static let activityStop = resource("widget.live_activity.stop", defaultValue: "Stop", comment: "Stop recording action in the recording Live Activity.")
    static let activityLanguage = resource("widget.live_activity.language", defaultValue: "Lang", comment: "Compact language label in the Dynamic Island.")
}

enum LiveTranscriberLaunchTarget: String, AppEnum {
    case quickRecording

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource(
        "control.quick_recording.title",
        defaultValue: "Quick Recording",
        table: "ControlCenter",
        comment: "Display name for the Control Center and Lock Screen quick recording control."
    ))
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .quickRecording: DisplayRepresentation(title: LocalizedStringResource(
            "control.quick_recording.destination",
            defaultValue: "Recording",
            table: "ControlCenter",
            comment: "App intent destination representing the live recording screen."
        ))
    ]
}

struct StartQuickRecordingIntent: OpenIntent, UISceneAppIntent {
    static let title = LocalizedStringResource(
        "control.quick_recording.start",
        defaultValue: "Start Recording",
        table: "ControlCenter",
        comment: "Action label for starting a recording from a system control."
    )
    static let description = IntentDescription(LocalizedStringResource(
        "control.quick_recording.description",
        defaultValue: "Open Live Transcriber and start recording.",
        table: "ControlCenter",
        comment: "Description for the Control Center quick recording control."
    ))

    @Parameter(title: LocalizedStringResource(
        "control.quick_recording.destination",
        defaultValue: "Recording",
        table: "ControlCenter",
        comment: "App intent destination representing the live recording screen."
    ))
    var target: LiveTranscriberLaunchTarget

    init() {
        target = .quickRecording
    }

    init(target: LiveTranscriberLaunchTarget) {
        self.target = target
    }
}
