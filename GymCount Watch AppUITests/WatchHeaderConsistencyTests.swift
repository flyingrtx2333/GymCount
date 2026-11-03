import XCTest

final class WatchHeaderConsistencyTests: XCTestCase {
    @MainActor func testRootHeadersChineseAndEnglish() {
        continueAfterFailure = false
        for english in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", english ? "(en)" : "(zh-Hans)", "-AppleLocale", english ? "en_US" : "zh_CN"]
            app.launch()
            checkTitle(app, english ? "Training" : "训练")
            app.buttons[english ? "Settings" : "设置"].tap()
            let back = app.buttons["watch.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
            let start = app.buttons["workout.start.squat"]
            XCTAssertTrue(start.waitForExistence(timeout: 5)); start.tap()
            XCTAssertTrue(app.staticTexts["whole.count"].waitForExistence(timeout: 8))
            checkTitle(app, english ? "Training" : "训练")
            let end = app.buttons["workout.end"]
            for _ in 0..<12 {
                if end.isHittable, end.frame.minY >= 44, end.frame.maxY <= app.frame.maxY - 6 { break }
                let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                a.press(forDuration: 0.1, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.1)
            }
            end.tap()
            XCTAssertTrue(app.buttons["whole.summary.done"].waitForExistence(timeout: 10))
            checkTitle(app, english ? "Workout Saved" : "训练已保存")
            Thread.sleep(forTimeInterval: 0.8)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = english ? "all-unified-result-en" : "all-unified-result-zh-Hans"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["whole.summary.done"].tap()
            XCTAssertTrue(start.waitForExistence(timeout: 5)); app.terminate()
        }
    }
    @MainActor private func checkTitle(_ app: XCUIApplication, _ text: String) {
        let title = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).element(boundBy: 0)
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, text)
        XCTAssertLessThan(title.frame.minY, 20)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.width - 60)
    }
}
