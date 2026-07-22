import AudioCommon
import XCTest

final class PortableFloat16Tests: XCTestCase {
    func testStorageMatchesCoreMLFloat16Width() {
        XCTAssertEqual(MemoryLayout<PortableFloat16>.size, 2)
        XCTAssertEqual(MemoryLayout<PortableFloat16>.stride, 2)
    }

    func testKnownIEEE754BitPatterns() {
        XCTAssertEqual(PortableFloat16(0).bitPattern, 0x0000)
        XCTAssertEqual(PortableFloat16(-0.0).bitPattern, 0x8000)
        XCTAssertEqual(PortableFloat16(1).bitPattern, 0x3C00)
        XCTAssertEqual(PortableFloat16(-2).bitPattern, 0xC000)
        XCTAssertEqual(PortableFloat16(Float.infinity).bitPattern, 0x7C00)
        XCTAssertEqual(PortableFloat16(-Float.infinity).bitPattern, 0xFC00)
        XCTAssertTrue(PortableFloat16(Float.nan).floatValue.isNaN)
    }

    func testFiniteValuesRoundTripAtHalfPrecision() {
        for value: Float in [-1000, -1.5, -0.0001, 0.0001, 0.5, 42.25, 65504] {
            let result = PortableFloat16(value).floatValue
            let tolerance = max(abs(value) * 0.001, 0.000_001)
            XCTAssertEqual(result, value, accuracy: tolerance)
        }
    }
}
