import AVFoundation
import AVKit
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import SwiftUI
import UIKit

/// PiP owns its presentation-only audio session independently so additions to
/// screen captions do not alter the committed recording/playback coordinator.
private actor CaptionPiPAudioSession {
    static let shared = CaptionPiPAudioSession()

    private var owner: UUID?

    func activate(owner: UUID) throws {
        guard self.owner != owner else {
            return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .moviePlayback,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
        self.owner = owner
    }

    func deactivate(owner: UUID) {
        guard self.owner == owner else {
            return
        }
        self.owner = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

@MainActor
final class CaptionPiPController: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isPossible = false
    @Published private(set) var isStarting = false
    @Published private(set) var errorMessage: String?

    let displayLayer = AVSampleBufferDisplayLayer()

    private let audioSessionOwner = UUID()
    private let renderer = CaptionFrameRenderer()
    private var pictureInPictureController: AVPictureInPictureController?
    private var snapshotCancellable: AnyCancellable?
    private var possibleObservation: NSKeyValueObservation?
    private var refreshTimer: Timer?
    private var latestSnapshot = CaptionSnapshot.empty
    private var presentationSeconds: Double = 0
    private var startRequestID = 0

    init(store: CaptionPresentationStore) {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        pictureInPictureController = controller
        possibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] controller, _ in
            Task { @MainActor [weak self] in
                self?.isPossible = controller.isPictureInPicturePossible
            }
        }
        snapshotCancellable = store.$snapshot.sink { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.receive(snapshot)
            }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.renderLatestSnapshot()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func attachDisplayLayer(to view: UIView) {
        if displayLayer.superlayer !== view.layer {
            displayLayer.removeFromSuperlayer()
            view.layer.addSublayer(displayLayer)
        }
        displayLayer.frame = view.bounds
        renderLatestSnapshot()
    }

    func updateDisplayLayerFrame(in view: UIView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = view.bounds
        CATransaction.commit()
    }

    func start() async {
        guard !isStarting, !isActive else {
            return
        }
        startRequestID &+= 1
        let requestID = startRequestID
        isStarting = true
        defer {
            if startRequestID == requestID {
                isStarting = false
            }
        }

        errorMessage = nil
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let pictureInPictureController else {
            errorMessage = String(localized: L10n.ScreenAudio.pipUnsupported)
            return
        }
        renderLatestSnapshot()

        do {
            try await CaptionPiPAudioSession.shared.activate(
                owner: audioSessionOwner
            )
            guard startRequestID == requestID else {
                await CaptionPiPAudioSession.shared.deactivate(
                    owner: audioSessionOwner
                )
                return
            }

            // A sample-buffer PiP source may not become possible until its
            // display layer has a frame and the playback audio session is
            // active. The old UI required isPossible before allowing the tap,
            // while activating that session only here, creating a deadlock.
            let becamePossible = await waitUntilPictureInPictureIsPossible(
                pictureInPictureController,
                requestID: requestID
            )
            guard becamePossible else {
                await CaptionPiPAudioSession.shared.deactivate(
                    owner: audioSessionOwner
                )
                if startRequestID == requestID {
                    errorMessage = String(localized: L10n.ScreenAudio.pipNotReady)
                }
                return
            }

            pictureInPictureController.startPictureInPicture()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        startRequestID &+= 1
        isStarting = false
        if pictureInPictureController?.isPictureInPictureActive == true {
            pictureInPictureController?.stopPictureInPicture()
        } else {
            Task {
                await CaptionPiPAudioSession.shared.deactivate(
                    owner: audioSessionOwner
                )
            }
        }
    }

    private func waitUntilPictureInPictureIsPossible(
        _ controller: AVPictureInPictureController,
        requestID: Int
    ) async -> Bool {
        for _ in 0..<20 {
            guard startRequestID == requestID, !Task.isCancelled else {
                return false
            }
            renderLatestSnapshot()
            controller.invalidatePlaybackState()
            if controller.isPictureInPicturePossible {
                isPossible = true
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return false
            }
        }
        return false
    }

    private func receive(_ snapshot: CaptionSnapshot) {
        latestSnapshot = snapshot
        renderLatestSnapshot()
        switch snapshot.sessionState {
        case .idle, .failed:
            if isActive {
                stop()
            }
        case .awaitingUserApproval, .waitingForAudio, .capturing, .paused, .stopping:
            break
        }
    }

    private func renderLatestSnapshot() {
        let sampleBufferRenderer = displayLayer.sampleBufferRenderer
        if sampleBufferRenderer.status == .failed {
            sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        }
        do {
            let sampleBuffer = try renderer.makeSampleBuffer(
                snapshot: latestSnapshot,
                presentationTime: CMTime(seconds: presentationSeconds, preferredTimescale: 600)
            )
            presentationSeconds += 1
            sampleBufferRenderer.enqueue(sampleBuffer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension CaptionPiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            self?.isActive = true
            self?.errorMessage = nil
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.isActive = false
            self?.errorMessage = error.localizedDescription
            guard let self else { return }
            await CaptionPiPAudioSession.shared.deactivate(
                owner: self.audioSessionOwner
            )
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActive = false
            await CaptionPiPAudioSession.shared.deactivate(
                owner: self.audioSessionOwner
            )
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

extension CaptionPiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        pictureInPictureController.invalidatePlaybackState()
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }
}

struct CaptionPiPPreview: UIViewRepresentable {
    @ObservedObject var controller: CaptionPiPController

    func makeUIView(context: Context) -> CaptionLayerHostView {
        let view = CaptionLayerHostView()
        view.backgroundColor = .black
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        view.controller = controller
        controller.attachDisplayLayer(to: view)
        return view
    }

    func updateUIView(_ view: CaptionLayerHostView, context: Context) {
        view.controller = controller
        controller.attachDisplayLayer(to: view)
    }
}

final class CaptionLayerHostView: UIView {
    weak var controller: CaptionPiPController?

    override func layoutSubviews() {
        super.layoutSubviews()
        controller?.updateDisplayLayerFrame(in: self)
    }
}

private final class CaptionFrameRenderer {
    private let width = 960
    private let height = 540

    func makeSampleBuffer(
        snapshot: CaptionSnapshot,
        presentationTime: CMTime
    ) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw CaptionRenderingError.pixelBufferCreationFailed(status)
        }

        try draw(snapshot: snapshot, into: pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw CaptionRenderingError.formatDescriptionCreationFailed(formatStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 1),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw CaptionRenderingError.sampleBufferCreationFailed(sampleStatus)
        }
        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldNotPropagate
        )
        return sampleBuffer
    }

    private func draw(snapshot: CaptionSnapshot, into pixelBuffer: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw CaptionRenderingError.contextCreationFailed
        }

        context.setFillColor(UIColor(red: 0.035, green: 0.045, blue: 0.075, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        let badge = statusText(snapshot.sessionState)
        drawText(
            "LIVE TRANSCRIBER  •  \(badge)",
            rect: CGRect(x: 54, y: 42, width: 852, height: 38),
            font: .systemFont(ofSize: 23, weight: .bold),
            color: UIColor(red: 0.42, green: 0.72, blue: 1, alpha: 1),
            alignment: .left
        )

        let original = snapshot.originalText.isEmpty
            ? String(localized: L10n.ScreenAudio.waitingForSpeech)
            : snapshot.originalText
        drawText(
            original,
            rect: CGRect(x: 54, y: 116, width: 852, height: 188),
            font: .systemFont(ofSize: 43, weight: .semibold),
            color: .white,
            alignment: .left
        )

        context.setFillColor(UIColor.white.withAlphaComponent(0.13).cgColor)
        context.fill(CGRect(x: 54, y: 326, width: 852, height: 2))

        let translated = snapshot.translatedText
            ?? String(localized: L10n.ScreenAudio.waitingForTranslation)
        drawText(
            translated,
            rect: CGRect(x: 54, y: 358, width: 852, height: 122),
            font: .systemFont(ofSize: 32, weight: .medium),
            color: UIColor.white.withAlphaComponent(snapshot.translatedText == nil ? 0.46 : 0.82),
            alignment: .left
        )
    }

    private func drawText(
        _ text: String,
        rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 5
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
            ],
            context: nil
        )
    }

    private func statusText(_ state: SystemAudioSessionState) -> String {
        switch state {
        case .idle:
            return String(localized: L10n.ScreenAudio.statusReady)
        case .awaitingUserApproval:
            return String(localized: L10n.ScreenAudio.statusApproval)
        case .waitingForAudio:
            return String(localized: L10n.ScreenAudio.statusWaiting)
        case .capturing:
            return String(localized: L10n.ScreenAudio.statusCapturing)
        case .paused:
            return String(localized: L10n.ScreenAudio.statusPaused)
        case .stopping:
            return String(localized: L10n.ScreenAudio.statusStopping)
        case .failed:
            return String(localized: L10n.ScreenAudio.statusFailed)
        }
    }
}

private enum CaptionRenderingError: LocalizedError {
    case pixelBufferCreationFailed(CVReturn)
    case formatDescriptionCreationFailed(OSStatus)
    case sampleBufferCreationFailed(OSStatus)
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .pixelBufferCreationFailed(let status):
            return "Could not create caption pixel buffer (\(status))."
        case .formatDescriptionCreationFailed(let status):
            return "Could not create caption format description (\(status))."
        case .sampleBufferCreationFailed(let status):
            return "Could not create caption sample buffer (\(status))."
        case .contextCreationFailed:
            return "Could not create caption rendering context."
        }
    }
}
