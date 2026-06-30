import UIKit

@MainActor
enum HapticFeedback {
    enum Event: Hashable {
        case navigation
        case tabSelection
        case menuSelection
        case primaryAction
        case recordingStart
        case recordingPause
        case recordingResume
        case recordingStop
        case recordingSaved
        case playbackToggle
        case timelineSeek
        case copy
        case importQueued
        case importStart
        case importComplete
        case retranscribeStart
        case retranscribeComplete
        case analysisStart
        case analysisComplete
        case deleteRequested
        case deleteConfirmed
        case blocked
        case warning
        case failure
    }

    private static var lastEventDates: [Event: Date] = [:]

    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        return generator
    }()

    private static let impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = {
        var values: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
        for style in [
            UIImpactFeedbackGenerator.FeedbackStyle.light,
            .medium,
            .heavy,
            .soft,
            .rigid
        ] {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            values[style] = generator
        }
        return values
    }()

    static func play(_ event: Event) {
        guard shouldPlay(event) else {
            return
        }

        switch event {
        case .navigation:
            softImpact(intensity: 0.35)
        case .tabSelection:
            selection()
            delayedImpact(.light, intensity: 0.42, afterMilliseconds: 24)
        case .menuSelection:
            selection()
        case .primaryAction:
            mediumImpact(intensity: 0.45)
        case .recordingStart:
            rigidImpact(intensity: 0.72)
            delayedImpact(.soft, intensity: 0.38, afterMilliseconds: 70)
        case .recordingPause:
            softImpact(intensity: 0.48)
        case .recordingResume:
            rigidImpact(intensity: 0.52)
        case .recordingStop:
            heavyImpact(intensity: 0.72)
            delayedImpact(.soft, intensity: 0.34, afterMilliseconds: 90)
        case .recordingSaved:
            success()
        case .playbackToggle:
            lightImpact(intensity: 0.48)
        case .timelineSeek:
            selection()
        case .copy:
            lightImpact(intensity: 0.42)
        case .importQueued:
            softImpact(intensity: 0.42)
        case .importStart:
            mediumImpact(intensity: 0.55)
        case .importComplete:
            success()
        case .retranscribeStart:
            mediumImpact(intensity: 0.52)
        case .retranscribeComplete:
            success()
        case .analysisStart:
            softImpact(intensity: 0.64)
            delayedImpact(.light, intensity: 0.32, afterMilliseconds: 80)
        case .analysisComplete:
            success()
        case .deleteRequested:
            rigidImpact(intensity: 0.58)
        case .deleteConfirmed:
            heavyImpact(intensity: 0.68)
        case .blocked:
            warning()
        case .warning:
            warning()
        case .failure:
            error()
        }
    }

    static func selection() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    static func lightImpact(intensity: CGFloat = 1.0) {
        impact(.light, intensity: intensity)
    }

    static func mediumImpact(intensity: CGFloat = 1.0) {
        impact(.medium, intensity: intensity)
    }

    static func heavyImpact(intensity: CGFloat = 1.0) {
        impact(.heavy, intensity: intensity)
    }

    static func softImpact(intensity: CGFloat = 1.0) {
        impact(.soft, intensity: intensity)
    }

    static func rigidImpact(intensity: CGFloat = 1.0) {
        impact(.rigid, intensity: intensity)
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    static func success() {
        notification(.success)
    }

    static func warning() {
        notification(.warning)
    }

    static func error() {
        notification(.error)
    }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        impactGenerators[style]?.impactOccurred(intensity: normalizedIntensity(intensity))
        impactGenerators[style]?.prepare()
    }

    private static func delayedImpact(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle,
        intensity: CGFloat,
        afterMilliseconds delayMilliseconds: Int64
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            impact(style, intensity: intensity)
        }
    }

    private static func shouldPlay(_ event: Event) -> Bool {
        let now = Date()
        let minimumInterval = minimumInterval(for: event)
        if let lastDate = lastEventDates[event],
           now.timeIntervalSince(lastDate) < minimumInterval {
            return false
        }
        lastEventDates[event] = now
        return true
    }

    private static func minimumInterval(for event: Event) -> TimeInterval {
        switch event {
        case .timelineSeek, .menuSelection:
            return 0.04
        case .navigation, .tabSelection, .playbackToggle, .copy:
            return 0.08
        case .blocked, .warning, .failure:
            return 0.35
        default:
            return 0.12
        }
    }

    private static func normalizedIntensity(_ intensity: CGFloat) -> CGFloat {
        max(0, min(intensity, 1))
    }
}
