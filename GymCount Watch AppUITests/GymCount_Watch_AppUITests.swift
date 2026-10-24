//
//  GymCount_Watch_AppUITests.swift
//  GymCount Watch AppUITests
//
//  Created by 向钧升 on 2025/10/13.
//

import XCTest

final class GymCount_Watch_AppUITests: XCTestCase {
    @MainActor
    func testSaveFailureAndRetry() throws {
        guard ProcessInfo.processInfo.environment["WATCH_SAVE_FAILURE_CHECK"] == "1" else {
            throw XCTSkip("Requires isolated filesystem failure setup and recovery watcher")
        }
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["workout.start.bench_press"].tap()
        app.buttons["增加次数"].tap()
        let end = app.buttons["workout.end"]
        if !end.isHittable { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.staticTexts["保存失败，训练仍在本页，请重试"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["已保存"].exists)
        app.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["重试保存"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "watch-save-failure"; shot.lifetime = .keepAlways; add(shot)
        // External review script removes the filesystem obstruction after this attachment.
        Thread.sleep(forTimeInterval: 3)
        app.buttons["workout.end"].tap()
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 3))
        let recovered = XCTAttachment(screenshot: app.screenshot()); recovered.name = "watch-save-retried"; recovered.lifetime = .keepAlways; add(recovered)
    }
    @MainActor
    func testWorkoutCompletionAndFeedbackNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let start = app.buttons["workout.start.bench_press"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let plus = app.buttons["增加次数"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap(); plus.tap(); plus.tap()
        let end = app.buttons["workout.end"]
        if !end.isHittable { app.swipeUp() }
        end.tap()
        let saved = app.staticTexts["已保存"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "watch-saved-green"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["计数不准？"].tap()
        XCTAssertTrue(app.staticTexts["计数反馈"].waitForExistence(timeout: 3))
        // A simulator has no real motion stream; it must never fabricate an upload.
        XCTAssertTrue(app.staticTexts["此记录没有可上传的采样"].exists)
        XCTAssertFalse(app.buttons["feedback.submit"].exists)
        app.buttons["返回"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workout.start.bench_press"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已保存"].exists)
    }

    @MainActor
    func testRealCaptureFeedbackForm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["历史"].tap()
        app.buttons["history.exercise.squat"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feedback.history."))
        // The read-only real capture used by this review is in October 2026.
        for _ in 0..<8 {
            if rows.count > 0 { break }
            app.buttons["上一周"].tap()
        }
        guard rows.count > 0 else { throw XCTSkip("Seed an isolated real capture and matching history before running") }
        if !rows.firstMatch.isHittable { app.swipeUp() }
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["计数反馈"].waitForExistence(timeout: 3))
        let plus = app.buttons["增加实际次数"]
        for _ in 0..<4 { plus.tap() }
        XCTAssertEqual(app.staticTexts["feedback.actual"].label, "4")
        let countShot = XCTAttachment(screenshot: app.screenshot()); countShot.name = "watch-feedback-count"; countShot.lifetime = .keepAlways; add(countShot)
        app.swipeUp()
        let submit = app.buttons["feedback.submit"]
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled)
        app.switches["已核对次数"].tap()
        XCTAssertTrue(submit.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "watch-feedback-confirmation"; shot.lifetime = .keepAlways; add(shot)
        // Do not submit historical/private evidence to production during UI checks.
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Notifications on isolated review simulator") { alert in
            let deny = alert.buttons["不允许"]
            if deny.exists { deny.tap(); return true }
            return false
        }

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
