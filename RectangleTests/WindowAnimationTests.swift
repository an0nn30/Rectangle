/// WindowAnimationTests.swift

import XCTest
@testable import Rectangle

final class WindowAnimationDefaultsTests: XCTestCase {

    func testDefaultsUseTheDocumentedKeys() {
        XCTAssertEqual(Defaults.windowAnimation.key, "windowAnimation")
        XCTAssertEqual(Defaults.windowAnimationDuration.key, "windowAnimationDuration")
    }

    func testDefaultsAreRegisteredForImportAndExport() {
        XCTAssertTrue(Defaults.array.contains { $0.key == "windowAnimation" })
        XCTAssertTrue(Defaults.array.contains { $0.key == "windowAnimationDuration" })
    }
}
