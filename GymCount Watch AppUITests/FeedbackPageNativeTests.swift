import XCTest

/// Uses the unchanged 82-record Watch backup, copied only into the preview installation.
final class FeedbackPageNativeTests: XCTestCase {
    @MainActor func testRealHistoryFeedbackPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["历史"].waitForExistence(timeout: 10)); app.buttons["历史"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "feedback.history.", "计数反馈"))
        for _ in 0..<12 {
            if rows.count > 0 { break }
            app.buttons["上一周"].tap()
        }
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if row.isHittable, row.frame.minY >= 44, row.frame.maxY <= app.frame.maxY - 8 { break }
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34))
            a.press(forDuration: 0.1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        row.tap()
        let back = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "watch.back", "计数反馈")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(back.frame.minX, 16, "Short empty-state text must not shrink and inset the page header")
        XCTAssertLessThanOrEqual(back.frame.maxX, app.frame.maxX - 60)
        XCTAssertTrue(app.staticTexts["此记录没有可上传的采样"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedback.submit"].exists)
        Thread.sleep(forTimeInterval: 0.6)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "all-real-feedback"; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "all-real-feedback-AX"; tree.lifetime = .keepAlways; add(tree)
        back.tap()
        XCTAssertTrue(app.buttons["history.exercise-filter"].waitForExistence(timeout: 5))
    }
}
