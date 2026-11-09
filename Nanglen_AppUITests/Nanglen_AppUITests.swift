//
//  Nanglen_AppUITests.swift
//  Nanglen_AppUITests
//
//  Smoke tests of the Guest journey against the in-process Demo backend (no network, no credentials).
//

import XCTest

final class Nanglen_AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-NanglenResetData", "-NanglenDemoBackend"]
        app.launch()
        return app
    }

    /// Guest can browse approved venues and open a detail without signing up.
    @MainActor
    func testGuestBrowsesAndOpensVenue() throws {
        let app = launch()
        let firstCard = app.tables.cells.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10), "Explore lists approved venues for a Guest")
        firstCard.tap()
        XCTAssertTrue(app.buttons["detail.writeReview"].waitForExistence(timeout: 5))
    }

    /// Guest tapping Write a Review is asked to verify a phone first (no review form).
    @MainActor
    func testGuestCannotWriteReview() throws {
        let app = launch()
        let firstCard = app.tables.cells.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))
        firstCard.tap()
        let write = app.buttons["detail.writeReview"]
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "registration prompt is shown")
        XCTAssertFalse(app.buttons["composer.submit"].exists)
    }
}
