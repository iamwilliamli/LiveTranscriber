import Foundation
import XCTest
@testable import LiveTranscriberMac

@MainActor
final class MacAppRouterTests: XCTestCase {
    func testSidebarContainsOnlyPrimaryDestinations() {
        XCTAssertEqual(
            MacSidebarDestination.allCases,
            [.transcribe, .recordings, .settings]
        )
    }

    func testSystemAudioOnlyModeDoesNotIncludeMicrophoneInSavedAudio() {
        XCTAssertTrue(MacRecordingInputMode.systemAudioOnly.usesSystemAudio)
        XCTAssertFalse(
            MacRecordingInputMode.systemAudioOnly.includesMicrophoneInSavedAudio
        )
        XCTAssertTrue(
            MacRecordingInputMode.microphoneAndSystemAudio
                .includesMicrophoneInSavedAudio
        )
    }

    func testLegacyCaptureDeepLinkRedirectsToTranscribe() throws {
        let router = MacAppRouter()

        router.handle(try XCTUnwrap(URL(string: "livetranscriber://capture")))

        XCTAssertEqual(router.requestedDestination, .transcribe)
    }

    func testLegacyCaptureLibraryDeepLinkRedirectsToRecordings() throws {
        let router = MacAppRouter()

        router.handle(try XCTUnwrap(URL(string: "livetranscriber://capture-library")))

        XCTAssertEqual(router.requestedDestination, .recordings)
    }

    func testSettingsDeepLinkSelectsSidebarSettings() throws {
        let router = MacAppRouter()

        router.handle(try XCTUnwrap(URL(string: "livetranscriber://settings")))

        XCTAssertEqual(router.requestedDestination, .settings)
    }
}
