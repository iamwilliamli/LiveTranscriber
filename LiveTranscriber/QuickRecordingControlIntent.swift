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
