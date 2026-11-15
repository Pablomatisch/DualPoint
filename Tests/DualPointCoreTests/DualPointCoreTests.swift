import XCTest
@testable import DualPointCore

final class DualPointCoreTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(DualPointCore.version.isEmpty)
        XCTAssertEqual(DualPointCore.bundleIdentifier, "com.dualpoint.DualPoint")
    }
}
