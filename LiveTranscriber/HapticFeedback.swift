import SwiftUI
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
            mediumImpact(intensity: 0.62)
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

private struct InteractiveNavigationPopGestureObserver: UIViewRepresentable {
    let onBegan: () -> Void
    let onCancelled: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onCancelled: onCancelled)
    }

    func makeUIView(context: Context) -> NavigationControllerObservationView {
        let view = NavigationControllerObservationView()
        let coordinator = context.coordinator
        view.onHierarchyChange = { [weak view, weak coordinator] in
            guard let view else {
                return
            }
            coordinator?.attach(to: view.containingNavigationController())
        }
        DispatchQueue.main.async { [weak view] in
            view?.notifyHierarchyChange()
        }
        return view
    }

    func updateUIView(_ uiView: NavigationControllerObservationView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onCancelled = onCancelled
        DispatchQueue.main.async { [weak uiView] in
            uiView?.notifyHierarchyChange()
        }
    }

    static func dismantleUIView(
        _ uiView: NavigationControllerObservationView,
        coordinator: Coordinator
    ) {
        uiView.onHierarchyChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onBegan: () -> Void
        var onCancelled: () -> Void

        private weak var navigationController: UINavigationController?
        private var observedRecognizers: [UIGestureRecognizer] = []
        private var activeInteractionID: UUID?

        init(onBegan: @escaping () -> Void, onCancelled: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onCancelled = onCancelled
        }

        func attach(to navigationController: UINavigationController?) {
            let recognizers = navigationController.map(Self.popGestureRecognizers) ?? []
            guard self.navigationController !== navigationController
                    || !Self.sameRecognizers(observedRecognizers, recognizers) else {
                return
            }

            detach()
            self.navigationController = navigationController
            observedRecognizers = recognizers
            for recognizer in recognizers {
                recognizer.addTarget(self, action: #selector(handlePopGesture(_:)))
            }
        }

        func detach() {
            for recognizer in observedRecognizers {
                recognizer.removeTarget(self, action: #selector(handlePopGesture(_:)))
            }
            observedRecognizers.removeAll()
            navigationController = nil
            activeInteractionID = nil
        }

        @objc
        private func handlePopGesture(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard activeInteractionID == nil else {
                    return
                }
                let interactionID = UUID()
                activeInteractionID = interactionID
                onBegan()
                observeTransitionCompletion(for: interactionID, remainingAttempts: 3)
            case .cancelled, .failed:
                cancelActiveInteraction()
            default:
                break
            }
        }

        private func observeTransitionCompletion(
            for interactionID: UUID,
            remainingAttempts: Int
        ) {
            guard activeInteractionID == interactionID else {
                return
            }

            if let transitionCoordinator = navigationController?.transitionCoordinator,
               transitionCoordinator.animate(alongsideTransition: nil, completion: { [weak self] context in
                   guard let self, self.activeInteractionID == interactionID else {
                       return
                   }
                   if context.isCancelled {
                       self.onCancelled()
                   }
                   self.activeInteractionID = nil
               }) {
                return
            }

            guard remainingAttempts > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self, self.activeInteractionID == interactionID else {
                        return
                    }
                    self.onCancelled()
                    self.activeInteractionID = nil
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.observeTransitionCompletion(
                    for: interactionID,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }

        private func cancelActiveInteraction() {
            guard activeInteractionID != nil else {
                return
            }
            activeInteractionID = nil
            onCancelled()
        }

        private static func popGestureRecognizers(
            for navigationController: UINavigationController
        ) -> [UIGestureRecognizer] {
            let candidates = [
                navigationController.interactivePopGestureRecognizer,
                navigationController.interactiveContentPopGestureRecognizer
            ].compactMap { $0 }

            return candidates.reduce(into: []) { result, recognizer in
                guard !result.contains(where: { $0 === recognizer }) else {
                    return
                }
                result.append(recognizer)
            }
        }

        private static func sameRecognizers(
            _ lhs: [UIGestureRecognizer],
            _ rhs: [UIGestureRecognizer]
        ) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { pair in
                pair.0 === pair.1
            }
        }
    }

    final class NavigationControllerObservationView: UIView {
        var onHierarchyChange: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            notifyHierarchyChange()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            notifyHierarchyChange()
        }

        func notifyHierarchyChange() {
            DispatchQueue.main.async { [weak self] in
                self?.onHierarchyChange?()
            }
        }

        func containingNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let nextResponder = responder?.next {
                if let navigationController = nextResponder as? UINavigationController {
                    return navigationController
                }
                if let viewController = nextResponder as? UIViewController,
                   let navigationController = viewController.navigationController {
                    return navigationController
                }
                responder = nextResponder
            }

            guard let rootViewController = window?.rootViewController else {
                return nil
            }
            return navigationController(containing: self, in: rootViewController)
        }

        private func navigationController(
            containing view: UIView,
            in viewController: UIViewController
        ) -> UINavigationController? {
            if let presentedViewController = viewController.presentedViewController,
               let match = navigationController(containing: view, in: presentedViewController) {
                return match
            }

            if let navigationController = viewController as? UINavigationController,
               view.isDescendant(of: navigationController.view) {
                return navigationController
            }

            for child in viewController.children {
                if let match = navigationController(containing: view, in: child) {
                    return match
                }
            }
            return nil
        }
    }
}

extension View {
    func onInteractiveNavigationPopGesture(
        onBegan: @escaping () -> Void,
        onCancelled: @escaping () -> Void = {}
    ) -> some View {
        background(alignment: .topLeading) {
            InteractiveNavigationPopGestureObserver(
                onBegan: onBegan,
                onCancelled: onCancelled
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
