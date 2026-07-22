import XCTest
@testable import LiveTranscriber

final class SystemAudioSessionStateTests: XCTestCase {
    func testOnlyIdleAndFailedStatesAreInactive() {
        XCTAssertFalse(SystemAudioSessionState.idle.isActive)
        XCTAssertFalse(SystemAudioSessionState.failed("failure").isActive)
        XCTAssertTrue(SystemAudioSessionState.awaitingUserApproval.isActive)
        XCTAssertTrue(SystemAudioSessionState.waitingForAudio.isActive)
        XCTAssertTrue(SystemAudioSessionState.capturing.isActive)
        XCTAssertTrue(SystemAudioSessionState.paused.isActive)
        XCTAssertTrue(SystemAudioSessionState.stopping.isActive)
    }

    func testCurrentOSChoosesExactlyOneBackend() {
        XCTAssertTrue(
            [SystemAudioBackend.replayKitCompatibility, .screenCaptureKit]
                .contains(SystemAudioBackend.preferredForCurrentOS)
        )
    }
}
