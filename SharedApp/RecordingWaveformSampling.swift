import Accelerate
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

struct RecordingSilenceInterval: Equatable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
}

enum RecordingSilenceDetector {
    private struct LoudnessWindow {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let decibels: Double
    }

    private static let analysisWindowDuration: TimeInterval = 0.1
    private static let audibleEdgePaddingWindowCount = 2
    private static let minimumSkippableDuration: TimeInterval = 0.9
    private static let minimumDynamicRangeDecibels = 8.0
    private static let minimumSilenceThresholdDecibels = -55.0
    private static let maximumSilenceThresholdDecibels = -32.0

    static func intervals(from url: URL) async -> [RecordingSilenceInterval] {
        let analysisTask = Task.detached(priority: .utility) {
            do {
                return try detectIntervals(from: url)
            } catch {
                return []
            }
        }
        return await withTaskCancellationHandler {
            await analysisTask.value
        } onCancel: {
            analysisTask.cancel()
        }
    }

    private static func detectIntervals(from url: URL) throws -> [RecordingSilenceInterval] {
        let audioFile = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        guard audioFile.length > 0,
              sampleRate.isFinite,
              sampleRate > 0,
              format.channelCount > 0 else {
            return []
        }

        let windowFrameCount = AVAudioFrameCount(
            min(
                max((sampleRate * analysisWindowDuration).rounded(), 1),
                Double(AVAudioFrameCount.max)
            )
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: windowFrameCount
        ) else {
            return []
        }

        var windows: [LoudnessWindow] = []
        windows.reserveCapacity(
            Int(ceil(Double(audioFile.length) / Double(windowFrameCount)))
        )
        var processedFrames: AVAudioFramePosition = 0

        while processedFrames < audioFile.length {
            try Task.checkCancellation()
            let remainingFrames = audioFile.length - processedFrames
            let framesToRead = AVAudioFrameCount(
                min(remainingFrames, AVAudioFramePosition(windowFrameCount))
            )
            buffer.frameLength = 0
            try audioFile.read(into: buffer, frameCount: framesToRead)

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0,
                  let channelData = buffer.floatChannelData else {
                break
            }

            var channelMeanSquareSum = 0.0
            for channel in 0..<Int(format.channelCount) {
                var rootMeanSquare: Float = 0
                vDSP_rmsqv(
                    channelData[channel],
                    1,
                    &rootMeanSquare,
                    vDSP_Length(frameLength)
                )
                let finiteRMS = rootMeanSquare.isFinite ? Double(rootMeanSquare) : 0
                channelMeanSquareSum += finiteRMS * finiteRMS
            }

            let combinedRMS = sqrt(
                channelMeanSquareSum / Double(format.channelCount)
            )
            let decibels = 20 * log10(max(combinedRMS, 0.000_001))
            let startTime = Double(processedFrames) / sampleRate
            processedFrames += AVAudioFramePosition(frameLength)
            let endTime = Double(processedFrames) / sampleRate
            windows.append(
                LoudnessWindow(
                    startTime: startTime,
                    endTime: endTime,
                    decibels: decibels
                )
            )
        }

        guard windows.count >= 2 else {
            return []
        }

        let sortedLevels = windows.map(\.decibels).sorted()
        let noiseFloor = percentile(0.2, in: sortedLevels)
        let audibleLevel = percentile(0.85, in: sortedLevels)
        guard audibleLevel - noiseFloor >= minimumDynamicRangeDecibels else {
            return []
        }

        let adaptiveThreshold = max(
            noiseFloor + 8,
            audibleLevel - 24
        )
        let silenceThreshold = min(
            max(adaptiveThreshold, minimumSilenceThresholdDecibels),
            maximumSilenceThresholdDecibels
        )

        var audibleWindows = windows.map { $0.decibels >= silenceThreshold }
        let unpaddedAudibleWindows = audibleWindows
        for index in unpaddedAudibleWindows.indices where unpaddedAudibleWindows[index] {
            let lowerBound = max(index - audibleEdgePaddingWindowCount, 0)
            let upperBound = min(
                index + audibleEdgePaddingWindowCount,
                audibleWindows.count - 1
            )
            for paddedIndex in lowerBound...upperBound {
                audibleWindows[paddedIndex] = true
            }
        }

        var intervals: [RecordingSilenceInterval] = []
        var index = audibleWindows.startIndex
        while index < audibleWindows.endIndex {
            guard !audibleWindows[index] else {
                index += 1
                continue
            }

            let silentStartIndex = index
            while index < audibleWindows.endIndex, !audibleWindows[index] {
                index += 1
            }
            let silentEndIndex = index - 1
            let startTime = windows[silentStartIndex].startTime
            let endTime = windows[silentEndIndex].endTime
            guard endTime - startTime >= minimumSkippableDuration else {
                continue
            }
            intervals.append(
                RecordingSilenceInterval(
                    startTime: startTime,
                    endTime: endTime
                )
            )
        }

        return intervals
    }

    private static func percentile(
        _ percentile: Double,
        in sortedValues: [Double]
    ) -> Double {
        let index = min(
            max(
                Int(
                    (Double(sortedValues.count - 1) * percentile)
                        .rounded(.down)
                ),
                0
            ),
            sortedValues.count - 1
        )
        return sortedValues[index]
    }
}
