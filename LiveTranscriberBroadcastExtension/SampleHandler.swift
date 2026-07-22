import CoreMedia
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private var producer: SharedAudioChunkProducer?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        do {
            let producer = try SharedAudioChunkProducer()
            try producer.start()
            self.producer = producer
        } catch {
            finishBroadcastWithError(error)
        }
    }

    override func broadcastPaused() {
        producer?.pause()
    }

    override func broadcastResumed() {
        producer?.resume()
    }

    override func broadcastFinished() {
        producer?.finish()
        producer = nil
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .audioApp:
            producer?.append(sampleBuffer)
        case .audioMic, .video:
            break
        @unknown default:
            break
        }
    }
}
