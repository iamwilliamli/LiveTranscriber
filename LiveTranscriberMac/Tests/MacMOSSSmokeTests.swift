import AVFoundation
import AppKit
import XCTest
@testable import LiveTranscriberMac

/// End-to-end MOSS smoke test. Downloads the real model into the app container
/// when needed, synthesizes a spoken sample, and runs the full transcription
/// pipeline. Gated behind LT_MOSS_SMOKE=1 (pass TEST_RUNNER_LT_MOSS_SMOKE=1 to
/// xcodebuild) so CI and regular test runs skip it.
final class MacMOSSSmokeTests: XCTestCase {
    func testMacMOSSDecoderExposesExtendedSegmentLengths() {
        XCTAssertEqual(
            MOSSDecoderSegmentDuration.allCases.map(\.rawValue),
            [30, 60, 90, 120, 180, 300, 600, 900, 1_200]
        )
        XCTAssertEqual(
            MOSSDecoderSegmentDuration.mobileOptions.map(\.rawValue),
            [30, 60, 90, 120, 180, 300]
        )
    }

    func testMOSSDecoderExposesConfigurableOutputTokenLimits() {
        XCTAssertEqual(
            MOSSDecoderMaximumOutputTokens.allCases.map(\.rawValue),
            [1_024, 2_048, 4_096, 8_192]
        )
        XCTAssertEqual(MOSSDecoderMaximumOutputTokens.defaultValue.rawValue, 2_048)
    }

    func testMOSSDownloadsModelAndTranscribesSpeech() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LT_MOSS_SMOKE"] == "1",
            "Set TEST_RUNNER_LT_MOSS_SMOKE=1 to run the MOSS smoke test."
        )

        if !MOSSLocalModelManager.currentStatus().isAvailable {
            _ = try await MOSSLocalModelManager.download { progress in
                if Int(progress * 100) % 10 == 0 {
                    print("MOSS smoke: download \(Int(progress * 100))%")
                }
            }
        }
        XCTAssertTrue(
            MOSSLocalModelManager.currentStatus().isAvailable,
            "MOSS model should be installed after download"
        )

        let audioURL = try await Self.makeSpokenSample(
            text: "Hello, this is a smoke test for the live transcriber project. "
                + "The quick brown fox jumps over the lazy dog."
        )
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let result = try await MOSSLocalTranscriptionService.transcribe(audioURL: audioURL) { progress in
            print("MOSS smoke: transcribe \(Int(progress * 100))%")
        }

        print("MOSS smoke transcript:\n\(result.lines.timedTranscriptText)")
        XCTAssertFalse(result.lines.isEmpty, "MOSS should produce transcript lines")
        XCTAssertFalse(
            result.diarization.segments.isEmpty,
            "MOSS should produce diarization segments"
        )
        let joinedText = result.lines.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(
            joinedText.contains("fox") || joinedText.contains("smoke")
                || joinedText.contains("transcriber") || joinedText.contains("dog"),
            "Transcript should contain recognizable words, got: \(joinedText)"
        )
    }

    private static func makeSpokenSample(text: String) async throws -> URL {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moss-smoke-\(UUID().uuidString).caf")

        let synthesizer = AVSpeechSynthesizer()
        var audioFile: AVAudioFile?

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            synthesizer.write(utterance) { buffer in
                do {
                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                        return
                    }
                    if pcmBuffer.frameLength == 0 {
                        // Zero-length buffer marks the end of synthesis.
                        guard !hasResumed else {
                            return
                        }
                        hasResumed = true
                        if audioFile != nil {
                            continuation.resume(returning: outputURL)
                        } else {
                            continuation.resume(
                                throwing: NSError(
                                    domain: "MacMOSSSmokeTests",
                                    code: 1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "Speech synthesis produced no audio",
                                    ]
                                )
                            )
                        }
                        return
                    }

                    if audioFile == nil {
                        audioFile = try AVAudioFile(
                            forWriting: outputURL,
                            settings: pcmBuffer.format.settings
                        )
                    }
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    guard !hasResumed else {
                        return
                    }
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

final class MacAppLanguageTests: XCTestCase {
    func testSupportedInterfaceLanguagesMatchBundledLocalizations() {
        XCTAssertEqual(
            MacAppLanguage.allCases.map(\.rawValue),
            ["system", "en", "zh-Hans", "zh-Hant", "ja", "de", "nl"]
        )
        XCTAssertNil(MacAppLanguage.system.localeIdentifier)
        XCTAssertEqual(MacAppLanguage.simplifiedChinese.localeIdentifier, "zh-Hans")
        XCTAssertEqual(MacAppLanguage.traditionalChinese.localeIdentifier, "zh-Hant")
    }
}

final class MacAppIconTests: XCTestCase {
    func testDebugAppBundleUsesRenderableAssetCatalogIcon() throws {
        let appBundle = Bundle(for: MacAppRouter.self)
        XCTAssertEqual(
            appBundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            "AppIcon"
        )

        let iconFile = try XCTUnwrap(
            appBundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        )
        XCTAssertTrue(["AppIcon", "AppIcon.icns"].contains(iconFile))

        let iconURL = try XCTUnwrap(
            appBundle.url(forResource: "AppIcon", withExtension: "icns")
        )
        let iconImage = try XCTUnwrap(NSImage(contentsOf: iconURL))
        XCTAssertFalse(iconImage.representations.isEmpty)
        XCTAssertGreaterThan(iconImage.size.width, 0)
        XCTAssertGreaterThan(iconImage.size.height, 0)
    }
}
