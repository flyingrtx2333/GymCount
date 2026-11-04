//
//  GymCount_Watch_AppUITests.swift
//  GymCount Watch AppUITests
//
//  Created by 向钧升 on 2025/10/13.
//

import XCTest

final class CommercialRepairWatchTests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        addUIInterruptionMonitor(withDescription: "Isolated preview notification permission") { alert in
            let deny = alert.buttons["不允许"]
            if deny.exists { deny.tap(); return true }
            return false
        }
        app.launch()
        let deny = XCUIApplication(bundleIdentifier: "com.apple.Carousel").alerts.buttons["不允许"]
        if deny.waitForExistence(timeout: 2) { deny.tap() }
        return app
    }
    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-AX"; tree.lifetime = .keepAlways; add(tree)
    }
    @MainActor func testInterruptedWorkoutResumeAndWeights() {
        let app = launch()
        XCTAssertTrue(app.buttons["workout.start.squat"].waitForExistence(timeout: 10))
        app.buttons["workout.start.squat"].tap()
        let plus = app.buttons["增加次数"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap(); plus.tap(); plus.tap()
        app.buttons["修改器械重量"].tap()
        XCTAssertTrue(app.buttons["weight-step-plus"].waitForExistence(timeout: 5))
        shot(app, "watch-weight-single-close")
        for _ in 0..<4 { app.buttons["weight-step-plus"].tap() }
        app.buttons["保存"].tap()
        plus.tap(); plus.tap()
        app.terminate(); app.launch()
        let resume = app.buttons["workout.recovery.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["5 次"].exists)
        XCTAssertFalse(plus.exists, "Recovered workouts must not restart counting on launch")
        shot(app, "watch-recovered-five-paused")
        resume.tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5)); plus.tap()
        app.buttons["workout.end"].tap()
        let close = app.buttons["workout.saved.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        app.buttons["历史"].tap(); app.buttons["history.exercise-filter"].tap(); app.buttons["history.exercise.squat"].tap()
        app.buttons["history.week-filter"].tap()
        XCTAssertTrue(app.staticTexts["330"].waitForExistence(timeout: 5), "3 × 50 + 3 × 60 must be 330 kg")
        shot(app, "watch-known-weight-volume")
    }
    @MainActor func testHistoryDensityAndDisclosure() {
        let app = launch()
        XCTAssertTrue(app.buttons["历史"].waitForExistence(timeout: 10)); app.buttons["历史"].tap()
        let picker = app.buttons["history.exercise-filter"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(picker.frame.height, 44)
        app.buttons["history.week-filter"].tap()
        let previous = app.buttons["history.week.previous"]
        XCTAssertGreaterThanOrEqual(previous.frame.width, 44)
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44)
        previous.tap()
        app.buttons["history.week-back"].firstMatch.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feedback.history.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Requires the real Oct 19 historical records")
        XCTAssertLessThanOrEqual(row.frame.maxY, app.frame.maxY)
        shot(app, "refined-watch-history-first-record")
        app.buttons["history.week-filter"].tap()
        shot(app, "refined-watch-history-expanded")
        app.buttons["history.week-back"].firstMatch.tap()
        picker.tap(); app.buttons["history.exercise.squat"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        shot(app, "refined-watch-history-squat")
    }
    @MainActor func testRecoveredWorkoutSaveAndDiscard() {
        let app = launch()
        XCTAssertTrue(app.buttons["workout.start.bench_press"].waitForExistence(timeout: 10))
        app.buttons["workout.start.bench_press"].tap()
        let plus = app.buttons["增加次数"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5)); plus.tap(); plus.tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workout.recovery.save"].waitForExistence(timeout: 10))
        app.buttons["workout.recovery.save"].tap()
        XCTAssertTrue(app.buttons["workout.saved.close"].waitForExistence(timeout: 5))
        app.buttons["workout.saved.close"].tap()
        app.buttons["workout.start.deadlift"].tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 5)); plus.tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workout.recovery.discard"].waitForExistence(timeout: 10))
        app.buttons["workout.recovery.discard"].tap()
        shot(app, "watch-discard-confirmation")
        // On the 41mm watchOS 27 review device this system action sheet has
        // inconsistent XCTest element types. Use its captured button position.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.64)).tap()
        XCTAssertTrue(app.buttons["workout.start.deadlift"].waitForExistence(timeout: 5))
        shot(app, "watch-recovered-discard-home")
    }
    @MainActor func testSettingsHelpAndNamedSwitches() {
        let app = launch()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10)); app.buttons["设置"].tap()
        let sync = app.switches["同步到运动圆环"].firstMatch
        for _ in 0..<3 { if sync.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(sync.exists, "The health switch needs an accessibility name")
        shot(app, "watch-settings-named-switch")
        for _ in 0..<4 { if app.buttons["使用帮助"].isHittable { break }; app.swipeUp() }
        app.buttons["使用帮助"].tap()
        shot(app, "watch-current-help")
        let siriPhrase = app.staticTexts["对手表说「开始健身计数」，再选择动作。"]
        for _ in 0..<8 {
            if siriPhrase.isHittable, siriPhrase.frame.minY >= 32, siriPhrase.frame.maxY <= 200 { break }
            let down = siriPhrase.exists && siriPhrase.frame.minY < 32
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: down ? 0.42 : 0.72))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: down ? 0.65 : 0.49))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(siriPhrase.isHittable)
        XCTAssertTrue(app.staticTexts["也可以说「用健身计数开始卧推」。"].exists)
        shot(app, "watch-siri-help")
    }
    @MainActor func testUnreadableWorkoutCanBePreservedAndReset() throws {
        guard ProcessInfo.processInfo.environment["WATCH_UNREADABLE_DRAFT_CHECK"] == "1" else {
            throw XCTSkip("Requires a damaged file in the isolated preview installation")
        }
        let app = launch()
        if app.buttons["知道了"].waitForExistence(timeout: 3) { app.buttons["知道了"].tap() }
        XCTAssertTrue(app.buttons["workout.draft.retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["workout.start.squat"].exists)
        shot(app, "watch-unreadable-workout-recovery")
        app.buttons["workout.draft.reset"].tap()
        shot(app, "watch-preserve-workout-confirmation")
        // The system action sheet uses the same 41mm layout as the captured
        // discard confirmation; its primary action is above Cancel.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66)).tap()
        XCTAssertTrue(app.buttons["workout.start.squat"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workout.start.squat"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["workout.draft.retry"].exists)
        shot(app, "watch-unreadable-workout-reset-home")
    }
    @MainActor func testDeniedReminderDoesNotBlockOtherSettings() throws {
        guard ProcessInfo.processInfo.environment["WATCH_DENIED_REMINDER_CHECK"] == "1" else {
            throw XCTSkip("Requires an enabled reminder with denied system permission in the isolated preview")
        }
        let app = launch()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 10)); app.buttons["设置"].tap()
        XCTAssertTrue(app.staticTexts["已拒绝"].exists, "The fixture must have denied notification permission")
        XCTAssertEqual(app.switches["每日提醒"].value as? String, "1")
        let equipment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "器械重量")).firstMatch
        XCTAssertTrue(equipment.waitForExistence(timeout: 5)); equipment.tap()
        XCTAssertTrue(app.buttons["增加重量"].waitForExistence(timeout: 5)); app.buttons["增加重量"].tap()
        app.buttons["完成"].tap()
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["workout.start.squat"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.buttons["设置"].tap()
        XCTAssertTrue(equipment.waitForExistence(timeout: 5))
        XCTAssertTrue(equipment.label.contains("52.5"), "An unrelated setting must persist even when reminders are denied")
        shot(app, "watch-denied-reminder-settings-saved")
    }
    @MainActor func testSaveFailureSurvivesRestart() throws {
        guard ProcessInfo.processInfo.environment["WATCH_COMMERCIAL_FAILURE_CHECK"] == "1" else {
            throw XCTSkip("Requires an isolated native filesystem failure watcher")
        }
        let app = launch()
        XCTAssertTrue(app.buttons["workout.start.squat"].waitForExistence(timeout: 10))
        app.buttons["workout.start.squat"].tap()
        let plus = app.buttons["增加次数"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5)); plus.tap(); plus.tap()
        XCTContext.runActivity(named: "CommercialWatchFailureReady") { _ in Thread.sleep(forTimeInterval: 3) }
        app.buttons["workout.end"].tap()
        XCTAssertTrue(app.staticTexts["保存失败，训练仍在本页，请重试"].waitForExistence(timeout: 5))
        app.buttons["知道了"].tap(); shot(app, "watch-native-save-failure")
        XCTContext.runActivity(named: "CommercialWatchRestoreHistory") { _ in Thread.sleep(forTimeInterval: 3) }
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workout.recovery.save"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["workout.recovery.resume"].exists)
        XCTAssertTrue(app.staticTexts["2 次"].exists)
        shot(app, "watch-failed-save-recovered")
        app.buttons["workout.recovery.save"].tap()
        XCTAssertTrue(app.buttons["workout.saved.close"].waitForExistence(timeout: 5))
    }
}

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
        XCTAssertFalse(app.buttons["workout.saved.close"].exists)
        app.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["重试保存"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "watch-save-failure"; shot.lifetime = .keepAlways; add(shot)
        // External review script removes the filesystem obstruction after this attachment.
        Thread.sleep(forTimeInterval: 3)
        app.buttons["workout.end"].tap()
        XCTAssertTrue(app.buttons["workout.saved.close"].waitForExistence(timeout: 3))
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
        let close = app.buttons["workout.saved.close"]
        let feedback = app.buttons["workout.saved.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable); XCTAssertTrue(feedback.isHittable)
        XCTAssertGreaterThanOrEqual(close.frame.width, 43.5)
        XCTAssertGreaterThanOrEqual(close.frame.height, 43.5)
        XCTAssertGreaterThanOrEqual(feedback.frame.height, 43.5)
        XCTAssertLessThanOrEqual(close.frame.maxY, feedback.frame.minY + 0.5)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "watch-saved-M2"; shot.lifetime = .keepAlways; add(shot)
        feedback.tap()
        XCTAssertTrue(app.staticTexts["计数反馈"].waitForExistence(timeout: 3))
        // A simulator has no real motion stream; it must never fabricate an upload.
        XCTAssertTrue(app.staticTexts["此记录没有可上传的采样"].exists)
        XCTAssertFalse(app.buttons["feedback.submit"].exists)
        app.buttons["返回"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["workout.start.bench_press"].waitForExistence(timeout: 5))
        XCTAssertFalse(close.exists)
    }

    @MainActor
    func testSavedBannerCloseAndAutoDismiss() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let close = app.buttons["workout.saved.close"]
        for exercise in ["squat", "deadlift"] {
            let start = app.buttons["workout.start." + exercise]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            start.tap()
            let plus = app.buttons["增加次数"]
            XCTAssertTrue(plus.waitForExistence(timeout: 5))
            for _ in 0..<(exercise == "squat" ? 10 : 1) { plus.tap() }
            let end = app.buttons["workout.end"]
            if !end.isHittable { app.swipeUp() }
            end.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "watch-saved-" + exercise; shot.lifetime = .keepAlways; add(shot)
            if exercise == "squat" {
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 2))
            } else {
                XCTAssertTrue(close.waitForNonExistence(timeout: 7))
            }
        }
        XCTAssertTrue(app.buttons["workout.start.deadlift"].exists)
    }

    @MainActor
    func testRealCaptureFeedbackForm() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["历史"].tap()
        app.buttons["history.exercise-filter"].tap()
        app.buttons["history.exercise.squat"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "feedback.history."))
        // The read-only real capture used by this review is in October 2026.
        for _ in 0..<8 {
            if rows.count > 0 { break }
            app.buttons["history.week-filter"].tap()
            app.buttons["history.week.previous"].tap()
            app.buttons["history.week-back"].firstMatch.tap()
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
