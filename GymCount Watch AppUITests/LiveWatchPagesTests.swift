import XCTest

final class LiveWatchPagesTests: XCTestCase {
    @MainActor func testLivePickersAndRecovery() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let start = app.buttons["workout.start.squat"]
        let previousResume = app.buttons["workout.recovery.resume"]
        if previousResume.waitForExistence(timeout: 2) {
            reveal(previousResume, app); previousResume.tap(); acknowledge(app)
            let end = app.buttons["workout.end"]
            reveal(end, app); end.tap()
            let done = app.buttons["whole.summary.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10)); reveal(done, app); done.tap()
        }
        XCTAssertTrue(start.waitForExistence(timeout: 12)); start.tap()
        acknowledge(app)
        XCTAssertTrue(app.staticTexts["whole.count"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["whole.count"].label, "0")
        let end = app.buttons["workout.end"]
        XCTAssertTrue(end.isHittable)
        XCTAssertLessThanOrEqual(end.frame.maxY, app.frame.maxY)
        XCTAssertLessThanOrEqual(app.staticTexts["whole.count"].frame.maxY, end.frame.minY)
        shot(app, "all-live")
        app.buttons["whole.exercise"].tap()
        let closePicker = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "watch.back", "切换动作")).firstMatch
        XCTAssertTrue(closePicker.waitForExistence(timeout: 5))
        shot(app, "all-live-exercise-picker")
        closePicker.tap()
        app.buttons["whole.weight"].tap()
        let closeWeight = app.buttons["weight-input-back"]
        XCTAssertTrue(closeWeight.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["weight-input-save"].isHittable)
        shot(app, "all-live-weight")
        closeWeight.tap()
        // Recovery uses the draft actually created by starting this isolated session.
        // No samples, repetitions, report or failure state is injected.
        app.terminate(); app.launch()
        let resume = app.buttons["workout.recovery.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        shot(app, "all-recovery")
        reveal(resume, app); resume.tap(); acknowledge(app)
        XCTAssertTrue(app.staticTexts["whole.count"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["whole.count"].label, "0")
        let finish = app.buttons["workout.end"]
        reveal(finish, app); finish.tap()
        let done = app.buttons["whole.summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        shot(app, "all-live-result-zero")
        reveal(done, app); done.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }
    @MainActor private func acknowledge(_ app: XCUIApplication) {
        let notice = app.buttons["知道了"]
        if notice.waitForExistence(timeout: 3) { notice.tap() }
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists, element.isHittable, element.frame.minY >= 32, element.frame.maxY <= app.frame.maxY - 4 { return }
            let down = element.exists && element.frame.minY < 32
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.35 : 0.65))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.65 : 0.35))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
}
