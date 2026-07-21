import AVFoundation
import Foundation

enum RecordingDisplayWaveformSampler {
    private static let maximumFramesPerSample: AVAudioFrameCount = 8_192

    static func samples(from url: URL, sampleCount: Int) async -> [CGFloat] {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return []
            }

            do {
                return try loadSamples(from: url, sampleCount: sampleCount)
            } catch {
                return []
            }
        }.value
    }

    private static func loadSamples(from url: URL, sampleCount: Int) throws -> [CGFloat] {
        let resolvedSampleCount = max(sampleCount, 1)
        let audioFile = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        let fileLength = audioFile.length

        guard fileLength > 0,
              format.channelCount > 0 else {
            return []
        }

        var levels = [Double](repeating: 0, count: resolvedSampleCount)

        for index in 0..<resolvedSampleCount {
            if Task.isCancelled {
                return []
            }

            let bucketStart = fileLength * AVAudioFramePosition(index) / AVAudioFramePosition(resolvedSampleCount)
            let bucketEnd = fileLength * AVAudioFramePosition(index + 1) / AVAudioFramePosition(resolvedSampleCount)
            let bucketLength = max(bucketEnd - bucketStart, 1)
            let framesToRead = AVAudioFrameCount(
                min(bucketLength, AVAudioFramePosition(maximumFramesPerSample))
            )
            let centeredStart = bucketStart + max(
                (bucketLength - AVAudioFramePosition(framesToRead)) / 2,
                0
            )

            audioFile.framePosition = min(centeredStart, max(fileLength - 1, 0))

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: framesToRead
            ) else {
                continue
            }

            try audioFile.read(into: buffer, frameCount: framesToRead)

            guard buffer.frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                continue
            }

            let channelCount = Int(format.channelCount)
            let frameCount = Int(buffer.frameLength)
            var sumOfSquares = 0.0
            var peak = 0.0
            var valueCount = 0

            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let value = Double(samples[frame])
                    guard value.isFinite else {
                        continue
                    }
                    let magnitude = abs(value)
                    sumOfSquares += value * value
                    peak = max(peak, magnitude)
                    valueCount += 1
                }
            }

            guard valueCount > 0 else {
                continue
            }

            let rms = sqrt(sumOfSquares / Double(valueCount))
            levels[index] = rms * 0.82 + peak * 0.18
        }

        let audibleLevels = levels.filter { $0 > 0 }.sorted()
        guard !audibleLevels.isEmpty else {
            return [CGFloat](repeating: 0, count: resolvedSampleCount)
        }

        let percentileIndex = min(
            Int((Double(audibleLevels.count - 1) * 0.92).rounded(.down)),
            audibleLevels.count - 1
        )
        let referenceLevel = max(audibleLevels[percentileIndex], 0.000_001)

        return levels.map { level in
            guard level > 0 else {
                return 0
            }
            let normalized = min(level / referenceLevel, 1)
            return CGFloat(pow(normalized, 0.55))
        }
    }
}
